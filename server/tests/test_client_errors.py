"""App crash reports (2026-10-20): POST /api/v1/client-errors works signed in
or not, folds repeats of the same error into one row, caps sizes, rate-limits,
and old reports are removed by the cleanup pass."""
from __future__ import annotations

import datetime
import uuid

import pytest
from sqlalchemy import delete, select, update

from server.db.session import async_session
from server.domains.diagnostics import router as diagnostics_router
from server.domains.diagnostics.models import ClientError
from server.domains.identity.models import User
from server.workers.cleanup import delete_old_client_errors


def _report(message: str, **extra) -> dict:
    return {
        "message": message,
        "stack": "#0 HomeScreen._load (package:study_os_frontend/home.dart:112:7)\n#1 main.dart:20",
        "app_version": "9.9.9-test",
        "platform": "android 14",
        **extra,
    }


@pytest.fixture(autouse=True)
async def _clean():
    diagnostics_router._recent.clear()
    yield
    diagnostics_router._recent.clear()
    async with async_session() as db:
        await db.execute(delete(ClientError).where(ClientError.app_version == "9.9.9-test"))
        await db.commit()


@pytest.fixture
async def student(client):
    email = f"pytest_errors_{uuid.uuid4().hex[:12]}@example.com"
    signup = await client.post("/api/auth/signup", json={"email": email, "password": "testpass123"})
    yield {"headers": {"Authorization": f"Bearer {signup.json()['token']}"}, "user_id": signup.json()["user"]["id"]}
    async with async_session() as db:
        await db.execute(delete(User).where(User.email == email))
        await db.commit()


async def _rows() -> list[ClientError]:
    async with async_session() as db:
        return list((await db.scalars(select(ClientError).where(ClientError.app_version == "9.9.9-test"))).all())


async def test_anonymous_report_is_stored_and_repeats_fold_into_one_row(client):
    for object_id in (101, 202, 303):
        # Differing ids in the message are masked out of the fingerprint.
        resp = await client.post("/api/v1/client-errors", json=_report(f"Null check failed on item {object_id}"))
        assert resp.status_code == 204, resp.text
    rows = await _rows()
    assert len(rows) == 1
    assert rows[0].count == 3 and rows[0].user_id is None


async def test_signed_in_report_is_tied_to_the_student_and_a_bad_token_still_counts(client, student):
    assert (await client.post("/api/v1/client-errors", json=_report("Boom"), headers=student["headers"])).status_code == 204
    resp = await client.post("/api/v1/client-errors", json=_report("Boom"), headers={"Authorization": "Bearer nonsense"})
    assert resp.status_code == 204
    rows = sorted(await _rows(), key=lambda r: r.user_id or 0)
    assert [r.user_id for r in rows] == [None, student["user_id"]]


async def test_long_fields_are_truncated_and_huge_ones_rejected(client):
    resp = await client.post("/api/v1/client-errors", json=_report("x" * 5_000, stack="y" * 20_000))
    assert resp.status_code == 204
    row = (await _rows())[0]
    assert len(row.message) == 2_000 and len(row.stack) == 8_000

    resp = await client.post("/api/v1/client-errors", json=_report("x" * 30_000))
    assert resp.status_code == 422


async def test_rate_limited_per_caller(client):
    for i in range(diagnostics_router.PER_HOUR):
        resp = await client.post("/api/v1/client-errors", json=_report(f"Error kind {chr(65 + i % 26)}"))
        assert resp.status_code == 204
    resp = await client.post("/api/v1/client-errors", json=_report("one too many"))
    assert resp.status_code == 429


async def test_cleanup_removes_reports_older_than_30_days(client):
    await client.post("/api/v1/client-errors", json=_report("Old error"))
    await client.post("/api/v1/client-errors", json=_report("Fresh error", stack="#0 elsewhere.dart:1"))
    async with async_session() as db:
        await db.execute(
            update(ClientError)
            .where(ClientError.message == "Old error")
            .values(last_seen=datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=31))
        )
        await db.commit()
    await delete_old_client_errors()
    assert [r.message for r in await _rows()] == ["Fresh error"]
