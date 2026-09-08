"""Signup / login / current-user endpoints. Signup and login are the ONLY
two calls that ever return a user's encryption_key — see crypto.py and
db.py's auth_user() vs public_user() for why (the device needs the key
once to persist it locally; routine calls like /me don't re-expose it)."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from .. import crypto, db, security

router = APIRouter()


class SignupRequest(BaseModel):
    email: str
    password: str
    display_name: str | None = None


class LoginRequest(BaseModel):
    email: str
    password: str


@router.post("/api/auth/signup")
async def signup(payload: SignupRequest) -> dict:
    if len(payload.password) < 8:
        raise HTTPException(status_code=400, detail="password must be at least 8 characters")

    conn = db.get_connection()
    try:
        existing = conn.execute("SELECT id FROM users WHERE email = ?", (payload.email,)).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="an account with this email already exists")

        password_hash = security.hash_password(payload.password)
        encryption_key = crypto.generate_user_key()
        cursor = conn.execute(
            "INSERT INTO users (email, password_hash, display_name, encryption_key, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (payload.email, password_hash, payload.display_name, encryption_key, datetime.now(timezone.utc).isoformat()),
        )
        conn.commit()
        user_row = conn.execute("SELECT * FROM users WHERE id = ?", (cursor.lastrowid,)).fetchone()
    finally:
        conn.close()

    token = security.create_token(user_row["id"])
    return {"token": token, "user": db.auth_user(user_row)}


@router.post("/api/auth/login")
async def login(payload: LoginRequest) -> dict:
    conn = db.get_connection()
    try:
        user_row = conn.execute("SELECT * FROM users WHERE email = ?", (payload.email,)).fetchone()
    finally:
        conn.close()

    if user_row is None or not security.verify_password(payload.password, user_row["password_hash"]):
        raise HTTPException(status_code=401, detail="invalid email or password")

    token = security.create_token(user_row["id"])
    # Returning the key again here (not just at signup) lets a reinstalled
    # app / new device recover it via a normal login, rather than losing
    # access to previously-encrypted local data if secure storage was wiped.
    return {"token": token, "user": db.auth_user(user_row)}


@router.get("/api/auth/me")
async def me(current_user: dict = Depends(security.get_current_user)) -> dict:
    return db.public_user(current_user)
