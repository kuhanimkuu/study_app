"""
Wallet/ledger operations shared by billing/router.py (top-ups) and the
hosted-tier debit call sites in routers/ask.py and
domains/assessment/router.py (usage charges) — kept in one place so every
caller debits/credits identically rather than duplicating the
read-modify-write logic.
"""
from __future__ import annotations

import datetime

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.config import get_settings
from . import credits, pricing
from .models import AiSpendLimit, AiUsage, LedgerEntry, WalletBalance


async def get_or_create_wallet(db: AsyncSession, user_id: int, for_update: bool = False) -> WalletBalance:
    """`for_update` locks the row until the transaction ends. Every change
    to balance_cents must use it: the change is read-then-write, so two
    requests finishing together (two hosted answers, or a double-tapped
    top-up confirm) used to both read the same balance and one of the two
    changes was lost."""
    query = select(WalletBalance).where(WalletBalance.user_id == user_id)
    if for_update:
        query = query.with_for_update()
    wallet = await db.scalar(query)
    if wallet is None:
        wallet = WalletBalance(user_id=user_id, balance_cents=0)
        db.add(wallet)
        try:
            async with db.begin_nested():
                await db.flush()
        except IntegrityError:
            # Another request created it first (user_id is unique).
            wallet = await db.scalar(query)
    return wallet


async def credit_topup(db: AsyncSession, user_id: int, amount_cents: int, reference: str) -> LedgerEntry:
    wallet = await get_or_create_wallet(db, user_id, for_update=True)
    wallet.balance_cents += amount_cents
    entry = LedgerEntry(
        user_id=user_id, kind="topup", amount_cents=amount_cents,
        payment_reference=reference, confirmed=True,
    )
    db.add(entry)
    await db.flush()
    return entry


async def charge_for_usage(
    db: AsyncSession, user_id: int, provider: str, model_name: str, usage: dict | None, source: str = "chat",
) -> LedgerEntry | None:
    """Charges the feature's fixed price in app credits (credits.py), not
    the tokens. No-op (returns None) if there's nothing to charge — `usage`
    is None for the local backend, and for any BYOK call, since neither is
    billed. The provider's own cost is kept on the row for Study OS's
    records; the student never sees it.

    Debits the wallet even if it lands negative: the balance was checked
    BEFORE the generation call (see model_config.resolve_model_config_async's
    pre-flight check), and discarding an already-completed (and already
    provider-billed) answer mid-response would be worse. The next hosted
    request is blocked until the student has credits again."""
    if usage is None:
        return None
    input_tokens = usage.get("input_tokens") or 0
    output_tokens = usage.get("output_tokens") or 0
    price = credits.credits_for(source)

    wallet = await get_or_create_wallet(db, user_id, for_update=True)
    wallet.balance_cents -= price
    entry = LedgerEntry(
        user_id=user_id, kind="usage", amount_cents=-price, feature=source,
        provider=provider, model_name=model_name,
        input_tokens=input_tokens, output_tokens=output_tokens,
        provider_cost_cents=pricing.provider_cost_cents(provider, model_name, input_tokens, output_tokens),
        confirmed=True,
    )
    db.add(entry)
    await db.flush()
    return entry


async def record_ai_usage(db: AsyncSession, user_id: int, model_config: dict, usage: dict | None, source: str) -> AiUsage | None:
    """The one call every AI call site makes after a model_router.run:
    logs the call for the token meter and, on the hosted tier only, charges
    the feature's credits (charge_for_usage). `source` names the feature
    (credits.FEATURE_CREDITS). No-op when `usage` is None — the local
    model, or a call that never reached a provider. Flushes, doesn't
    commit: callers commit with their own rows (or right away, where the
    provider's bill must persist even if the request then fails)."""
    if usage is None:
        return None
    # Imported here, not at module top: the model router pulls in the
    # provider SDKs, which billing's own unit tests don't need.
    from ... import engines

    input_tokens = usage.get("input_tokens") or 0
    output_tokens = usage.get("output_tokens") or 0
    hosted_provider = model_config.get("hosted_provider")
    charged = None
    if hosted_provider:
        provider = hosted_provider
        model_name = engines.model_router.DEFAULT_MODEL_NAMES[hosted_provider]
        entry = await charge_for_usage(db, user_id, provider, model_name, usage, source)
        charged = -entry.amount_cents if entry is not None else None
    else:
        provider = model_config.get("backend", "local")
        model_name = model_config.get("model_name") or engines.model_router.DEFAULT_MODEL_NAMES.get(provider, provider)
    # Hosted: what the provider charged Study OS (the hidden allowance
    # counts it). BYOK: an estimate of the student's own provider bill.
    cost = pricing.estimate_cost_micro_usd(provider, model_name, input_tokens, output_tokens)

    row = AiUsage(
        user_id=user_id, provider=provider, model_name=model_name, source=source,
        hosted=bool(hosted_provider), input_tokens=input_tokens, output_tokens=output_tokens,
        cost_micro_usd=cost, credits=charged,
    )
    db.add(row)
    await db.flush()
    return row


