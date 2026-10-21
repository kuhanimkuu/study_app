"""
/api/v1/lessons — "teach me this" (2026-10-21).

  POST   /lessons                          write a lesson on a topic (a subject's concept, or anything)
  GET    /lessons                          recent lessons (Home's "continue your lesson")
  GET    /lessons/{id}                     one lesson, with answers for the steps already done
  POST   /lessons/{id}/steps/{i}/answer    grade a step's check question
  POST   /lessons/{id}/complete            finish: the recap becomes flashcards
  DELETE /lessons/{id}

A lesson lives in a subject (Knowledge Space) and teaches one concept in
it — found or created by name — so everything it produces lands where the
rest of the app looks: its check questions are ordinary practice
questions on that concept, graded by the same grade_and_record as the
Practice tab (so mastery and weak spots update), and its recap becomes
flashcards in the review queue. Without a subject it goes in "My lessons".
"""
from __future__ import annotations

import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...ai.memory.models import Memory
from ...ai.moderator.style import build_adaptive_style_note
from ...ai.personality.router import get_or_create_personality
from ...core import security
from ...core.model_config import ModelConfig, resolve_model_config_async
from ...core.rate_limit import ai_user
from ...db.session import get_db
from ..assessment.models import Question
from ..assessment.router import grade_and_record
from ..identity.models import User
from ..knowledge import index_store
from ..knowledge.models import KnowledgeSpace
from ..knowledge.router import _slugify
from ..learning import generation
from ..learning.models import Concept, Flashcard
from ..learning.router import get_concept_or_404
from .lessons import lesson_prompt, parse_lesson
from .models import Lesson

router = APIRouter(prefix="/api/v1")

DEFAULT_SPACE_NAME = "My lessons"
_LESSON_MAX_TOKENS = 3_000


class StartLesson(BaseModel):
    topic: str | None = Field(default=None, max_length=200)
    knowledge_space_slug: str | None = Field(default=None, max_length=255)
    concept_id: int | None = None
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


class AnswerStep(BaseModel):
    answer: Any
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


async def _get_lesson_or_404(db: AsyncSession, user_id: int, lesson_id: int) -> Lesson:
    lesson = await db.scalar(select(Lesson).where(Lesson.id == lesson_id, Lesson.user_id == user_id))
    if lesson is None:
        raise HTTPException(status_code=404, detail=f"no lesson with id {lesson_id}")
    return lesson


async def _space_for(db: AsyncSession, user_id: int, slug: str | None) -> KnowledgeSpace:
    if slug:
        space = await db.scalar(select(KnowledgeSpace).where(KnowledgeSpace.user_id == user_id, KnowledgeSpace.slug == slug))
        if space is None:
            raise HTTPException(status_code=404, detail=f"no subject named {slug!r}")
        return space
    default_slug = _slugify(DEFAULT_SPACE_NAME)
    space = await db.scalar(
        select(KnowledgeSpace).where(KnowledgeSpace.user_id == user_id, KnowledgeSpace.slug == default_slug)
    )
    if space is None:
        space = KnowledgeSpace(user_id=user_id, slug=default_slug, display_name=DEFAULT_SPACE_NAME)
        db.add(space)
        await db.flush()
    return space


async def _concept_for(db: AsyncSession, space: KnowledgeSpace, topic: str) -> Concept:
    concept = await db.scalar(
        select(Concept).where(Concept.knowledge_space_id == space.id, func.lower(Concept.name) == topic.lower())
    )
    if concept is None:
        concept = Concept(knowledge_space_id=space.id, name=topic[:255])
        db.add(concept)
        await db.flush()
    return concept


async def _style_note(db: AsyncSession, user_id: int) -> str:
    personality = await get_or_create_personality(db, user_id)
    memories = (await db.scalars(select(Memory).where(Memory.user_id == user_id, Memory.type == "explicit"))).all()
    return build_adaptive_style_note(personality, [{"key": m.key, "value": m.value} for m in memories]) or ""


async def _lesson_view(db: AsyncSession, lesson: Lesson) -> dict:
    """The lesson for the app. A step's question shows its answer and the
    explanation only once the student has answered it."""
    ids = [s["question_id"] for s in lesson.steps if s.get("question_id")]
    questions = {q.id: q for q in (await db.scalars(select(Question).where(Question.id.in_(ids)))).all()} if ids else {}
    space = await db.get(KnowledgeSpace, lesson.knowledge_space_id)
    steps = []
    for step in lesson.steps:
        question = questions.get(step.get("question_id"))
        answered = step.get("result") is not None
        view = {"heading": step["heading"], "explanation": step["explanation"], "question": None, "result": step.get("result")}
        if question is not None:
            view["question"] = question.public(include_answer=answered)
            if answered:
                view["why"] = step.get("why")
        steps.append(view)
    return {
        **lesson.summary(),
        "subject": space.public() if space else None,
        "grounded_in_notes": lesson.grounded_in_notes,
        "lesson_steps": steps,
        "worked_example": lesson.worked_example,
        "recap": lesson.recap,
    }


