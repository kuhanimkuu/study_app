from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.session import get_db

router = APIRouter()


@router.get("/api/health")
async def health() -> dict:
    return {"status": "ok"}


@router.get("/api/health/ready")
async def ready(db: AsyncSession = Depends(get_db)) -> dict:
    """/api/health only proves the process answers; this also proves the
    database does (2026-10-21). For deploy checks and an uptime monitor:
    a 503 here means students can't log in even though the app is up."""
    try:
        await db.execute(text("select 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="database unreachable") from exc
    return {"status": "ok", "database": "ok"}
