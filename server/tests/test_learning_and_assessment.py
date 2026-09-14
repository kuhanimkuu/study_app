"""Integration tests for server/domains/learning and server/domains/assessment
— Concepts, FSRS-based Mastery, Question grading (deterministic types only;
short_answer needs a live LLM call and is exercised separately, not here,
to keep this suite fast), and misconception detection.

Run with: python -m pytest server/tests/test_learning_and_assessment.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_learning_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    """A signed-up user with one Knowledge Space and one Concept already
    created via the real HTTP API. Deletes the user row afterward
    (cascades through knowledge_spaces -> concepts -> mastery/questions/
    question_attempts/misconceptions via their FKs)."""
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Algebra"}, headers=headers)
    assert space.status_code == 200, space.text
    slug = space.json()["slug"]

    concept = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/concepts",
        json={"name": "Linear Equations", "description": "ax + b = c"},
        headers=headers,
    )
    assert concept.status_code == 200, concept.text

    yield {"headers": headers, "email": email, "slug": slug, "concept_id": concept.json()["id"]}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def _create_question(client, headers, concept_id, **kwargs):
    resp = await client.post(f"/api/v1/concepts/{concept_id}/questions", json=kwargs, headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


async def test_concept_crud(client, student):
    headers, slug = student["headers"], student["slug"]
    listed = await client.get(f"/api/v1/knowledge-spaces/{slug}/concepts", headers=headers)
    assert listed.status_code == 200
    names = [c["name"] for c in listed.json()["concepts"]]
    assert "Linear Equations" in names


async def test_mastery_starts_at_zero_before_any_attempt(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    resp = await client.get(f"/api/v1/concepts/{concept_id}/mastery", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["mastery"] == 0.0
    assert body["attempts"] == 0
    assert body["next_review"] is None


@pytest.mark.parametrize(
    "type_,create_kwargs,correct_answer,wrong_answer",
    [
        ("mcq", {"options": ["2", "3", "4"], "correct_answer": "3"}, "3", "2"),
        ("true_false", {"correct_answer": "true"}, "true", "false"),
        ("fill_in_blank", {"correct_answer": "mitochondria"}, "Mitochondria", "nucleus"),
        ("multi_select", {"options": ["a", "b", "c"], "correct_answer": ["a", "c"]}, ["c", "a"], ["a", "b"]),
        ("numerical", {"correct_answer": 4.0, "tolerance": 0.01}, 4.005, 5.0),
        ("equation", {"correct_answer": "x + 1"}, "1 + x", "x + 2"),
        ("matching", {"correct_answer": {"A": "1", "B": "2"}}, {"B": "2", "A": "1"}, {"A": "2", "B": "1"}),
        ("ordering", {"correct_answer": ["first", "second", "third"]}, ["first", "second", "third"], ["second", "first", "third"]),
    ],
)
async def test_deterministic_grading_per_type(client, student, type_, create_kwargs, correct_answer, wrong_answer):
    headers, concept_id = student["headers"], student["concept_id"]
    question = await _create_question(
        client, headers, concept_id, type=type_, prompt=f"test {type_} question", **create_kwargs
    )
    assert question["correct_answer"] == create_kwargs["correct_answer"]

    ok = await client.post(
        f"/api/v1/questions/{question['id']}/attempt", json={"answer": correct_answer}, headers=headers
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["correct"] is True
    assert ok.json()["evaluated_by"] == "deterministic"

    bad = await client.post(
        f"/api/v1/questions/{question['id']}/attempt", json={"answer": wrong_answer}, headers=headers
    )
    assert bad.status_code == 200
    assert bad.json()["correct"] is False


async def test_attempt_updates_mastery_and_schedules_next_review(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    question = await _create_question(
        client, headers, concept_id, type="numerical", prompt="2+2", correct_answer=4.0, tolerance=0.01
    )

    resp = await client.post(f"/api/v1/questions/{question['id']}/attempt", json={"answer": 4.0}, headers=headers)
    assert resp.status_code == 200
    mastery_after = resp.json()["mastery_after"]
    assert mastery_after["attempts"] == 1
    assert mastery_after["correct"] == 1
    assert mastery_after["next_review"] is not None
    assert mastery_after["retrievability"] is not None

    listed = await client.get("/api/v1/mastery", headers=headers)
    entry = next(m for m in listed.json()["mastery"] if m["concept_id"] == concept_id)
    assert entry["concept_name"] == "Linear Equations"
    assert entry["knowledge_space_slug"] == student["slug"]

    attempts = await client.get("/api/v1/attempts", headers=headers)
    assert attempts.status_code == 200
    attempt_rows = attempts.json()["attempts"]
    assert len(attempt_rows) == 1
    assert attempt_rows[0]["question_id"] == question["id"]
    assert attempt_rows[0]["question_prompt"] == "2+2"
    assert attempt_rows[0]["question_type"] == "numerical"
    assert attempt_rows[0]["concept_id"] == concept_id
    assert attempt_rows[0]["concept_name"] == "Linear Equations"
    assert attempt_rows[0]["is_correct"] is True


async def test_unsupported_question_type_returns_clear_error_not_fake_grade(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    # "code" stays unsupported deliberately (needs a sandboxed execution
    # environment — its own dedicated pass, see grading.py's module
    # docstring) — unlike "essay", which this slice added real support for.
    question = await _create_question(
        client, headers, concept_id, type="code", prompt="write a function", correct_answer="anything"
    )
    resp = await client.post(f"/api/v1/questions/{question['id']}/attempt", json={"answer": "def f(): pass"}, headers=headers)
    assert resp.status_code == 400
    assert "not yet supported" in resp.json()["detail"]


async def test_grading_input_error_on_malformed_answer(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    question = await _create_question(
        client, headers, concept_id, type="numerical", prompt="2+2", correct_answer=4.0
    )
    resp = await client.post(
        f"/api/v1/questions/{question['id']}/attempt", json={"answer": "not a number"}, headers=headers
    )
    assert resp.status_code == 400


async def test_question_list_hides_correct_answer(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    await _create_question(client, headers, concept_id, type="mcq", options=["a", "b"], prompt="pick one", correct_answer="a")
    listed = await client.get(f"/api/v1/concepts/{concept_id}/questions", headers=headers)
    assert listed.status_code == 200
    for q in listed.json()["questions"]:
        assert "correct_answer" not in q


async def test_misconception_detected_after_repeated_wrong_answers_and_resolves(client, student):
    headers, concept_id = student["headers"], student["concept_id"]
    question = await _create_question(
        client, headers, concept_id, type="numerical", prompt="2+2", correct_answer=4.0, tolerance=0.01
    )

    for _ in range(3):
        r = await client.post(f"/api/v1/questions/{question['id']}/attempt", json={"answer": 999.0}, headers=headers)
        assert r.status_code == 200

    misconceptions = await client.get("/api/v1/misconceptions", headers=headers)
    assert misconceptions.status_code == 200
    entry = next(m for m in misconceptions.json()["misconceptions"] if m["concept_id"] == concept_id)
    assert entry["concept_name"] == "Linear Equations"

    for _ in range(2):
        r = await client.post(f"/api/v1/questions/{question['id']}/attempt", json={"answer": 4.0}, headers=headers)
        assert r.status_code == 200

    misconceptions_after = await client.get("/api/v1/misconceptions", headers=headers)
    assert not any(m["concept_id"] == concept_id for m in misconceptions_after.json()["misconceptions"])


async def test_question_and_attempt_require_ownership(client, student):
    """A question belonging to another user's concept must 404, not leak
    through a bare question_id."""
    other_email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    headers, concept_id = student["headers"], student["concept_id"]
    question = await _create_question(
        client, headers, concept_id, type="numerical", prompt="2+2", correct_answer=4.0
    )

    resp = await client.post(
        f"/api/v1/questions/{question['id']}/attempt", json={"answer": 4.0}, headers=other_headers
    )
    assert resp.status_code == 404

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()
