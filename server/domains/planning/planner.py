"""
Prioritization + session phase generation (blueprint Sections 21-22).

Priority formula now includes a real (if scoped-down) version of blueprint
Section 22's "prerequisite_importance", now that learning/models.py's
ConceptRelationship exists: a concept gets a priority boost if other
concepts already in this planning pass "require"/"depend_on" it and are
themselves not yet solidly mastered — mastering a real prerequisite
unblocks real progress elsewhere. Scoped to relationships AMONG the
concepts already being considered in this call (not the student's entire
graph) — enough to reorder priority within one planning pass without an
extra broad query; a concept whose only dependents live in a different
Knowledge Space than the one being planned won't get credit for them here.

Weights below (0.6/0.4 review-vs-weakness blend, 0.7/0.3 base-vs-deadline
blend, the 1-week/30-day normalization windows, the 0.15 prerequisite
headroom-boost factor) are reasonable defaults, not tuned against real
usage data — there isn't any yet. Same honesty-note convention as
learning/scheduler.py's mastery_score blend.
"""
from __future__ import annotations

import datetime
from collections import defaultdict

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..knowledge.models import KnowledgeSpace
from ..learning.models import Concept, ConceptRelationship, Mastery
from ..learning.scheduler import mastery_score
from .models import Goal

_REVIEW_URGENCY_WINDOW_HOURS = 24 * 7  # a week: fully "urgent" once a review is this overdue
_DEADLINE_URGENCY_WINDOW_DAYS = 30  # ramps 0->1 over the last 30 days before a deadline
_PREREQUISITE_DEPENDENT_MASTERY_THRESHOLD = 0.7  # a dependent below this still "needs" its prerequisite
_PREREQUISITE_SATURATION_COUNT = 3  # importance maxes out around this many not-yet-mastered dependents

_PHASE_FRACTIONS = [
    ("retrieval_practice", 0.15),
    ("focus_weak_concepts", 0.50),
    ("practice", 0.25),
]
_REFLECTION_FRACTION = 0.10
_MINUTES_PER_CONCEPT = 5


def _clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def score_concept(
    mastery: Mastery | None,
    deadline: datetime.datetime | None,
    now: datetime.datetime,
    prerequisite_importance: float = 0.0,
) -> float:
    if mastery is None or mastery.attempts == 0:
        base = 0.8  # "need to learn" — never attempted, no FSRS state to reason about yet
    else:
        overdue_hours = (now - mastery.fsrs_due).total_seconds() / 3600
        review_urgency = _clamp(0.5 + overdue_hours / _REVIEW_URGENCY_WINDOW_HOURS)
        weakness = 1.0 - mastery_score(mastery)
        base = 0.6 * review_urgency + 0.4 * weakness

    if deadline is not None:
        days_left = max((deadline - now).total_seconds() / 86400, 0)
        deadline_urgency = _clamp(1.0 - days_left / _DEADLINE_URGENCY_WINDOW_DAYS)
        base = 0.7 * base + 0.3 * deadline_urgency

    if prerequisite_importance:
        # Additive headroom boost, NOT a blend/average — a concept already
        # scoring high (e.g. 0.8 for "never attempted") has little room
        # left to move, but critically must never move DOWN just because
        # prerequisite_importance happens to be lower than the base score.
        # (Caught by testing: an early version used
        # `0.85*base + 0.15*prerequisite_importance`, which pulled a
        # never-attempted prerequisite's score from 0.8 down to 0.73 —
        # exactly backwards for something meant to be a boost.)
        base = base + 0.15 * prerequisite_importance * (1.0 - base)

    return round(base, 4)


