"""Lessons (2026-10-21): Sage teaches a topic in steps with check questions.
The model is faked with a fixed lesson; the rest is real — the questions
are graded by the same code as Practice, mastery moves, and finishing the
lesson puts its recap in the flashcard queue."""
from __future__ import annotations

import json
import uuid

import pytest
from sqlalchemy import delete

from server import engines
from server.db.session import async_session
from server.domains.identity.models import User
from server.domains.tutor.lessons import parse_lesson

LESSON = {
    "title": "Osmosis in 3 steps",
    "steps": [
        {
            "heading": "Water moves",
            "explanation": "Water moves across a **membrane**.",
            "check": {"type": "mcq", "prompt": "What moves in osmosis?", "options": ["Water", "Salt", "Sugar", "Air"],
                      "answer": "Water", "why": "Osmosis is about water."},
        },
        {
            "heading": "Towards more solute",
            "explanation": "It moves towards the side with more dissolved stuff.",
            "check": {"type": "true_false", "prompt": "Water moves towards higher solute concentration.",
                      "answer": "true", "why": "It dilutes the stronger solution."},
        },
        {
            "heading": "Why it matters",
            "explanation": "Cells swell or shrink.",
            "check": {"type": "short_answer", "prompt": "What happens to a cell in pure water?", "answer": "It swells",
                      "why": "Water rushes in."},
        },
    ],
    "worked_example": {"problem": "A cell in salty water?", "solution": "It shrinks."},
    "recap": [{"front": "Osmosis", "back": "Water across a membrane"}, {"front": "Hypotonic", "back": "Cell swells"}],
}


@pytest.fixture
def model(monkeypatch):
    calls: list[dict] = []

    async def fake(**kwargs):
        calls.append(kwargs)
        if "grading a student's" in kwargs["prompt"]:
            return {"text": "Correct — that's it.", "tier": "tiny", "backend": "local"}
        return {"text": "Here you go:\n```json\n" + json.dumps(LESSON) + "\n```", "tier": "tiny", "backend": "local"}

    monkeypatch.setattr(engines.model_router, "run", fake)
    return calls


@pytest.fixture
async def student(client):
    email = f"pytest_lesson_{uuid.uuid4().hex[:10]}@example.com"
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    yield {"Authorization": f"Bearer {resp.json()['token']}"}
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_a_full_lesson(client, student, model):
    resp = await client.post("/api/v1/lessons", json={"topic": "osmosis"}, headers=student)
    assert resp.status_code == 200, resp.text
    lesson = resp.json()
    assert lesson["title"] == "Osmosis in 3 steps"
    assert lesson["subject"]["display_name"] == "My lessons"
    assert lesson["checks"] == 3 and lesson["status"] == "in_progress"
    first = lesson["lesson_steps"][0]
    assert first["question"]["options"] == ["Water", "Salt", "Sugar", "Air"]
    assert "correct_answer" not in first["question"]  # not before answering
    assert "why" not in first

    lid = lesson["id"]
    r = await client.post(f"/api/v1/lessons/{lid}/steps/0/answer", json={"answer": "Salt"}, headers=student)
    assert r.status_code == 200, r.text
    assert r.json()["correct"] is False
    assert r.json()["correct_answer"] == "Water" and r.json()["why"] == "Osmosis is about water."
    # Answering again doesn't count twice.
    again = await client.post(f"/api/v1/lessons/{lid}/steps/0/answer", json={"answer": "Water"}, headers=student)
    assert again.json()["correct"] is False and again.json()["lesson"]["answered"] == 1

    r = await client.post(f"/api/v1/lessons/{lid}/steps/1/answer", json={"answer": "true"}, headers=student)
    assert r.json()["correct"] is True
    r = await client.post(f"/api/v1/lessons/{lid}/steps/2/answer", json={"answer": "it gets bigger"}, headers=student)
    assert r.json()["correct"] is True  # graded by the (faked) AI grader
    assert r.json()["lesson"] == {**r.json()["lesson"], "answered": 3, "correct": 2}

    # The answers count as practice on the concept.
    mastery = (await client.get(f"/api/v1/concepts/{lesson['concept_id']}/mastery", headers=student)).json()
    assert mastery["attempts"] == 3 and mastery["correct"] == 2

    done = await client.post(f"/api/v1/lessons/{lid}/complete", headers=student)
    assert done.json()["flashcards_added"] == 2 and done.json()["lesson"]["status"] == "completed"
    assert (await client.post(f"/api/v1/lessons/{lid}/complete", headers=student)).json()["flashcards_added"] == 0
    cards = (await client.get("/api/v1/flashcards/due", headers=student)).json()
    assert {"Osmosis", "Hypotonic"} <= {c["front"] for c in cards["flashcards"]}

    reopened = (await client.get(f"/api/v1/lessons/{lid}", headers=student)).json()
    assert reopened["lesson_steps"][0]["result"]["correct"] is False
    assert reopened["lesson_steps"][0]["question"]["correct_answer"] == "Water"
    listed = (await client.get("/api/v1/lessons?status=completed", headers=student)).json()["lessons"]
    assert [item["id"] for item in listed] == [lid]


