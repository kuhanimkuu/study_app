"""Account settings — display name only. BYOK model preference (backend +
API key) is NOT server state anymore — it lives on the device and is sent
per-request (encrypted, see crypto.py) to whichever /api/ask/* call needs
it. See routers/ask.py's ModelConfig for that."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from .. import db, security

router = APIRouter()


class AccountUpdate(BaseModel):
    display_name: str | None = None


@router.get("/api/account")
async def get_account(current_user: dict = Depends(security.get_current_user)) -> dict:
    return db.public_user(current_user)


@router.patch("/api/account")
async def update_account(payload: AccountUpdate, current_user: dict = Depends(security.get_current_user)) -> dict:
    if payload.display_name is None:
        return db.public_user(current_user)

    conn = db.get_connection()
    try:
        conn.execute("UPDATE users SET display_name = ? WHERE id = ?", (payload.display_name, current_user["id"]))
        conn.commit()
        user_row = conn.execute("SELECT * FROM users WHERE id = ?", (current_user["id"],)).fetchone()
    finally:
        conn.close()

    return db.public_user(user_row)
