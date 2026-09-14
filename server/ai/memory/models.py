"""
Memory (blueprint Sections 8-9) — the two tiers not already covered by
existing real data: `explicit` (deliberately stated preferences/facts) and
`episodic` (significant study events). Learning memory is already
Mastery/Misconception/ConceptRelationship; session memory is correctly
ephemeral in-process state (features/moderator/engine.py's `_pending`
dict, StudySession) — neither gets a parallel table here, see
STUDY_OS_PROGRESS.md's 2026-09-14 entry for why.

One table for both tiers, not two: they share the same shape (source,
confidence, timestamps) blueprint Section 9 describes — a second table
would just repeat the same columns under a different name.

`confidence`/`source` are set SERVER-SIDE only (never trusted from a
client request) — see ai/memory/router.py's create_explicit_memory: a
client stating a preference always gets source="user_stated",
confidence=1.0, regardless of what it sends, so a client can't forge a
fake high-confidence "system_derived" entry.
"""
from __future__ import annotations

import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base

MEMORY_TYPES = frozenset({"explicit", "episodic"})
MEMORY_SOURCES = frozenset({"user_stated", "system_derived"})


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class Memory(Base):
    __tablename__ = "memories"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(20), nullable=False, index=True)  # "explicit" | "episodic"
    key: Mapped[str] = mapped_column(String(255), nullable=False)
    value: Mapped[Any] = mapped_column(JSONB, nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False)  # "user_stated" | "system_derived"
    confidence: Mapped[float] = mapped_column(nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )
    last_used_at: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    def public(self) -> dict:
        return {
            "id": self.id,
            "type": self.type,
            "key": self.key,
            "value": self.value,
            "source": self.source,
            "confidence": self.confidence,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "last_used_at": self.last_used_at.isoformat() if self.last_used_at else None,
        }
