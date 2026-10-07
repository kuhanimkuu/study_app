"""
Opening stored files from the app (2026-10-07) — uploaded originals and
Studio-generated PDFs, both kept in Postgres (models.StoredFile).

Two steps because the phone opens a file in its own browser / PDF viewer,
which can't send the app's Authorization header:

  POST /api/files/{id}/link   (logged in)   -> {"url": "/api/files/{id}?token=..."}
  GET  /api/files/{id}?token=...            -> the file, inline

The token is short-lived, scoped to one file, and signed with a key that
can't be used to log in (security.create_file_token).
"""
from __future__ import annotations

from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from .models import StoredFile

router = APIRouter()

# Generous for lecture PDFs, small enough that one upload can't eat a
# meaningful share of a free 1 GB Postgres.
MAX_STORED_FILE_BYTES = 25 * 1024 * 1024


async def store_file(db: AsyncSession, user_id: int, filename: str, mime_type: str, data: bytes) -> StoredFile | None:
    """Adds the file (caller commits). Returns None for a file over the cap
    — it's still indexed and searchable, just not re-openable."""
    if len(data) > MAX_STORED_FILE_BYTES:
        return None
    stored = StoredFile(user_id=user_id, filename=filename, mime_type=mime_type, size=len(data), data=data)
    db.add(stored)
    await db.flush()
    return stored


@router.post("/api/files/{file_id}/link")
async def create_file_link(
    file_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    stored = await db.get(StoredFile, file_id)
    if stored is None or stored.user_id != current_user["id"]:
        raise HTTPException(status_code=404, detail="file not found")
    token = security.create_file_token(file_id, current_user["id"])
    return {"url": f"/api/files/{file_id}?token={token}", "expires_in": security.FILE_TOKEN_TTL_SECONDS}


@router.get("/api/files/{file_id}")
async def get_file(file_id: int, token: str, db: AsyncSession = Depends(get_db)) -> Response:
    user_id = security.decode_file_token(token, file_id)
    stored = await db.get(StoredFile, file_id)
    if stored is None or stored.user_id != user_id:
        raise HTTPException(status_code=404, detail="file not found — it may have been deleted")
    return Response(
        content=stored.data,
        media_type=stored.mime_type,
        # inline: open in the viewer rather than force a download; the
        # viewer's own download/share button still works.
        headers={"Content-Disposition": f"inline; filename*=UTF-8''{quote(stored.filename)}"},
    )
