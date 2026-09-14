"""
Authentication logic — password hashing, JWT issuing/verification, and the
FastAPI dependency (get_current_user) that protects every /api/ask/*,
/api/account, and knowledge-space endpoint.

Auth is REQUIRED for this app (not optional/guest mode) — see the
top-level README.md's "Architecture note" for why: per-user API keys and
history only make sense tied to a real account, and a parallel anonymous
mode would just duplicate the existing session_id system pointlessly.

DEV-MODE NOTE on the JWT secret: generated into a local gitignored file on
first run, not a proper secrets manager. Fine for local development, not
for real deployment.

Moved here from server/security.py as part of the Postgres migration
(STUDY_OS_PROGRESS.md, 2026-09-14) — get_current_user now queries Postgres
via SQLAlchemy instead of sqlite3, and is async all the way through.
"""
from __future__ import annotations

import secrets
import time
from pathlib import Path

import bcrypt
import jwt
from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.session import get_db
from ..domains.identity.models import User

_SECRET_PATH = Path(__file__).resolve().parent.parent / ".jwt_secret"
_ALGORITHM = "HS256"
_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30  # 30 days


def _get_secret() -> str:
    if _SECRET_PATH.exists():
        return _SECRET_PATH.read_text()
    secret = secrets.token_hex(32)
    _SECRET_PATH.write_text(secret)
    return secret


_SECRET = _get_secret()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode(), password_hash.encode())


def create_token(user_id: int) -> str:
    # "sub" must be a string per the JWT spec (RFC 7519) — recent PyJWT
    # versions enforce this on decode(), rejecting a raw int even though
    # encode() accepts it silently.
    payload = {"sub": str(user_id), "exp": int(time.time()) + _TOKEN_TTL_SECONDS}
    return jwt.encode(payload, _SECRET, algorithm=_ALGORITHM)


def _decode_token(token: str) -> int:
    try:
        payload = jwt.decode(token, _SECRET, algorithms=[_ALGORITHM])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail=f"invalid or expired token: {exc}") from exc
    return int(payload["sub"])


async def get_current_user(
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """FastAPI dependency: `current_user: dict = Depends(get_current_user)`.
    Returns a dict (id/email/display_name/encryption_key), same shape the
    old sqlite3-backed version returned — kept dict-shaped (rather than the
    raw SQLAlchemy User) so every existing consumer (routers/ask.py's
    current_user["id"]/["encryption_key"] etc.) keeps working unchanged;
    only their `security` import path moves. Never includes password_hash."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing or malformed Authorization header")
    token = authorization.removeprefix("Bearer ").strip()
    user_id = _decode_token(token)

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "encryption_key": user.encryption_key,
    }
