"""Forgot password by email (2026-10-21): a 6-digit code through Resend.
Resend itself is faked; these test the flow, its limits and that it
never reveals which emails have accounts."""
from __future__ import annotations

import uuid

import pytest
from sqlalchemy import delete, select

from server.core import email as email_module
from server.db.session import async_session
from server.domains.identity.models import PasswordResetCode, User


@pytest.fixture
def outbox(monkeypatch):
    sent: list[dict] = []
    monkeypatch.setattr(email_module, "email_configured", lambda: True)
    monkeypatch.setattr(
        email_module, "send_email",
        lambda to, subject, text, html: sent.append({"to": to, "subject": subject, "text": text}),
    )
    return sent


@pytest.fixture
async def account(client):
    email = f"pytest_reset_{uuid.uuid4().hex[:10]}@example.com"
    resp = await client.post("/api/auth/signup", json={"email": email, "password": "oldpass123"})
    assert resp.status_code == 200
    yield {"email": email, "token": resp.json()["token"]}
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


def _code(message: dict) -> str:
    return message["subject"].rsplit(" ", 1)[-1]


async def test_reset_with_the_emailed_code(client, outbox, account):
    resp = await client.post("/api/auth/password-reset/request", json={"email": account["email"].upper()})
    assert resp.status_code == 200
    assert len(outbox) == 1 and outbox[0]["to"] == account["email"]
    code = _code(outbox[0])
    assert len(code) == 6 and code.isdigit()

    resp = await client.post(
        "/api/auth/password-reset/confirm",
        json={"email": account["email"], "code": code, "new_password": "brandnew456"},
    )
    assert resp.status_code == 200, resp.text
    assert (await client.get("/api/auth/me", headers={"Authorization": f"Bearer {resp.json()['token']}"})).status_code == 200
    # Old sessions are signed out; the new password works, the old one doesn't.
    assert (await client.get("/api/auth/me", headers={"Authorization": f"Bearer {account['token']}"})).status_code == 401
    assert (await client.post("/api/auth/login", json={"email": account["email"], "password": "brandnew456"})).status_code == 200
    assert (await client.post("/api/auth/login", json={"email": account["email"], "password": "oldpass123"})).status_code == 401
    # A code works once.
    again = await client.post(
        "/api/auth/password-reset/confirm",
        json={"email": account["email"], "code": code, "new_password": "another789"},
    )
    assert again.status_code == 400


async def test_unknown_email_gets_the_same_answer_and_no_email(client, outbox, account):
    known = await client.post("/api/auth/password-reset/request", json={"email": account["email"]})
    unknown = await client.post("/api/auth/password-reset/request", json={"email": f"nobody_{uuid.uuid4().hex[:6]}@example.com"})
    assert known.status_code == unknown.status_code == 200
    assert known.json() == unknown.json()
    assert len(outbox) == 1


async def test_five_wrong_codes_burn_the_code(client, outbox, account):
    await client.post("/api/auth/password-reset/request", json={"email": account["email"]})
    real = _code(outbox[0])
    wrong = "000000" if real != "000000" else "111111"
    for _ in range(4):
        r = await client.post("/api/auth/password-reset/confirm", json={"email": account["email"], "code": wrong, "new_password": "brandnew456"})
        assert r.status_code == 400
    r = await client.post("/api/auth/password-reset/confirm", json={"email": account["email"], "code": wrong, "new_password": "brandnew456"})
    assert "Too many wrong codes" in r.json()["detail"]
    # Even the right code is now dead.
    r = await client.post("/api/auth/password-reset/confirm", json={"email": account["email"], "code": real, "new_password": "brandnew456"})
    assert r.status_code == 400


async def test_one_inbox_cant_be_flooded(client, outbox, account):
    for _ in range(5):
        assert (await client.post("/api/auth/password-reset/request", json={"email": account["email"]})).status_code == 200
    assert len(outbox) == 3  # per-email limit; the answer stays the same


async def test_only_a_hash_of_the_code_is_stored(client, outbox, account):
    await client.post("/api/auth/password-reset/request", json={"email": account["email"]})
    async with async_session() as db:
        stored = await db.scalar(select(PasswordResetCode.code_hash).join(User).where(User.email == account["email"]))
    assert stored and _code(outbox[0]) not in stored and len(stored) == 64


async def test_not_set_up_says_so(client, account, monkeypatch):
    monkeypatch.setattr(email_module, "email_configured", lambda: False)
    resp = await client.post("/api/auth/password-reset/request", json={"email": account["email"]})
    assert resp.status_code == 503
