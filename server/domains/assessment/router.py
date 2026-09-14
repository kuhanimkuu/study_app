"""
/api/v1/... — Question authoring, practice, and grading. The `attempt`
endpoint is the one place in this slice where several things happen
together in one transaction: grade the answer, record the attempt, update
FSRS mastery, and check/update misconception status.
"""
from __future__ import annotations

import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...ai.memory.service import create_episodic_memory
from ...core import security
from ...core.model_config import ModelConfig, resolve_model_config
from ...db.session import get_db
from ..learning.models import Concept
from ..learning.router import get_concept_or_404, get_or_create_mastery
from ..learning.scheduler import mastery_score, review_after_attempt, serialize_mastery
from .grading import GradingInputError, GradingUnavailable, UnsupportedQuestionType, grade
from .models import Misconception, Question, QuestionAttempt

router = APIRouter(prefix="/api/v1")

# Repeated-error heuristic (see models.py's Misconception docstring): a
# structural "struggling here" signal, not semantic classification.
_MISCONCEPTION_TRIGGER_STREAK = 3
_MISCONCEPTION_RESOLVE_STREAK = 2

# Episodic-memory trigger (server/ai/memory/): a concept crossing INTO this
# territory is a real, notable event, worth remembering once — not every
# correct attempt after, which is why submit_attempt checks the score
# BEFORE this attempt too, not just whether it's currently high.
_MASTERED_THRESHOLD = 0.85


class CreateQuestion(BaseModel):
    type: str
    prompt: str
    correct_answer: Any
    options: list[str] | None = None
    tolerance: float | None = None


class SubmitAttempt(BaseModel):
    answer: Any
    # Same pydantic-v2-reserved-name workaround as routers/ask.py's TextAsk
    # ("model_config" is BaseModel's own class-level ConfigDict).
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


