"""/api/v1/personality — get-or-create + partial update. Ownership here is
simpler than elsewhere in this app: ownership IS the user_id match, no
join through a Knowledge Space needed (a personality profile belongs
directly to a user, not to anything else)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...db.session import get_db
from .models import (
    FORMALITY_VALUES,
    TEACHING_STYLE_VALUES,
    TONE_VALUES,
    VERBOSITY_VALUES,
    PersonalityProfile,
)

router = APIRouter(prefix="/api/v1")


async def get_or_create_personality(db: AsyncSession, user_id: int) -> PersonalityProfile:
    profile = await db.scalar(select(PersonalityProfile).where(PersonalityProfile.user_id == user_id))
    if profile is None:
        profile = PersonalityProfile(user_id=user_id)
        db.add(profile)
        await db.flush()
    return profile


@router.get("/personality")
async def get_personality(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    profile = await get_or_create_personality(db, current_user["id"])
    await db.commit()
    return profile.public()


class UpdatePersonality(BaseModel):
    tone: str | None = None
    formality: str | None = None
    humor: float | None = None
    encouragement: float | None = None
    directness: float | None = None
    challenge_level: float | None = None
    verbosity: str | None = None
    teaching_style: str | None = None


_NUMERIC_FIELDS = ("humor", "encouragement", "directness", "challenge_level")
_CATEGORICAL_CHOICES = {
    "tone": TONE_VALUES,
    "formality": FORMALITY_VALUES,
    "verbosity": VERBOSITY_VALUES,
    "teaching_style": TEACHING_STYLE_VALUES,
}


@router.patch("/personality")
async def update_personality(
    payload: UpdatePersonality,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    updates = payload.model_dump(exclude_unset=True)

    for field, choices in _CATEGORICAL_CHOICES.items():
        if field in updates and updates[field] not in choices:
            raise HTTPException(status_code=400, detail=f"{field} must be one of {sorted(choices)}")
    for field in _NUMERIC_FIELDS:
        if field in updates and not (0.0 <= updates[field] <= 1.0):
            raise HTTPException(status_code=400, detail=f"{field} must be between 0.0 and 1.0")

    profile = await get_or_create_personality(db, current_user["id"])
    for field, value in updates.items():
        setattr(profile, field, value)

    await db.commit()
    await db.refresh(profile)
    return profile.public()
