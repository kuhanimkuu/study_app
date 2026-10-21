"""AI setup's "Test and save" (2026-10-21): one tiny call with the key about
to be saved, and a plain-words reason when it fails. The provider is faked."""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server import crypto, engines
from server.db.session import async_session
from server.domains.identity.models import User
from server.routers.ai_check import explain_failure


class _ProviderError(Exception):
    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


@pytest.fixture
async def student(client):
    email = f"pytest_aicheck_{uuid.uuid4().hex[:10]}@example.com"
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    body = resp.json()
    config = {
        "backend": "deepseek",
        "encrypted_api_key": crypto.encrypt_for_user(body["user"]["encryption_key"], "sk-test-not-real"),
    }
    yield {"headers": {"Authorization": f"Bearer {body['token']}"}, "config": config}
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_a_working_key(client, student, monkeypatch):
    seen = {}

    async def fake(**kwargs):
        seen.update(kwargs)
        return {"text": "OK", "usage": None}

    monkeypatch.setattr(engines.model_router, "run", fake)
    resp = await client.post("/api/v1/ai/check", json={"model_config": student["config"]}, headers=student["headers"])
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"ok": True, "provider": "DeepSeek"}
    assert seen["api_key"] == "sk-test-not-real" and seen["max_tokens"] == 5


@pytest.mark.parametrize(
    "error, expected",
    [
        (_ProviderError("Authentication Fails, Your api key is invalid", 401), "didn't accept that key"),
        (_ProviderError("Insufficient Balance", 402), "no credit yet"),
        (_ProviderError("You exceeded your current quota (insufficient_quota)", 429), "no credit yet"),
        (_ProviderError("Rate limit reached", 429), "Wait a minute"),
    ],
)
async def test_failures_say_what_to_do(client, student, monkeypatch, error, expected):
    async def fake(**kwargs):
        raise error

    monkeypatch.setattr(engines.model_router, "run", fake)
    resp = await client.post("/api/v1/ai/check", json={"model_config": student["config"]}, headers=student["headers"])
    assert resp.status_code == 400
    assert expected in resp.json()["detail"]


async def test_the_free_local_backend_needs_a_provider(client, student):
    resp = await client.post("/api/v1/ai/check", json={"model_config": {"backend": "local"}}, headers=student["headers"])
    assert resp.status_code == 400 and "Choose a provider" in resp.json()["detail"]


def test_unknown_errors_pass_through():
    assert explain_failure("openai", RuntimeError("boom")) == "OpenAI didn't answer: boom"
