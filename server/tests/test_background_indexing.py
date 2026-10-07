"""Background indexing of uploads (2026-10-07) — the real production path
(conftest.py indexes inline for every other test).

The bug this covers: indexing ran inside the upload request and blocked
the event loop for minutes on Render's fractional CPU, so Render's health
check got "connection reset by peer" and restarted the instance mid-upload.

Run with: python -m pytest server/tests/test_background_indexing.py -v
"""
from __future__ import annotations

import asyncio
import time
import uuid

import pytest
from sqlalchemy import select

from server.db.session import async_session
from server.domains.knowledge import router as knowledge_router
from server.domains.knowledge.models import Material

_PASSWORD = "testpass123"
# Enough chunks that indexing takes a measurable while (≈300 x 500-char chunks).
_LONG_MATERIAL = " ".join(
    f"Section {i}: mitochondria produce ATP through cellular respiration, the nucleus stores DNA, "
    f"and ribosomes translate messenger RNA into proteins during gene expression." for i in range(900)
)


@pytest.fixture
async def user(client, monkeypatch):
    monkeypatch.setattr(knowledge_router, "INDEX_IN_BACKGROUND", True)
    email = f"pytest_bg_{uuid.uuid4().hex[:12]}@example.com"
    token = (await client.post("/api/auth/signup", json={"email": email, "password": _PASSWORD})).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    slug = (await client.post("/api/projects", json={"display_name": "Bio"}, headers=headers)).json()["slug"]
    yield {"headers": headers, "slug": slug}
    # Let any still-running job finish before the account (and its rows) go.
    for _ in range(600):
        if not knowledge_router._background_jobs:
            break
        await asyncio.sleep(0.1)
    await client.request("DELETE", "/api/account", json={"password": _PASSWORD}, headers=headers)


async def _wait_for(client, user, filename: str, timeout: float = 120) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        materials = (await client.get(f"/api/projects/{user['slug']}/materials", headers=user["headers"])).json()["materials"]
        mine = [m for m in materials if m["filename"] == filename]
        if mine and mine[0]["status"] != "indexing":
            return mine[0]
        await asyncio.sleep(0.2)
    raise AssertionError(f"{filename} still indexing after {timeout}s")


async def test_upload_returns_immediately_and_server_stays_responsive(client, user):
    h, slug = user["headers"], user["slug"]
    t0 = time.monotonic()
    resp = await client.post(
        f"/api/projects/{slug}/material",
        files={"file": ("notes.txt", _LONG_MATERIAL.encode(), "text/plain")},
        headers=h,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "indexing"
    assert resp.json()["material"]["status"] == "indexing"

    # The exact failure on Render: while indexing runs, health must answer fast.
    health_t0 = time.monotonic()
    health = await client.get("/api/health")
    health_seconds = time.monotonic() - health_t0
    still_indexing = (
        await client.get(f"/api/projects/{slug}/materials", headers=h)
    ).json()["materials"][0]["status"] == "indexing"
    assert health.status_code == 200
    assert health_seconds < 2, f"health took {health_seconds:.1f}s during indexing"
    assert still_indexing, "indexing finished before the health check — test material too small to prove anything"

    done = await _wait_for(client, user, "notes.txt")
    assert done["status"] == "indexed" and done["error"] is None
    found = (await client.get(f"/api/v1/knowledge-spaces/{slug}/search", params={"q": "ribosomes"}, headers=h)).json()
    assert found["results"]
    assert time.monotonic() - t0 < 120


async def test_unreadable_pdf_is_marked_failed_with_a_reason(client, user):
    h, slug = user["headers"], user["slug"]
    resp = await client.post(
        f"/api/projects/{slug}/material",
        files={"file": ("broken.pdf", b"this is not really a pdf", "application/pdf")},
        headers=h,
    )
    assert resp.status_code == 200
    done = await _wait_for(client, user, "broken.pdf")
    assert done["status"] == "failed"
    assert done["error"]


async def test_two_uploads_are_indexed_one_after_another_and_both_land(client, user):
    h, slug = user["headers"], user["slug"]
    for name, topic in [("a.txt", "osmosis moves water across membranes"), ("b.txt", "the Golgi apparatus packages proteins")]:
        r = await client.post(f"/api/projects/{slug}/material", data={"text": f"{topic}. " * 50}, headers=h)
        assert r.status_code == 200
    # Pasted text is recorded as pasted_text.txt — wait for both rows.
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        materials = (await client.get(f"/api/projects/{slug}/materials", headers=h)).json()["materials"]
        if len(materials) == 2 and all(m["status"] == "indexed" for m in materials):
            break
        await asyncio.sleep(0.2)
    else:
        raise AssertionError(f"not both indexed: {materials}")
    for q in ["osmosis", "Golgi"]:
        results = (await client.get(f"/api/v1/knowledge-spaces/{slug}/search", params={"q": q}, headers=h)).json()["results"]
        assert any(q.lower() in r["chunk"].lower() for r in results), q


async def test_startup_marks_interrupted_indexing_as_failed(client, user):
    h, slug = user["headers"], user["slug"]
    space_id = (await client.get("/api/projects", headers=h)).json()["projects"][0]["id"]
    async with async_session() as db:
        db.add(Material(knowledge_space_id=space_id, filename="cut-off.pdf", mime_type="application/pdf", status="indexing"))
        await db.commit()

    await knowledge_router.mark_interrupted_indexing_failed()

    async with async_session() as db:
        m = await db.scalar(select(Material).where(Material.knowledge_space_id == space_id, Material.filename == "cut-off.pdf"))
        assert m.status == "failed"
        assert "upload it again" in m.error
