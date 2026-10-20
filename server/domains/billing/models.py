"""
Billing — the hosted pay-as-you-go AI tier (blueprint Section 42.1, added
2026-09-20). Study OS holds its own pooled provider key(s) (see
server/core/config.py's hosted_<provider>_api_key settings) rather than
provisioning a raw key per user — see STUDY_OS_PROGRESS.md's 2026-09-20
entry for why: the originally-proposed per-user key provisioning was found
to conflict with Anthropic's, and likely OpenAI's, Terms of Service.

WalletBalance is a get-or-create single row per user (same pattern as
server/ai/personality's PersonalityProfile). LedgerEntry is append-only — a
topup or a usage charge, never edited or deleted after creation, so a
user's spend is always auditable from the log alone, not just the current
balance.

Amounts are integer cents (not float) throughout to avoid floating-point
rounding drift accumulating across many small usage charges.
"""
from __future__ import annotations

import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base

LEDGER_KINDS = frozenset({"topup", "usage"})


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class WalletBalance(Base):
    __tablename__ = "wallet_balances"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    balance_cents: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {"balance_cents": self.balance_cents, "updated_at": self.updated_at.isoformat()}


class LedgerEntry(Base):
    __tablename__ = "ledger_entries"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    # "topup" (amount_cents > 0) | "usage" (amount_cents < 0) — see LEDGER_KINDS.
    kind: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    amount_cents: Mapped[int] = mapped_column(Integer, nullable=False)

    # usage rows only — null for topups.
    provider: Mapped[str | None] = mapped_column(String(20), nullable=True)
    model_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    input_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    output_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Decomposed charge, so a usage row is auditable from the log alone
    # rather than trusting one opaque total — see pricing.compute_charge.
    # infra_surcharge_cents is tracked as its own column (not folded into
    # markup_cents) per the user's explicit instruction that server/hosting
    # cost must be a separately visible, separately adjustable line item.
    provider_cost_cents: Mapped[int | None] = mapped_column(Integer, nullable=True)
    markup_cents: Mapped[int | None] = mapped_column(Integer, nullable=True)
    infra_surcharge_cents: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # topup rows only — the payment provider's transaction/intent id (a
    # real provider) or the mock provider's generated reference.
    payment_reference: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "amount_cents": self.amount_cents,
            "provider": self.provider,
            "model_name": self.model_name,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "provider_cost_cents": self.provider_cost_cents,
            "markup_cents": self.markup_cents,
            "infra_surcharge_cents": self.infra_surcharge_cents,
            "payment_reference": self.payment_reference,
            "confirmed": self.confirmed,
            "created_at": self.created_at.isoformat(),
        }


class AiUsage(Base):
    """One row per real AI provider call, for the student-facing token meter
    (2026-10-20) — every backend that reports token counts (BYOK and the
    hosted tier alike), unlike LedgerEntry, which only exists for hosted
    calls because only those move money in this app. Local-model calls
    report no usage and are free, so they get no row.

    cost_micro_usd is millionths of a dollar, not cents: a typical BYOK
    call costs a small fraction of a cent, which cents would round to 0.
    For a hosted call it's what the wallet was actually debited; for BYOK
    it's an estimate from pricing.py's price table (the student's provider
    bills them directly, Study OS never sees that bill), and null for a
    model that table doesn't price — never a guessed $0."""

    __tablename__ = "ai_usage"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    provider: Mapped[str] = mapped_column(String(20), nullable=False)
    model_name: Mapped[str] = mapped_column(String(100), nullable=False)
    # "chat" | "explain" | "grading" | "generation" — which feature spent it.
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    hosted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    cost_micro_usd: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )


class AiSpendLimit(Base):
    """A student's own monthly cap on AI spending (2026-10-20), checked
    before every non-local AI call (core/model_config.py's
    resolve_model_config_async). One row per student, only once they set
    one; no row (or a null limit) means no cap. Counted against the same
    estimates the token meter shows, per calendar month (UTC)."""

    __tablename__ = "ai_spend_limits"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    monthly_limit_cents: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )
