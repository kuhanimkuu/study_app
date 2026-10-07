"""
Postgres-backed durability for each Knowledge Space's RAG index (2026-10-07)
— see models.ProjectIndex for why. The engines (rag/projects, the
moderator's project route, semantic search) keep reading and writing the
per-project JSON file exactly as before; this module only:

  - save_index():        after rag/projects writes the file, copy it into
                         Postgres (the durable source of truth);
  - ensure_index_file(): before anything reads the file, restore it from
                         Postgres if the host's disk lost it.

Spaces indexed before this table existed have no row; the first
ensure_index_file() call that still finds their file on disk backfills it.
"""
from __future__ import annotations

from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ... import engines
from .models import KnowledgeSpace, ProjectIndex


def _index_file(user_id: int, slug: str) -> Path:
    return engines.moderator._user_projects_dir(user_id) / f"{slug}.json"


async def _space_id(db: AsyncSession, user_id: int, slug: str) -> int | None:
    return await db.scalar(
        select(KnowledgeSpace.id).where(KnowledgeSpace.user_id == user_id, KnowledgeSpace.slug == slug)
    )


async def save_index(db: AsyncSession, space_id: int, user_id: int, slug: str) -> None:
    """Upserts the on-disk index into Postgres. Doesn't commit — the
    caller's transaction (alongside the Material row) does."""
    path = _index_file(user_id, slug)
    if not path.exists():
        return
    data = path.read_text(encoding="utf-8")
    row = await db.scalar(select(ProjectIndex).where(ProjectIndex.knowledge_space_id == space_id))
    if row is None:
        db.add(ProjectIndex(knowledge_space_id=space_id, data=data))
    else:
        row.data = data


async def ensure_index_file(db: AsyncSession, user_id: int, slug: str) -> None:
    """Call before any read of the index file. A no-op when the file and
    its Postgres copy both exist (the common case). Never raises for a
    space with no material at all — the reader then reports that itself."""
    space_id = await _space_id(db, user_id, slug)
    if space_id is None:
        return
    path = _index_file(user_id, slug)
    row = await db.scalar(select(ProjectIndex).where(ProjectIndex.knowledge_space_id == space_id))
    if row is not None:
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(row.data, encoding="utf-8")
        return
    if path.exists():
        # Indexed before the table existed — backfill so a later wipe of
        # the disk doesn't lose it.
        db.add(ProjectIndex(knowledge_space_id=space_id, data=path.read_text(encoding="utf-8")))
        await db.commit()
