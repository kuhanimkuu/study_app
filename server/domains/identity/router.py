"""
/api/auth/* and /api/account — signup / login / current-user / display-name
update. Same URL paths, request/response shapes, and bcrypt/JWT logic as
the old server/routers/auth.py + server/routers/account.py — only the
storage moved (sqlite3 -> Postgres via SQLAlchemy). The Flutter client
needs zero changes. See STUDY_OS_PROGRESS.md, 2026-09-14.

Signup and login are the ONLY two calls that ever return a user's
encryption_key — see server/crypto.py and User.auth_response() vs
User.public() for why (the device needs the key once to persist it
locally; routine calls like /me don't re-expose it).
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import secrets
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ... import crypto
from ...core import email, rate_limit, security
from ...core.config import get_settings
from ...core.rate_limit import check_rate_limit
from ...db.session import get_db
from .export import export_user_data
from .models import PasswordResetCode, User

router = APIRouter()

# This user's RAG project-index JSON files (features/rag/projects's engine
# — see server/domains/knowledge/models.py's Material docstring for why
# that storage isn't in Postgres yet) live outside any table this app's
# ondelete=CASCADE chain reaches, so account deletion has to clean them up
# itself. Mirrors features/moderator/engine.py's own _user_projects_dir
# (repo_root/features/rag/projects/projects/user_<id>) rather than
# importing that module, which pulls in the full moderator/model-loading
# chain for one path computation.
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
_RAG_PROJECTS_ROOT = _REPO_ROOT / "features" / "rag" / "projects" / "projects"

# Brute-force protection (blueprint Section 37) — see core/rate_limit.py
# for what this does and doesn't protect against. Signup gets a stricter
# window than login (spam-account creation vs. legitimate retry-after-typo
# traffic have different tolerances).
# Per address. Generous since 2026-10-21: a class on one school Wi-Fi shares
# an address, and the password lanes in core/security.py (not these limits)
# are what keep a flood from slowing everyone else down.
_LOGIN_MAX_ATTEMPTS, _LOGIN_WINDOW_SECONDS = 60, 5 * 60
_SIGNUP_MAX_ATTEMPTS, _SIGNUP_WINDOW_SECONDS = 30, 60 * 60


def _check_new_password(password: str) -> None:
    if len(password) < 8:
        raise HTTPException(status_code=400, detail="password must be at least 8 characters")
    if len(password.encode()) > security.MAX_PASSWORD_BYTES:
        raise HTTPException(status_code=400, detail="password must be at most 72 characters")


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=1024)
    display_name: str | None = Field(default=None, max_length=255)

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, v: str) -> str:
        # Without this, "User@Example.com" and "user@example.com" would
        # pass the DB's case-sensitive unique constraint as two different
        # accounts — a real pre-existing bug, not a hypothetical.
        return v.strip().lower()


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=1024)

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class AccountUpdate(BaseModel):
    # Caps match the column sizes in models.py: longer text used to reach
    # Postgres and come back as a 500 instead of a clear 422.
    display_name: str | None = Field(default=None, max_length=255)
    education_level: str | None = Field(default=None, max_length=100)
    course: str | None = Field(default=None, max_length=255)
    institution: str | None = Field(default=None, max_length=255)
    preferred_language: str | None = Field(default=None, max_length=50)
    daily_study_target_minutes: int | None = Field(default=None, ge=0, le=24 * 60)


class PasswordChangeRequest(BaseModel):
    # Required when the account has a password; a Google-only account
    # (no password yet) can set its first one without it.
    current_password: str | None = Field(default=None, max_length=1024)
    new_password: str = Field(max_length=1024)


class AccountDeleteRequest(BaseModel):
    # Optional: a Google-only account (see User.password_hash's docstring)
    # has no password to confirm — see delete_account below for how that's
    # handled instead.
    password: str | None = Field(default=None, max_length=1024)


_DELETE_MAX_ATTEMPTS, _DELETE_WINDOW_SECONDS = 10, 5 * 60
_GOOGLE_SIGNIN_MAX_ATTEMPTS, _GOOGLE_SIGNIN_WINDOW_SECONDS = 10, 5 * 60

# Reused across requests — it internally caches Google's public signing
# certs rather than refetching them every call.
_google_auth_request = google_requests.Request()


class GoogleSignInRequest(BaseModel):
    id_token: str


async def _verify_google_id_token(token: str) -> dict:
    """Verifies signature, expiry, issuer, AND audience (against our own
    Web OAuth client id) — not just decoding the JWT's claims unchecked.
    `verify_oauth2_token` is a blocking call (fetches/caches Google's
    public certs over HTTPS the first time), so it runs off the event
    loop via `asyncio.to_thread` rather than blocking every other request
    this server is handling concurrently."""
    client_id = get_settings().google_oauth_client_id
    if not client_id:
        raise HTTPException(status_code=503, detail="Google Sign-In is not configured on this server")
    try:
        claims = await asyncio.to_thread(google_id_token.verify_oauth2_token, token, _google_auth_request, client_id)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=f"invalid Google ID token: {exc}") from exc
    if not claims.get("email_verified", False):
        raise HTTPException(status_code=401, detail="Google account email is not verified")
    return claims


@router.post("/api/auth/signup")
async def signup(payload: SignupRequest, request: Request, db: AsyncSession = Depends(get_db)) -> dict:
    check_rate_limit(request, "signup", _SIGNUP_MAX_ATTEMPTS, _SIGNUP_WINDOW_SECONDS)

    _check_new_password(payload.password)

    existing = await db.scalar(select(User).where(User.email == payload.email))
    if existing is not None:
        raise HTTPException(status_code=409, detail="an account with this email already exists")

    user = User(
        email=payload.email,
        password_hash=await security.hash_password_async(payload.password),
        display_name=payload.display_name,
        encryption_key=crypto.generate_user_key(),
    )
    db.add(user)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="an account with this email already exists")
    await db.refresh(user)

    token = security.create_token(user.id, user.token_version)
    return {"token": token, "user": user.auth_response()}


@router.post("/api/auth/login")
async def login(payload: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)) -> dict:
    check_rate_limit(request, "login", _LOGIN_MAX_ATTEMPTS, _LOGIN_WINDOW_SECONDS)

    user = await db.scalar(select(User).where(User.email == payload.email))
    # user.password_hash is None for a Google-only account (never set one)
    # — checked explicitly rather than letting it reach verify_password,
    # which would raise on a None hash instead of cleanly rejecting.
    if user is None or user.password_hash is None:
        # Same ~0.3 s as a wrong password, so timing doesn't reveal which
        # emails have accounts (core/security.py's _DUMMY_HASH).
        await security.burn_password_check(payload.password)
        raise HTTPException(status_code=401, detail="invalid email or password")
    if not await security.verify_password_async(payload.password, user.password_hash, user_id=user.id):
        raise HTTPException(status_code=401, detail="invalid email or password")

    token = security.create_token(user.id, user.token_version)
    # Returning the key again here (not just at signup) lets a reinstalled
    # app / new device recover it via a normal login, rather than losing
    # access to previously-encrypted local data if secure storage was wiped.
    return {"token": token, "user": user.auth_response()}


@router.post("/api/auth/google")
async def google_sign_in(
    payload: GoogleSignInRequest, request: Request, db: AsyncSession = Depends(get_db)
) -> dict:
    """Blueprint Section 4's required Google Sign-In. One endpoint covers
    both signup and login: an unrecognized (verified) Google email
    creates a new password-less account; a recognized one just logs in —
    Google already re-proves identity every call, so there's no separate
    "confirm your email" step needed the way password signup has.

    If the email already belongs to an existing PASSWORD account, this
    links Google to it (sets google_sub) rather than refusing or creating
    a second account — Google has verified that email, so treating "same
    email, first Google sign-in" as "this is the same person adding a
    second way to log in" is the correct behavior, not silently ignored.
    """
    check_rate_limit(request, "google_signin", _GOOGLE_SIGNIN_MAX_ATTEMPTS, _GOOGLE_SIGNIN_WINDOW_SECONDS)

    claims = await _verify_google_id_token(payload.id_token)
    email = claims["email"].strip().lower()
    google_sub = claims["sub"]

    user = await db.scalar(select(User).where(User.email == email))
    if user is None:
        user = User(
            email=email,
            password_hash=None,
            display_name=claims.get("name"),
            encryption_key=crypto.generate_user_key(),
            google_sub=google_sub,
        )
        db.add(user)
    elif user.google_sub is None:
        user.google_sub = google_sub

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="this Google account is already linked to a different user")
    await db.refresh(user)

    token = security.create_token(user.id, user.token_version)
    return {"token": token, "user": user.auth_response()}


@router.get("/api/auth/me")
async def me(
    current_user: dict = Depends(security.get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    # Re-fetches rather than trusting current_user's narrower dict (used
    # for auth checks everywhere and deliberately left unchanged) so the
    # session-restore call at app startup also carries the profile fields
    # below — otherwise they'd only appear after a separate GET /api/account.
    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    return user.public()


@router.get("/api/account")
async def get_account(
    current_user: dict = Depends(security.get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    return user.public()


@router.patch("/api/account")
async def update_account(
    payload: AccountUpdate,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")

    changed = False
    for field in (
        "display_name",
        "education_level",
        "course",
        "institution",
        "preferred_language",
        "daily_study_target_minutes",
    ):
        value = getattr(payload, field)
        if value is not None:
            setattr(user, field, value)
            changed = True
    if changed:
        await db.commit()
        await db.refresh(user)
    return user.public()


_EXPORT_MAX_ATTEMPTS, _EXPORT_WINDOW_SECONDS = 5, 60 * 60


@router.get("/api/account/export")
async def export_account(
    request: Request,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JSONResponse:
    """Everything this account has stored, as one JSON file — see export.py."""
    check_rate_limit(request, "account_export", _EXPORT_MAX_ATTEMPTS, _EXPORT_WINDOW_SECONDS)
    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    data = await export_user_data(db, user)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return JSONResponse(
        data, headers={"Content-Disposition": f'attachment; filename="study-os-data-{stamp}.json"'}
    )


# --- forgot password (2026-10-21) ---
# 1. POST /api/auth/password-reset/request {email}: emails a 6-digit code.
#    The answer is the same whether or not the email has an account, and
#    the email is sent after the answer, so neither the words nor the time
#    taken tell anyone which emails are registered.
# 2. POST /api/auth/password-reset/confirm {email, code, new_password}:
#    sets the password, signs out every other device and signs this one in.
_RESET_CODE_TTL = timedelta(minutes=15)
_RESET_MAX_TRIES = 5
_RESET_REQUESTS_PER_IP, _RESET_REQUESTS_IP_WINDOW = 20, 60 * 60
_RESET_REQUESTS_PER_EMAIL, _RESET_REQUESTS_EMAIL_WINDOW = 3, 60 * 60
_RESET_CONFIRMS_PER_IP, _RESET_CONFIRMS_IP_WINDOW = 30, 60 * 60
_RESET_SENT = "If an account uses that email, we've sent it a 6-digit code. It works for 15 minutes."


class PasswordResetRequest(BaseModel):
    email: EmailStr

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class PasswordResetConfirm(PasswordResetRequest):
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")
    new_password: str = Field(max_length=1024)


def _reset_code_hash(user_id: int, code: str) -> str:
    return hmac.new(security.RESET_CODE_KEY, f"{user_id}:{code}".encode(), hashlib.sha256).hexdigest()


def _send_reset_code(to: str, code: str) -> None:
    try:
        email.send_email(
            to,
            subject=f"Your Study OS code: {code}",
            text=(
                f"Your code to reset your Study OS password is {code}.\n\n"
                "Enter it in the app within 15 minutes. If you didn't ask for this, ignore this email: "
                "your password stays the same."
            ),
            html=(
                "<p>Your code to reset your Study OS password is:</p>"
                f"<p style=\"font-size:28px;font-weight:700;letter-spacing:4px\">{code}</p>"
                "<p>Enter it in the app within 15 minutes. If you didn't ask for this, ignore this email: "
                "your password stays the same.</p>"
            ),
        )
    except Exception:
        pass  # logged in email.send_email; the student can ask for another code


@router.post("/api/auth/password-reset/request")
async def request_password_reset(
    payload: PasswordResetRequest, request: Request, background: BackgroundTasks, db: AsyncSession = Depends(get_db)
) -> dict:
    if not email.email_configured():
        raise HTTPException(status_code=503, detail="Password reset by email isn't set up on this server yet.")
    check_rate_limit(request, "reset_request", _RESET_REQUESTS_PER_IP, _RESET_REQUESTS_IP_WINDOW)
    try:
        # Per address being reset too, so nobody can flood one inbox.
        rate_limit.check_key(f"reset_email:{payload.email}", _RESET_REQUESTS_PER_EMAIL, _RESET_REQUESTS_EMAIL_WINDOW)
    except HTTPException:
        return {"message": _RESET_SENT}

    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is not None:
        code = f"{secrets.randbelow(10**6):06d}"
        await db.execute(delete(PasswordResetCode).where(PasswordResetCode.user_id == user.id))
        db.add(PasswordResetCode(
            user_id=user.id, code_hash=_reset_code_hash(user.id, code),
            expires_at=datetime.now(timezone.utc) + _RESET_CODE_TTL,
        ))
        await db.commit()
        background.add_task(asyncio.to_thread, _send_reset_code, user.email, code)
    return {"message": _RESET_SENT}


@router.post("/api/auth/password-reset/confirm")
async def confirm_password_reset(
    payload: PasswordResetConfirm, request: Request, db: AsyncSession = Depends(get_db)
) -> dict:
    check_rate_limit(request, "reset_confirm", _RESET_CONFIRMS_PER_IP, _RESET_CONFIRMS_IP_WINDOW)
    wrong = HTTPException(status_code=400, detail="That code is wrong or has expired. Check it, or ask for a new one.")
    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is None:
        raise wrong
    entry = await db.scalar(
        select(PasswordResetCode).where(PasswordResetCode.user_id == user.id).with_for_update()
    )
    if entry is None or entry.expires_at <= datetime.now(timezone.utc):
        raise wrong
    entry.attempts += 1
    if not hmac.compare_digest(entry.code_hash, _reset_code_hash(user.id, payload.code)):
        if entry.attempts >= _RESET_MAX_TRIES:
            await db.delete(entry)
            await db.commit()
            raise HTTPException(status_code=400, detail="Too many wrong codes. Ask for a new one.")
        await db.commit()
        raise wrong
    _check_new_password(payload.new_password)

    user.password_hash = await security.hash_password_async(payload.new_password)
    user.token_version += 1
    await db.delete(entry)
    await db.commit()
    await db.refresh(user)
    return {"token": security.create_token(user.id, user.token_version), "user": user.auth_response()}


_PASSWORD_CHANGE_MAX_ATTEMPTS, _PASSWORD_CHANGE_WINDOW_SECONDS = 10, 5 * 60


@router.post("/api/account/password")
async def change_password(
    payload: PasswordChangeRequest,
    request: Request,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Changes (or, for a Google-only account, sets) the password and signs
    out every other device: their tokens carry the old token_version. This
    device gets a fresh token in the reply so it stays signed in."""
    check_rate_limit(request, "password_change", _PASSWORD_CHANGE_MAX_ATTEMPTS, _PASSWORD_CHANGE_WINDOW_SECONDS)
    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    if user.password_hash is not None:
        if payload.current_password is None or not await security.verify_password_async(
            payload.current_password, user.password_hash, user_id=user.id
        ):
            raise HTTPException(status_code=401, detail="current password is incorrect")
    _check_new_password(payload.new_password)

    user.password_hash = await security.hash_password_async(payload.new_password)
    user.token_version += 1
    await db.commit()
    return {"token": security.create_token(user.id, user.token_version)}


