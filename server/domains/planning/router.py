"""
/api/v1/goals, /api/v1/plan, /api/v1/study-sessions* — blueprint Sections
21-22. Knowledge Spaces are referenced by slug at the API boundary (same
convention as every other endpoint that touches one), resolved to an
internal id via knowledge/router.py's get_space_or_404 before storage.
"""
from __future__ import annotations

import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from ..knowledge.router import get_space_or_404
from .models import Goal, StudySession
from .planner import build_plan

router = APIRouter(prefix="/api/v1")


async def _get_goal_or_404(db: AsyncSession, user_id: int, goal_id: int) -> Goal:
    goal = await db.scalar(select(Goal).where(Goal.id == goal_id, Goal.user_id == user_id))
    if goal is None:
        raise HTTPException(status_code=404, detail=f"no goal with id {goal_id}")
    return goal


async def _get_session_or_404(db: AsyncSession, user_id: int, session_id: int) -> StudySession:
    session = await db.scalar(
        select(StudySession).where(StudySession.id == session_id, StudySession.user_id == user_id)
    )
    if session is None:
        raise HTTPException(status_code=404, detail=f"no study session with id {session_id}")
    return session


class CreateGoal(BaseModel):
    title: str
    target_date: datetime.datetime | None = None
    knowledge_space_slug: str | None = None


@router.post("/goals")
async def create_goal(
    payload: CreateGoal,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    knowledge_space_id = None
    if payload.knowledge_space_slug is not None:
        space = await get_space_or_404(db, current_user["id"], payload.knowledge_space_slug)
        knowledge_space_id = space.id

    goal = Goal(user_id=current_user["id"], knowledge_space_id=knowledge_space_id,
                title=payload.title, target_date=payload.target_date)
    db.add(goal)
    await db.commit()
    await db.refresh(goal)
    return goal.public()


@router.get("/goals")
async def list_goals(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    goals = (
        await db.scalars(select(Goal).where(Goal.user_id == current_user["id"]).order_by(Goal.created_at.desc()))
    ).all()
    return {"goals": [g.public() for g in goals]}


@router.delete("/goals/{goal_id}")
async def delete_goal(
    goal_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    goal = await _get_goal_or_404(db, current_user["id"], goal_id)
    await db.delete(goal)
    await db.commit()
    return {"deleted": goal_id}


@router.get("/plan")
async def get_plan(
    duration_minutes: int = 60,
    knowledge_space_slug: str | None = None,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    knowledge_space_id = None
    if knowledge_space_slug is not None:
        space = await get_space_or_404(db, current_user["id"], knowledge_space_slug)
        knowledge_space_id = space.id
    return await build_plan(db, current_user["id"], duration_minutes, knowledge_space_id)


class CreateStudySession(BaseModel):
    duration_minutes: int = 60
    knowledge_space_slug: str | None = None


@router.post("/study-sessions")
async def create_study_session(
    payload: CreateStudySession,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    knowledge_space_id = None
    if payload.knowledge_space_slug is not None:
        space = await get_space_or_404(db, current_user["id"], payload.knowledge_space_slug)
        knowledge_space_id = space.id

    plan = await build_plan(db, current_user["id"], payload.duration_minutes, knowledge_space_id)
    session = StudySession(
        user_id=current_user["id"], planned_duration_minutes=payload.duration_minutes, plan=plan
    )
    db.add(session)
    await db.commit()
    await db.refresh(session)
    return session.public()


@router.get("/study-sessions")
async def list_study_sessions(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    sessions = (
        await db.scalars(
            select(StudySession)
            .where(StudySession.user_id == current_user["id"])
            .order_by(StudySession.created_at.desc())
        )
    ).all()
    return {"study_sessions": [s.public() for s in sessions]}


@router.get("/study-sessions/{session_id}")
async def get_study_session(
    session_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    session = await _get_session_or_404(db, current_user["id"], session_id)
    return session.public()


@router.post("/study-sessions/{session_id}/complete")
async def complete_study_session(
    session_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    session = await _get_session_or_404(db, current_user["id"], session_id)
    if session.status == "completed":
        raise HTTPException(status_code=400, detail="this study session is already completed")
    session.status = "completed"
    session.ended_at = datetime.datetime.now(datetime.timezone.utc)
    await db.commit()
    await db.refresh(session)
    return session.public()
