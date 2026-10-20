"""
Crash reports from the app (2026-10-20) — kept on Study OS's own server
rather than a third-party crash service, so no student data goes anywhere
new. What's stored is only what the privacy policy names: the error, where
in the code it happened (stack), the app version and the phone platform —
never notes, chats or what the student typed.

Repeats of the same error are folded into one row (`count`, `last_seen`)
by fingerprint, so a crash loop on one phone is one line in the report,
not thousands of rows. Deleted after 30 days by workers/cleanup.py.
"""
from __future__ import annotations

import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base

RETENTION_DAYS = 30


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class ClientError(Base):
    __tablename__ = "client_errors"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Null when the error happened before login. SET NULL, not CASCADE: a
    # deleted account's crash still matters, just no longer tied to anyone.
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    fingerprint: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    app_version: Mapped[str] = mapped_column(String(40), nullable=False)
    platform: Mapped[str] = mapped_column(String(60), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    stack: Mapped[str] = mapped_column(Text, nullable=False)
    count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    first_seen: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)
    last_seen: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )
