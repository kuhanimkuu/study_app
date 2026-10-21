"""Login/signup under a bot flood (2026-10-21) — see core/security.py's
password lanes. Before, bcrypt ran on the event loop: 100 bot signups made
a real login take 16-21 s and froze every other request for ~14 s."""
from __future__ import annotations

import asyncio
import time
import uuid

import pytest
from sqlalchemy import delete

from server.core import security
from server.db.session import async_session
from server.domains.identity.models import User


@pytest.fixture
async def accounts(client):
    emails = [f"pytest_load_{uuid.uuid4().hex[:10]}@example.com" for _ in range(2)]
    ids = []
    for email in emails:
        resp = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
        assert resp.status_code == 200, resp.text
        ids.append(resp.json()["user"]["id"])
    yield list(zip(emails, ids))
    async with async_session() as db:
        await db.execute(delete(User).where(User.email.in_(emails)))
        await db.commit()


async def test_password_checks_do_not_block_other_requests(client, accounts):
    (email, _), _ = accounts

    async def wrong_login():
        return await client.post("/api/auth/login", json={"email": email, "password": "wrong-guess"})

    async def health_after_a_moment():
        await asyncio.sleep(0.05)
        started = time.perf_counter()
        resp = await client.get("/api/health")
        return resp.status_code, time.perf_counter() - started

    # Four ~0.3 s checks queue for the same account / lane; health must not wait on them.
    *_, (status, took) = await asyncio.gather(*(wrong_login() for _ in range(4)), health_after_a_moment())
    assert status == 200
    assert took < 0.25, f"health waited {took:.2f}s behind password hashing"


async def test_a_full_login_lane_answers_busy_at_once_instead_of_queueing(client, accounts, monkeypatch):
    (email, _), _ = accounts
    monkeypatch.setattr(security.login_lane, "in_lane", security.login_lane._max_in_lane)
    started = time.perf_counter()
    resp = await client.post("/api/auth/login", json={"email": email, "password": "testpass123"})
    assert resp.status_code == 503
    assert resp.headers["retry-after"] == "5"
    assert time.perf_counter() - started < 0.2


async def test_bots_on_one_account_dont_hold_up_other_accounts(client, accounts, monkeypatch):
    (attacked_email, attacked_id), (other_email, _) = accounts
    # As if a bot's guess for this account is still being checked.
    monkeypatch.setattr(security, "_verifying_accounts", {attacked_id})

    resp = await client.post("/api/auth/login", json={"email": attacked_email, "password": "testpass123"})
    assert resp.status_code == 503  # the app retries this quietly
    resp = await client.post("/api/auth/login", json={"email": other_email, "password": "testpass123"})
    assert resp.status_code == 200, resp.text


async def test_a_signup_flood_does_not_block_logins(client, accounts, monkeypatch):
    (email, _), _ = accounts
    monkeypatch.setattr(security.signup_lane, "in_lane", security.signup_lane._max_in_lane)

    resp = await client.post(
        "/api/auth/signup", json={"email": f"pytest_load_{uuid.uuid4().hex[:10]}@example.com", "password": "testpass123"}
    )
    assert resp.status_code == 503
    resp = await client.post("/api/auth/login", json={"email": email, "password": "testpass123"})
    assert resp.status_code == 200, resp.text


async def test_account_slot_is_released_after_each_check(client, accounts):
    (email, user_id), _ = accounts
    assert (await client.post("/api/auth/login", json={"email": email, "password": "wrong"})).status_code == 401
    assert user_id not in security._verifying_accounts
    assert (await client.post("/api/auth/login", json={"email": email, "password": "testpass123"})).status_code == 200
