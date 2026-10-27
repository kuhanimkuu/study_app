"""Integration tests for server/domains/billing — the hosted AI tier
(blueprint Section 42.1), paid in app credits since 2026-10-27. Real Postgres, same style as the other
test modules. See STUDY_OS_PROGRESS.md's 2026-09-20 entry for the ToS
research that led to this design (Study OS's own pooled keys, never a
per-user provisioned raw key).

Run with: python -m pytest server/tests/test_billing.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server import engines
from server.core.config import get_settings
from server.core.model_config import ModelConfig, resolve_model_config_async
from server.db.session import async_session
from server.domains.billing import credits, pricing, service as billing_service
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
def hosted_configured(monkeypatch):
    """Points the server's hosted model (deepseek by default) at a fake
    (never-used — every test using this fixture also mocks
    model_router.run, so no real network call is ever made) key, so
    resolve_model_config_async's "is the hosted tier configured" check
    passes and tests can exercise the credits logic past it."""
    monkeypatch.setenv("HOSTED_DEFAULT_PROVIDER", "deepseek")
    monkeypatch.setenv("HOSTED_DEEPSEEK_API_KEY", "test-fake-key-not-real")
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


async def test_charge_for_usage_charges_the_features_credits_not_the_tokens(student):
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 100, "test-topup-1")
        await db.commit()

    async with async_session() as db:
        lesson = await billing_service.charge_for_usage(
            db, student["user_id"], "deepseek", "deepseek-chat",
            usage={"input_tokens": 2_000, "output_tokens": 5_000}, source="lesson",
        )
        chat = await billing_service.charge_for_usage(
            db, student["user_id"], "deepseek", "deepseek-chat",
            usage={"input_tokens": 100_000, "output_tokens": 100_000}, source="chat",
        )
        await db.commit()

        assert lesson.kind == "usage" and lesson.feature == "lesson"
        assert lesson.amount_cents == -credits.FEATURE_CREDITS["lesson"] == -3
        assert chat.amount_cents == -1  # same price however long it was
        # Study OS's own record of what the provider charged: 2k*0.27 + 5k*1.10 micro-USD -> 1 cent.
        assert lesson.provider_cost_cents == 1
        public = lesson.public()
        assert public["credits"] == -3 and public["feature_name"] == "Lesson"
        for hidden in ("provider", "model_name", "input_tokens", "provider_cost_cents", "markup_cents"):
            assert hidden not in public

        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 100 - 3 - 1


def test_every_feature_price_covers_its_worst_case_on_deepseek():
    """Plan Step 4: each credit price stays above the most that feature
    can cost on deepseek-chat, from its output cap and a generous input."""
    worst = {  # (input tokens, output tokens)
        "chat": (6_000, 1_400 + 1_200),
        "chat_exam": (6_000, 2_240 + 1_200),
        "pdf_summary": (2_000, 1_800),
        "lesson": (3_000, 5_000),
        "go_deeper": (5_000, 700),
        "explain": (3_000, 1_500),
        "generation": (6_000, 2_350),
        "grading": (3_000, 300),
    }
    for source, (input_tokens, output_tokens) in worst.items():
        cost = pricing.estimate_cost_micro_usd("deepseek", "deepseek-chat", input_tokens, output_tokens)
        price = credits.credits_for(source) * credits.CREDIT_PRICE_CENTS * 10_000
        assert cost < price, (source, cost, price)
    assert credits.credits_for("something-new") == credits.DEFAULT_CREDITS > 0


# ---------------------------------------------------------------------------
# resolve_model_config_async — the "hosted" backend's real gating logic
# ---------------------------------------------------------------------------

async def test_resolve_hosted_requires_configured_key(student, monkeypatch):
    # No hosted_configured fixture here on purpose: with no key for the
    # server's hosted model this should fail clearly (503) rather than
    # silently using an empty key.
    monkeypatch.setenv("HOSTED_DEFAULT_PROVIDER", "deepseek")
    monkeypatch.setenv("HOSTED_DEEPSEEK_API_KEY", "")
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


async def test_resolve_hosted_requires_positive_balance(student, hosted_configured):
    async with async_session() as db:
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(
                ModelConfig(backend="hosted", hosted_provider="anthropic"),
                {"id": student["user_id"], "encryption_key": "unused"},
                db,
            )
        assert exc_info.value.status_code == 402


async def test_resolve_hosted_with_balance_uses_pooled_key_not_a_user_submitted_one(
    student, hosted_configured
):
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 1000, "test-topup-2")
        await db.commit()

    async with async_session() as db:
        # The student can't choose the provider: an old app's "anthropic"
        # is ignored and the server's hosted model is used.
        config = await resolve_model_config_async(
            ModelConfig(backend="hosted", hosted_provider="anthropic"),
            {"id": student["user_id"], "encryption_key": "unused"},
            db,
        )
        assert config["backend"] == "deepseek"
        assert config["hosted_provider"] == "deepseek"
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
        "backend": kwargs.get("backend", "deepseek"),
        "usage": {"input_tokens": 1_000, "output_tokens": 500},
    }


async def test_ask_text_with_hosted_backend_debits_wallet_end_to_end(
    client, student, hosted_configured, monkeypatch
):
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 100, "test-topup-3")
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
        assert wallet.balance_cents == 100 - 1

    usage_resp = await client.get("/api/v1/billing/usage", headers=student["headers"])
    assert usage_resp.status_code == 200, usage_resp.text
    entries = usage_resp.json()["entries"]
    assert len(entries) == 1
    assert entries[0]["credits"] == -1
    assert entries[0]["feature_name"] == "Chat answer"
    assert "provider" not in entries[0] and "model_name" not in entries[0]

    # The token meter shows credits for hosted calls, never their cost.
    meter = (await client.get("/api/v1/billing/ai-usage", headers=student["headers"])).json()
    assert meter["all_time"]["calls"] == 1
    assert meter["all_time"]["credits_used"] == 1
    assert meter["all_time"]["cost_micro_usd"] == 0
    assert meter["by_model"] == [{
        "provider": "Study OS", "model_name": "Study OS AI", "hosted": True, "calls": 1,
        "input_tokens": 1_000, "output_tokens": 500, "cost_micro_usd": None, "credits": 1,
    }]

    # An exam-level answer costs more.
    resp = await client.post(
        "/api/ask/text",
        json={"content": "hi again", "depth": "exam", "model_config": {"backend": "hosted"}},
        headers=student["headers"],
    )
    assert resp.status_code == 200, resp.text
    async with async_session() as db:
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 100 - 1 - 2


async def test_explain_concept_with_hosted_backend_debits_wallet_end_to_end(
    client, student, hosted_configured, monkeypatch
):
    """Same mechanism, second real call site (server/ai/moderator/router.py's
    /explain) — proves the write-back pattern wasn't special-cased to
    ask_text alone."""
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 100, "test-topup-4")
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

    monkeypatch.setattr(engines.model_router, "run", _fake_model_router_run)

    resp = await client.post(
        f"/api/v1/concepts/{concept_id}/explain",
        json={"model_config": {"backend": "hosted", "hosted_provider": "anthropic"}},
        headers=student["headers"],
    )
    assert resp.status_code == 200, resp.text

    async with async_session() as db:
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 100 - credits.FEATURE_CREDITS["explain"]


# ---------------------------------------------------------------------------
# App credits (2026-10-27): packs, prices, and the hidden allowance.
# ---------------------------------------------------------------------------

async def test_balance_shows_credits_prices_and_packs_and_a_pack_tops_up(client, student):
    body = (await client.get("/api/v1/billing/balance", headers=student["headers"])).json()
    assert body["credits"] == 0
    assert "balance_cents" not in body
    assert {"feature": "lesson", "name": "Lesson", "credits": 3} in body["prices"]
    assert all(price["credits"] > 0 for price in body["prices"])
    assert [pack["id"] for pack in body["packs"]] == ["small", "medium", "large"]

    resp = await client.post("/api/v1/billing/topups", json={"pack": "medium"}, headers=student["headers"])
    assert resp.status_code == 200, resp.text
    assert resp.json()["credits"] == 550
    body = (await client.get("/api/v1/billing/balance", headers=student["headers"])).json()
    assert body["credits"] == 550

    bad = await client.post("/api/v1/billing/topups", json={"pack": "huge"}, headers=student["headers"])
    assert bad.status_code == 422
    old_app = await client.post("/api/v1/billing/topups", json={"amount_cents": 500}, headers=student["headers"])
    assert old_app.status_code == 422


async def test_hidden_allowance_stops_hosted_calls_that_cost_more_than_their_credits(
    student, hosted_configured
):
    from server.domains.billing.models import AiUsage

    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 1_000, "test-allowance")
        await db.commit()
    user = {"id": student["user_id"], "encryption_key": "unused"}

    async with async_session() as db:
        # A normal month: 10 chat answers at 1 credit, each costing well under a cent.
        for _ in range(10):
            db.add(AiUsage(
                user_id=student["user_id"], provider="deepseek", model_name="deepseek-chat", source="chat",
                hosted=True, input_tokens=1_000, output_tokens=500, cost_micro_usd=820, credits=1,
            ))
        await db.commit()
        config = await resolve_model_config_async(ModelConfig(backend="hosted"), user, db)
        assert config["backend"] == "deepseek"

        # Then calls that cost Study OS far more than the credits they took.
        db.add(AiUsage(
            user_id=student["user_id"], provider="deepseek", model_name="deepseek-chat", source="chat",
            hosted=True, input_tokens=1_000_000, output_tokens=0, cost_micro_usd=270_000, credits=1,
        ))
        await db.commit()
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(ModelConfig(backend="hosted"), user, db)
        assert exc_info.value.status_code == 402
        assert exc_info.value.detail == billing_service.ALLOWANCE_USED_UP
        assert "$" not in exc_info.value.detail


async def test_hidden_allowance_has_a_monthly_ceiling(student, hosted_configured, monkeypatch):
    from server.domains.billing.models import AiUsage

    monkeypatch.setenv("HOSTED_MONTHLY_COST_CAP_USD", "0.05")
    get_settings.cache_clear()
    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 1_000, "test-ceiling")
        # Fairly priced calls (cost under their credits), but past the ceiling.
        for _ in range(20):
            db.add(AiUsage(
                user_id=student["user_id"], provider="deepseek", model_name="deepseek-chat", source="lesson",
                hosted=True, input_tokens=2_000, output_tokens=2_000, cost_micro_usd=2_740, credits=3,
            ))
        await db.commit()
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(ModelConfig(backend="hosted"), {"id": student["user_id"]}, db)
        assert exc_info.value.status_code == 402


async def test_out_of_credits_says_so_without_dollars(student, hosted_configured):
    async with async_session() as db:
        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(ModelConfig(backend="hosted"), {"id": student["user_id"]}, db)
        assert exc_info.value.status_code == 402
        assert "credits" in exc_info.value.detail and "$" not in exc_info.value.detail


# ---------------------------------------------------------------------------
# Token meter (2026-10-20) — every provider call is logged per student, BYOK
# included; the summary endpoint only ever shows the caller's own rows.
# ---------------------------------------------------------------------------

def test_estimate_cost_is_none_for_an_unpriced_model_not_zero():
    assert pricing.estimate_cost_micro_usd("openai", "some-custom-model", 1000, 1000) is None
    # gpt-4o-mini: 1M in @ $0.15 + 1M out @ $0.60 = $0.75 = 750,000 micro-USD.
    assert pricing.estimate_cost_micro_usd("openai", "gpt-4o-mini", 1_000_000, 1_000_000) == 750_000


async def test_record_ai_usage_logs_byok_without_touching_the_wallet(student):
    async with async_session() as db:
        row = await billing_service.record_ai_usage(
            db, student["user_id"], {"backend": "openai", "api_key": "k"},
            {"input_tokens": 2000, "output_tokens": 500}, "chat",
        )
        await billing_service.record_ai_usage(
            db, student["user_id"], {"backend": "openai", "api_key": "k", "model_name": "custom-x"},
            {"input_tokens": 10, "output_tokens": 10}, "chat",
        )
        none_row = await billing_service.record_ai_usage(db, student["user_id"], {"backend": "local"}, None, "chat")
        await db.commit()
        assert none_row is None
        assert row.model_name == "gpt-4o-mini" and row.hosted is False
        assert row.cost_micro_usd == 600  # 2000 * 0.15 + 500 * 0.60
        wallet = await billing_service.get_or_create_wallet(db, student["user_id"])
        assert wallet.balance_cents == 0


async def test_ai_usage_summary_totals_and_partial_pricing(client, student):
    async with async_session() as db:
        for _ in range(2):
            await billing_service.record_ai_usage(
                db, student["user_id"], {"backend": "openai", "api_key": "k"},
                {"input_tokens": 2000, "output_tokens": 500}, "chat",
            )
        await billing_service.record_ai_usage(
            db, student["user_id"], {"backend": "openai", "api_key": "k", "model_name": "custom-x"},
            {"input_tokens": 10, "output_tokens": 10}, "grading",
        )
        await db.commit()

    resp = await client.get("/api/v1/billing/ai-usage", headers=student["headers"])
    assert resp.status_code == 200, resp.text
    body = resp.json()
    for period in ("today", "last_30_days", "all_time"):
        assert body[period] == {
            "calls": 3, "input_tokens": 4010, "output_tokens": 1010,
            "cost_micro_usd": 1200, "unpriced_calls": 1, "credits_used": 0,
        }
    models = {m["model_name"]: m for m in body["by_model"]}
    assert models["gpt-4o-mini"]["calls"] == 2 and models["gpt-4o-mini"]["cost_micro_usd"] == 1200
    assert models["custom-x"]["cost_micro_usd"] is None


async def test_ai_usage_summary_never_shows_another_students_usage(client, student):
    async with async_session() as db:
        await billing_service.record_ai_usage(
            db, student["user_id"], {"backend": "openai", "api_key": "k"},
            {"input_tokens": 2000, "output_tokens": 500}, "chat",
        )
        await db.commit()

    other_email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    try:
        resp = await client.get(
            "/api/v1/billing/ai-usage", headers={"Authorization": f"Bearer {signup.json()['token']}"}
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["all_time"]["calls"] == 0
        assert resp.json()["by_model"] == []
    finally:
        async with async_session() as db:
            await db.execute(delete(User).where(User.email == other_email))
            await db.commit()


async def test_ai_usage_requires_login(client):
    resp = await client.get("/api/v1/billing/ai-usage")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Monthly spending limit (2026-10-20) — the student's own cap, enforced on
# every paid (non-local) call before it's made.
# ---------------------------------------------------------------------------

async def test_spend_limit_blocks_paid_calls_once_reached_but_never_local(client, student):
    resp = await client.put(
        "/api/v1/billing/ai-usage/limit", json={"monthly_limit_cents": 1}, headers=student["headers"]
    )
    assert resp.status_code == 200, resp.text

    async with async_session() as db:
        # Under the cap: a BYOK call resolves (no key decryption needed to
        # pass the limit check, so check the limit directly).
        await billing_service.enforce_spend_limit(db, student["user_id"])
        # 1,000,000 in-tokens of gpt-4o-mini = $0.15, past the $0.01 cap.
        await billing_service.record_ai_usage(
            db, student["user_id"], {"backend": "openai", "api_key": "k"},
            {"input_tokens": 1_000_000, "output_tokens": 0}, "chat",
        )
        await db.commit()

        with pytest.raises(Exception) as exc_info:
            await resolve_model_config_async(
                ModelConfig(backend="openai", encrypted_api_key="x"), {"id": student["user_id"]}, db
            )
        assert getattr(exc_info.value, "status_code", None) == 402
        assert "monthly AI spending limit of $0.01" in exc_info.value.detail

        # The free local model is never blocked.
        local = await resolve_model_config_async(ModelConfig(backend="local"), {"id": student["user_id"]}, db)
        assert local["backend"] == "local"

    meter = (await client.get("/api/v1/billing/ai-usage", headers=student["headers"])).json()
    assert meter["monthly_limit_cents"] == 1
    assert meter["this_month"]["cost_micro_usd"] == 150_000

    # Removing the cap unblocks.
    resp = await client.put(
        "/api/v1/billing/ai-usage/limit", json={"monthly_limit_cents": None}, headers=student["headers"]
    )
    assert resp.status_code == 200
    async with async_session() as db:
        await billing_service.enforce_spend_limit(db, student["user_id"])


async def test_spend_limit_rejects_zero_and_absurd_values(client, student):
    for bad in (0, -5, 100_001):
        resp = await client.put(
            "/api/v1/billing/ai-usage/limit", json={"monthly_limit_cents": bad}, headers=student["headers"]
        )
        assert resp.status_code == 422, bad


async def test_two_charges_finishing_together_are_both_kept(student):
    """charge_for_usage reads the balance and writes it back; without the
    row lock two requests finishing at once both read the same balance and
    one charge was lost."""
    import asyncio

    from sqlalchemy import select

    from server.domains.billing.models import WalletBalance

    async with async_session() as db:
        await billing_service.credit_topup(db, student["user_id"], 1_000, "test-race")
        await db.commit()

    usage = {"input_tokens": 1_000, "output_tokens": 0}
    one_charge = credits.credits_for("lesson")

    async def charge():
        async with async_session() as db:
            await billing_service.charge_for_usage(
                db, student["user_id"], "deepseek", "deepseek-chat", usage, source="lesson"
            )
            await asyncio.sleep(0.5)  # keep the transaction open so the two overlap
            await db.commit()

    await asyncio.gather(charge(), charge())
    async with async_session() as db:
        balance = await db.scalar(
            select(WalletBalance.balance_cents).where(WalletBalance.user_id == student["user_id"])
        )
    assert balance == 1_000 - 2 * one_charge


async def test_meter_today_is_the_students_own_day(client, student):
    import datetime

    from server.domains.billing.models import AiUsage

    now = datetime.datetime.now(datetime.timezone.utc)
    # An offset that puts the student's local midnight 30 minutes ago.
    offset = (30 - (now.hour * 60 + now.minute)) % (24 * 60)
    if offset > 14 * 60:
        offset -= 24 * 60
    async with async_session() as db:
        for minutes_ago in (60, 1):  # local yesterday, then local today
            db.add(AiUsage(
                user_id=student["user_id"], provider="openai", model_name="gpt-4o-mini", source="ask",
                hosted=False, input_tokens=10, output_tokens=10, cost_micro_usd=1,
                created_at=now - datetime.timedelta(minutes=minutes_ago),
            ))
        await db.commit()

    meter = (await client.get(
        f"/api/v1/billing/ai-usage?tz_offset_minutes={offset}", headers=student["headers"]
    )).json()
    assert meter["today"]["calls"] == 1
    assert meter["all_time"]["calls"] == 2