async def _compute_prerequisite_importance(
    db: AsyncSession, concept_ids: list[int], mastery_by_concept: dict[int, Mastery | None]
) -> dict[int, float]:
    if not concept_ids:
        return {}
    edges = (
        await db.execute(
            select(ConceptRelationship.from_concept_id, ConceptRelationship.to_concept_id).where(
                ConceptRelationship.relationship_type.in_(("requires", "depends_on")),
                ConceptRelationship.from_concept_id.in_(concept_ids),
                ConceptRelationship.to_concept_id.in_(concept_ids),
            )
        )
    ).all()

    # from_concept "requires"/"depends_on" to_concept -> to_concept is the
    # prerequisite; count it once per dependent that isn't solidly
    # mastered yet (a dependent the student has already mastered doesn't
    # make its prerequisite newly important right now).
    dependent_counts: dict[int, int] = defaultdict(int)
    for from_id, to_id in edges:
        dependent_mastery = mastery_by_concept.get(from_id)
        dependent_score = mastery_score(dependent_mastery) if dependent_mastery else 0.0
        if dependent_score < _PREREQUISITE_DEPENDENT_MASTERY_THRESHOLD:
            dependent_counts[to_id] += 1

    return {
        concept_id: min(count / _PREREQUISITE_SATURATION_COUNT, 1.0)
        for concept_id, count in dependent_counts.items()
    }


async def build_plan(
    db: AsyncSession, user_id: int, duration_minutes: int, knowledge_space_id: int | None = None
) -> dict:
    now = datetime.datetime.now(datetime.timezone.utc)

    stmt = (
        select(Concept, Mastery)
        .join(KnowledgeSpace, KnowledgeSpace.id == Concept.knowledge_space_id)
        .outerjoin(Mastery, and_(Mastery.concept_id == Concept.id, Mastery.user_id == user_id))
        .where(KnowledgeSpace.user_id == user_id)
    )
    if knowledge_space_id is not None:
        stmt = stmt.where(Concept.knowledge_space_id == knowledge_space_id)
    rows = (await db.execute(stmt)).all()

    # Soonest upcoming target_date per knowledge_space_id; a Goal with no
    # knowledge_space_id (account-wide) applies to every concept that
    # doesn't have a more specific one of its own.
    goal_rows = (
        await db.scalars(select(Goal).where(Goal.user_id == user_id, Goal.target_date.is_not(None)))
    ).all()
    deadline_by_space: dict[int | None, datetime.datetime] = {}
    for goal in goal_rows:
        key = goal.knowledge_space_id
        if key not in deadline_by_space or goal.target_date < deadline_by_space[key]:
            deadline_by_space[key] = goal.target_date
    account_wide_deadline = deadline_by_space.get(None)

    concept_ids = [concept.id for concept, _mastery in rows]
    mastery_by_concept = {concept.id: mastery for concept, mastery in rows}
    prerequisite_importance = await _compute_prerequisite_importance(db, concept_ids, mastery_by_concept)

    scored = []
    for concept, mastery in rows:
        deadline = deadline_by_space.get(concept.knowledge_space_id, account_wide_deadline)
        scored.append(
            (score_concept(mastery, deadline, now, prerequisite_importance.get(concept.id, 0.0)), concept)
        )
    scored.sort(key=lambda pair: pair[0], reverse=True)

    return {
        "generated_at": now.isoformat(),
        "duration_minutes": duration_minutes,
        "concepts_considered": len(scored),
        "phases": _allocate_phases(scored, duration_minutes),
    }


def _allocate_phases(scored: list[tuple[float, Concept]], duration_minutes: int) -> list[dict]:
    remaining = list(scored)
    phases = []
    for name, fraction in _PHASE_FRACTIONS:
        phase_minutes = round(duration_minutes * fraction)
        n_concepts = phase_minutes // _MINUTES_PER_CONCEPT if remaining else 0
        chosen, remaining = remaining[:n_concepts], remaining[n_concepts:]
        phases.append(
            {
                "phase": name,
                "duration_minutes": phase_minutes,
                "concept_ids": [concept.id for _, concept in chosen],
                # Redundant with concept_ids above, but a plan can span (or
                # omit) specific Knowledge Spaces and there's no batch
                # "get concepts by ids" endpoint — the client needs names
                # to render a phase without an extra lookup it can't make.
                "concepts": [{"id": concept.id, "name": concept.name} for _, concept in chosen],
            }
        )
    phases.append(
        {
            "phase": "reflection",
            "duration_minutes": round(duration_minutes * _REFLECTION_FRACTION),
            "concept_ids": [],
            "concepts": [],
        }
    )
    return phases
