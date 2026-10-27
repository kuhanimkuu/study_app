"""Go deeper (2026-10-27, Study OS plan steps 2-3): cached API results, a
log of every source shown, students' reports, and a blocklist that can be
changed without a release."""
from __future__ import annotations

import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class ResearchCache(Base):
    """One API answer, kept to save quota and be polite to the providers."""

    __tablename__ = "research_cache"

    id: Mapped[int] = mapped_column(primary_key=True)
    key: Mapped[str] = mapped_column(String(400), nullable=False, unique=True)
    value: Mapped[Any] = mapped_column(JSONB, nullable=False)
    expires_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)


class SourceLog(Base):
    """Every source shown to a student: if someone complains about one, this
    says what was shown, under which licence and tier, and when."""

    __tablename__ = "source_log"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    url: Mapped[str] = mapped_column(String(2000), nullable=False)
    provider: Mapped[str] = mapped_column(String(40), nullable=False)
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    licence: Mapped[str | None] = mapped_column(String(80), nullable=True)
    tier: Mapped[str] = mapped_column(String(1), nullable=False)
    attribution: Mapped[str] = mapped_column(Text, nullable=False)
    retrieved_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False, index=True)


class SourceReport(Base):
    __tablename__ = "source_reports"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    url: Mapped[str] = mapped_column(String(2000), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)


class BlockedSource(Base):
    """A domain ("example.com", also blocks its subdomains) or an exact URL
    never to show. Managed with `python -m server.domains.research.blocklist`."""

    __tablename__ = "blocked_sources"

    id: Mapped[int] = mapped_column(primary_key=True)
    pattern: Mapped[str] = mapped_column(String(500), nullable=False, unique=True)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)
