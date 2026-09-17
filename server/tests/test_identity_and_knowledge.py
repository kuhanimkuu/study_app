"""Integration tests for server/domains/identity and server/domains/knowledge
— the Postgres-backed replacements for the old sqlite3 auth.py/account.py/
projects.py. Run against the real local Postgres instance; each test uses a
unique email and deletes its own user row (cascades to knowledge_spaces/
materials/generated_artifacts via the FK relationships in models.py) so
the suite is repeatable without a separate throwaway database.

Run with: python -m pytest server/tests/ -v
"""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_{uuid.uuid4().hex[:12]}@example.com"


@pytest.fixture
async def signed_up_user(client):
    """Creates a real account via the HTTP API (not a DB shortcut — this
    also exercises the signup endpoint itself) and yields (email, token,
    headers). Deletes the user row afterward, cascading to any knowledge
    spaces/materials/artifacts the test created."""
    email = _unique_email()
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    token = body["token"]
    headers = {"Authorization": f"Bearer {token}"}
    yield {"email": email, "token": token, "headers": headers, "user_id": body["user"]["id"]}

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_signup_returns_token_and_encryption_key(client):
    email = _unique_email()
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "token" in body
    assert body["user"]["email"] == email
    assert "encryption_key" in body["user"]
    assert "password_hash" not in body["user"]

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_signup_rejects_short_password(client):
    resp = await client.post("/api/auth/signup", json={"email": _unique_email(), "password": "short"})
    assert resp.status_code == 400


async def test_signup_rejects_malformed_email(client):
    resp = await client.post("/api/auth/signup", json={"email": "not-an-email", "password": "testpass123"})
    assert resp.status_code == 422


async def test_email_is_case_normalized(client):
    """"User@Example.com" and "user@example.com" must be the same account
    — without normalization they'd pass the DB's case-sensitive unique
    constraint as two different ones (a real pre-existing bug this fixed,
    not a hypothetical)."""
    local, domain = _unique_email().split("@")
    mixed_case = f"{local.upper()}@{domain.upper()}"

    signup = await client.post("/api/auth/signup", json={"email": mixed_case, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    assert signup.json()["user"]["email"] == mixed_case.lower()

    duplicate = await client.post(
        "/api/auth/signup", json={"email": mixed_case.lower(), "password": "testpass123"}
    )
    assert duplicate.status_code == 409

    login = await client.post("/api/auth/login", json={"email": mixed_case.lower(), "password": "testpass123"})
    assert login.status_code == 200

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == mixed_case.lower()))
        await db.commit()


async def test_login_rate_limit_blocks_after_repeated_attempts(client):
    email = _unique_email()
    await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})

    from server.domains.identity.router import _LOGIN_MAX_ATTEMPTS

    last_status = None
    for _ in range(_LOGIN_MAX_ATTEMPTS + 1):
        resp = await client.post("/api/auth/login", json={"email": email, "password": "wrong-password"})
        last_status = resp.status_code
    assert last_status == 429

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_signup_rejects_duplicate_email(client, signed_up_user):
    resp = await client.post(
        "/api/auth/signup", json={"email": signed_up_user["email"], "password": "testpass123"}
    )
    assert resp.status_code == 409


async def test_login_with_correct_and_wrong_password(client, signed_up_user):
    ok = await client.post(
        "/api/auth/login", json={"email": signed_up_user["email"], "password": "testpass123"}
    )
    assert ok.status_code == 200
    assert "encryption_key" in ok.json()["user"]

    bad = await client.post(
        "/api/auth/login", json={"email": signed_up_user["email"], "password": "wrong-password"}
    )
    assert bad.status_code == 401


async def test_me_and_account_endpoints(client, signed_up_user):
    me = await client.get("/api/auth/me", headers=signed_up_user["headers"])
    assert me.status_code == 200
    assert me.json()["email"] == signed_up_user["email"]
    assert "encryption_key" not in me.json()

    updated = await client.patch(
        "/api/account", json={"display_name": "Test Student"}, headers=signed_up_user["headers"]
    )
    assert updated.status_code == 200
    assert updated.json()["display_name"] == "Test Student"
    # New profile fields default to null and never block/require each other
    assert updated.json()["education_level"] is None

    # Updating only a profile field (no display_name) must still persist —
    # the original implementation only committed when display_name was set.
    profile_updated = await client.patch(
        "/api/account",
        json={"education_level": "undergraduate", "daily_study_target_minutes": 45},
        headers=signed_up_user["headers"],
    )
    assert profile_updated.status_code == 200
    body = profile_updated.json()
    assert body["education_level"] == "undergraduate"
    assert body["daily_study_target_minutes"] == 45
    assert body["display_name"] == "Test Student"  # untouched by this call, not wiped

    refetched = await client.get("/api/account", headers=signed_up_user["headers"])
    assert refetched.json()["education_level"] == "undergraduate"


