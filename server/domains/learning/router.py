"""
/api/v1/... — Concepts (scoped to a Knowledge Space) and Mastery. First
domain under the new versioned prefix (blueprint Section 36) — existing
unversioned endpoints (/api/projects, /api/ask/*) are untouched; versioning
starts here for genuinely new endpoint groups rather than retrofitting old
ones, see STUDY_OS_PROGRESS.md, 2026-09-14.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from ..knowledge.models import KnowledgeSpace
from ..knowledge.router import get_space_or_404
from .models import Concept, ConceptRelationship, Mastery, RELATIONSHIP_TYPES
from .scheduler import serialize_mastery

router = APIRouter(prefix="/api/v1")


async def get_concept_or_404(db: AsyncSession, user_id: int, concept_id: int) -> Concept:
    """A concept has no user_id of its own — ownership is via its
    Knowledge Space, so this joins through it rather than trusting a bare
    concept_id (which could belong to another user's space)."""
    from ..knowledge.models import KnowledgeSpace

    concept = await db.scalar(
        select(Concept)
        .join(KnowledgeSpace, KnowledgeSpace.id == Concept.knowledge_space_id)
        .where(Concept.id == concept_id, KnowledgeSpace.user_id == user_id)
    )
    if concept is None:
        raise HTTPException(status_code=404, detail=f"no concept with id {concept_id}")
    return concept


async def get_or_create_mastery(db: AsyncSession, user_id: int, concept_id: int) -> Mastery:
    mastery = await db.scalar(
        select(Mastery).where(Mastery.user_id == user_id, Mastery.concept_id == concept_id)
    )
    if mastery is None:
        mastery = Mastery(user_id=user_id, concept_id=concept_id)
        db.add(mastery)
        await db.flush()
    return mastery


class CreateConcept(BaseModel):
    name: str
    description: str | None = None


@router.post("/knowledge-spaces/{slug}/concepts")
async def create_concept(
    slug: str,
    payload: CreateConcept,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    concept = Concept(knowledge_space_id=space.id, name=payload.name, description=payload.description)
    db.add(concept)
    await db.commit()
    await db.refresh(concept)
    return concept.public()


@router.get("/knowledge-spaces/{slug}/concepts")
async def list_concepts(
    slug: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    concepts = (
        await db.scalars(
            select(Concept).where(Concept.knowledge_space_id == space.id).order_by(Concept.created_at)
        )
    ).all()
    return {"concepts": [c.public() for c in concepts]}


@router.get("/concepts/{concept_id}/mastery")
async def get_concept_mastery(
    concept_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await get_concept_or_404(db, current_user["id"], concept_id)
    mastery = await db.scalar(
        select(Mastery).where(Mastery.user_id == current_user["id"], Mastery.concept_id == concept_id)
    )
    if mastery is None:
        # Never attempted — honest zero-state rather than a fabricated row.
        return {"concept_id": concept_id, "mastery": 0.0, "retrievability": None, "attempts": 0,
                "correct": 0, "incorrect": 0, "last_correct_at": None, "last_incorrect_at": None,
                "next_review": None}
    return serialize_mastery(mastery)


@router.get("/mastery")
async def list_my_mastery(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Account-wide, unlike GET /concepts/{id}/mastery — a plan/progress
    screen has no single Knowledge Space to resolve concept_id against, so
    the name has to come from here directly (same reasoning as planner.py's
    `concepts` field)."""
    rows = (
        await db.execute(
            select(Mastery, Concept.name, KnowledgeSpace.slug)
            .join(Concept, Concept.id == Mastery.concept_id)
            .join(KnowledgeSpace, KnowledgeSpace.id == Concept.knowledge_space_id)
            .where(Mastery.user_id == current_user["id"])
        )
    ).all()
    return {
        "mastery": [
            {**serialize_mastery(mastery), "concept_name": name, "knowledge_space_slug": slug}
            for mastery, name, slug in rows
        ]
    }


class CreateRelationship(BaseModel):
    to_concept_id: int
    relationship_type: str


@router.post("/concepts/{concept_id}/relationships")
async def create_relationship(
    concept_id: int,
    payload: CreateRelationship,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if payload.relationship_type not in RELATIONSHIP_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"relationship_type must be one of {sorted(RELATIONSHIP_TYPES)}",
        )
    if payload.to_concept_id == concept_id:
        raise HTTPException(status_code=400, detail="a concept cannot have a relationship to itself")

    # Both ends must belong to the current user — a relationship pointing
    # at someone else's concept would otherwise let one user's graph leak
    # references into another's.
    await get_concept_or_404(db, current_user["id"], concept_id)
    await get_concept_or_404(db, current_user["id"], payload.to_concept_id)

    relationship = ConceptRelationship(
        from_concept_id=concept_id, to_concept_id=payload.to_concept_id, relationship_type=payload.relationship_type
    )
    db.add(relationship)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="this relationship already exists")
    await db.refresh(relationship)
    return relationship.public()


@router.get("/concepts/{concept_id}/relationships")
async def list_relationships(
    concept_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await get_concept_or_404(db, current_user["id"], concept_id)
    rows = (
        await db.scalars(
            select(ConceptRelationship).where(
                or_(ConceptRelationship.from_concept_id == concept_id, ConceptRelationship.to_concept_id == concept_id)
            )
        )
    ).all()
    return {
        "relationships": [
            {**r.public(), "direction": "outgoing" if r.from_concept_id == concept_id else "incoming"}
            for r in rows
        ]
    }


@router.delete("/concepts/{concept_id}/relationships/{relationship_id}")
async def delete_relationship(
    concept_id: int,
    relationship_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await get_concept_or_404(db, current_user["id"], concept_id)
    relationship = await db.scalar(
        select(ConceptRelationship).where(
            ConceptRelationship.id == relationship_id,
            or_(ConceptRelationship.from_concept_id == concept_id, ConceptRelationship.to_concept_id == concept_id),
        )
    )
    if relationship is None:
        raise HTTPException(status_code=404, detail=f"no relationship with id {relationship_id} on this concept")
    await db.delete(relationship)
    await db.commit()
    return {"deleted": relationship_id}
