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

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from . import service
from .models import LedgerEntry
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
