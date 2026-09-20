"""
/api/v1/memories — explicit memory only (episodic memory is
system-generated, see service.py's create_episodic_memory; this router
only lists/deletes it, never creates it directly). Blueprint Section 9
requires memory be user-editable/removable — that's what DELETE is for.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Any

from ...core import security
from ...db.session import get_db
from .models import MEMORY_TYPES, Memory

router = APIRouter(prefix="/api/v1")


class CreateExplicitMemory(BaseModel):
    key: str
    value: Any


@router.post("/memories")
async def create_explicit_memory(
    payload: CreateExplicitMemory,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    # type/source/confidence are NEVER taken from the request body — see
    # models.py's docstring for why a client stating a preference must not
    # be able to forge a "system_derived", high-confidence entry.
    memory = Memory(
        user_id=current_user["id"],
        type="explicit",
        key=payload.key,
        value=payload.value,
        source="user_stated",
        confidence=1.0,
    )
    db.add(memory)
    await db.commit()
    await db.refresh(memory)
    return memory.public()


@router.get("/memories")
async def list_memories(
    type: str | None = None,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if type is not None and type not in MEMORY_TYPES:
        raise HTTPException(status_code=400, detail=f"type must be one of {sorted(MEMORY_TYPES)}")
    stmt = select(Memory).where(Memory.user_id == current_user["id"])
    if type is not None:
        stmt = stmt.where(Memory.type == type)
    rows = (await db.scalars(stmt.order_by(Memory.created_at.desc()))).all()
    return {"memories": [m.public() for m in rows]}


@router.delete("/memories/{memory_id}")
async def delete_memory(
    memory_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    memory = await db.scalar(select(Memory).where(Memory.id == memory_id, Memory.user_id == current_user["id"]))
    if memory is None:
        raise HTTPException(status_code=404, detail=f"no memory with id {memory_id}")
    await db.delete(memory)
    await db.commit()
    return {"deleted": memory_id}
