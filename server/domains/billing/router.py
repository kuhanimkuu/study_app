"""
/api/v1/billing/... — hosted-tier wallet balance, top-ups, and usage
history (blueprint Section 42.1). No real payment processor is wired in
yet (see payment_provider.py) — POST /topups/{reference}/confirm exists so
the mock provider's synchronous-confirm flow can be exercised over real
HTTP today; a real processor would normally settle a topup via its own
server-to-server webhook route instead of this user-triggered one, which
is the shape to add when a real processor gets chosen.
"""
from __future__ import annotations

import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from . import service
from .models import AiUsage, LedgerEntry
from .payment_provider import get_payment_provider

router = APIRouter(prefix="/api/v1/billing")


@router.get("/balance")
async def get_balance(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    wallet = await service.get_or_create_wallet(db, current_user["id"])
    await db.commit()
    return wallet.public()


class CreateTopup(BaseModel):
    amount_cents: int = Field(gt=0)


@router.post("/topups")
async def create_topup(
    payload: CreateTopup,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    provider = get_payment_provider()
    result = provider.create_topup(current_user["id"], payload.amount_cents)

    if result["confirmed"]:
        entry = await service.credit_topup(db, current_user["id"], payload.amount_cents, result["reference"])
        await db.commit()
        await db.refresh(entry)
        return entry.public()

    # Real-processor path: the topup is pending until a webhook (future
    # work) or an explicit /confirm call marks it settled.
    entry = LedgerEntry(
        user_id=current_user["id"], kind="topup", amount_cents=payload.amount_cents,
        payment_reference=result["reference"], confirmed=False,
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return entry.public()


@router.post("/topups/{reference}/confirm")
async def confirm_topup(
    reference: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    entry = await db.scalar(
        select(LedgerEntry).where(
            LedgerEntry.payment_reference == reference,
            LedgerEntry.user_id == current_user["id"],
            LedgerEntry.kind == "topup",
        )
    )
    if entry is None:
        raise HTTPException(status_code=404, detail=f"no pending topup with reference {reference!r}")
    if entry.confirmed:
        return entry.public()

    provider = get_payment_provider()
    if not provider.confirm_topup(reference):
        raise HTTPException(status_code=409, detail="payment not yet confirmed by the provider")

    wallet = await service.get_or_create_wallet(db, current_user["id"])
    wallet.balance_cents += entry.amount_cents
    entry.confirmed = True
    await db.commit()
    await db.refresh(entry)
    return entry.public()


@router.get("/usage")
async def list_usage(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    # Wrapped in a named key, not a bare list — matches every other list
    # endpoint in this backend (list_questions -> {"questions": [...]},
    # list_study_sessions -> {"study_sessions": [...]}, etc.), which the
    # Flutter ApiClient's _decode() always assumes (a bare JSON array
    # would fail its Map<String, dynamic> cast).
    entries = await db.scalars(
        select(LedgerEntry)
        .where(LedgerEntry.user_id == current_user["id"], LedgerEntry.kind == "usage")
        .order_by(LedgerEntry.created_at.desc())
        .limit(100)
    )
    return {"entries": [entry.public() for entry in entries]}


@router.get("/ai-usage")
async def ai_usage_summary(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """The token meter (2026-10-20): this student's own AI usage — today,
    the last 30 days and all time — plus a per-model breakdown. Only ever
    the caller's rows; no key or other student's data is involved.

    cost_micro_usd sums only priced calls; unpriced_calls counts the rest
    (a BYOK model the price table doesn't know), so the app can say the
    total is partial instead of passing it off as complete."""
    now = datetime.datetime.now(datetime.timezone.utc)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    periods = {
        "today": day_start,
        "this_month": service.month_start(now),
        "last_30_days": now - datetime.timedelta(days=30),
        "all_time": None,
    }

    def totals_query(since):
        q = select(
            func.count(AiUsage.id),
            func.coalesce(func.sum(AiUsage.input_tokens), 0),
            func.coalesce(func.sum(AiUsage.output_tokens), 0),
            func.coalesce(func.sum(AiUsage.cost_micro_usd), 0),
            func.count(AiUsage.id).filter(AiUsage.cost_micro_usd.is_(None)),
        ).where(AiUsage.user_id == current_user["id"])
        if since is not None:
            q = q.where(AiUsage.created_at >= since)
        return q

    summary = {}
    for name, since in periods.items():
        calls, input_tokens, output_tokens, cost, unpriced = (await db.execute(totals_query(since))).one()
        summary[name] = {
            "calls": calls, "input_tokens": input_tokens, "output_tokens": output_tokens,
            "cost_micro_usd": cost, "unpriced_calls": unpriced,
        }

    rows = await db.execute(
        select(
            AiUsage.provider, AiUsage.model_name, AiUsage.hosted,
            func.count(AiUsage.id),
            func.sum(AiUsage.input_tokens), func.sum(AiUsage.output_tokens),
            func.sum(AiUsage.cost_micro_usd),
        )
        .where(AiUsage.user_id == current_user["id"])
        .group_by(AiUsage.provider, AiUsage.model_name, AiUsage.hosted)
        .order_by(func.sum(AiUsage.input_tokens + AiUsage.output_tokens).desc())
    )
    by_model = [
        {
            "provider": provider, "model_name": model_name, "hosted": hosted, "calls": calls,
            "input_tokens": input_tokens or 0, "output_tokens": output_tokens or 0,
            # null when none of this model's calls could be priced.
            "cost_micro_usd": cost,
        }
        for provider, model_name, hosted, calls, input_tokens, output_tokens, cost in rows
    ]
    limit_cents = await service.get_monthly_limit_cents(db, current_user["id"])
    return {**summary, "by_model": by_model, "monthly_limit_cents": limit_cents}


class SpendLimit(BaseModel):
    # null removes the cap; capped at $1,000 so a typo can't silently
    # mean "no limit".
    monthly_limit_cents: int | None = Field(default=None, ge=1, le=100_000)


@router.put("/ai-usage/limit")
async def set_spend_limit(
    payload: SpendLimit,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await service.set_monthly_limit_cents(db, current_user["id"], payload.monthly_limit_cents)
    await db.commit()
    return {"monthly_limit_cents": payload.monthly_limit_cents}
