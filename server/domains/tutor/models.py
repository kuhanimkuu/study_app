"""Lessons (2026-10-21): Sage teaches one topic in small steps, each ending
in a question that checks it landed — the app's answer to "it feels like
an AI prompting app". See lessons.py for generation, router.py for the
flow."""
from __future__ import annotations

import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class Lesson(Base):
    __tablename__ = "lessons"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    knowledge_space_id: Mapped[int] = mapped_column(
        ForeignKey("knowledge_spaces.id", ondelete="CASCADE"), nullable=False, index=True
    )
    concept_id: Mapped[int] = mapped_column(ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True)
    topic: Mapped[str] = mapped_column(String(255), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    # [{"heading", "explanation", "question_id" | None, "why", "result": None | {"correct", "answer", "feedback"}}]
    steps: Mapped[Any] = mapped_column(JSONB, nullable=False)
    worked_example: Mapped[Any | None] = mapped_column(JSONB, nullable=True)  # {"problem", "solution"}
    recap: Mapped[Any] = mapped_column(JSONB, nullable=False)  # [{"front", "back"}]
    grounded_in_notes: Mapped[bool] = mapped_column(nullable=False, default=False)
    answered: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    correct: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="in_progress")  # | "completed"
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )
    completed_at: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    @property
    def checks(self) -> int:
        return sum(1 for step in self.steps if step.get("question_id"))

    def summary(self) -> dict:
        return {
            "id": self.id,
            "topic": self.topic,
            "title": self.title,
            "concept_id": self.concept_id,
            "status": self.status,
            "steps": len(self.steps),
            "checks": self.checks,
            "answered": self.answered,
            "correct": self.correct,
            "created_at": self.created_at.isoformat(),
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
