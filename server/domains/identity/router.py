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

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ... import crypto
from ...core import security
from ...core.rate_limit import check_rate_limit
from ...db.session import get_db
from .models import User

router = APIRouter()

# Brute-force protection (blueprint Section 37) — see core/rate_limit.py
# for what this does and doesn't protect against. Signup gets a stricter
# window than login (spam-account creation vs. legitimate retry-after-typo
# traffic have different tolerances).
_LOGIN_MAX_ATTEMPTS, _LOGIN_WINDOW_SECONDS = 10, 5 * 60
_SIGNUP_MAX_ATTEMPTS, _SIGNUP_WINDOW_SECONDS = 5, 60 * 60


class SignupRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, v: str) -> str:
        # Without this, "User@Example.com" and "user@example.com" would
        # pass the DB's case-sensitive unique constraint as two different
        # accounts — a real pre-existing bug, not a hypothetical.
        return v.strip().lower()


class LoginRequest(BaseModel):
    email: EmailStr
    password: str

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class AccountUpdate(BaseModel):
    display_name: str | None = None
    education_level: str | None = None
    course: str | None = None
    institution: str | None = None
    preferred_language: str | None = None
    daily_study_target_minutes: int | None = None


@router.post("/api/auth/signup")
async def signup(payload: SignupRequest, request: Request, db: AsyncSession = Depends(get_db)) -> dict:
    check_rate_limit(request, "signup", _SIGNUP_MAX_ATTEMPTS, _SIGNUP_WINDOW_SECONDS)

    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="password must be at least 8 characters")

    existing = await db.scalar(select(User).where(User.email == payload.email))
    if existing is not None:
        raise HTTPException(status_code=409, detail="an account with this email already exists")

    user = User(
        email=payload.email,
        password_hash=security.hash_password(payload.password),
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

    token = security.create_token(user.id)
    return {"token": token, "user": user.auth_response()}


@router.post("/api/auth/login")
async def login(payload: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)) -> dict:
    check_rate_limit(request, "login", _LOGIN_MAX_ATTEMPTS, _LOGIN_WINDOW_SECONDS)

    user = await db.scalar(select(User).where(User.email == payload.email))
    if user is None or not security.verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="invalid email or password")

    token = security.create_token(user.id)
    # Returning the key again here (not just at signup) lets a reinstalled
    # app / new device recover it via a normal login, rather than losing
    # access to previously-encrypted local data if secure storage was wiped.
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
