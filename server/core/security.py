"""
Authentication logic — password hashing, JWT issuing/verification, and the
FastAPI dependency (get_current_user) that protects every /api/ask/*,
/api/account, and knowledge-space endpoint.

Auth is REQUIRED for this app (not optional/guest mode) — see the
top-level README.md's "Architecture note" for why: per-user API keys and
history only make sense tied to a real account, and a parallel anonymous
mode would just duplicate the existing session_id system pointlessly.

JWT secret: an env var (`JWT_SECRET`) takes precedence when set — required
for any host with an ephemeral/non-persistent filesystem (e.g. a Railway
container without an attached volume), since a secret regenerated on every
restart invalidates every existing session. Falls back to a local
gitignored file, auto-generated on first run, for local dev where no env
var is set.

Moved here from server/security.py as part of the Postgres migration
(STUDY_OS_PROGRESS.md, 2026-09-14) — get_current_user now queries Postgres
via SQLAlchemy instead of sqlite3, and is async all the way through.
"""
from __future__ import annotations

import asyncio
import os
import secrets
import time
from concurrent.futures import ThreadPoolExecutor
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
    env_secret = os.environ.get("JWT_SECRET")
    if env_secret:
        return env_secret
    if _SECRET_PATH.exists():
        return _SECRET_PATH.read_text()
    secret = secrets.token_hex(32)
    _SECRET_PATH.write_text(secret)
    return secret


_SECRET = _get_secret()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


# bcrypt only reads the first 72 bytes, and bcrypt 5 raises on anything
# longer (that was a 500 on login/signup). Signup and password change
# refuse longer passwords (identity/router.py); a longer one at login can't
# be anyone's password, so it's simply wrong.
MAX_PASSWORD_BYTES = 72


def verify_password(password: str, password_hash: str) -> bool:
    encoded = password.encode()
    if len(encoded) > MAX_PASSWORD_BYTES:
        return False
    return bcrypt.checkpw(encoded, password_hash.encode())


# --- bcrypt off the event loop, in bounded lanes (2026-10-21) ---
# A bcrypt check is ~0.3 s of CPU on purpose. Run inline it froze the whole
# single-worker app: 100 bot signups from many addresses made a real
# student's login take 16-21 s and every other request (health, chat) 14 s.
# Now:
#   - hashing runs in its own threads (bcrypt releases the GIL), so the
#     rest of the app never waits on it;
#   - login and signup get separate lanes, so a signup flood can't delay
#     people logging in to existing accounts (logins are what matter most);
#   - each lane admits only a few waiting requests. Past that the server
#     answers "busy, try again in a few seconds" straight away (503 +
#     Retry-After) instead of putting the student at the back of a long
#     queue. Worst case to get in: about (waiting / threads) x 0.3 s.
# The per-IP limits in core/rate_limit.py (and nginx's, see setup_server.sh)
# stop most of a flood before it gets here; these lanes are for a flood
# spread across many addresses, which per-IP limits can't catch.

class _HashLane:
    def __init__(self, name: str, threads: int, max_waiting: int):
        self._pool = ThreadPoolExecutor(max_workers=threads, thread_name_prefix=f"bcrypt-{name}")
        self._max_in_lane = threads + max_waiting
        self.in_lane = 0

    async def run(self, fn, *args):
        if self.in_lane >= self._max_in_lane:
            raise HTTPException(
                status_code=503,
                detail="The server is busy right now — please try again in a few seconds.",
                headers={"Retry-After": "5"},
            )
        self.in_lane += 1  # single event loop thread: no lock needed
        try:
            return await asyncio.get_running_loop().run_in_executor(self._pool, fn, *args)
        finally:
            self.in_lane -= 1


# ~0.3 s per check: up to 12 waiting on 2 threads is about 2 s at worst.
login_lane = _HashLane("login", threads=2, max_waiting=12)
signup_lane = _HashLane("signup", threads=1, max_waiting=6)

