"""
PersonalityProfile (blueprint Section 7) — one row per user. Implements
exactly the 8 dimensions blueprint's OWN worked JSON example uses (tone,
formality, humor, encouragement, directness, challenge_level, verbosity,
teaching_style), not its full 14-dimension aspirational list (which also
names patience, explanation_depth, use_of_examples, visual_preference,
socratic_questioning_preference, correction_style, motivation_style —
deferred, no concrete worked example to anchor a first implementation to).

Real typed columns, not a JSONB blob like Memory: personality has a small,
fixed, well-known set of dimensions per user — that's what columns are
for. Categorical dimensions (tone/formality/verbosity/teaching_style) are
constrained to a closed set for the same data-quality reason
RELATIONSHIP_TYPES/GRADABLE_TYPES are — a typo'd value would silently
never match anything that branches on it (see prompt.py).

Defaults (set here, applied by router.py's get-or-create) match
blueprint's own example values — a reasonable, neutral starting point,
not zero/empty, so a first `/explain` call before any personality setup
still reads naturally.
"""
from __future__ import annotations

import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from ...db.base import Base

TONE_VALUES = frozenset({"friendly", "neutral", "formal", "playful"})
FORMALITY_VALUES = frozenset({"casual", "neutral", "formal"})
VERBOSITY_VALUES = frozenset({"concise", "moderate", "detailed"})
TEACHING_STYLE_VALUES = frozenset({"example_first", "theory_first", "socratic", "story_driven"})


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class PersonalityProfile(Base):
    __tablename__ = "personality_profiles"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )

    tone: Mapped[str] = mapped_column(String(20), nullable=False, default="friendly")
    formality: Mapped[str] = mapped_column(String(20), nullable=False, default="casual")
    humor: Mapped[float] = mapped_column(nullable=False, default=0.3)
    encouragement: Mapped[float] = mapped_column(nullable=False, default=0.7)
    directness: Mapped[float] = mapped_column(nullable=False, default=0.6)
    challenge_level: Mapped[float] = mapped_column(nullable=False, default=0.5)
    verbosity: Mapped[str] = mapped_column(String(20), nullable=False, default="moderate")
    teaching_style: Mapped[str] = mapped_column(String(20), nullable=False, default="example_first")

    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
    updated_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "tone": self.tone,
            "formality": self.formality,
            "humor": self.humor,
            "encouragement": self.encouragement,
            "directness": self.directness,
            "challenge_level": self.challenge_level,
            "verbosity": self.verbosity,
            "teaching_style": self.teaching_style,
            "updated_at": self.updated_at.isoformat(),
        }
