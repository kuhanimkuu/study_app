"""Idempotency keys (2026-10-27): a repeated request — retry after a lost
connection, a timeout, a double tap — is done once. See core/idempotency.py."""
from __future__ import annotations

import asyncio
import json
import uuid

import pytest
from sqlalchemy import delete, func, select

from server import engines
from server.db.session import async_session
from server.domains.identity.models import User
from server.domains.tutor.models import Lesson

LESSON = {
    "title": "Osmosis",
    "steps": [
        {"heading": "a", "explanation": "b", "check": {"type": "true_false", "prompt": "p1", "answer": "true", "why": "w"}},
        {"heading": "c", "explanation": "d", "check": {"type": "true_false", "prompt": "p2", "answer": "false", "why": "w"}},
    ],
    "worked_example": None,
    "recap": [],
}


async def _signup(client) -> tuple[str, dict]:
    email = f"pytest_idem_{uuid.uuid4().hex[:10]}@example.com"
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    return email, {"Authorization": f"Bearer {resp.json()['token']}"}


@pytest.fixture
async def student(client):
    email, headers = await _signup(client)
    yield headers
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


def _key() -> dict:
    return {"Idempotency-Key": str(uuid.uuid4())}


async def test_a_repeated_create_is_done_once(client, student):
    key = _key()
    first = await client.post("/api/projects", json={"display_name": "Chemistry"}, headers={**student, **key})
    again = await client.post("/api/projects", json={"display_name": "Chemistry"}, headers={**student, **key})
    assert first.status_code == again.status_code == 200
    assert again.json() == first.json()
    assert again.headers["idempotent-replayed"] == "true"
    assert "idempotent-replayed" not in first.headers
    # Without the key the same request runs — and here the app's own rule refuses it.
    third = await client.post("/api/projects", json={"display_name": "Chemistry"}, headers=student)
    assert third.status_code == 409


async def test_failures_are_not_remembered(client, student):
    key = _key()
    missing = await client.post("/api/v1/knowledge-spaces/nope/notes", json={"title": "t", "content": "c"}, headers={**student, **key})
    assert missing.status_code == 404
    await client.post("/api/projects", json={"display_name": "nope"}, headers=student)
    retried = await client.post("/api/v1/knowledge-spaces/nope/notes", json={"title": "t", "content": "c"}, headers={**student, **key})
    assert retried.status_code == 200, retried.text  # ran again, now that the subject exists


async def test_keys_belong_to_one_account(client, student):
    key = _key()
    mine = await client.post("/api/projects", json={"display_name": "Mine"}, headers={**student, **key})
    email, other = await _signup(client)
    try:
        theirs = await client.post("/api/projects", json={"display_name": "Theirs"}, headers={**other, **key})
        assert theirs.status_code == 200 and theirs.json()["display_name"] == "Theirs"
        assert "idempotent-replayed" not in theirs.headers
        assert mine.json()["display_name"] == "Mine"
    finally:
        async with async_session() as db:
            await db.execute(delete(User).where(User.email == email))
            await db.commit()


async def test_a_double_tap_while_the_first_runs(client, student, monkeypatch):
    calls = 0

    async def slow_model(**kwargs):
        nonlocal calls
        calls += 1
        await asyncio.sleep(0.3)
        return {"text": json.dumps(LESSON), "tier": "tiny", "backend": "local"}

    monkeypatch.setattr(engines.model_router, "run", slow_model)
    key = _key()
    a, b = await asyncio.gather(
        client.post("/api/v1/lessons", json={"topic": "osmosis"}, headers={**student, **key}),
        client.post("/api/v1/lessons", json={"topic": "osmosis"}, headers={**student, **key}),
    )
    assert sorted([a.status_code, b.status_code]) == [200, 409]
    assert calls == 1  # one AI call, one charge
    later = await client.post("/api/v1/lessons", json={"topic": "osmosis"}, headers={**student, **key})
    assert later.status_code == 200 and later.headers["idempotent-replayed"] == "true"
    user_id = (await client.get("/api/auth/me", headers=student)).json()["id"]
    async with async_session() as db:
        count = await db.scalar(select(func.count(Lesson.id)).where(Lesson.user_id == user_id))
    assert count == 1  # one lesson, not two


async def test_a_chat_retry_gets_the_same_answer_without_a_second_ai_call(client, student, monkeypatch):
    calls = 0

    async def model(**kwargs):
        nonlocal calls
        calls += 1
        return {"text": f"Answer {calls}", "tier": "tiny", "backend": "local"}

    monkeypatch.setattr(engines.model_router, "run", model)
    key = _key()
    body = {"content": "what is osmosis", "tutor_mode": False}
    first = await client.post("/api/ask/text", json=body, headers={**student, **key})
    again = await client.post("/api/ask/text", json=body, headers={**student, **key})
    assert first.json()["blocks"][0]["content"] == again.json()["blocks"][0]["content"] == "Answer 1"
    assert calls == 1


async def test_misuse_of_a_key(client, student):
    key = _key()
    await client.post("/api/projects", json={"display_name": "Physics"}, headers={**student, **key})
    other_route = await client.post("/api/v1/goals", json={"title": "x"}, headers={**student, **key})
    assert other_route.status_code == 422
    bad = await client.post("/api/projects", json={"display_name": "x"}, headers={**student, "Idempotency-Key": "short"})
    assert bad.status_code == 400


async def test_requests_without_a_key_are_untouched(client, student):
    a = await client.post("/api/v1/goals", json={"title": "Exam"}, headers=student)
    b = await client.post("/api/v1/goals", json={"title": "Exam"}, headers=student)
    assert a.status_code == b.status_code == 200 and a.json()["id"] != b.json()["id"]