# Accounts with a password check running right now. One at a time per
# account: bots guessing one account's password then hold one slot of the
# login lane, not all of it, so everyone else still gets in.
_verifying_accounts: set[int] = set()


async def hash_password_async(password: str) -> str:
    return await signup_lane.run(hash_password, password)


# A real bcrypt hash of a random password nobody knows: login checks it
# when the email has no account (or no password), so that answer takes as
# long as a wrong password does — otherwise the faster reply tells anyone
# which emails are registered.
_DUMMY_HASH = hash_password(secrets.token_hex(16))


async def burn_password_check(password: str) -> None:
    await login_lane.run(verify_password, password, _DUMMY_HASH)


async def verify_password_async(password: str, password_hash: str, user_id: int | None = None) -> bool:
    """With `user_id`, refuses (503) while another check for the same
    account is still running — see _verifying_accounts."""
    if user_id is None:
        return await login_lane.run(verify_password, password, password_hash)
    if user_id in _verifying_accounts:
        # 503 like a full lane: "busy, retry shortly" (the app retries these
        # by itself), unlike core/rate_limit.py's per-address 429.
        raise HTTPException(
            status_code=503,
            detail="Another sign-in to this account is in progress — please try again in a moment.",
            headers={"Retry-After": "2"},
        )
    _verifying_accounts.add(user_id)
    try:
        return await login_lane.run(verify_password, password, password_hash)
    finally:
        _verifying_accounts.discard(user_id)


def create_token(user_id: int, token_version: int = 0) -> str:
    # "sub" must be a string per the JWT spec (RFC 7519) — recent PyJWT
    # versions enforce this on decode(), rejecting a raw int even though
    # encode() accepts it silently. "ver" is the user's token_version at
    # issue time (see get_current_user).
    payload = {"sub": str(user_id), "ver": token_version, "exp": int(time.time()) + _TOKEN_TTL_SECONDS}
    return jwt.encode(payload, _SECRET, algorithm=_ALGORITHM)


def _decode_token(token: str) -> tuple[int, int]:
    try:
        payload = jwt.decode(token, _SECRET, algorithms=[_ALGORITHM])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail=f"invalid or expired token: {exc}") from exc
    return int(payload["sub"]), int(payload.get("ver", 0))


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
    user_id, token_version = _decode_token(token)

    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    if token_version != user.token_version:
        # The password was changed, or "sign out everywhere" was used.
        raise HTTPException(status_code=401, detail="you were signed out — please log in again")
    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "encryption_key": user.encryption_key,
    }


# --- signed file links (2026-10-07) ---
# A phone's browser / PDF viewer can't send the app's Authorization header,
# so opening an uploaded or generated file uses a short-lived link instead.
# Signed with a key DERIVED from the login secret (not the secret itself),
# so a file token can never be accepted as a login token, and scoped to one
# file id.
_FILE_TOKEN_SECRET = _SECRET + ":file-links"
# Keys the stored HMAC of password-reset codes (identity/router.py).
RESET_CODE_KEY = (_SECRET + ":password-reset").encode()
FILE_TOKEN_TTL_SECONDS = 15 * 60


def create_file_token(file_id: int, user_id: int) -> str:
    payload = {"file": file_id, "user": user_id, "exp": int(time.time()) + FILE_TOKEN_TTL_SECONDS}
    return jwt.encode(payload, _FILE_TOKEN_SECRET, algorithm=_ALGORITHM)


def decode_file_token(token: str, file_id: int) -> int:
    """Returns the owning user id, or raises 401/403."""
    try:
        payload = jwt.decode(token, _FILE_TOKEN_SECRET, algorithms=[_ALGORITHM])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail="this link has expired — open the file again from the app") from exc
    if payload.get("file") != file_id:
        raise HTTPException(status_code=403, detail="this link is for a different file")
    return int(payload["user"])
