"""
Deletes files the server no longer needs (2026-10-19). Before this nothing
was ever removed: the 15-user load test wrote ~830 files in two minutes, so
a long-running server's disk would only ever fill up.

Runs inside the app (started from server/main.py's lifespan) rather than as
a cron/systemd timer, so it works the same on every host. One pass a minute
after startup, then every CLEANUP_INTERVAL_HOURS. What it removes:

  server/uploads/**           files older than UPLOAD_RETENTION_HOURS (24).
                              Chat uploads are only needed while a PDF
                              follow-up is pending (minutes); a project
                              upload only while it's indexed, and its
                              original is kept in Postgres (StoredFile).
  features/moderator/generated/*
                              chat-made images/GIFs/PDFs/3D models older than
                              GENERATED_RETENTION_DAYS (14). Only old chat
                              history on the phone points at them; it then
                              shows "expired" instead of the picture.
  generated/user_<id>/, rag/projects/projects/user_<id>/
                              only when that user no longer exists. Studio
                              PDFs and project indexes of real users are
                              tracked in Postgres and never touched here.
                              (Closes the deleted-account-while-indexing
                              orphan found on 2026-10-19.)

CLEANUP_INTERVAL_HOURS=0 turns it off.
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import shutil
import time
from dataclasses import dataclass, field
from pathlib import Path

import datetime

from sqlalchemy import delete, select

from ..db.session import async_session
from ..domains.diagnostics.models import RETENTION_DAYS as CLIENT_ERROR_RETENTION_DAYS
from ..domains.diagnostics.models import ClientError
from ..domains.identity.models import User

logger = logging.getLogger("study_os.cleanup")

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
UPLOADS_DIR = _REPO_ROOT / "server" / "uploads"
GENERATED_DIR = _REPO_ROOT / "features" / "moderator" / "generated"
RAG_PROJECTS_DIR = _REPO_ROOT / "features" / "rag" / "projects" / "projects"

_USER_DIR_RE = re.compile(r"^user_(\d+)$")
_FIRST_RUN_DELAY_SECONDS = 60
# A user who signs up during a pass isn't in its user list yet; leaving any
# folder touched within the last hour means theirs is never mistaken for
# an orphan.
_ORPHAN_MIN_AGE_SECONDS = 3600


def _hours_setting(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


@dataclass
class CleanupResult:
    files: int = 0
    bytes: int = 0
    orphan_dirs: list[str] = field(default_factory=list)


def _delete_old_files(root: Path, max_age_seconds: float, now: float, result: CleanupResult, recursive: bool) -> None:
    if not root.is_dir():
        return
    for path in root.rglob("*") if recursive else root.iterdir():
        try:
            if path.is_file() and not path.is_symlink():
                stat = path.stat()
                if now - stat.st_mtime > max_age_seconds:
                    path.unlink()
                    result.files += 1
                    result.bytes += stat.st_size
        except OSError:
            continue  # vanished or locked meanwhile — try again next pass
    if recursive:
        # deepest first, so a session folder emptied above goes too; never root itself
        for path in sorted((p for p in root.rglob("*") if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
            try:
                path.rmdir()  # only succeeds when empty
            except OSError:
                pass


def _delete_orphan_user_dirs(root: Path, live_user_ids: set[int], now: float, result: CleanupResult) -> None:
    if not root.is_dir():
        return
    for path in root.iterdir():
        match = _USER_DIR_RE.match(path.name)
        if (
            path.is_dir()
            and match
            and int(match.group(1)) not in live_user_ids
            and now - path.stat().st_mtime > _ORPHAN_MIN_AGE_SECONDS
        ):
            shutil.rmtree(path, ignore_errors=True)
            result.orphan_dirs.append(str(path.relative_to(_REPO_ROOT)))


def clean_files(live_user_ids: set[int], *, upload_hours: float, generated_days: float, now: float | None = None) -> CleanupResult:
    """One synchronous pass (blocking file I/O — run it in a thread)."""
    now = time.time() if now is None else now
    result = CleanupResult()
    _delete_old_files(UPLOADS_DIR, upload_hours * 3600, now, result, recursive=True)
    _delete_old_files(GENERATED_DIR, generated_days * 86400, now, result, recursive=False)
    for root in (GENERATED_DIR, RAG_PROJECTS_DIR, UPLOADS_DIR / "projects"):
        _delete_orphan_user_dirs(root, live_user_ids, now, result)
    return result


async def delete_expired_reset_codes() -> int:
    """Forgot-password codes past their 15 minutes (identity/router.py)."""
    from ..domains.identity.models import PasswordResetCode

    async with async_session() as db:
        result = await db.execute(
            delete(PasswordResetCode).where(PasswordResetCode.expires_at < datetime.datetime.now(datetime.timezone.utc))
        )
        await db.commit()
    return result.rowcount or 0


async def delete_old_client_errors() -> int:
    """App crash reports are kept 30 days after they were last seen, as the
    privacy policy says. Returns how many were deleted."""
    cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=CLIENT_ERROR_RETENTION_DAYS)
    async with async_session() as db:
        result = await db.execute(delete(ClientError).where(ClientError.last_seen < cutoff))
        await db.commit()
    return result.rowcount or 0


async def run_cleanup_once() -> CleanupResult:
    async with async_session() as db:
        live_user_ids = set((await db.scalars(select(User.id))).all())
    await delete_old_client_errors()
    await delete_expired_reset_codes()
    result = await asyncio.to_thread(
        clean_files,
        live_user_ids,
        upload_hours=_hours_setting("UPLOAD_RETENTION_HOURS", 24),
        generated_days=_hours_setting("GENERATED_RETENTION_DAYS", 14),
    )
    if result.files or result.orphan_dirs:
        # warning: nothing configures this logger's level, and a line per
        # pass that actually deleted something is worth seeing in the logs
        logger.warning(
            "cleanup: deleted %d old files (%.1f MB) and %d orphaned user folders",
            result.files, result.bytes / 1024**2, len(result.orphan_dirs),
        )
    return result


async def cleanup_loop() -> None:
    interval_hours = _hours_setting("CLEANUP_INTERVAL_HOURS", 6)
    if interval_hours <= 0:
        return
    await asyncio.sleep(_FIRST_RUN_DELAY_SECONDS)
    while True:
        try:
            await run_cleanup_once()
        except Exception:
            # a failed pass (e.g. the database briefly down) must not kill
            # the loop — the next one simply tries again
            logger.exception("cleanup pass failed")
        await asyncio.sleep(interval_hours * 3600)
