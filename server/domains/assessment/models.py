"""
Question / QuestionAttempt / Misconception (blueprint Sections 18-19).
Grading logic lives in grading.py, not here — these are pure data models.

`correct_answer`/`options`/`submitted_answer` are JSONB (native Postgres
JSON, not a serialized-string column) since their shape genuinely varies
by question `type` — see grading.py for exactly what shape each type
expects (e.g. a list of strings for multi_select, a single string for
mcq/numerical/equation/short_answer).
"""
from __future__ import annotations

import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ...db.base import Base

# Question types this slice can actually grade — see grading.py. The
# `type` column itself isn't constrained to only these (a future slice can
# add rows for other types), but the attempt endpoint refuses to fake a
# grade for one outside this set.
GRADABLE_TYPES = frozenset(
    {
        "mcq",
        "true_false",
        "fill_in_blank",
        "multi_select",
        "numerical",
        "equation",
        "matching",
        "ordering",
        "short_answer",
        "essay",
    }
)


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class Question(Base):
    __tablename__ = "questions"

    id: Mapped[int] = mapped_column(primary_key=True)
    concept_id: Mapped[int] = mapped_column(ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(50), nullable=False)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    correct_answer: Mapped[Any] = mapped_column(JSONB, nullable=False)
    options: Mapped[Any | None] = mapped_column(JSONB, nullable=True)
    tolerance: Mapped[float | None] = mapped_column(nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self, *, include_answer: bool = False) -> dict:
        """include_answer=False (the default, used when a student is
        practicing) never leaks correct_answer/tolerance — only the
        authoring endpoint's own response includes them."""
        d = {
            "id": self.id,
            "concept_id": self.concept_id,
            "type": self.type,
            "prompt": self.prompt,
            "options": self.options,
            "created_at": self.created_at.isoformat(),
        }
        if include_answer:
            d["correct_answer"] = self.correct_answer
            d["tolerance"] = self.tolerance
        return d


class QuestionAttempt(Base):
    __tablename__ = "question_attempts"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    question_id: Mapped[int] = mapped_column(ForeignKey("questions.id", ondelete="CASCADE"), nullable=False, index=True)
    submitted_answer: Mapped[Any] = mapped_column(JSONB, nullable=False)
    is_correct: Mapped[bool] = mapped_column(nullable=False)
    evaluated_by: Mapped[str] = mapped_column(String(20), nullable=False)  # "deterministic" | "ai"
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "question_id": self.question_id,
            "is_correct": self.is_correct,
            "evaluated_by": self.evaluated_by,
            "feedback": self.feedback,
            "created_at": self.created_at.isoformat(),
        }


class Misconception(Base):
    """A structural signal (repeated wrong answers on one concept), not a
    semantic classification of *what* the student misunderstands — see
    STUDY_OS_PROGRESS.md, 2026-09-14 for the scope boundary."""

    __tablename__ = "misconceptions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    concept_id: Mapped[int] = mapped_column(ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    detected_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    resolved_at: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    def public(self) -> dict:
        return {
            "id": self.id,
            "concept_id": self.concept_id,
            "description": self.description,
            "detected_at": self.detected_at.isoformat(),
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
        }
