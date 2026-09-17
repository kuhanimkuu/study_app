"""/api/v1/knowledge-spaces/{slug}/notes and /api/v1/notes/{id} — student-
authored Notes (blueprint Section 14). A separate router/file from
router.py's legacy unversioned /api/projects endpoints — same reasoning as
learning/assessment/planning being separate domains despite sharing
Knowledge Space ownership: this is genuinely new functionality, so it
starts versioned from day one rather than retrofitting the old routes.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from .models import KnowledgeSpace, Note
from .router import get_space_or_404

router = APIRouter(prefix="/api/v1")


async def get_note_or_404(db: AsyncSession, user_id: int, note_id: int) -> Note:
    """A note has no user_id of its own — ownership is via its Knowledge
    Space, same join pattern as get_concept_or_404/get_flashcard_or_404."""
    note = await db.scalar(
        select(Note)
        .join(KnowledgeSpace, KnowledgeSpace.id == Note.knowledge_space_id)
        .where(Note.id == note_id, KnowledgeSpace.user_id == user_id)
    )
    if note is None:
        raise HTTPException(status_code=404, detail=f"no note with id {note_id}")
    return note


class CreateNote(BaseModel):
    title: str
    body: str = ""


class UpdateNote(BaseModel):
    title: str | None = None
    body: str | None = None


@router.post("/knowledge-spaces/{slug}/notes")
async def create_note(
    slug: str,
    payload: CreateNote,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    note = Note(knowledge_space_id=space.id, title=payload.title, body=payload.body)
    db.add(note)
    await db.commit()
    await db.refresh(note)
    return note.public()


@router.get("/knowledge-spaces/{slug}/notes")
async def list_notes(
    slug: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    notes = (
        await db.scalars(
            select(Note).where(Note.knowledge_space_id == space.id).order_by(Note.updated_at.desc())
        )
    ).all()
    return {"notes": [n.public() for n in notes]}


@router.patch("/notes/{note_id}")
async def update_note(
    note_id: int,
    payload: UpdateNote,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    note = await get_note_or_404(db, current_user["id"], note_id)
    if payload.title is not None:
        note.title = payload.title
    if payload.body is not None:
        note.body = payload.body
    await db.commit()
    await db.refresh(note)
    return note.public()


@router.delete("/notes/{note_id}")
async def delete_note(
    note_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    note = await get_note_or_404(db, current_user["id"], note_id)
    await db.delete(note)
    await db.commit()
    return {"deleted": note_id}
