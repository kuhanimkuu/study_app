"""
POST /api/v1/client-errors — the app's crash reports (see models.py).

Works with or without a login (an app can crash on the sign-in screen); a
valid token just ties the report to the account. Rate-limited per account
or address and size-capped, since anyone can call it.
"""
from __future__ import annotations

import collections
import datetime
import hashlib
import re
import time

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from .models import ClientError

router = APIRouter(prefix="/api/v1")

_MAX_MESSAGE = 2_000
_MAX_STACK = 8_000
PER_HOUR = 30
_recent: dict[str, collections.deque[float]] = collections.defaultdict(collections.deque)


class ClientErrorReport(BaseModel):
    message: str = Field(min_length=1, max_length=20_000)
    stack: str = Field(default="", max_length=100_000)
    app_version: str = Field(min_length=1, max_length=40)
    platform: str = Field(min_length=1, max_length=60)


def _rate_limited(key: str) -> bool:
    now = time.monotonic()
    hits = _recent[key]
    while hits and now - hits[0] > 3600:
        hits.popleft()
    if len(hits) >= PER_HOUR:
        return True
    hits.append(now)
    return False


def fingerprint(message: str, stack: str) -> str:
    """Same error from the same place → same fingerprint. Numbers and hex
    (ids, addresses, offsets) are masked so one bug doesn't scatter across
    many rows."""
    first_line = message.strip().splitlines()[0] if message.strip() else ""
    first_frames = "\n".join(stack.strip().splitlines()[:4])
    normalised = re.sub(r"0x[0-9a-fA-F]+|\d+", "#", first_line + "\n" + first_frames)
    return hashlib.sha256(normalised.encode()).hexdigest()


@router.post("/client-errors", status_code=204, response_class=Response)
async def report_client_error(
    payload: ClientErrorReport,
    request: Request,
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> Response:
    user_id = None
    if authorization and authorization.startswith("Bearer "):
        try:
            user_id = (await security.get_current_user(authorization=authorization, db=db))["id"]
        except HTTPException:
            user_id = None  # an expired token shouldn't lose the crash report

    # nginx sets X-Real-IP; without it every caller would look like 127.0.0.1.
    address = request.headers.get("x-real-ip") or (request.client.host if request.client else "unknown")
    if _rate_limited(f"user:{user_id}" if user_id else f"ip:{address}"):
        raise HTTPException(status_code=429, detail="too many error reports; try again later")

    message = payload.message[:_MAX_MESSAGE]
    stack = payload.stack[:_MAX_STACK]
    fp = fingerprint(message, stack)
    now = datetime.datetime.now(datetime.timezone.utc)

    existing = await db.scalar(
        select(ClientError).where(
            ClientError.fingerprint == fp,
            ClientError.app_version == payload.app_version,
            ClientError.user_id.is_(None) if user_id is None else ClientError.user_id == user_id,
        )
    )
    if existing is not None:
        existing.count += 1
        existing.last_seen = now
    else:
        db.add(ClientError(
            user_id=user_id, fingerprint=fp, app_version=payload.app_version, platform=payload.platform,
            message=message, stack=stack, first_seen=now, last_seen=now,
        ))
    await db.commit()
    return Response(status_code=204)
