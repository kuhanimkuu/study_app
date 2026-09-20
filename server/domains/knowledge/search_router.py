"""GET /api/v1/knowledge-spaces/{slug}/search — a standalone semantic
search endpoint over a Knowledge Space's stored material.

Closes a real, previously-named gap (STUDY_OS_PROGRESS.md, 2026-09-14
audit): search only existed inside POST /api/ask/project's query flow,
which returns chat response blocks, not a structured result a search UI
could render directly. This reuses the exact same engines
(rag/semantic_search + the per-user project index moderator/engine.py
already builds) rather than duplicating that logic — `/api/ask/project`
and this endpoint now both read the one index, they just shape the
output differently for their different callers.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ... import engines
from ...core import security
from ...db.session import get_db
from .router import get_space_or_404

router = APIRouter(prefix="/api/v1")


@router.get("/knowledge-spaces/{slug}/search")
async def search_knowledge_space(
    slug: str,
    q: str,
    limit: int = 5,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await get_space_or_404(db, current_user["id"], slug)

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    index = engines.moderator._load_project_index(slug, projects_dir)
    if index is None or not index.get("chunks"):
        return {"results": []}

    try:
        search_result = await engines.semantic_search.run(index=index, query=q, top_k=limit)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"search failed: {exc}") from exc

    return search_result
