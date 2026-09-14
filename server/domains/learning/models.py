"""
Concept, Mastery, and ConceptRelationship (blueprint Sections 15-16). A
Concept belongs to a Knowledge Space (Section 14) — e.g. "Bernoulli
Equation" under "Fluid Mechanics". Mastery is one row per (user, concept),
tracking real FSRS scheduling state (see scheduler.py) plus raw attempt
counters.

Deliberately NOT storing separate "recall"/"retention"/"confidence"
columns the blueprint's wishlist (Section 16) names individually — those
are derivable from the FSRS state (stability/difficulty/last_review) at
read time via the FSRS library's own retrievability formula
(scheduler.py's retrievability()), and a composite `mastery` score is
likewise computed, not stored. Storing them as separate columns would let
them drift out of sync with the FSRS state that actually determines them
— a staleness bug waiting to happen, not a feature.

ConceptRelationship is a deliberately SCOPED-DOWN version of blueprint
Section 15's Knowledge Graph: concept-to-concept edges only (not the full
multi-node-type graph across Topic/Formula/Definition/Example/Skill/etc.
Section 15 describes) — the real near-term payoff is feeding
`planning/planner.py`'s `prerequisite_importance` component (explicitly
omitted 2 slices ago for lack of any relationship data), not building a
general knowledge-representation system speculatively.
"""
from __future__ import annotations

import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ...db.base import Base

# The 7 relationship types blueprint Section 15 names. A closed set (not
# an open string) for the same data-quality reason question `type` isn't
# open-ended either — a typo'd relationship type would silently never
# match anything that queries by it.
RELATIONSHIP_TYPES = frozenset(
    {"requires", "depends_on", "related_to", "part_of", "contrasts_with", "applied_to", "tested_by"}
)


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class Concept(Base):
    __tablename__ = "concepts"

    id: Mapped[int] = mapped_column(primary_key=True)
    knowledge_space_id: Mapped[int] = mapped_column(
        ForeignKey("knowledge_spaces.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "knowledge_space_id": self.knowledge_space_id,
            "name": self.name,
            "description": self.description,
            "created_at": self.created_at.isoformat(),
        }


class Mastery(Base):
    __tablename__ = "mastery"
    __table_args__ = (UniqueConstraint("user_id", "concept_id", name="uq_mastery_user_concept"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    concept_id: Mapped[int] = mapped_column(ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True)

    # Mirrors fsrs.Card's fields exactly (see scheduler.py's
    # _card_from_mastery/_apply_card_to_mastery) so round-tripping through
    # the FSRS library on every review is a direct field-for-field mapping,
    # not a lossy translation.
    fsrs_state: Mapped[int] = mapped_column(Integer, nullable=False, default=1)  # fsrs.State: 1=Learning 2=Review 3=Relearning
    fsrs_step: Mapped[int | None] = mapped_column(Integer, nullable=True, default=0)
    fsrs_stability: Mapped[float | None] = mapped_column(nullable=True)
    fsrs_difficulty: Mapped[float | None] = mapped_column(nullable=True)
    fsrs_due: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)
    fsrs_last_review: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    correct: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    incorrect: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_correct_at: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_incorrect_at: Mapped[datetime.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    concept: Mapped[Concept] = relationship()


class ConceptRelationship(Base):
    __tablename__ = "concept_relationships"
    __table_args__ = (
        UniqueConstraint(
            "from_concept_id", "to_concept_id", "relationship_type", name="uq_concept_relationship"
        ),
        CheckConstraint("from_concept_id != to_concept_id", name="ck_concept_relationship_no_self_edge"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    from_concept_id: Mapped[int] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    to_concept_id: Mapped[int] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    relationship_type: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "from_concept_id": self.from_concept_id,
            "to_concept_id": self.to_concept_id,
            "relationship_type": self.relationship_type,
            "created_at": self.created_at.isoformat(),
        }
