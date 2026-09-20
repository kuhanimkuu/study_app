"""Integration tests for server/domains/billing — the hosted pay-as-you-go
AI tier (blueprint Section 42.1). Real Postgres, same style as the other
test modules. See STUDY_OS_PROGRESS.md's 2026-09-20 entry for the ToS
research that led to this design (Study OS's own pooled keys, never a
per-user provisioned raw key).

Run with: python -m pytest server/tests/test_billing.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.ai.moderator import router as moderator_router_module
from server.core.config import get_settings
from server.core.model_config import ModelConfig, resolve_model_config_async
from server.db.session import async_session
from server.domains.billing import pricing, service as billing_service
from server.domains.identity.models import User
from server.routers import ask as ask_router_module


def _unique_email() -> str:
    return f"pytest_billing_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}
    user_id = signup.json()["user"]["id"]

    yield {"headers": headers, "email": email, "user_id": user_id}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


@pytest.fixture
def hosted_anthropic_configured(monkeypatch):
    """Points Settings.hosted_anthropic_api_key at a fake (never-used —
    every test using this fixture also mocks model_router.run, so no real
    network call is ever made) key, so resolve_model_config_async's "is
    the hosted tier configured for this provider" check passes and tests
    can exercise the balance/billing logic past it."""
    monkeypatch.setenv("HOSTED_ANTHROPIC_API_KEY", "test-fake-key-not-real")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


# ---------------------------------------------------------------------------
# pricing.compute_charge — pure function, no DB/HTTP needed
# ---------------------------------------------------------------------------

def test_compute_charge_known_model_decomposes_correctly():
    # claude-sonnet-5: $3.00/1M input, $15.00/1M output (pricing.py).
    # 100,000 input + 100,000 output tokens -> $0.30 + $1.50 = $1.80 = 180 cents.
    charge = pricing.compute_charge("anthropic", "claude-sonnet-5", 100_000, 100_000)
    assert charge["provider_cost_cents"] == 180
    # Default 30% markup, 0% infra surcharge (server/core/config.py defaults,
    # confirmed unset in this repo's local .env).
    assert charge["markup_cents"] == 54
    assert charge["infra_surcharge_cents"] == 0
    assert charge["total_cents"] == 234


def test_compute_charge_unknown_model_raises_rather_than_charging_zero():
    with pytest.raises(ValueError):
        pricing.compute_charge("anthropic", "some-made-up-model", 1000, 1000)


def test_compute_charge_zero_tokens_is_free():
    charge = pricing.compute_charge("openai", "gpt-4o-mini", 0, 0)
    assert charge == {
        "provider_cost_cents": 0, "markup_cents": 0, "infra_surcharge_cents": 0, "total_cents": 0,
    }


# ---------------------------------------------------------------------------
# Wallet / ledger service functions
# ---------------------------------------------------------------------------

async def test_wallet_starts_at_zero(student):
    async with async_session() as db:
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        await db.commit()
        assert wallet.balance_cents == 0


async def test_charge_for_usage_noop_when_usage_none(student):
    async with async_session() as db:
        entry = await billing_service.charge_for_usage(
            db, student["user_id"], "anthropic", "claude-sonnet-5", usage=None
        )
        await db.commit()
        assert entry is None
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 0


async def test_charge_for_usage_debits_wallet_and_records_decomposed_ledger_entry(student):
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 10_000, "test-topup-1")
        await db.commit()

    async with async_session() as db:
        entry = await billing_service.charge_for_usage(
            db, student["user_id"], "anthropic", "claude-sonnet-5",
            usage={"input_tokens": 100_000, "output_tokens": 100_000},
        )
        await db.commit()

        assert entry.kind == "usage"
        assert entry.amount_cents == -234  # see test_compute_charge_known_model_decomposes_correctly
        assert entry.provider_cost_cents == 180
        assert entry.markup_cents == 54
        assert entry.infra_surcharge_cents == 0

        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 10_000 - 234


# ---------------------------------------------------------------------------
# resolve_model_config_async — the "hosted" backend's real gating logic
# ---------------------------------------------------------------------------

async def test_resolve_hosted_rejects_unknown_provider(student):
    async with async_session() as db:
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(
                ModelConfig(backend="hosted", hosted_provider="not-a-real-provider"),
                {"id": student["user_id"], "encryption_key": "unused"},
                db,
            )
        assert exc_info.value.status_code == 400


async def test_resolve_hosted_requires_configured_key(student):
    # No hosted_anthropic_configured fixture here on purpose — this repo's
    # local .env has no HOSTED_ANTHROPIC_API_KEY set, so this should fail
    # clearly (503) rather than silently using an empty key.
    get_settings.cache_clear()
    async with async_session() as db:
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(
                ModelConfig(backend="hosted", hosted_provider="anthropic"),
                {"id": student["user_id"], "encryption_key": "unused"},
                db,
            )
        assert exc_info.value.status_code == 503
    get_settings.cache_clear()


async def test_resolve_hosted_requires_positive_balance(student, hosted_anthropic_configured):
    async with async_session() as db:
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(
                ModelConfig(backend="hosted", hosted_provider="anthropic"),
                {"id": student["user_id"], "encryption_key": "unused"},
                db,
            )
        assert exc_info.value.status_code == 402


async def test_resolve_hosted_with_balance_uses_pooled_key_not_a_user_submitted_one(
    student, hosted_anthropic_configured
):
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 1000, "test-topup-2")
        await db.commit()

    async with async_session() as db:
        config = await resolve_model_config_async(
            ModelConfig(backend="hosted", hosted_provider="anthropic"),
            {"id": student["user_id"], "encryption_key": "unused"},
            db,
        )
        assert config["backend"] == "anthropic"
        assert config["hosted_provider"] == "anthropic"
        assert config["api_key"] == "test-fake-key-not-real"  # the POOLED key, not a decrypted user one
        # No model_name override honored for the hosted tier (see
        # model_config.py's docstring) — pricing only has real numbers for
        # the fixed default model per provider.
        assert "model_name" not in config


# ---------------------------------------------------------------------------
# Full HTTP round trip: /api/ask/text with backend="hosted" actually bills.
# model_router.run is monkeypatched so this never makes a real network call
# or needs a real Anthropic key — it proves the write-back plumbing through
# moderator/engine.py (model_config["_billed_usage"]) actually reaches
# routers/ask.py's billing call, which is the fragile part of this design.
# ---------------------------------------------------------------------------

async def _fake_model_router_run(**kwargs):
    return {
        "text": "A fake but real-shaped hosted-tier reply.",
        "tier": kwargs.get("tier", "tiny"),
        "backend": kwargs.get("backend", "anthropic"),
        "usage": {"input_tokens": 100_000, "output_tokens": 100_000},
    }


async def test_ask_text_with_hosted_backend_debits_wallet_end_to_end(
    client, student, hosted_anthropic_configured, monkeypatch
):
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 10_000, "test-topup-3")
        await db.commit()

    monkeypatch.setattr(ask_router_module.engines.model_router, "run", _fake_model_router_run)

    resp = await client.post(
        "/api/ask/text",
        json={"content": "hi", "model_config": {"backend": "hosted", "hosted_provider": "anthropic"}},
        headers=student["headers"],
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "_usage" not in body  # internal signal, must not leak into the public response

    async with async_session() as db:
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 10_000 - 234

    usage_resp = await client.get("/api/v1/billing/usage", headers=student["headers"])
    assert usage_resp.status_code == 200, usage_resp.text
    entries = usage_resp.json()["entries"]
    assert len(entries) == 1
    assert entries[0]["provider"] == "anthropic"
    assert entries[0]["model_name"] == "claude-sonnet-5"
    assert entries[0]["amount_cents"] == -234


async def test_explain_concept_with_hosted_backend_debits_wallet_end_to_end(
    client, student, hosted_anthropic_configured, monkeypatch
):
    """Same mechanism, second real call site (server/ai/moderator/router.py's
    /explain) — proves the write-back pattern wasn't special-cased to
    ask_text alone."""
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 10_000, "test-topup-4")
        await db.commit()

    space = await client.post("/api/projects", json={"display_name": "Physics"}, headers=student["headers"])
    assert space.status_code == 200, space.text
    slug = space.json()["slug"]
    concept = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/concepts",
        json={"name": "Momentum", "description": "mass times velocity"},
        headers=student["headers"],
    )
    assert concept.status_code == 200, concept.text
    concept_id = concept.json()["id"]

    monkeypatch.setattr(moderator_router_module.engines.model_router, "run", _fake_model_router_run)

    resp = await client.post(
        f"/api/v1/concepts/{concept_id}/explain",
        json={"model_config": {"backend": "hosted", "hosted_provider": "anthropic"}},
        headers=student["headers"],
    )
    assert resp.status_code == 200, resp.text

    async with async_session() as db:
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 10_000 - 234
