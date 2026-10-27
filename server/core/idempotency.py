"""
Idempotency keys (2026-10-27): the same request sent twice — a retry after
a dropped connection or a timeout, a double tap — is done once.

The app sends `Idempotency-Key: <uuid>` on every request that changes
something and reuses it when it repeats that request (frontend
core/api/idempotent_client.dart). Here:

  - first time: the request runs; a 2xx answer is stored for 24 hours;
  - same key again: the stored answer is sent back (marked
    `Idempotent-Replayed: true`) without running anything — no second
    lesson, flashcard, upload or AI charge;
  - same key while the first is still running: 409 "still processing";
  - a failed attempt (any non-2xx) isn't stored, so retrying it runs again.

Keys belong to the caller's login (a hash of the Authorization header), so
one account can never replay another's answer. Requests without a key, or
without a login, pass straight through.
"""
from __future__ import annotations

import datetime
import hashlib
import json
import re

from sqlalchemy import DateTime, Integer, LargeBinary, String, UniqueConstraint, delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, mapped_column

from ..db.base import Base
from ..db.session import async_session

_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
_KEY_RE = re.compile(r"^[A-Za-z0-9_.:-]{8,100}$")
_MAX_STORED_BODY = 1_000_000  # bigger answers aren't stored (the request then just isn't deduplicated)
KEEP_FOR = datetime.timedelta(hours=24)
# A row still "in progress" after this long belongs to a request that died
# with the process (restart); a retry may run again.
_STALE_IN_PROGRESS = datetime.timedelta(minutes=10)


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class IdempotencyKey(Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (UniqueConstraint("owner", "key"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    owner: Mapped[str] = mapped_column(String(64), nullable=False)  # sha256 of the Authorization header
    key: Mapped[str] = mapped_column(String(100), nullable=False)
    method: Mapped[str] = mapped_column(String(10), nullable=False)
    path: Mapped[str] = mapped_column(String(500), nullable=False)
    status_code: Mapped[int | None] = mapped_column(Integer, nullable=True)  # None = still running
    content_type: Mapped[str | None] = mapped_column(String(200), nullable=True)
    body: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False, index=True)


async def _json(send, status: int, detail: str, extra_headers: list | None = None) -> None:
    body = json.dumps({"detail": detail}).encode()
    headers = [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]
    await send({"type": "http.response.start", "status": status, "headers": headers + (extra_headers or [])})
    await send({"type": "http.response.body", "body": body})


async def _forget(row_id: int) -> None:
    async with async_session() as db:
        await db.execute(delete(IdempotencyKey).where(IdempotencyKey.id == row_id))
        await db.commit()


async def delete_expired_keys() -> int:
    """Called by the cleanup worker."""
    async with async_session() as db:
        result = await db.execute(delete(IdempotencyKey).where(IdempotencyKey.created_at < _utcnow() - KEEP_FOR))
        await db.commit()
    return result.rowcount or 0


class IdempotencyMiddleware:
    """Plain ASGI middleware, so it can hold back a request until it knows
    whether it's a repeat and capture the answer as it's sent."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in _METHODS:
            return await self.app(scope, receive, send)
        headers = dict(scope["headers"])
        raw_key, auth = headers.get(b"idempotency-key"), headers.get(b"authorization")
        if not raw_key or not auth:
            return await self.app(scope, receive, send)
        key = raw_key.decode("latin-1").strip()
        if not _KEY_RE.match(key):
            return await _json(send, 400, "Idempotency-Key must be 8-100 letters, digits or - _ . :")

        owner = hashlib.sha256(auth).hexdigest()
        method, path = scope["method"], scope["path"]
        row_id = await self._claim(owner, key, method, path, send)
        if row_id is None:
            return  # answered already: a replay, "still processing" or a mismatch

        status, content_type, chunks, too_big = None, None, [], False

        async def capture(message):
            nonlocal status, content_type, too_big
            if message["type"] == "http.response.start":
                status = message["status"]
                content_type = dict(message.get("headers") or []).get(b"content-type", b"").decode("latin-1") or None
            elif message["type"] == "http.response.body" and not too_big:
                chunks.append(message.get("body", b""))
                too_big = sum(len(c) for c in chunks) > _MAX_STORED_BODY
            await send(message)

        try:
            await self.app(scope, receive, capture)
        except Exception:
            await _forget(row_id)
            raise
        if status is not None and 200 <= status < 300 and not too_big:
            async with async_session() as db:
                row = await db.get(IdempotencyKey, row_id)
                if row is not None:
                    row.status_code, row.content_type, row.body = status, content_type, b"".join(chunks)
                    await db.commit()
        else:
            await _forget(row_id)

    async def _claim(self, owner: str, key: str, method: str, path: str, send) -> int | None:
        """The new row's id when this request should run; None after
        answering it here."""
        async with async_session() as db:
            row = IdempotencyKey(owner=owner, key=key, method=method, path=path)
            db.add(row)
            try:
                await db.commit()
                return row.id
            except IntegrityError:
                await db.rollback()
            existing = await db.scalar(select(IdempotencyKey).where(IdempotencyKey.owner == owner, IdempotencyKey.key == key))
            if existing is None:  # expired and deleted in between: run it
                row = IdempotencyKey(owner=owner, key=key, method=method, path=path)
                db.add(row)
                await db.commit()
                return row.id
            if (existing.method, existing.path) != (method, path):
                await _json(send, 422, "This Idempotency-Key was already used for a different request.")
                return None
            if existing.status_code is None:
                if _utcnow() - existing.created_at < _STALE_IN_PROGRESS:
                    await _json(send, 409, "This request is still being processed — wait a moment.", [(b"retry-after", b"2")])
                    return None
                existing.created_at = _utcnow()  # died with a restart: take it over
                await db.commit()
                return existing.id
            body = existing.body or b""
            response_headers = [(b"content-length", str(len(body)).encode()), (b"idempotent-replayed", b"true")]
            if existing.content_type:
                response_headers.append((b"content-type", existing.content_type.encode("latin-1")))
            await send({"type": "http.response.start", "status": existing.status_code, "headers": response_headers})
            await send({"type": "http.response.body", "body": body})
            return None
