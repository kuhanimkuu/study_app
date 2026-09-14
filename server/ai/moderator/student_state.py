"""
A compact per-concept snapshot of what's actually known about a student —
built from Mastery (blueprint Phase 2, `server/domains/learning/`),
Misconception (`server/domains/assessment/`), explicit Memory
(`server/ai/memory/`), and, as of 2026-09-14, the student's
PersonalityProfile (`server/ai/personality/`) — style preferences now
reach `explain.py`'s prompt alongside mastery-driven depth and stated
memories.

Explicit memories are user/account-scoped, not concept-scoped (a
preference about explanation style isn't "about" any one concept), so this
fetches all of the user's explicit memories, not ones filtered to this
concept — in practice a small number, no pagination needed yet.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...ai.memory.models import Memory
from ...ai.personality.models import PersonalityProfile
from ...ai.personality.router import get_or_create_personality
from ...domains.assessment.models import Misconception
from ...domains.learning.models import Concept, Mastery
from ...domains.learning.scheduler import mastery_score, retrievability


@dataclass
class StudentState:
    concept_name: str
    concept_description: str | None
    attempts: int
    mastery: float
    retrievability: float | None
    has_active_misconception: bool
    misconception_notes: list[str]
    personality: PersonalityProfile
    relevant_memories: list[dict] = field(default_factory=list)


async def get_student_state(db: AsyncSession, user_id: int, concept: Concept) -> StudentState:
    mastery_row = await db.scalar(
        select(Mastery).where(Mastery.user_id == user_id, Mastery.concept_id == concept.id)
    )
    misconceptions = (
        await db.scalars(
            select(Misconception).where(
                Misconception.user_id == user_id,
                Misconception.concept_id == concept.id,
                Misconception.resolved_at.is_(None),
            )
        )
    ).all()
    explicit_memories = (
        await db.scalars(select(Memory).where(Memory.user_id == user_id, Memory.type == "explicit"))
    ).all()
    personality = await get_or_create_personality(db, user_id)

    return StudentState(
        concept_name=concept.name,
        concept_description=concept.description,
        attempts=mastery_row.attempts if mastery_row else 0,
        mastery=mastery_score(mastery_row) if mastery_row else 0.0,
        retrievability=round(retrievability(mastery_row), 4) if mastery_row and mastery_row.attempts else None,
        has_active_misconception=bool(misconceptions),
        misconception_notes=[m.description for m in misconceptions],
        personality=personality,
        relevant_memories=[{"key": m.key, "value": m.value} for m in explicit_memories],
    )
