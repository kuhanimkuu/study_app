"""Integration tests for server/domains/learning's Flashcard endpoints
(blueprint Sections 17, 27, 32) — CRUD, ownership, the due-review queue,
and the full 4-value FSRS rating scale (Again/Hard/Good/Easy), distinct
from Mastery's binary Good/Again mapping since flashcards are self-graded.

Run with: python -m pytest server/tests/test_flashcards.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_flashcards_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Biology"}, headers=headers)
    assert space.status_code == 200, space.text
    slug = space.json()["slug"]

    concept = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/concepts",
        json={"name": "Cell Division", "description": "Mitosis vs meiosis"},
        headers=headers,
    )
    assert concept.status_code == 200, concept.text

    yield {"headers": headers, "email": email, "slug": slug, "concept_id": concept.json()["id"]}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_create_and_list_flashcards(client, student):
    headers, slug, concept_id = student["headers"], student["slug"], student["concept_id"]

    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards",
        json={"front": "What is mitosis?", "back": "Cell division producing two identical cells", "concept_id": concept_id},
        headers=headers,
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["front"] == "What is mitosis?"
    assert body["concept_id"] == concept_id
    assert body["reviews"] == 0
    assert body["due"] is not None

    standalone = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards",
        json={"front": "What is ATP?", "back": "Adenosine triphosphate"},
        headers=headers,
    )
    assert standalone.status_code == 200, standalone.text
    assert standalone.json()["concept_id"] is None

    listed = await client.get(f"/api/v1/knowledge-spaces/{slug}/flashcards", headers=headers)
    assert listed.status_code == 200
    fronts = [f["front"] for f in listed.json()["flashcards"]]
    assert "What is mitosis?" in fronts
    assert "What is ATP?" in fronts


async def test_flashcard_requires_existing_space(client, student):
    resp = await client.post(
        "/api/v1/knowledge-spaces/does-not-exist/flashcards",
        json={"front": "a", "back": "b"},
        headers=student["headers"],
    )
    assert resp.status_code == 404


async def test_flashcard_rejects_concept_from_nowhere(client, student):
    resp = await client.post(
        f"/api/v1/knowledge-spaces/{student['slug']}/flashcards",
        json={"front": "a", "back": "b", "concept_id": 999999},
        headers=student["headers"],
    )
    assert resp.status_code == 404


async def test_new_flashcard_is_immediately_due(client, student):
    slug, headers = student["slug"], student["headers"]
    await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a", "back": "b"}, headers=headers
    )
    due = await client.get("/api/v1/flashcards/due", headers=headers)
    assert due.status_code == 200
    assert len(due.json()["flashcards"]) >= 1


async def test_list_all_flashcards_includes_future_due_cards(client, student):
    slug, headers = student["slug"], student["headers"]
    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a", "back": "b"}, headers=headers
    )
    flashcard_id = created.json()["id"]
    # Push its due date into the future via a review — it should drop out
    # of /flashcards/due but still appear in the unfiltered /flashcards.
    await client.post(f"/api/v1/flashcards/{flashcard_id}/review", json={"rating": "easy"}, headers=headers)

    due = await client.get("/api/v1/flashcards/due", headers=headers)
    assert flashcard_id not in [f["id"] for f in due.json()["flashcards"]]

    all_cards = await client.get("/api/v1/flashcards", headers=headers)
    assert all_cards.status_code == 200, all_cards.text
    assert flashcard_id in [f["id"] for f in all_cards.json()["flashcards"]]


async def test_review_pushes_due_date_forward_and_removes_from_queue(client, student):
    slug, headers = student["slug"], student["headers"]
    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a", "back": "b"}, headers=headers
    )
    flashcard_id = created.json()["id"]
    original_due = created.json()["due"]

    reviewed = await client.post(
        f"/api/v1/flashcards/{flashcard_id}/review", json={"rating": "good"}, headers=headers
    )
    assert reviewed.status_code == 200, reviewed.text
    body = reviewed.json()
    assert body["reviews"] == 1
    assert body["due"] > original_due
    assert body["last_review"] is not None

    due_queue = await client.get("/api/v1/flashcards/due", headers=headers)
    assert flashcard_id not in [f["id"] for f in due_queue.json()["flashcards"]]


async def test_review_rejects_invalid_rating(client, student):
    slug, headers = student["slug"], student["headers"]
    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a", "back": "b"}, headers=headers
    )
    resp = await client.post(
        f"/api/v1/flashcards/{created.json()['id']}/review", json={"rating": "excellent"}, headers=headers
    )
    assert resp.status_code == 400


async def test_again_rating_keeps_card_due_sooner_than_easy(client, student):
    """The whole point of the 4-value scale over Mastery's binary one:
    Again and Easy on the SAME fresh card must schedule differently."""
    slug, headers = student["slug"], student["headers"]

    again_card = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a1", "back": "b1"}, headers=headers
    )
    easy_card = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a2", "back": "b2"}, headers=headers
    )

    again_result = await client.post(
        f"/api/v1/flashcards/{again_card.json()['id']}/review", json={"rating": "again"}, headers=headers
    )
    easy_result = await client.post(
        f"/api/v1/flashcards/{easy_card.json()['id']}/review", json={"rating": "easy"}, headers=headers
    )
    assert again_result.json()["due"] < easy_result.json()["due"]


async def test_flashcard_delete_and_ownership(client, student):
    slug, headers = student["slug"], student["headers"]
    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards", json={"front": "a", "back": "b"}, headers=headers
    )
    flashcard_id = created.json()["id"]

    other_email = _unique_email()
    other_signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {other_signup.json()['token']}"}

    forbidden_review = await client.post(
        f"/api/v1/flashcards/{flashcard_id}/review", json={"rating": "good"}, headers=other_headers
    )
    assert forbidden_review.status_code == 404
    forbidden_delete = await client.delete(f"/api/v1/flashcards/{flashcard_id}", headers=other_headers)
    assert forbidden_delete.status_code == 404

    deleted = await client.delete(f"/api/v1/flashcards/{flashcard_id}", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json() == {"deleted": flashcard_id}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()
