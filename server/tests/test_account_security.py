"""Account security fixes from the 2026-10-21 audit: password change and
"sign out everywhere" (token_version), the login timing leak, bcrypt's
72-byte limit, length caps on profile text, and the SSRF guard on
/api/ask/web."""
from __future__ import annotations

import time
import uuid

import pytest
from sqlalchemy import delete

from server.db.session import async_session
from server.domains.identity.models import User


@pytest.fixture
async def account(client):
    email = f"pytest_acct_{uuid.uuid4().hex[:10]}@example.com"
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert resp.status_code == 200, resp.text
    yield {"email": email, "token": resp.json()["token"]}
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def test_password_change_signs_out_other_devices(client, account):
    other_device = account["token"]
    resp = await client.post(
        "/api/account/password",
        json={"current_password": "wrong-password", "new_password": "newpass456"},
        headers=_auth(account["token"]),
    )
    assert resp.status_code == 401

    resp = await client.post(
        "/api/account/password",
        json={"current_password": "testpass123", "new_password": "newpass456"},
        headers=_auth(account["token"]),
    )
    assert resp.status_code == 200, resp.text
    new_token = resp.json()["token"]

    assert (await client.get("/api/auth/me", headers=_auth(other_device))).status_code == 401
    assert (await client.get("/api/auth/me", headers=_auth(new_token))).status_code == 200
    login = await client.post("/api/auth/login", json={"email": account["email"], "password": "newpass456"})
    assert login.status_code == 200
    old = await client.post("/api/auth/login", json={"email": account["email"], "password": "testpass123"})
    assert old.status_code == 401


async def test_new_password_rules_apply_to_a_change(client, account):
    for bad in ("short", "x" * 73):
        resp = await client.post(
            "/api/account/password",
            json={"current_password": "testpass123", "new_password": bad},
            headers=_auth(account["token"]),
        )
        assert resp.status_code == 400, bad


async def test_sign_out_everywhere(client, account):
    resp = await client.post("/api/account/sign-out-everywhere", headers=_auth(account["token"]))
    assert resp.status_code == 200
    assert (await client.get("/api/auth/me", headers=_auth(account["token"]))).status_code == 401
    assert (await client.get("/api/auth/me", headers=_auth(resp.json()["token"]))).status_code == 200


async def test_unknown_email_takes_as_long_as_a_wrong_password(client, account):
    started = time.perf_counter()
    resp = await client.post(
        "/api/auth/login", json={"email": f"nobody_{uuid.uuid4().hex[:8]}@example.com", "password": "whatever1"}
    )
    unknown = time.perf_counter() - started
    assert resp.status_code == 401

    started = time.perf_counter()
    resp = await client.post("/api/auth/login", json={"email": account["email"], "password": "whatever1"})
    wrong = time.perf_counter() - started
    assert resp.status_code == 401
    # Before the fix the unknown email answered without any bcrypt work.
    assert unknown > wrong * 0.5, (unknown, wrong)


async def test_passwords_over_72_bytes_are_refused_not_a_crash(client, account):
    resp = await client.post(
        "/api/auth/signup", json={"email": f"pytest_acct_{uuid.uuid4().hex[:10]}@example.com", "password": "p" * 100}
    )
    assert resp.status_code == 400
    resp = await client.post("/api/auth/login", json={"email": account["email"], "password": "p" * 100})
    assert resp.status_code == 401


async def test_profile_text_longer_than_its_column_is_a_clear_error(client, account):
    resp = await client.patch("/api/account", json={"display_name": "n" * 300}, headers=_auth(account["token"]))
    assert resp.status_code == 422


@pytest.mark.parametrize(
    "url",
    ["http://127.0.0.1:8000/api/health", "http://localhost/", "http://169.254.169.254/latest/", "file:///etc/passwd"],
)
async def test_web_fetch_refuses_the_servers_private_side(client, account, url):
    resp = await client.post("/api/ask/web", json={"url": url}, headers=_auth(account["token"]))
    assert resp.status_code == 400
    assert "could not fetch URL" in resp.json()["detail"]


async def test_export_has_my_data_and_nobody_elses(client, account):
    me = _auth(account["token"])
    space = await client.post("/api/projects", json={"display_name": "Biology"}, headers=me)
    slug = space.json()["slug"]
    concept = await client.post(
        f"/api/v1/knowledge-spaces/{slug}/concepts", json={"name": "Mitosis"}, headers=me
    )
    await client.post(
        f"/api/v1/knowledge-spaces/{slug}/flashcards",
        json={"front": "phases?", "back": "PMAT", "concept_id": concept.json()["id"]}, headers=me,
    )

    other_email = f"pytest_acct_{uuid.uuid4().hex[:10]}@example.com"
    other = await client.post("/api/auth/signup", json={"email": other_email, "password": "testpass123"})
    try:
        await client.post("/api/projects", json={"display_name": "Someone else's"}, headers=_auth(other.json()["token"]))

        resp = await client.get("/api/account/export", headers=me)
        assert resp.status_code == 200, resp.text
        assert "attachment" in resp.headers["content-disposition"]
        data = resp.json()
        assert data["account"]["email"] == account["email"]
        assert [s["display_name"] for s in data["tables"]["knowledge_spaces"]] == ["Biology"]
        assert [c["name"] for c in data["tables"]["concepts"]] == ["Mitosis"]
        assert [f["back"] for f in data["tables"]["flashcards"]] == ["PMAT"]
        text = resp.text
        assert "password_hash" not in text and "encryption_key" not in text
        assert "Someone else" not in text and other_email not in text
    finally:
        async with async_session() as db:
            await db.execute(delete(User).where(User.email == other_email))
            await db.commit()


async def test_an_upload_must_really_be_the_type_it_claims(client, account, monkeypatch):
    from server import engines
    from server.routers import ask as ask_router

    for leftover in (ask_router.UPLOADS_DIR / "upload-check").glob("*"):
        leftover.unlink()

    tiff = b"II*\x00" + b"\x00" * 64  # a TIFF header, named like a photo
    resp = await client.post(
        "/api/ask/image", files={"file": ("notes.png", tiff, "image/png")},
        data={"session_id": "upload-check"}, headers=_auth(account["token"]),
    )
    assert resp.status_code == 400
    assert "isn't a real image" in resp.json()["detail"]
    assert not list((ask_router.UPLOADS_DIR / "upload-check").glob("*.png"))  # refused file not kept

    async def fake_run(**kwargs):
        return {"blocks": [{"type": "text", "content": "ok", "source": "test"}], "session_id": "upload-check"}

    monkeypatch.setattr(engines.moderator, "run", fake_run)
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", (8, 8), "white").save(buffer, format="PNG")
    png = buffer.getvalue()
    resp = await client.post(
        "/api/ask/image", files={"file": ("notes.png", png, "image/png")},
        data={"session_id": "upload-check"}, headers=_auth(account["token"]),
    )
    assert resp.status_code == 200, resp.text


async def test_readiness_check_reaches_the_database(client):
    resp = await client.get("/api/health/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "database": "ok"}