@router.post("/api/account/sign-out-everywhere")
async def sign_out_everywhere(
    current_user: dict = Depends(security.get_current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    """For a lost phone or a shared computer: every existing token stops
    working. This device gets a fresh token so it stays signed in."""
    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    user.token_version += 1
    await db.commit()
    return {"token": security.create_token(user.id, user.token_version)}


@router.delete("/api/account")
async def delete_account(
    payload: AccountDeleteRequest,
    request: Request,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Blueprint Section 4 lists account deletion as required. Requires
    re-confirming the password (not just holding a valid token) — the same
    reasoning as login's rate limit: this is an irreversible, high-blast-
    radius action, so a leaked/stale token alone shouldn't be enough.

    A Google-only account (no password_hash — see that column's docstring)
    has nothing to confirm against, so it's deleted on being authenticated
    alone, same bar as every other authenticated action on this account.
    That's a real, narrower safety net than the password-confirm path,
    accepted deliberately rather than inventing a substitute confirmation
    step (e.g. re-verifying a fresh Google ID token) this pass.

    Every domain table is reachable from `users` via ondelete="CASCADE"
    (confirmed 2026-09-14/15 across knowledge/learning/assessment/planning/
    memory/personality), so deleting the row cascades correctly. The one
    thing NOT covered by that cascade is this user's RAG project-index
    JSON files (see _RAG_PROJECTS_ROOT above), cleaned up explicitly here.
    Deliberately NOT attempting to clean up server/uploads/<session_id>/ —
    upload sessions aren't tied to user_id anywhere in the schema (a
    pre-existing gap, unrelated to this endpoint) so there's no reliable
    way to attribute those files to this account; logged in
    STUDY_OS_PROGRESS.md rather than silently ignored.
    """
    check_rate_limit(request, "account_delete", _DELETE_MAX_ATTEMPTS, _DELETE_WINDOW_SECONDS)

    user = await db.get(User, current_user["id"])
    if user is None:
        raise HTTPException(status_code=401, detail="user no longer exists")
    if user.password_hash is not None:
        if payload.password is None or not await security.verify_password_async(payload.password, user.password_hash):
            raise HTTPException(status_code=401, detail="incorrect password")

    user_id = user.id
    await db.delete(user)
    await db.commit()

    shutil.rmtree(_RAG_PROJECTS_ROOT / f"user_{user_id}", ignore_errors=True)

    return {"deleted": True}