def month_start(now: datetime.datetime | None = None) -> datetime.datetime:
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


async def month_spend_micro_usd(db: AsyncSession, user_id: int) -> int:
    """This calendar month's (UTC) priced spend on the student's own keys —
    unpriced calls can't count toward a dollar limit, which the app's meter
    screen says. Hosted calls are paid in credits, so they don't count."""
    total = await db.scalar(
        select(func.coalesce(func.sum(AiUsage.cost_micro_usd), 0)).where(
            AiUsage.user_id == user_id, AiUsage.created_at >= month_start(), AiUsage.hosted.is_(False)
        )
    )
    return int(total or 0)


ALLOWANCE_USED_UP = (
    "You've used this month's Study OS AI allowance. It renews on the 1st — until then you can "
    "use your own AI key (Profile → Set up AI)."
)

# A small float so a student's first answers aren't blocked before any
# credits have been counted.
_ALLOWANCE_FLOAT_MICRO_USD = 100_000


async def enforce_hosted_allowance(db: AsyncSession, user_id: int) -> None:
    """The hidden allowance (credits.py): raises 402 once this month's
    hosted calls have cost Study OS more than the credits spent on them
    sold for (plus a 10-cent float), or more than the server's monthly cap.
    With the hosted model priced in credits.py neither should happen in
    normal use; they are what keeps the worst case below the price if the
    model or its prices change first."""
    cost, spent = (
        await db.execute(
            select(
                func.coalesce(func.sum(AiUsage.cost_micro_usd), 0),
                func.coalesce(func.sum(AiUsage.credits), 0),
            ).where(AiUsage.user_id == user_id, AiUsage.hosted.is_(True), AiUsage.created_at >= month_start())
        )
    ).one()
    cap = int(get_settings().hosted_monthly_cost_cap_usd * 1_000_000)
    earned = int(spent) * credits.CREDIT_PRICE_CENTS * 10_000 + _ALLOWANCE_FLOAT_MICRO_USD
    if int(cost) >= min(cap, earned):
        raise HTTPException(status_code=402, detail=ALLOWANCE_USED_UP)


async def get_monthly_limit_cents(db: AsyncSession, user_id: int) -> int | None:
    return await db.scalar(select(AiSpendLimit.monthly_limit_cents).where(AiSpendLimit.user_id == user_id))


async def set_monthly_limit_cents(db: AsyncSession, user_id: int, limit_cents: int | None) -> None:
    row = await db.scalar(select(AiSpendLimit).where(AiSpendLimit.user_id == user_id))
    if row is None:
        row = AiSpendLimit(user_id=user_id)
        db.add(row)
    row.monthly_limit_cents = limit_cents
    await db.flush()


async def enforce_spend_limit(db: AsyncSession, user_id: int) -> None:
    """Raises 402 once this month's spend has reached the student's own
    cap. Checked before the call (like the hosted balance check), so one
    call can take the total a little past the cap — the next is blocked."""
    limit_cents = await get_monthly_limit_cents(db, user_id)
    if limit_cents is None:
        return
    if await month_spend_micro_usd(db, user_id) >= limit_cents * 10_000:
        raise HTTPException(
            status_code=402,
            detail=f"You've reached your monthly AI spending limit of ${limit_cents / 100:.2f}. "
            "Raise or remove it in Profile → AI usage, or switch to the free model.",
        )
