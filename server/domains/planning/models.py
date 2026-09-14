"""
Goal and StudySession (blueprint Sections 21-22). A Goal is optionally
scoped to a Knowledge Space (nullable — an account-wide goal like "pass my
finals" doesn't have to name one space); a StudySession stores its
generated plan as JSONB (see planner.py) since the plan is a document
returned to the client, not something queried/joined on independently.
"""
from __future__ import annotations

import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class Goal(Base):
    __tablename__ = "goals"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    knowledge_space_id: Mapped[int | None] = mapped_column(
        ForeignKey("knowledge_spaces.id", ondelete="CASCADE"), nullable=True, index=True
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    target_date: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "knowledge_space_id": self.knowledge_space_id,
            "title": self.title,
            "target_date": self.target_date.isoformat() if self.target_date else None,
            "created_at": self.created_at.isoformat(),
        }


class StudySession(Base):
    __tablename__ = "study_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    planned_duration_minutes: Mapped[int] = mapped_column(nullable=False)
    plan: Mapped[Any] = mapped_column(JSONB, nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")  # active | completed
    started_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    ended_at: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "planned_duration_minutes": self.planned_duration_minutes,
            "plan": self.plan,
            "status": self.status,
            "started_at": self.started_at.isoformat(),
            "ended_at": self.ended_at.isoformat() if self.ended_at else None,
            "created_at": self.created_at.isoformat(),
        }
