"""Integration tests for server/ai/memory — explicit memory CRUD, episodic
memory auto-creation at its two real trigger points, and student_state's
memory retrieval. Real Postgres, same style as the other test modules.

Run with: python -m pytest server/tests/test_memory.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.ai.moderator.student_state import get_student_state
from server.db.session import async_session
from server.domains.identity.models import User
from server.domains.learning.models import Concept


def _unique_email() -> str:
    return f"pytest_memory_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Geography"}, headers=headers)
    slug = space.json()["slug"]
    concept = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": "Plate Tectonics"}, headers=headers
    )

    yield {
        "headers": headers,
        "email": email,
        "user_id": signup.json()["user"]["id"],
        "slug": slug,
        "concept_id": concept.json()["id"],
    }

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_explicit_memory_crud(client, student):
    headers = student["headers"]
    created = await client.post(
        "/api/v1/memories", json={"key": "explanation_style", "value": "prefers examples over theory"}, headers=headers
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["type"] == "explicit"
    assert body["source"] == "user_stated"
    assert body["confidence"] == 1.0
    memory_id = body["id"]

    listed = await client.get("/api/v1/memories", headers=headers)
    assert any(m["id"] == memory_id for m in listed.json()["memories"])

    filtered = await client.get("/api/v1/memories?type=explicit", headers=headers)
    assert any(m["id"] == memory_id for m in filtered.json()["memories"])

    deleted = await client.delete(f"/api/v1/memories/{memory_id}", headers=headers)
    assert deleted.status_code == 200
    after = await client.get("/api/v1/memories", headers=headers)
    assert not any(m["id"] == memory_id for m in after.json()["memories"])


async def test_explicit_memory_ignores_client_supplied_source_and_confidence(client, student):
    """Security-relevant, not just a happy-path check: a client must not
    be able to forge a "system_derived", high-confidence entry by just
    sending those fields in the request body."""
    headers = student["headers"]
    resp = await client.post(
        "/api/v1/memories",
        json={
            "key": "sneaky",
            "value": "x",
            "source": "system_derived",
            "confidence": 0.99,
            "type": "episodic",
        },
        headers=headers,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["type"] == "explicit"
    assert body["source"] == "user_stated"
    assert body["confidence"] == 1.0


async def test_memory_requires_ownership(client, student):
    other_email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    headers = student["headers"]
    created = await client.post("/api/v1/memories", json={"key": "k", "value": "v"}, headers=headers)
    memory_id = created.json()["id"]

    resp = await client.delete(f"/api/v1/memories/{memory_id}", headers=other_headers)
    assert resp.status_code == 404

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()


async def test_invalid_type_filter_rejected(client, student):
    resp = await client.get("/api/v1/memories?type=nonsense", headers=student["headers"])
    assert resp.status_code == 400


async def test_episodic_memory_created_on_misconception_resolution(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    q = await client.post(
        f"/api/v1/concepts/{concept_id}/questions",
        json={"type": "true_false", "prompt": "test", "correct_answer": "true"},
        headers=headers,
    )
    qid = q.json()["id"]

    for _ in range(3):
        await client.post(f"/api/v1/questions/{qid}/attempt", json={"answer": "false"}, headers=headers)

    before = await client.get("/api/v1/memories?type=episodic", headers=headers)
    assert not any(m["value"].get("event") == "misconception_resolved" for m in before.json()["memories"])

    for _ in range(2):
        await client.post(f"/api/v1/questions/{qid}/attempt", json={"answer": "true"}, headers=headers)

    after = await client.get("/api/v1/memories?type=episodic", headers=headers)
    resolved = [m for m in after.json()["memories"] if m["value"].get("event") == "misconception_resolved"]
    assert len(resolved) == 1
    assert resolved[0]["source"] == "system_derived"
    assert resolved[0]["value"]["concept_id"] == concept_id


async def test_episodic_memory_created_once_on_mastery_crossing_not_on_every_subsequent_correct(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    q = await client.post(
        f"/api/v1/concepts/{concept_id}/questions",
        json={"type": "true_false", "prompt": "test", "correct_answer": "true"},
        headers=headers,
    )
    qid = q.json()["id"]

    # several correct answers to push mastery_score up past the threshold
    for _ in range(4):
        await client.post(f"/api/v1/questions/{qid}/attempt", json={"answer": "true"}, headers=headers)

    after_first_batch = await client.get("/api/v1/memories?type=episodic", headers=headers)
    mastered_events = [m for m in after_first_batch.json()["memories"] if m["value"].get("event") == "concept_mastered"]
    assert len(mastered_events) == 1, "should fire exactly once when crossing the threshold"

    # more correct answers after already being mastered — must NOT refire
    for _ in range(3):
        await client.post(f"/api/v1/questions/{qid}/attempt", json={"answer": "true"}, headers=headers)

    after_more = await client.get("/api/v1/memories?type=episodic", headers=headers)
    mastered_events_after = [m for m in after_more.json()["memories"] if m["value"].get("event") == "concept_mastered"]
    assert len(mastered_events_after) == 1, "must not refire on subsequent correct attempts after already crossing"


async def test_student_state_includes_explicit_memories(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    await client.post(
        "/api/v1/memories", json={"key": "explanation_style", "value": "prefers short answers"}, headers=headers
    )

    async with async_session() as db:
        concept = await db.get(Concept, concept_id)
        state = await get_student_state(db, student["user_id"], concept)

    assert len(state.relevant_memories) == 1
    assert state.relevant_memories[0]["key"] == "explanation_style"
    assert state.relevant_memories[0]["value"] == "prefers short answers"