async def test_lessons_reuse_the_concept_and_stay_private(client, student, model):
    a = (await client.post("/api/v1/lessons", json={"topic": "Osmosis"}, headers=student)).json()
    b = (await client.post("/api/v1/lessons", json={"topic": "osmosis"}, headers=student)).json()
    assert a["concept_id"] == b["concept_id"]

    email = f"pytest_lesson_{uuid.uuid4().hex[:10]}@example.com"
    other = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    try:
        stranger = {"Authorization": f"Bearer {other.json()['token']}"}
        assert (await client.get(f"/api/v1/lessons/{a['id']}", headers=stranger)).status_code == 404
        r = await client.post(f"/api/v1/lessons/{a['id']}/steps/0/answer", json={"answer": "Water"}, headers=stranger)
        assert r.status_code == 404
    finally:
        async with async_session() as db:
            await db.execute(delete(User).where(User.email == email))
            await db.commit()


async def test_lesson_from_a_subjects_notes_is_grounded_in_them(client, student, model):
    space = (await client.post("/api/projects", json={"display_name": "Biology"}, headers=student)).json()
    await client.post(
        f"/api/projects/{space['slug']}/material",
        data={"text": "Osmosis: water crosses the partially permeable membrane of root hair cells. " * 20},
        headers=student,
    )
    resp = await client.post(
        "/api/v1/lessons", json={"topic": "osmosis", "knowledge_space_slug": space["slug"]}, headers=student
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["grounded_in_notes"] is True
    assert "root hair cells" in model[-1]["prompt"] and "<material>" in model[-1]["prompt"]


def test_parser_keeps_only_gradable_checks():
    bad = {**LESSON, "steps": [
        {**LESSON["steps"][0], "check": {**LESSON["steps"][0]["check"], "answer": "Plasma"}},  # answer not an option
        {**LESSON["steps"][1], "check": {**LESSON["steps"][1]["check"], "answer": "maybe"}},
        LESSON["steps"][2],
    ]}
    with pytest.raises(Exception) as refused:
        parse_lesson(json.dumps(bad), "osmosis")
    assert "usable lesson" in str(refused.value.detail)

    letter = {**LESSON, "steps": [{**s, "check": {**s["check"], "answer": "A"}} if i == 0 else s for i, s in enumerate(LESSON["steps"])]}
    assert parse_lesson(json.dumps(letter), "osmosis")["steps"][0]["check"]["correct_answer"] == "Water"


async def test_no_topic_is_a_clear_error(client, student, model):
    resp = await client.post("/api/v1/lessons", json={"topic": "  "}, headers=student)
    assert resp.status_code == 400


async def test_a_chat_answer_becomes_flashcards(client, student, monkeypatch):
    prompts: list[str] = []

    async def fake(**kwargs):
        prompts.append(kwargs["prompt"])
        return {"text": "Q: What is osmosis? | A: Water moving across a membrane.\nQ: Which way? | A: Towards more solute.",
                "tier": "tiny", "backend": "local"}

    monkeypatch.setattr(engines.model_router, "run", fake)
    space = (await client.post("/api/projects", json={"display_name": "Bio"}, headers=student)).json()
    answer = "Osmosis is water moving across a partially permeable membrane, towards more solute."
    resp = await client.post(
        f"/api/v1/knowledge-spaces/{space['slug']}/flashcards/from-text", json={"text": answer}, headers=student
    )
    assert resp.status_code == 200, resp.text
    assert [c["front"] for c in resp.json()["flashcards"]] == ["What is osmosis?", "Which way?"]
    assert f"<material>\n{answer}\n</material>" in prompts[-1]
