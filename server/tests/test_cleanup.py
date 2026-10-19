"""Tests for server/workers/cleanup.py (2026-10-19) — run against temporary
folders, never the real uploads/generated directories.

Run with: python -m pytest server/tests/test_cleanup.py -v
"""
from __future__ import annotations

import os
import time

import pytest

from server.workers import cleanup

NOW = time.time()
DAY = 86400


def _file(path, age_seconds: float, size: int = 10):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    os.utime(path, (NOW - age_seconds, NOW - age_seconds))
    return path


def _age_dir(path, age_seconds: float):
    os.utime(path, (NOW - age_seconds, NOW - age_seconds))


@pytest.fixture
def dirs(tmp_path, monkeypatch):
    roots = {
        "uploads": tmp_path / "server" / "uploads",
        "generated": tmp_path / "features" / "moderator" / "generated",
        "rag": tmp_path / "features" / "rag" / "projects" / "projects",
    }
    for d in roots.values():
        d.mkdir(parents=True)
    monkeypatch.setattr(cleanup, "_REPO_ROOT", tmp_path)
    monkeypatch.setattr(cleanup, "UPLOADS_DIR", roots["uploads"])
    monkeypatch.setattr(cleanup, "GENERATED_DIR", roots["generated"])
    monkeypatch.setattr(cleanup, "RAG_PROJECTS_DIR", roots["rag"])
    return roots


def test_old_uploads_go_recent_stay(dirs):
    old_chat = _file(dirs["uploads"] / "session1" / "a.png", 2 * DAY)
    new_chat = _file(dirs["uploads"] / "session2" / "b.png", 60)
    old_project = _file(dirs["uploads"] / "projects" / "user_1" / "bio_x_notes.pdf", 2 * DAY)

    result = cleanup.clean_files({1}, upload_hours=24, generated_days=14, now=NOW)

    assert not old_chat.exists() and not old_project.exists()
    assert new_chat.exists()
    assert not (dirs["uploads"] / "session1").exists()  # emptied folder removed too
    assert dirs["uploads"].exists()  # the root itself is never removed
    assert result.files == 2 and result.bytes == 20


def test_generated_keeps_studio_folders_of_live_users(dirs):
    old_chat_image = _file(dirs["generated"] / "abc.png", 20 * DAY)
    recent_chat_image = _file(dirs["generated"] / "def.png", 2 * DAY)
    studio_pdf = _file(dirs["generated"] / "user_1" / "guide.pdf", 100 * DAY)
    _age_dir(dirs["generated"] / "user_1", 100 * DAY)

    cleanup.clean_files({1}, upload_hours=24, generated_days=14, now=NOW)

    assert not old_chat_image.exists()
    assert recent_chat_image.exists()
    assert studio_pdf.exists()  # tracked in Postgres; never aged out


def test_orphaned_user_folders_removed_only_when_old(dirs):
    orphan = dirs["rag"] / "user_99"
    _file(orphan / "bio.json", 2 * DAY)
    _age_dir(orphan, 2 * DAY)
    just_signed_up = dirs["rag"] / "user_100"
    _file(just_signed_up / "bio.json", 10)
    live = dirs["rag"] / "user_1"
    _file(live / "bio.json", 50 * DAY)
    _age_dir(live, 50 * DAY)

    result = cleanup.clean_files({1}, upload_hours=24, generated_days=14, now=NOW)

    assert not orphan.exists()
    assert just_signed_up.exists()  # not in this pass's user list yet, but too new to judge
    assert live.exists()
    assert result.orphan_dirs == [os.path.join("features", "rag", "projects", "projects", "user_99")]


async def test_cleanup_loop_disabled_by_setting(monkeypatch):
    monkeypatch.setenv("CLEANUP_INTERVAL_HOURS", "0")
    await cleanup.cleanup_loop()  # returns at once instead of looping
