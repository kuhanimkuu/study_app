"""
Payment provider abstraction for hosted-tier top-ups. No real payment
processor is integrated yet — see STUDY_OS_PROGRESS.md's 2026-09-20 entry:
the processor (Stripe/Paystack/etc.) is the user's own business decision
and account to create, not made yet. MockPaymentProvider is the default so
the whole topup -> balance -> usage -> debit flow is real, testable, and
demoable without a merchant account; it moves NO real money.

Wiring in a real processor later means adding a new class here (e.g.
StripePaymentProvider) implementing the same PaymentProvider protocol and
pointing PAYMENT_PROVIDER at it — additive, not a rewrite of anything else
in this domain (router.py/service.py only ever call through this
protocol, never a concrete class directly).
"""
from __future__ import annotations

import uuid
from typing import Protocol

from ...core.config import get_settings


class PaymentProvider(Protocol):
    def create_topup(self, user_id: int, amount_cents: int) -> dict:
        """Returns {"reference": str, "confirmed": bool}. `confirmed` is
        True only for a provider that can settle a payment synchronously
        within this one call (like the mock) — a real processor would
        return confirmed=False here and settle later via its own
        server-to-server webhook, not this call."""
        ...

    def confirm_topup(self, reference: str) -> bool:
        """Best-effort re-check of a pending topup's status. The mock
        provider always returns True (it already confirmed synchronously
        in create_topup)."""
        ...


class MockPaymentProvider:
    """Local-dev/testing only — confirms every topup immediately. No real
    money changes hands. Never point a real deployment's PAYMENT_PROVIDER
    at this; it exists so the ledger/balance mechanism can be built and
    tested end-to-end before a real processor is chosen."""

    def create_topup(self, user_id: int, amount_cents: int) -> dict:
        return {"reference": f"mock_{uuid.uuid4().hex}", "confirmed": True}

    def confirm_topup(self, reference: str) -> bool:
        return True


def get_payment_provider() -> PaymentProvider:
    provider = get_settings().payment_provider
    if provider == "mock":
        return MockPaymentProvider()
    raise NotImplementedError(
        f"payment_provider={provider!r} is not wired up yet — no real payment "
        "processor integration exists (see STUDY_OS_PROGRESS.md, 2026-09-20: "
        "processor choice is still open). Set PAYMENT_PROVIDER=mock for local "
        "dev/testing, or implement a real provider class before using this value."
    )