@router.post("/lessons")
async def start_lesson(
    payload: StartLesson,
    current_user: dict = Depends(ai_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    user_id = current_user["id"]
    if payload.concept_id is not None:
        concept = await get_concept_or_404(db, user_id, payload.concept_id)
        space = await db.get(KnowledgeSpace, concept.knowledge_space_id)
        topic = (payload.topic or concept.name).strip()
    else:
        topic = (payload.topic or "").strip()
        if not topic:
            raise HTTPException(status_code=400, detail="say what you'd like to learn")
        space = await _space_for(db, user_id, payload.knowledge_space_slug)
        concept = await _concept_for(db, space, topic)

    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)

    # Ground it in the subject's notes when it has any.
    material = None
    await index_store.ensure_index_file(db, user_id, space.slug)
    try:
        query = f"{concept.name}. {concept.description or ''} {topic}"
        material = await generation.relevant_material(user_id, space.slug, query, generation.material_budget(model_config))
    except HTTPException:
        material = None  # no notes in this subject

    user = await db.get(User, user_id)
    level = ", ".join(v for v in (user.education_level, user.course) if v) if user else None
    style = await _style_note(db, user_id)
    text = await generation.call_model(
        lesson_prompt(topic, material, level, style), _LESSON_MAX_TOKENS, model_config, db, user_id
    )
    parsed = parse_lesson(text, topic)

    steps = []
    for step in parsed["steps"]:
        check = step["check"]
        question_id = None
        if check is not None:
            question = Question(
                concept_id=concept.id, type=check["type"], prompt=check["prompt"],
                correct_answer=check["correct_answer"], options=check["options"],
            )
            db.add(question)
            await db.flush()
            question_id = question.id
        steps.append({
            "heading": step["heading"], "explanation": step["explanation"],
            "question_id": question_id, "why": check["why"] if check else None, "result": None,
        })
    lesson = Lesson(
        user_id=user_id, knowledge_space_id=space.id, concept_id=concept.id, topic=topic[:255],
        title=parsed["title"], steps=steps, worked_example=parsed["worked_example"], recap=parsed["recap"],
        grounded_in_notes=bool(material),
    )
    db.add(lesson)
    await db.commit()
    await db.refresh(lesson)
    return await _lesson_view(db, lesson)


@router.get("/lessons")
async def list_lessons(
    status: str | None = Query(default=None, pattern="^(in_progress|completed)$"),
    limit: int = Query(default=10, ge=1, le=50),
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    query = select(Lesson).where(Lesson.user_id == current_user["id"])
    if status:
        query = query.where(Lesson.status == status)
    lessons = (await db.scalars(query.order_by(Lesson.created_at.desc()).limit(limit))).all()
    return {"lessons": [lesson.summary() for lesson in lessons]}


@router.get("/lessons/{lesson_id}")
async def get_lesson(
    lesson_id: int, current_user: dict = Depends(security.get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    return await _lesson_view(db, await _get_lesson_or_404(db, current_user["id"], lesson_id))


@router.post("/lessons/{lesson_id}/steps/{index}/answer")
async def answer_step(
    lesson_id: int,
    index: int,
    payload: AnswerStep,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    lesson = await _get_lesson_or_404(db, current_user["id"], lesson_id)
    if not 0 <= index < len(lesson.steps) or not lesson.steps[index].get("question_id"):
        raise HTTPException(status_code=404, detail="this step has no question")
    step = lesson.steps[index]
    question = await db.get(Question, step["question_id"])
    if question is None:
        raise HTTPException(status_code=404, detail="this step's question was deleted")
    if step.get("result") is not None:
        # Answered already (a double tap, or a retry after a lost reply):
        # the first answer stands and isn't counted again.
        return {**step["result"], "why": step.get("why"), "correct_answer": question.correct_answer, "lesson": lesson.summary()}

    concept = await get_concept_or_404(db, current_user["id"], question.concept_id)
    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)
    graded = await grade_and_record(db, current_user["id"], question, concept, payload.answer, model_config)

    result = {"correct": graded["correct"], "answer": payload.answer, "feedback": graded["feedback"]}
    steps = [dict(s) for s in lesson.steps]
    steps[index]["result"] = result
    lesson.steps = steps  # reassigned so the JSONB change is saved
    lesson.answered += 1
    lesson.correct += int(graded["correct"])
    await db.commit()
    await db.refresh(lesson)
    return {
        **result, "why": step.get("why"), "correct_answer": question.correct_answer,
        "mastery_after": graded["mastery_after"], "lesson": lesson.summary(),
    }


@router.post("/lessons/{lesson_id}/complete")
async def complete_lesson(
    lesson_id: int, current_user: dict = Depends(security.get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    lesson = await _get_lesson_or_404(db, current_user["id"], lesson_id)
    added = 0
    if lesson.status != "completed":
        existing = {
            f.lower()
            for f in (await db.scalars(select(Flashcard.front).where(Flashcard.knowledge_space_id == lesson.knowledge_space_id))).all()
        }
        for card in lesson.recap:
            if card["front"].lower() in existing:
                continue
            existing.add(card["front"].lower())
            db.add(Flashcard(
                knowledge_space_id=lesson.knowledge_space_id, concept_id=lesson.concept_id,
                front=card["front"], back=card["back"],
            ))
            added += 1
        lesson.status = "completed"
        lesson.completed_at = datetime.datetime.now(datetime.timezone.utc)
        await db.commit()
        await db.refresh(lesson)
    return {"lesson": lesson.summary(), "flashcards_added": added}


@router.delete("/lessons/{lesson_id}")
async def delete_lesson(
    lesson_id: int, current_user: dict = Depends(security.get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    lesson = await _get_lesson_or_404(db, current_user["id"], lesson_id)
    await db.delete(lesson)
    await db.commit()
    return {"deleted": lesson_id}
