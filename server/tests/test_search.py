"""Integration tests for server/domains/knowledge's standalone semantic
search endpoint (blueprint Sections 12-13) — real embeddings via
fastembed, not mocked, same engine POST /api/ask/project already uses
internally.

Run with: python -m pytest server/tests/test_search.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_search_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Search Smoke"}, headers=headers)
    assert space.status_code == 200, space.text
    slug = space.json()["slug"]

    yield {"headers": headers, "email": email, "slug": slug}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_search_with_no_material_returns_empty(client, student):
    resp = await client.get(
        f"/api/v1/knowledge-spaces/{student['slug']}/search",
        params={"q": "anything"},
        headers=student["headers"],
    )
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"results": []}


async def test_search_requires_existing_space(client, student):
    resp = await client.get(
        "/api/v1/knowledge-spaces/does-not-exist/search", params={"q": "x"}, headers=student["headers"]
    )
    assert resp.status_code == 404


async def test_search_ranks_relevant_material_above_unrelated(client, student):
    slug, headers = student["slug"], student["headers"]
    await client.post(
        f"/api/projects/{slug}/material",
        data={
            "text": (
                "Newton's second law states that force equals mass times acceleration, F = ma. "
                "This is a foundational principle of classical mechanics."
            )
        },
        headers=headers,
    )
    await client.post(
        f"/api/projects/{slug}/material",
        data={
            "text": (
                "Photosynthesis is the process by which plants convert sunlight, water, and "
                "carbon dioxide into glucose and oxygen."
            )
        },
        headers=headers,
    )

    resp = await client.get(
        f"/api/v1/knowledge-spaces/{slug}/search",
        params={"q": "what is Newton's second law of motion?", "limit": 2},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    results = resp.json()["results"]
    assert len(results) >= 1
    assert "force" in results[0]["chunk"].lower() or "newton" in results[0]["chunk"].lower()
    assert results[0]["score"] > results[-1]["score"] if len(results) > 1 else True


async def test_search_requires_auth(client, student):
    resp = await client.get(f"/api/v1/knowledge-spaces/{student['slug']}/search", params={"q": "x"})
    assert resp.status_code == 401
