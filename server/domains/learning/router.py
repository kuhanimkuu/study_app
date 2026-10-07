"""
/api/v1/... — Concepts (scoped to a Knowledge Space) and Mastery. First
domain under the new versioned prefix (blueprint Section 36) — existing
unversioned endpoints (/api/projects, /api/ask/*) are untouched; versioning
starts here for genuinely new endpoint groups rather than retrofitting old
ones, see STUDY_OS_PROGRESS.md, 2026-09-14.
"""
from __future__ import annotations

import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...core.model_config import ModelConfig, resolve_model_config_async
from ...db.session import get_db
from ..knowledge.models import KnowledgeSpace
from ..knowledge.router import get_space_or_404
from . import generation
from .flashcard_scheduler import RATINGS, review_flashcard
from .models import Concept, ConceptRelationship, Flashcard, Mastery, RELATIONSHIP_TYPES
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


class GenerateRequest(BaseModel):
    """Body for every AI-generation endpoint (2026-10-07). `count` is a
    target, not a guarantee — malformed model output is dropped, never
    saved half-valid. Same pydantic-v2 reserved-name workaround as
    routers/ask.py's TextAsk for `model_config`."""

    count: int = Field(default=8, ge=1, le=20)
    concept_id: int | None = None
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


@router.post("/knowledge-spaces/{slug}/concepts/generate")
async def generate_concepts(
    slug: str,
    payload: GenerateRequest,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Extracts the key concepts from this space's uploaded material and
    saves the new ones — names already present (case-insensitive) are
    skipped, so running it again after adding material only adds what's
    new rather than duplicating."""
    space = await get_space_or_404(db, current_user["id"], slug)
    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)
    chunks = generation.load_chunks(current_user["id"], slug)
    existing = (await db.scalars(select(Concept.name).where(Concept.knowledge_space_id == space.id))).all()

    material = generation.sample_material(chunks, generation.material_budget(model_config))
    text = await generation.call_model(
        generation.concepts_prompt(material, list(existing)), 700, model_config, db, current_user["id"]
    )
    parsed = generation.parse_concepts(text)
    if not parsed:
        raise generation._nothing_usable("concepts")

    taken = {n.lower() for n in existing}
    created: list[Concept] = []
    for name, description in parsed:
        if name.lower() in taken:
            continue
        taken.add(name.lower())
        concept = Concept(knowledge_space_id=space.id, name=name, description=description or None)
        db.add(concept)
        created.append(concept)
    await db.commit()
    for c in created:
        await db.refresh(c)
    return {"concepts": [c.public() for c in created], "skipped_existing": len(parsed) - len(created)}


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
    """`related_concept_name` is resolved here, not left for the client to
    figure out which end of `from_concept_id`/`to_concept_id` is "the
    other one" — same "resolve ids to names at the source" discipline as
    `list_my_mastery`/`planner.py`'s own `concepts` field."""
    await get_concept_or_404(db, current_user["id"], concept_id)
    rows = (
        await db.scalars(
            select(ConceptRelationship).where(
                or_(ConceptRelationship.from_concept_id == concept_id, ConceptRelationship.to_concept_id == concept_id)
            )
        )
    ).all()
    other_ids = {r.to_concept_id if r.from_concept_id == concept_id else r.from_concept_id for r in rows}
    names: dict[int, str] = {}
    if other_ids:
        name_rows = (await db.execute(select(Concept.id, Concept.name).where(Concept.id.in_(other_ids)))).all()
        names = {cid: name for cid, name in name_rows}
    return {
        "relationships": [
            {
                **r.public(),
                "direction": "outgoing" if r.from_concept_id == concept_id else "incoming",
                "related_concept_id": r.to_concept_id if r.from_concept_id == concept_id else r.from_concept_id,
                "related_concept_name": names.get(
                    r.to_concept_id if r.from_concept_id == concept_id else r.from_concept_id
                ),
            }
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


# --- Flashcards (blueprint Sections 17, 27, 32) ---


async def get_flashcard_or_404(db: AsyncSession, user_id: int, flashcard_id: int) -> Flashcard:
    """A flashcard has no user_id of its own — ownership is via its
    Knowledge Space, same join pattern as get_concept_or_404."""
    flashcard = await db.scalar(
        select(Flashcard)
        .join(KnowledgeSpace, KnowledgeSpace.id == Flashcard.knowledge_space_id)
        .where(Flashcard.id == flashcard_id, KnowledgeSpace.user_id == user_id)
    )
    if flashcard is None:
        raise HTTPException(status_code=404, detail=f"no flashcard with id {flashcard_id}")
    return flashcard


class CreateFlashcard(BaseModel):
    front: str
    back: str
    concept_id: int | None = None


@router.post("/knowledge-spaces/{slug}/flashcards")
async def create_flashcard(
    slug: str,
    payload: CreateFlashcard,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    if payload.concept_id is not None:
        # Must belong to the same user (and, since concepts are scoped to
        # one space, this also confirms it's a real concept — not
        # necessarily THIS space, matching between spaces is allowed the
        # same way a relationship can cross concepts, but cross-user is not).
        await get_concept_or_404(db, current_user["id"], payload.concept_id)

    flashcard = Flashcard(
        knowledge_space_id=space.id, concept_id=payload.concept_id, front=payload.front, back=payload.back
    )
    db.add(flashcard)
    await db.commit()
    await db.refresh(flashcard)
    return flashcard.public()


@router.post("/knowledge-spaces/{slug}/flashcards/generate")
async def generate_flashcards(
    slug: str,
    payload: GenerateRequest,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Writes flashcards from this space's material straight into its deck
    (so they enter FSRS review like hand-made cards). With `concept_id`,
    the cards are grounded in that concept's most relevant passages and
    linked to it."""
    space = await get_space_or_404(db, current_user["id"], slug)
    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)
    budget = generation.material_budget(model_config)
    focus = None
    if payload.concept_id is not None:
        concept = await get_concept_or_404(db, current_user["id"], payload.concept_id)
        focus = concept.name
        material = await generation.relevant_material(
            current_user["id"], slug, f"{concept.name} {concept.description or ''}", budget
        )
    else:
        material = generation.sample_material(generation.load_chunks(current_user["id"], slug), budget)

    text = await generation.call_model(
        generation.flashcards_prompt(material, payload.count, focus), 120 + 90 * payload.count,
        model_config, db, current_user["id"],
    )
    cards = generation.parse_flashcards(text, payload.count)
    if not cards:
        raise generation._nothing_usable("flashcards")

    existing_fronts = {
        f.lower()
        for f in (await db.scalars(select(Flashcard.front).where(Flashcard.knowledge_space_id == space.id))).all()
    }
    created: list[Flashcard] = []
    for front, back in cards:
        if front.lower() in existing_fronts:
            continue
        existing_fronts.add(front.lower())
        card = Flashcard(knowledge_space_id=space.id, concept_id=payload.concept_id, front=front, back=back)
        db.add(card)
        created.append(card)
    await db.commit()
    for c in created:
        await db.refresh(c)
    return {"flashcards": [c.public() for c in created], "skipped_existing": len(cards) - len(created)}


@router.get("/knowledge-spaces/{slug}/flashcards")
async def list_flashcards(
    slug: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    flashcards = (
        await db.scalars(
            select(Flashcard).where(Flashcard.knowledge_space_id == space.id).order_by(Flashcard.created_at)
        )
    ).all()
    return {"flashcards": [f.public() for f in flashcards]}


@router.get("/flashcards")
async def list_my_flashcards(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Account-wide, every card regardless of due status — unlike
    /flashcards/due (filtered to fsrs_due <= now). Exists for the Planner
    calendar (blueprint Section 22), which needs to plot every card's
    upcoming review date, not just the ones already due today."""
    flashcards = (
        await db.scalars(
            select(Flashcard)
            .join(KnowledgeSpace, KnowledgeSpace.id == Flashcard.knowledge_space_id)
            .where(KnowledgeSpace.user_id == current_user["id"])
            .order_by(Flashcard.fsrs_due)
        )
    ).all()
    return {"flashcards": [f.public() for f in flashcards]}


@router.get("/flashcards/due")
async def list_due_flashcards(
    knowledge_space_slug: str | None = None,
    limit: int = 20,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Account-wide by default (a review session usually spans every space,
    same reasoning as GET /mastery) — optionally scoped to one space via
    `knowledge_space_slug`."""
    query = (
        select(Flashcard)
        .join(KnowledgeSpace, KnowledgeSpace.id == Flashcard.knowledge_space_id)
        .where(KnowledgeSpace.user_id == current_user["id"], Flashcard.fsrs_due <= datetime.datetime.now(datetime.timezone.utc))
        .order_by(Flashcard.fsrs_due)
        .limit(limit)
    )
    if knowledge_space_slug is not None:
        query = query.where(KnowledgeSpace.slug == knowledge_space_slug)
    flashcards = (await db.scalars(query)).all()
    return {"flashcards": [f.public() for f in flashcards]}


@router.delete("/flashcards/{flashcard_id}")
async def delete_flashcard(
    flashcard_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    flashcard = await get_flashcard_or_404(db, current_user["id"], flashcard_id)
    await db.delete(flashcard)
    await db.commit()
    return {"deleted": flashcard_id}


class ReviewFlashcard(BaseModel):
    rating: str


@router.post("/flashcards/{flashcard_id}/review")
async def review_flashcard_endpoint(
    flashcard_id: int,
    payload: ReviewFlashcard,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if payload.rating not in RATINGS:
        raise HTTPException(status_code=400, detail=f"rating must be one of {sorted(RATINGS)}")
    flashcard = await get_flashcard_or_404(db, current_user["id"], flashcard_id)
    review_flashcard(flashcard, payload.rating)
    await db.commit()
    await db.refresh(flashcard)
    return flashcard.public()
