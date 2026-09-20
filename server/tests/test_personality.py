"""Integration tests for server/ai/personality — get-or-create defaults,
partial PATCH updates, and validation. Real Postgres, same style as the
other test modules.

Run with: python -m pytest server/tests/test_personality.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_personality_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    yield {"headers": headers, "email": email}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_get_returns_sensible_defaults_on_first_access(client, student):
    resp = await client.get("/api/v1/personality", headers=student["headers"])
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # not an error, not nulls — real, sensible defaults matching blueprint's own example
    assert body["tone"] == "friendly"
    assert body["formality"] == "casual"
    assert body["verbosity"] == "moderate"
    assert body["teaching_style"] == "example_first"
    for field in ("humor", "encouragement", "directness", "challenge_level"):
        assert 0.0 <= body[field] <= 1.0


async def test_get_is_idempotent_not_recreated_each_time(client, student):
    first = await client.get("/api/v1/personality", headers=student["headers"])
    second = await client.get("/api/v1/personality", headers=student["headers"])
    assert first.json()["updated_at"] == second.json()["updated_at"]


async def test_patch_updates_only_supplied_fields(client, student):
    headers = student["headers"]
    await client.get("/api/v1/personality", headers=headers)  # establish defaults

    patched = await client.patch("/api/v1/personality", json={"humor": 0.9, "tone": "playful"}, headers=headers)
    assert patched.status_code == 200, patched.text
    body = patched.json()
    assert body["humor"] == 0.9
    assert body["tone"] == "playful"
    # untouched fields keep their defaults
    assert body["formality"] == "casual"
    assert body["verbosity"] == "moderate"

    refetched = await client.get("/api/v1/personality", headers=headers)
    assert refetched.json()["humor"] == 0.9
    assert refetched.json()["tone"] == "playful"


async def test_patch_rejects_invalid_categorical_value(client, student):
    resp = await client.patch("/api/v1/personality", json={"tone": "sarcastic"}, headers=student["headers"])
    assert resp.status_code == 400


@pytest.mark.parametrize("bad_value", [-0.1, 1.1, 2.0])
async def test_patch_rejects_numeric_out_of_range(client, student, bad_value):
    resp = await client.patch("/api/v1/personality", json={"humor": bad_value}, headers=student["headers"])
    assert resp.status_code == 400


async def test_personality_requires_auth(client):
    resp = await client.get("/api/v1/personality")
    assert resp.status_code == 401
