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
from sqlalchemy.ext.asyncio import AsyncSession

from . import pricing
from .models import AiSpendLimit, AiUsage, LedgerEntry, WalletBalance


async def get_or_create_wallet(db: AsyncSession, user_id: int) -> WalletBalance:
    wallet = await db.scalar(select(WalletBalance).where(WalletBalance.user_id == user_id))
    if wallet is None:
        wallet = WalletBalance(user_id=user_id, balance_cents=0)
        db.add(wallet)
        await db.flush()
    return wallet


async def credit_topup(db: AsyncSession, user_id: int, amount_cents: int, reference: str) -> LedgerEntry:
    wallet = await get_or_create_wallet(db, user_id)
    wallet.balance_cents += amount_cents
    entry = LedgerEntry(
        user_id=user_id, kind="topup", amount_cents=amount_cents,
        payment_reference=reference, confirmed=True,
    )
    db.add(entry)
    await db.flush()
    return entry


async def charge_for_usage(
    db: AsyncSession, user_id: int, provider: str, model_name: str, usage: dict | None,
) -> LedgerEntry | None:
    """No-op (returns None) if there's nothing to charge — `usage` is None
    for the local backend, and for any BYOK call, since neither is billed.

    Debits the wallet even if it lands negative: the balance was checked
    BEFORE the generation call (see model_config.resolve_model_config_async's
    `balance_cents > 0` pre-flight check), but the exact cost is only known
    AFTER, from real token counts. That means a request which passes the
    pre-flight check can, in principle, leave the balance slightly negative
    if the actual usage costs more than a bare "balance > 0" check implied.
    The next hosted-tier request is blocked until the user tops back up —
    a small, named overdraft window, chosen over discarding an
    already-completed (and already provider-billed-to-Study-OS) generation
    mid-response."""
    if usage is None:
        return None
    input_tokens = usage.get("input_tokens") or 0
    output_tokens = usage.get("output_tokens") or 0
    charge = pricing.compute_charge(provider, model_name, input_tokens, output_tokens)

    wallet = await get_or_create_wallet(db, user_id)
    wallet.balance_cents -= charge["total_cents"]
    entry = LedgerEntry(
        user_id=user_id, kind="usage", amount_cents=-charge["total_cents"],
        provider=provider, model_name=model_name,
        input_tokens=input_tokens, output_tokens=output_tokens,
        provider_cost_cents=charge["provider_cost_cents"],
        markup_cents=charge["markup_cents"],
        infra_surcharge_cents=charge["infra_surcharge_cents"],
        confirmed=True,
    )
    db.add(entry)
    await db.flush()
    return entry


async def record_ai_usage(db: AsyncSession, user_id: int, model_config: dict, usage: dict | None, source: str) -> AiUsage | None:
    """The one call every AI call site makes after a model_router.run:
    logs the call for the token meter and, on the hosted tier only, debits
    the wallet (charge_for_usage). No-op when `usage` is None — the local
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
    if hosted_provider:
        provider = hosted_provider
        model_name = engines.model_router.DEFAULT_MODEL_NAMES[hosted_provider]
        entry = await charge_for_usage(db, user_id, provider, model_name, usage)
        cost = entry.amount_cents * -10_000 if entry is not None else None
    else:
        provider = model_config.get("backend", "local")
        model_name = model_config.get("model_name") or engines.model_router.DEFAULT_MODEL_NAMES.get(provider, provider)
        cost = pricing.estimate_cost_micro_usd(provider, model_name, input_tokens, output_tokens)

    row = AiUsage(
        user_id=user_id, provider=provider, model_name=model_name, source=source,
        hosted=bool(hosted_provider), input_tokens=input_tokens, output_tokens=output_tokens,
        cost_micro_usd=cost,
    )
    db.add(row)
    await db.flush()
    return row


def month_start(now: datetime.datetime | None = None) -> datetime.datetime:
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


async def month_spend_micro_usd(db: AsyncSession, user_id: int) -> int:
    """This calendar month's (UTC) priced AI spend — unpriced calls can't
    count toward a dollar limit, which the app's meter screen says."""
    total = await db.scalar(
        select(func.coalesce(func.sum(AiUsage.cost_micro_usd), 0)).where(
            AiUsage.user_id == user_id, AiUsage.created_at >= month_start()
        )
    )
    return int(total or 0)


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
