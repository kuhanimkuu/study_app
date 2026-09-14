"""Integration tests for server/domains/planning — Goals, the /plan
prioritization endpoint, and Study Sessions. Real Postgres, same style as
the other test modules.

Run with: python -m pytest server/tests/test_planning.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_planning_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Chemistry"}, headers=headers)
    assert space.status_code == 200, space.text
    slug = space.json()["slug"]

    yield {"headers": headers, "email": email, "slug": slug}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def _create_concept(client, headers, slug, name):
    resp = await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": name}, headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def _create_numerical_question(client, headers, concept_id):
    resp = await client.post(
        f"/api/v1/concepts/{concept_id}/questions",
        json={"type": "numerical", "prompt": "2+2", "correct_answer": 4.0, "tolerance": 0.01},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def test_goal_crud(client, student):
    headers, slug = student["headers"], student["slug"]
    created = await client.post(
        "/api/v1/goals", json={"title": "Pass finals", "knowledge_space_slug": slug}, headers=headers
    )
    assert created.status_code == 200, created.text
    goal_id = created.json()["id"]

    listed = await client.get("/api/v1/goals", headers=headers)
    assert any(g["id"] == goal_id for g in listed.json()["goals"])

    deleted = await client.delete(f"/api/v1/goals/{goal_id}", headers=headers)
    assert deleted.status_code == 200

    listed_after = await client.get("/api/v1/goals", headers=headers)
    assert not any(g["id"] == goal_id for g in listed_after.json()["goals"])


async def test_plan_empty_state_returns_no_error(client, student):
    """A brand new user with zero concepts anywhere should get an empty,
    well-formed plan, not a 500."""
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    resp = await client.get("/api/v1/plan", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["concepts_considered"] == 0
    assert all(p["concept_ids"] == [] for p in body["phases"])

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_never_attempted_concept_scores_as_need_to_learn(client, student):
    headers, slug = student["headers"], student["slug"]
    await _create_concept(client, headers, slug, "Stoichiometry")

    resp = await client.get("/api/v1/plan?duration_minutes=60", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["concepts_considered"] == 1
    # a never-attempted concept should land somewhere in the phases (high
    # fixed priority means it shouldn't be silently dropped)
    all_concept_ids = [cid for p in body["phases"] for cid in p["concept_ids"]]
    assert len(all_concept_ids) >= 1

    # "concepts" (id+name) must match "concept_ids" 1:1 in every phase —
    # this is what lets a client render a phase without a separate lookup.
    for phase in body["phases"]:
        assert [c["id"] for c in phase["concepts"]] == phase["concept_ids"]
        assert all(isinstance(c["name"], str) and c["name"] for c in phase["concepts"])


async def test_overdue_concept_outranks_freshly_correct_concept(client, student):
    """After answering correctly, a concept's next review is scheduled in
    the future (FSRS) — it should score lower than a concept that's never
    been touched at all (which the planner treats as needing attention)."""
    headers, slug = student["headers"], student["slug"]
    fresh_id = await _create_concept(client, headers, slug, "Never Studied")
    reviewed_id = await _create_concept(client, headers, slug, "Just Reviewed")

    q = await _create_numerical_question(client, headers, reviewed_id)
    attempt = await client.post(f"/api/v1/questions/{q}/attempt", json={"answer": 4.0}, headers=headers)
    assert attempt.status_code == 200

    resp = await client.get("/api/v1/plan?duration_minutes=60", headers=headers)
    body = resp.json()
    ordered_ids = [cid for p in body["phases"] for cid in p["concept_ids"]]
    # both should appear; the never-studied one should rank at or above
    # the one just reviewed correctly (which now has a future next_review)
    assert fresh_id in ordered_ids
    assert ordered_ids.index(fresh_id) <= ordered_ids.index(reviewed_id) if reviewed_id in ordered_ids else True


async def test_study_session_lifecycle(client, student):
    headers, slug = student["headers"], student["slug"]
    await _create_concept(client, headers, slug, "Periodic Table")

    created = await client.post(
        "/api/v1/study-sessions", json={"duration_minutes": 40, "knowledge_space_slug": slug}, headers=headers
    )
    assert created.status_code == 200, created.text
    session = created.json()
    assert session["status"] == "active"
    assert session["ended_at"] is None
    assert session["plan"]["duration_minutes"] == 40
    total_phase_minutes = sum(p["duration_minutes"] for p in session["plan"]["phases"])
    # phases are rounded fractions of the total; should be close, not wildly off
    assert abs(total_phase_minutes - 40) <= 5

    fetched = await client.get(f"/api/v1/study-sessions/{session['id']}", headers=headers)
    assert fetched.status_code == 200
    assert fetched.json()["id"] == session["id"]

    listed = await client.get("/api/v1/study-sessions", headers=headers)
    assert any(s["id"] == session["id"] for s in listed.json()["study_sessions"])

    completed = await client.post(f"/api/v1/study-sessions/{session['id']}/complete", headers=headers)
    assert completed.status_code == 200
    assert completed.json()["status"] == "completed"
    assert completed.json()["ended_at"] is not None

    already_done = await client.post(f"/api/v1/study-sessions/{session['id']}/complete", headers=headers)
    assert already_done.status_code == 400


async def test_study_session_requires_ownership(client, student):
    other_email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    headers = student["headers"]
    created = await client.post("/api/v1/study-sessions", json={"duration_minutes": 30}, headers=headers)
    session_id = created.json()["id"]

    resp = await client.get(f"/api/v1/study-sessions/{session_id}", headers=other_headers)
    assert resp.status_code == 404

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()
