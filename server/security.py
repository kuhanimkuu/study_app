"""
Authentication logic — password hashing, JWT issuing/verification, and the
FastAPI dependency (get_current_user) that protects every /api/ask/*,
/api/account, and /api/history endpoint.

Auth is REQUIRED for this app (not optional/guest mode) — see the
top-level README.md's "Architecture note" for why: per-user API keys and
history only make sense tied to a real account, and a parallel anonymous
mode would just duplicate the existing session_id system pointlessly.

DEV-MODE NOTE on the JWT secret: same caveat as crypto.py's encryption
key — generated into a local gitignored file on first run, not a proper
secrets manager. Fine for local development, not for real deployment.
"""
from __future__ import annotations

import secrets
import time
from pathlib import Path

import bcrypt
import jwt
from fastapi import Header, HTTPException

from . import db

_SECRET_PATH = Path(__file__).resolve().parent / ".jwt_secret"
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
    # encode() accepts it silently. Found by testing: signup/login worked
    # (encode), but every subsequent authenticated call failed with
    # "Subject must be a string" (decode). str()/int() convert at the
    # boundary so callers everywhere else still deal in real ints.
    payload = {"sub": str(user_id), "exp": int(time.time()) + _TOKEN_TTL_SECONDS}
    return jwt.encode(payload, _SECRET, algorithm=_ALGORITHM)


def _decode_token(token: str) -> int:
    try:
        payload = jwt.decode(token, _SECRET, algorithms=[_ALGORITHM])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail=f"invalid or expired token: {exc}") from exc
    return int(payload["sub"])


async def get_current_user(authorization: str | None = Header(default=None)) -> dict:
    """FastAPI dependency: `current_user: dict = Depends(get_current_user)`.
    Returns the full user row as a dict (sqlite3.Row) — callers that send
    data to the client must use db.public_user() to strip the password
    hash / raw encrypted key first."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing or malformed Authorization header")
    token = authorization.removeprefix("Bearer ").strip()
    user_id = _decode_token(token)

    conn = db.get_connection()
    try:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    finally:
        conn.close()
    if row is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    return dict(row)
