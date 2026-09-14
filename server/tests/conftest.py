"""Shared pytest fixtures. Tests run against the real local Postgres
instance (server/core/config.py's DATABASE_URL / .env) — no mocking of the
database, this is an integration suite. Each test creates its own
uniquely-emailed user and cleans up after itself (see test files) rather
than requiring a separate throwaway database."""
from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from server.core import rate_limit
from server.main import app


@pytest.fixture(autouse=True)
def _reset_rate_limits():
    """Every request in this suite shares one synthetic client IP under
    httpx's ASGITransport (see server/core/rate_limit.py's reset()
    docstring) — without this, the real signup/login rate limits (correct,
    intentional behavior for production) would exhaust after a handful of
    tests regardless of which test actually needs them tight."""
    rate_limit.reset()
    yield


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
