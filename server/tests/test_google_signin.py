"""Integration tests for POST /api/auth/google (blueprint Section 4).

Google's own `verify_oauth2_token` is mocked throughout — these tests
exercise this app's account-creation/linking/rate-limit logic, not
Google's token-verification library itself (that has its own test suite
upstream), and none of them touch the network.

Run with: python -m pytest server/tests/test_google_signin.py -v
"""
from __future__ import annotations

import uuid
from unittest.mock import patch

import pytest
from sqlalchemy import delete, select

from server.db.session import async_session
from server.domains.identity.models import User


def _unique_email() -> str:
    return f"pytest_google_{uuid.uuid4().hex[:12]}@example.com"


def _fake_claims(email: str, sub: str, *, email_verified: bool = True, name: str | None = "Test Student") -> dict:
    return {"email": email, "sub": sub, "email_verified": email_verified, "name": name}


async def _cleanup(email: str) -> None:
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def test_google_signin_creates_new_account(client):
    email = _unique_email()
    sub = f"google-{uuid.uuid4().hex[:16]}"
    try:
        with patch(
            "server.domains.identity.router.google_id_token.verify_oauth2_token",
            return_value=_fake_claims(email, sub),
        ):
            resp = await client.post("/api/auth/google", json={"id_token": "fake"})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["user"]["email"] == email
        assert body["user"]["display_name"] == "Test Student"
        assert "encryption_key" in body["user"]  # auth_response, same as signup/login
        assert "token" in body

        async with async_session() as db:
            user = await db.scalar(select(User).where(User.email == email))
            assert user is not None
            assert user.google_sub == sub
            assert user.password_hash is None
    finally:
        await _cleanup(email)


async def test_google_signin_second_call_logs_into_same_account(client):
    email = _unique_email()
    sub = f"google-{uuid.uuid4().hex[:16]}"
    try:
        with patch(
            "server.domains.identity.router.google_id_token.verify_oauth2_token",
            return_value=_fake_claims(email, sub),
        ):
            first = await client.post("/api/auth/google", json={"id_token": "fake"})
            second = await client.post("/api/auth/google", json={"id_token": "fake"})
        assert first.status_code == 200 and second.status_code == 200
        assert first.json()["user"]["id"] == second.json()["user"]["id"]

        async with async_session() as db:
            count = len((await db.scalars(select(User).where(User.email == email))).all())
            assert count == 1  # no duplicate account created on the second sign-in
    finally:
        await _cleanup(email)


async def test_google_signin_links_to_existing_password_account(client):
    email = _unique_email()
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    assert signup.status_code == 200, signup.text
    original_id = signup.json()["user"]["id"]

    sub = f"google-{uuid.uuid4().hex[:16]}"
    try:
        with patch(
            "server.domains.identity.router.google_id_token.verify_oauth2_token",
            return_value=_fake_claims(email, sub),
        ):
            resp = await client.post("/api/auth/google", json={"id_token": "fake"})
        assert resp.status_code == 200, resp.text
        assert resp.json()["user"]["id"] == original_id  # same account, not a new one

        async with async_session() as db:
            user = await db.get(User, original_id)
            assert user.google_sub == sub
            assert user.password_hash is not None  # the original password still works too

        # The original password login must still work after linking.
        login = await client.post("/api/auth/login", json={"email": email, "password": "testpass123"})
        assert login.status_code == 200
    finally:
        await _cleanup(email)


async def test_google_signin_rejects_unverified_email(client):
    email = _unique_email()
    sub = f"google-{uuid.uuid4().hex[:16]}"
    with patch(
        "server.domains.identity.router.google_id_token.verify_oauth2_token",
        return_value=_fake_claims(email, sub, email_verified=False),
    ):
        resp = await client.post("/api/auth/google", json={"id_token": "fake"})
    assert resp.status_code == 401

    async with async_session() as db:
        assert await db.scalar(select(User).where(User.email == email)) is None


async def test_google_signin_rejects_invalid_token(client):
    with patch(
        "server.domains.identity.router.google_id_token.verify_oauth2_token",
        side_effect=ValueError("Token expired"),
    ):
        resp = await client.post("/api/auth/google", json={"id_token": "garbage"})
    assert resp.status_code == 401


async def test_password_login_rejected_for_google_only_account(client):
    email = _unique_email()
    sub = f"google-{uuid.uuid4().hex[:16]}"
    try:
        with patch(
            "server.domains.identity.router.google_id_token.verify_oauth2_token",
            return_value=_fake_claims(email, sub),
        ):
            await client.post("/api/auth/google", json={"id_token": "fake"})

        # No password was ever set for this account — a password login
        # attempt (with any password) must be rejected the same clean way
        # as a wrong password, not crash on a None hash.
        resp = await client.post("/api/auth/login", json={"email": email, "password": "anything123"})
        assert resp.status_code == 401
    finally:
        await _cleanup(email)


async def test_delete_account_without_password_succeeds_for_google_only_account(client):
    email = _unique_email()
    sub = f"google-{uuid.uuid4().hex[:16]}"
    with patch(
        "server.domains.identity.router.google_id_token.verify_oauth2_token",
        return_value=_fake_claims(email, sub),
    ):
        signin = await client.post("/api/auth/google", json={"id_token": "fake"})
    headers = {"Authorization": f"Bearer {signin.json()['token']}"}

    # No password field at all — must still succeed since this account has
    # no password_hash to confirm against.
    resp = await client.request("DELETE", "/api/account", json={}, headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"deleted": True}

    async with async_session() as db:
        assert await db.scalar(select(User).where(User.email == email)) is None


async def test_google_signin_returns_503_when_not_configured(client):
    with patch("server.domains.identity.router.get_settings") as mock_settings:
        mock_settings.return_value.google_oauth_client_id = ""
        resp = await client.post("/api/auth/google", json={"id_token": "fake"})
    assert resp.status_code == 503
