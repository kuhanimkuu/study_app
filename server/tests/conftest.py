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


@pytest.fixture(scope="session", autouse=True)
def _remove_rag_dirs_of_deleted_test_users():
    """Most fixtures clean up with a raw `delete(User)` (cascades every
    table) — but a user's RAG index lives on disk under
    features/rag/projects/projects/user_<id>/, outside the cascade, so
    every suite run used to leave ~4 orphaned directories behind (found
    2026-10-07: 24 accumulated over two days). Only directories that
    appear *during this run* and whose user no longer exists are removed —
    anything present before the run is never touched."""
    import asyncio
    import re
    import shutil

    import asyncpg

    from server.core.config import get_settings
    from server.domains.identity.router import _RAG_PROJECTS_ROOT

    def _user_dirs() -> set[str]:
        if not _RAG_PROJECTS_ROOT.exists():
            return set()
        return {p.name for p in _RAG_PROJECTS_ROOT.iterdir() if p.is_dir() and re.fullmatch(r"user_\d+", p.name)}

    before = _user_dirs()
    yield
    created = _user_dirs() - before
    if not created:
        return

    async def _existing_ids() -> set[int]:
        conn = await asyncpg.connect(re.sub(r"\+asyncpg", "", get_settings().database_url))
        try:
            return {r["id"] for r in await conn.fetch("select id from users")}
        finally:
            await conn.close()

    alive = asyncio.run(_existing_ids())
    for name in created:
        if int(name[5:]) not in alive:
            shutil.rmtree(_RAG_PROJECTS_ROOT / name, ignore_errors=True)
