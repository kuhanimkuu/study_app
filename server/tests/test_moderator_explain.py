"""Tests for server/ai/moderator — get_student_state's shape and the
explain endpoint's ownership enforcement. Deliberately does NOT call the
real LLM here (that's exercised once in a real-HTTP smoke test instead,
same split as test_learning_and_assessment.py's short_answer grading) —
these stay fast and deterministic.

decide_depth's boundary cases are unit-tested standalone (no DB/LLM
needed), not duplicated here.

Run with: python -m pytest server/tests/test_moderator_explain.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.ai.moderator.server_events import get_server_side_events
from server.ai.moderator.student_state import get_student_state
from server.db.session import async_session
from server.domains.identity.models import User
from server.domains.learning.models import Concept


def _unique_email() -> str:
    return f"pytest_explain_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Physics"}, headers=headers)
    slug = space.json()["slug"]
    concept = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/concepts",
        json={"name": "Newton's First Law", "description": "An object in motion stays in motion."},
        headers=headers,
    )
    concept_id = concept.json()["id"]

    yield {"headers": headers, "email": email, "user_id": signup.json()["user"]["id"], "concept_id": concept_id}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_student_state_for_never_attempted_concept(client, student):
    async with async_session() as db:
        concept = await db.get(Concept, student["concept_id"])
        state = await get_student_state(db, student["user_id"], concept)

    assert state.attempts == 0
    assert state.mastery == 0.0
    assert state.retrievability is None
    assert state.has_active_misconception is False
    assert state.concept_name == "Newton's First Law"
    assert state.concept_description == "An object in motion stays in motion."


async def test_student_state_after_a_correct_attempt(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    q = await client.post(
        f"/api/v1/concepts/{concept_id}/questions",
        json={"type": "true_false", "prompt": "Inertia is real", "correct_answer": "true"},
        headers=headers,
    )
    await client.post(f"/api/v1/questions/{q.json()['id']}/attempt", json={"answer": "true"}, headers=headers)

    async with async_session() as db:
        concept = await db.get(Concept, concept_id)
        state = await get_student_state(db, student["user_id"], concept)

    assert state.attempts == 1
    assert state.mastery > 0.0
    assert state.retrievability is not None


async def test_explain_endpoint_requires_ownership(client, student):
    other_email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    resp = await client.post(f"/api/v1/concepts/{student['concept_id']}/explain", headers=other_headers)
    assert resp.status_code == 404

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()


async def test_explain_endpoint_requires_auth(client, student):
    resp = await client.post(f"/api/v1/concepts/{student['concept_id']}/explain")
    assert resp.status_code == 401


async def test_explain_nonexistent_concept_404s(client, student):
    resp = await client.post("/api/v1/concepts/999999999/explain", headers=student["headers"])
    assert resp.status_code == 404


async def test_server_side_events_empty_for_new_user(client, student):
    async with async_session() as db:
        events = await get_server_side_events(db, student["user_id"])
    assert events == []


async def test_server_side_events_reflect_real_mastery_and_misconceptions(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    q = await client.post(
        f"/api/v1/concepts/{concept_id}/questions",
        json={"type": "true_false", "prompt": "test", "correct_answer": "true"},
        headers=headers,
    )
    qid = q.json()["id"]

    for _ in range(3):
        await client.post(f"/api/v1/questions/{qid}/attempt", json={"answer": "false"}, headers=headers)

    async with async_session() as db:
        events = await get_server_side_events(db, student["user_id"])

    # Two separate entries are expected here, not a bug: a Mastery-derived
    # one (accuracy/retrievability-based) and a Misconception-derived one
    # (the repeated-error signal) — get_server_side_events doesn't merge
    # them, it surfaces both real signals as-is.
    matching = [e for e in events if e["topic"] == "Newton's First Law"]
    assert len(matching) == 2

    mastery_event = next(e for e in matching if "misconception" not in e["labels"])
    assert mastery_event["score"] < 0.5, (
        "3 consecutive wrong answers should score well below 0.5 — if this "
        "fails, learning/scheduler.py's mastery_score weighting regressed "
        "back to the retrievability-heavy blend that scored this ~0.6"
    )
    assert "struggle" in mastery_event["labels"]

    misconception_event = next(e for e in matching if "misconception" in e["labels"])
    assert misconception_event["score"] == 0.0
    assert "struggle" in misconception_event["labels"]
    assert misconception_event["timestamp"] is not None
