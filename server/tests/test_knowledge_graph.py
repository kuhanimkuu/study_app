"""Integration tests for server/domains/learning's ConceptRelationship
(blueprint Section 15, scoped-down) and its effect on
server/domains/planning/planner.py's prerequisite_importance. Real
Postgres, same style as the other test modules.

Run with: python -m pytest server/tests/test_knowledge_graph.py -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_kg_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def student(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    space = await client.post("/api/projects", json={"display_name": "Calculus"}, headers=headers)
    slug = space.json()["slug"]

    yield {"headers": headers, "email": email, "slug": slug}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def _create_concept(client, headers, slug, name):
    resp = await client.post(f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": name}, headers=headers)
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


async def test_relationship_crud(client, student):
    headers, slug = student["headers"], student["slug"]
    limits = await _create_concept(client, headers, slug, "Limits")
    derivatives = await _create_concept(client, headers, slug, "Derivatives")

    created = await client.post(
        f"/api/v1/concepts/{derivatives}/relationships",
        json={"to_concept_id": limits, "relationship_type": "requires"},
        headers=headers,
    )
    assert created.status_code == 200, created.text
    rel_id = created.json()["id"]
    assert created.json()["from_concept_id"] == derivatives
    assert created.json()["to_concept_id"] == limits

    # visible from both ends, correctly labeled by direction
    from_dependent = await client.get(f"/api/v1/concepts/{derivatives}/relationships", headers=headers)
    assert any(r["id"] == rel_id and r["direction"] == "outgoing" for r in from_dependent.json()["relationships"])

    from_prerequisite = await client.get(f"/api/v1/concepts/{limits}/relationships", headers=headers)
    assert any(r["id"] == rel_id and r["direction"] == "incoming" for r in from_prerequisite.json()["relationships"])

    deleted = await client.delete(f"/api/v1/concepts/{derivatives}/relationships/{rel_id}", headers=headers)
    assert deleted.status_code == 200

    after = await client.get(f"/api/v1/concepts/{derivatives}/relationships", headers=headers)
    assert after.json()["relationships"] == []


async def test_relationship_rejects_invalid_type(client, student):
    headers, slug = student["headers"], student["slug"]
    a = await _create_concept(client, headers, slug, "A")
    b = await _create_concept(client, headers, slug, "B")
    resp = await client.post(
        f"/api/v1/concepts/{a}/relationships", json={"to_concept_id": b, "relationship_type": "made_up_type"}, headers=headers
    )
    assert resp.status_code == 400


async def test_relationship_rejects_self_edge(client, student):
    headers, slug = student["headers"], student["slug"]
    a = await _create_concept(client, headers, slug, "A")
    resp = await client.post(
        f"/api/v1/concepts/{a}/relationships", json={"to_concept_id": a, "relationship_type": "requires"}, headers=headers
    )
    assert resp.status_code == 400


async def test_relationship_rejects_duplicate(client, student):
    headers, slug = student["headers"], student["slug"]
    a = await _create_concept(client, headers, slug, "A")
    b = await _create_concept(client, headers, slug, "B")
    payload = {"to_concept_id": b, "relationship_type": "requires"}
    first = await client.post(f"/api/v1/concepts/{a}/relationships", json=payload, headers=headers)
    assert first.status_code == 200
    duplicate = await client.post(f"/api/v1/concepts/{a}/relationships", json=payload, headers=headers)
    assert duplicate.status_code == 409


async def test_relationship_requires_ownership_of_both_ends(client, student):
    other_email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    other_headers = {"Authorization": f"Bearer {signup.json()['token']}"}
    other_space = await client.post("/api/projects", json={"display_name": "OtherSpace"}, headers=other_headers)
    other_concept = await _create_concept(client, other_headers, other_space.json()["slug"], "NotYours")

    headers, slug = student["headers"], student["slug"]
    my_concept = await _create_concept(client, headers, slug, "Mine")

    resp = await client.post(
        f"/api/v1/concepts/{my_concept}/relationships",
        json={"to_concept_id": other_concept, "relationship_type": "requires"},
        headers=headers,
    )
    assert resp.status_code == 404

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == other_email))
        await db.commit()


async def test_prerequisite_boosts_planner_priority(client, student):
    """A prerequisite of a poorly-mastered dependent should outrank an
    unrelated, equally-never-attempted concept."""
    headers, slug = student["headers"], student["slug"]
    prerequisite = await _create_concept(client, headers, slug, "Limits")
    dependent = await _create_concept(client, headers, slug, "Derivatives")
    unrelated = await _create_concept(client, headers, slug, "Unrelated Topic")

    await client.post(
        f"/api/v1/concepts/{dependent}/relationships",
        json={"to_concept_id": prerequisite, "relationship_type": "requires"},
        headers=headers,
    )

    # give the dependent (Derivatives) some poor-mastery history so it
    # counts as "not yet mastered" for the prerequisite_importance calc
    q = await client.post(
        f"/api/v1/concepts/{dependent}/questions",
        json={"type": "true_false", "prompt": "test", "correct_answer": "true"},
        headers=headers,
    )
    await client.post(f"/api/v1/questions/{q.json()['id']}/attempt", json={"answer": "false"}, headers=headers)

    resp = await client.get(f"/api/v1/plan?duration_minutes=90&knowledge_space_slug={slug}", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    ordered_ids = [cid for p in body["phases"] for cid in p["concept_ids"]]

    assert prerequisite in ordered_ids
    assert unrelated in ordered_ids
    assert ordered_ids.index(prerequisite) < ordered_ids.index(unrelated), (
        "the prerequisite of a poorly-mastered concept should rank above an "
        "unrelated concept with no such relationship, both otherwise never-attempted"
    )
