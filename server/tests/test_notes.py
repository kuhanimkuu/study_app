"""Integration tests for server/domains/knowledge's Note endpoints
(blueprint Section 14) — CRUD and ownership.

Run with: python -m pytest server/tests/test_notes.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_notes_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "History"}, headers=headers)
    assert space.status_code == 200, space.text
    slug = space.json()["slug"]

    yield {"headers": headers, "email": email, "slug": slug}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_create_and_list_notes(client, student):
    headers, slug = student["headers"], student["slug"]

    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/notes",
        json={"title": "French Revolution", "body": "1789-1799"},
        headers=headers,
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["title"] == "French Revolution"
    assert body["body"] == "1789-1799"
    # created_at/updated_at are independent Python-side defaults (both call
    # _utcnow() separately at insert), so they can differ by microseconds
    # even on the very first row — not asserting exact equality here.
    assert body["created_at"] is not None and body["updated_at"] is not None

    empty_body = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/notes", json={"title": "Untitled draft"}, headers=headers
    )
    assert empty_body.status_code == 200, empty_body.text
    assert empty_body.json()["body"] == ""

    listed = await client.get(f"/api/v1/knowledge-spaces/{slug}/notes", headers=headers)
    assert listed.status_code == 200
    titles = [n["title"] for n in listed.json()["notes"]]
    assert "French Revolution" in titles
    assert "Untitled draft" in titles


async def test_note_requires_existing_space(client, student):
    resp = await client.post(
        "/api/v1/knowledge-spaces/does-not-exist/notes", json={"title": "x"}, headers=student["headers"]
    )
    assert resp.status_code == 404


async def test_update_note_partial_and_full(client, student):
    headers, slug = student["headers"], student["slug"]
    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/notes", json={"title": "Draft", "body": "wip"}, headers=headers
    )
    note_id = created.json()["id"]

    title_only = await client.patch(f"/api/v1/notes/{note_id}", json={"title": "Final"}, headers=headers)
    assert title_only.status_code == 200, title_only.text
    assert title_only.json()["title"] == "Final"
    assert title_only.json()["body"] == "wip"  # untouched
    assert title_only.json()["updated_at"] >= created.json()["updated_at"]

    body_only = await client.patch(f"/api/v1/notes/{note_id}", json={"body": "done"}, headers=headers)
    assert body_only.status_code == 200, body_only.text
    assert body_only.json()["title"] == "Final"  # still untouched
    assert body_only.json()["body"] == "done"


async def test_note_delete_and_ownership(client, student):
    headers, slug = student["headers"], student["slug"]
    created = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/notes", json={"title": "x", "body": "y"}, headers=headers
    )
    note_id = created.json()["id"]

    other_email = _unique_email()
    other_signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {other_signup.json()['token']}"}

    forbidden_update = await client.patch(
        f"/api/v1/notes/{note_id}", json={"title": "hijacked"}, headers=other_headers
    )
    assert forbidden_update.status_code == 404
    forbidden_delete = await client.delete(f"/api/v1/notes/{note_id}", headers=other_headers)
    assert forbidden_delete.status_code == 404

    deleted = await client.delete(f"/api/v1/notes/{note_id}", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json() == {"deleted": note_id}

    listed = await client.get(f"/api/v1/knowledge-spaces/{slug}/notes", headers=headers)
    assert listed.json()["notes"] == []

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()
