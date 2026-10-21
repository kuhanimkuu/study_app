"""Tests for the 2026-10-19 load work: how server/core/runtime_env.py
resolves the engine limits, run_in_thread, and the pending-clarification
bug the 15-user load test found (a new upload after a PDF's "what would you
like me to do with it?" was discarded and the old PDF replayed).

Run with: python -m pytest server/tests/test_heavy_engine_limits.py -v
"""
from __future__ import annotations

import threading
import types

import features.moderator.engine as moderator_engine
from server.core import runtime_env


def test_resolve_auto_and_explicit(monkeypatch):
    monkeypatch.setenv("STUDY_OS_TEST_LIMIT", "auto")
    assert runtime_env._resolve("STUDY_OS_TEST_LIMIT", 3) == 3
    monkeypatch.setenv("STUDY_OS_TEST_LIMIT", "5")
    assert runtime_env._resolve("STUDY_OS_TEST_LIMIT", 3) == 5
    # never 0 workers/threads, even if someone writes 0
    monkeypatch.setenv("STUDY_OS_TEST_LIMIT", "0")
    assert runtime_env._resolve("STUDY_OS_TEST_LIMIT", 3) == 1
    monkeypatch.delenv("STUDY_OS_TEST_LIMIT")
    assert runtime_env._resolve("STUDY_OS_TEST_LIMIT", 2) == 2


async def test_run_in_thread_runs_off_the_event_loop():
    seen: dict = {}

    async def fake_run(**kwargs):
        seen["thread"] = threading.current_thread().name
        return {"echo": kwargs}

    engine = types.SimpleNamespace(run=fake_run)
    result = await moderator_engine.run_in_thread(engine, value=1)
    assert result == {"echo": {"value": 1}}
    assert seen["thread"].startswith("heavy-engine")


async def test_new_pdf_upload_replaces_pending_pdf_clarification():
    session = "test_pending_new_upload"
    moderator_engine._pending.pop((None, session), None)
    try:
        first = await moderator_engine.run(input_type="pdf", content="old notes", session_id=session)
        assert first["blocks"][0]["type"] == "clarification"

        second = await moderator_engine.run(input_type="pdf", content="new notes", session_id=session)
        assert second["blocks"][0]["type"] == "clarification"
        # before the fix the pending context was resumed, so this was still "old notes"
        assert moderator_engine._pending[(None, session)]["context"]["content"] == "new notes"
    finally:
        moderator_engine._pending.pop((None, session), None)


async def test_pdf_follow_up_without_new_content_still_resumes():
    session = "test_pending_follow_up"
    moderator_engine._pending.pop((None, session), None)
    try:
        await moderator_engine.run(input_type="pdf", content="old notes", session_id=session)
        # a bare follow-up (the /api/ask/pdf query-only call) carries no content or path;
        # it must still resume the stored PDF — here it then asks for the missing path
        result = await moderator_engine.run(input_type="pdf", content="", query="mitosis", session_id=session)
        assert result["blocks"][0]["type"] == "clarification"
        assert moderator_engine._pending[(None, session)]["context"]["content"] == "old notes"
    finally:
        moderator_engine._pending.pop((None, session), None)


async def test_pending_clarifications_are_per_user():
    # The project screen names its session "project_<slug>", so two students
    # with a project of the same name used to share one pending entry.
    session = "project_biology"
    for uid in (101, 202):
        moderator_engine._pending.pop((uid, session), None)
    try:
        await moderator_engine.run(input_type="pdf", content="student A's notes", session_id=session, user_id=101)
        # Student B's bare follow-up used to resume student A's stored PDF.
        result = await moderator_engine.run(input_type="pdf", content="", query="mitosis", session_id=session, user_id=202)
        assert (101, session) in moderator_engine._pending
        assert moderator_engine._pending[(101, session)]["context"]["content"] == "student A's notes"
        assert "student A" not in str(result)
    finally:
        for uid in (101, 202):
            moderator_engine._pending.pop((uid, session), None)


async def test_pending_clarifications_expire(monkeypatch):
    session = "test_pending_expiry"
    moderator_engine._pending.pop((None, session), None)
    await moderator_engine.run(input_type="pdf", content="old notes", session_id=session)
    moderator_engine._pending[(None, session)]["at"] -= moderator_engine._PENDING_TTL_SECONDS + 1
    assert moderator_engine._take_pending((None, session)) is None