@router.post("/concepts/{concept_id}/questions")
async def create_question(
    concept_id: int,
    payload: CreateQuestion,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await get_concept_or_404(db, current_user["id"], concept_id)

    question = Question(
        concept_id=concept_id,
        type=payload.type,
        prompt=payload.prompt,
        correct_answer=payload.correct_answer,
        options=payload.options,
        tolerance=payload.tolerance,
    )
    db.add(question)
    await db.commit()
    await db.refresh(question)
    return question.public(include_answer=True)


@router.get("/concepts/{concept_id}/questions")
async def list_questions(
    concept_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await get_concept_or_404(db, current_user["id"], concept_id)
    questions = (
        await db.scalars(
            select(Question).where(Question.concept_id == concept_id).order_by(Question.created_at)
        )
    ).all()
    # include_answer=False (default): a student practicing must not see the
    # correct answer in the same payload as the question.
    return {"questions": [q.public() for q in questions]}


@router.post("/questions/{question_id}/attempt")
async def submit_attempt(
    question_id: int,
    payload: SubmitAttempt,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    question = await db.get(Question, question_id)
    if question is None:
        raise HTTPException(status_code=404, detail=f"no question with id {question_id}")
    # Ownership is via concept -> knowledge space -> user, same as every
    # other lookup in this slice — a bare question_id could otherwise
    # belong to another user's concept.
    concept = await get_concept_or_404(db, current_user["id"], question.concept_id)

    model_config = resolve_model_config(payload.model_config_, current_user)
    try:
        is_correct, feedback, evaluated_by = await grade(question, payload.answer, model_config)
    except UnsupportedQuestionType as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except GradingInputError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except GradingUnavailable as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    attempt = QuestionAttempt(
        user_id=current_user["id"],
        question_id=question.id,
        submitted_answer=payload.answer,
        is_correct=is_correct,
        evaluated_by=evaluated_by,
        feedback=feedback,
    )
    db.add(attempt)
    await db.flush()  # so this attempt is included in the misconception streak check below

    mastery = await get_or_create_mastery(db, current_user["id"], question.concept_id)
    score_before = mastery_score(mastery) if mastery.attempts > 0 else 0.0
    review_after_attempt(mastery, is_correct)
    score_after = mastery_score(mastery)

    if score_before < _MASTERED_THRESHOLD <= score_after:
        await create_episodic_memory(
            db,
            current_user["id"],
            key=concept.name,
            value={"event": "concept_mastered", "concept_id": concept.id, "mastery": score_after},
        )

    await _check_misconception(db, current_user["id"], concept)

    await db.commit()
    await db.refresh(mastery)

    return {
        "correct": is_correct,
        "feedback": feedback,
        "evaluated_by": evaluated_by,
        "mastery_after": serialize_mastery(mastery),
    }


@router.get("/misconceptions")
async def list_misconceptions(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    rows = (
        await db.execute(
            select(Misconception, Concept.name)
            .join(Concept, Concept.id == Misconception.concept_id)
            .where(Misconception.user_id == current_user["id"], Misconception.resolved_at.is_(None))
        )
    ).all()
    return {
        "misconceptions": [{**misconception.public(), "concept_name": name} for misconception, name in rows]
    }


@router.get("/attempts")
async def list_attempts(
    limit: int = 50,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """No attempt-listing endpoint existed anywhere before this (confirmed
    by audit — QuestionAttempt rows were only ever written, never read back
    to a client) — a real gap for any activity/progress view. Joins
    Question (for prompt/type) and Concept (for name) so one response is
    enough to render a readable feed without N+1 lookups."""
    rows = (
        await db.execute(
            select(QuestionAttempt, Question.prompt, Question.type, Question.concept_id, Concept.name)
            .join(Question, Question.id == QuestionAttempt.question_id)
            .join(Concept, Concept.id == Question.concept_id)
            .where(QuestionAttempt.user_id == current_user["id"])
            .order_by(QuestionAttempt.created_at.desc())
            .limit(limit)
        )
    ).all()
    return {
        "attempts": [
            {
                **attempt.public(),
                "question_prompt": prompt,
                "question_type": qtype,
                "concept_id": concept_id,
                "concept_name": concept_name,
            }
            for attempt, prompt, qtype, concept_id, concept_name in rows
        ]
    }


async def _check_misconception(db: AsyncSession, user_id: int, concept: Concept) -> None:
    window = max(_MISCONCEPTION_TRIGGER_STREAK, _MISCONCEPTION_RESOLVE_STREAK)
    recent = (
        await db.scalars(
            select(QuestionAttempt)
            .join(Question, Question.id == QuestionAttempt.question_id)
            .where(QuestionAttempt.user_id == user_id, Question.concept_id == concept.id)
            .order_by(QuestionAttempt.created_at.desc())
            .limit(window)
        )
    ).all()

    existing = await db.scalar(
        select(Misconception).where(
            Misconception.user_id == user_id,
            Misconception.concept_id == concept.id,
            Misconception.resolved_at.is_(None),
        )
    )

    trigger_slice = recent[:_MISCONCEPTION_TRIGGER_STREAK]
    resolve_slice = recent[:_MISCONCEPTION_RESOLVE_STREAK]

    if (
        existing is None
        and len(trigger_slice) == _MISCONCEPTION_TRIGGER_STREAK
        and all(not a.is_correct for a in trigger_slice)
    ):
        db.add(
            Misconception(
                user_id=user_id,
                concept_id=concept.id,
                description=(
                    f"{_MISCONCEPTION_TRIGGER_STREAK} consecutive incorrect attempts on this concept"
                ),
            )
        )
    elif (
        existing is not None
        and len(resolve_slice) == _MISCONCEPTION_RESOLVE_STREAK
        and all(a.is_correct for a in resolve_slice)
    ):
        existing.resolved_at = datetime.datetime.now(datetime.timezone.utc)
        await create_episodic_memory(
            db,
            user_id,
            key=concept.name,
            value={"event": "misconception_resolved", "concept_id": concept.id, "description": existing.description},
        )