async def test_protected_endpoint_requires_auth(client):
    resp = await client.get("/api/auth/me")
    assert resp.status_code == 401


async def test_knowledge_space_crud(client, signed_up_user):
    headers = signed_up_user["headers"]

    created = await client.post(
        "/api/projects", json={"display_name": "Fluid Mechanics"}, headers=headers
    )
    assert created.status_code == 200, created.text
    space = created.json()
    assert space["slug"] == "fluid_mechanics"
    assert space["display_name"] == "Fluid Mechanics"

    duplicate = await client.post(
        "/api/projects", json={"display_name": "Fluid Mechanics"}, headers=headers
    )
    assert duplicate.status_code == 409

    listed = await client.get("/api/projects", headers=headers)
    assert listed.status_code == 200
    slugs = [p["slug"] for p in listed.json()["projects"]]
    assert "fluid_mechanics" in slugs
    assert listed.json()["projects"][0]["chunk_count"] == 0

    deleted = await client.delete("/api/projects/fluid_mechanics", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json() == {"deleted": "fluid_mechanics"}

    gone = await client.get("/api/projects", headers=headers)
    assert "fluid_mechanics" not in [p["slug"] for p in gone.json()["projects"]]


async def test_add_material_indexes_and_tracks_metadata(client, signed_up_user):
    headers = signed_up_user["headers"]
    await client.post("/api/projects", json={"display_name": "Thermo"}, headers=headers)

    added = await client.post(
        "/api/projects/thermo/material",
        data={"text": "The first law of thermodynamics relates energy conservation to heat and work."},
        headers=headers,
    )
    assert added.status_code == 200, added.text

    listed = await client.get("/api/projects", headers=headers)
    thermo = next(p for p in listed.json()["projects"] if p["slug"] == "thermo")
    assert thermo["chunk_count"] >= 1

    materials = await client.get("/api/projects/thermo/materials", headers=headers)
    assert materials.status_code == 200, materials.text
    assert len(materials.json()["materials"]) == 1
    assert materials.json()["materials"][0]["filename"] == "pasted_text.txt"
    assert materials.json()["materials"][0]["mime_type"] == "text/plain"

    await client.delete("/api/projects/thermo", headers=headers)


async def test_list_materials_requires_existing_space(client, signed_up_user):
    resp = await client.get("/api/projects/does-not-exist/materials", headers=signed_up_user["headers"])
    assert resp.status_code == 404


async def test_material_requires_existing_space(client, signed_up_user):
    resp = await client.post(
        "/api/projects/does-not-exist/material",
        data={"text": "some text"},
        headers=signed_up_user["headers"],
    )
    assert resp.status_code == 404


async def test_delete_account_requires_correct_password(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    wrong = await client.request(
        "DELETE", "/api/account", json={"password": "wrong-password"}, headers=headers
    )
    assert wrong.status_code == 401

    # Account must still exist and be usable after a rejected delete attempt.
    still_there = await client.get("/api/auth/me", headers=headers)
    assert still_there.status_code == 200

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_delete_account_cascades_and_invalidates_token(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    body = signup.json()
    headers = {"Authorization": f"Bearer {body['token']}"}
    user_id = body["user"]["id"]

    space = await client.post("/api/projects", json={"display_name": "Delete Me"}, headers=headers)
    assert space.status_code == 200, space.text
    await client.post(
        "/api/projects/delete_me/material",
        data={"text": "some material that should be gone after account deletion."},
        headers=headers,
    )

    ok = await client.request("DELETE", "/api/account", json={"password": "testpass123"}, headers=headers)
    assert ok.status_code == 200
    assert ok.json() == {"deleted": True}

    # The now-invalid token must be rejected, not silently accepted.
    after = await client.get("/api/auth/me", headers=headers)
    assert after.status_code == 401

    async with async_session() as db:
        assert await db.get(User, user_id) is None

    from server.domains.identity.router import _RAG_PROJECTS_ROOT

    assert not (_RAG_PROJECTS_ROOT / f"user_{user_id}").exists()


async def test_delete_account_rate_limited(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    headers = {"Authorization": f"Bearer {signup.json()['token']}"}

    from server.domains.identity.router import _DELETE_MAX_ATTEMPTS

    last_status = None
    for _ in range(_DELETE_MAX_ATTEMPTS + 1):
        resp = await client.request(
            "DELETE", "/api/account", json={"password": "wrong-password"}, headers=headers
        )
        last_status = resp.status_code
    assert last_status == 429

    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()
