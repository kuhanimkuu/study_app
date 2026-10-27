"""
/api/v1 — Go deeper and videos (2026-10-27).

  POST /go-deeper        2-3 real resources on a topic (go_deeper.py)
  POST /videos/resolve   a pasted YouTube link → a video to play in the app,
                         with the section worth watching when it has chapters
  POST /sources/report   "Report this source"
"""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ...core import security
from ...core.model_config import ModelConfig, resolve_model_config_async
from ...core.rate_limit import ai_user
from ...db.session import get_db
from ..identity.models import User
from ..learning import generation
from . import go_deeper, providers
from .models import SourceReport

router = APIRouter(prefix="/api/v1")

_PICK_MAX_TOKENS = 700


class GoDeeper(BaseModel):
    topic: str = Field(min_length=2, max_length=200)
    context: str | None = Field(default=None, max_length=2_000)
    level: Literal["beginner", "exam", "advanced"] | None = None
    depth: Literal["quick", "full", "exam"] | None = None
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


class ResolveVideo(BaseModel):
    url: str = Field(max_length=500)
    context: str | None = Field(default=None, max_length=2_000)
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


class ReportSource(BaseModel):
    url: str = Field(min_length=8, max_length=2_000)
    reason: str = Field(min_length=3, max_length=1_000)


async def _pick(db: AsyncSession, user_id: int, model_config: dict, prompt: str) -> str | None:
    """The model's choice, or None when there's no usable model (the
    caller then picks by kind)."""
    try:
        return await generation.call_model(prompt, _PICK_MAX_TOKENS, model_config, db, user_id, source="go_deeper")
    except HTTPException:
        return None


@router.post("/go-deeper")
async def go_deeper_endpoint(
    payload: GoDeeper, current_user: dict = Depends(ai_user), db: AsyncSession = Depends(get_db)
) -> dict:
    user = await db.get(User, current_user["id"])
    level = go_deeper.level_for(payload.level, payload.depth, user.education_level if user else None)
    candidates = await go_deeper.gather(payload.topic, level)
    if not candidates:
        return {"level": level, "items": [], "picked_by": None}

    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)
    text = await _pick(db, current_user["id"], model_config, go_deeper.pick_prompt(payload.topic, level, candidates, payload.context))
    picks = go_deeper.parse_picks(text or "", candidates)
    picked_by = "ai" if picks else "default"
    if not picks:
        picks = go_deeper.default_picks(candidates)
    by_id = {c["id"]: c for c in candidates}
    items = [go_deeper.to_item(by_id[p["id"]], p) for p in picks]
    return {"level": level, "items": await go_deeper.finish(items, current_user["id"]), "picked_by": picked_by}


async def video_item(
    url: str, context: str | None, model_config: dict, db: AsyncSession, user_id: int
) -> dict:
    """A YouTube link → a video to play inside the app. With chapters and a
    topic to go on (`context`), the model picks the section worth watching
    and says what it covers; otherwise it starts where the link said.
    Raises 400 for a non-YouTube link, 404 for a missing video."""
    parsed = providers.youtube_video_id(url)
    if parsed is None:
        raise HTTPException(status_code=400, detail="That isn't a YouTube video link.")
    video_id, start = parsed
    found = await providers.youtube_video(video_id)
    if not found:
        raise HTTPException(status_code=404, detail="Couldn't find that video — it may be private or removed.")
    candidate = {**found[0], "id": "c1", "tier": "B"}
    pick = {"id": "c1", "reason": None, "chapter": None, "covers": None}
    if candidate.get("chapters") and context:
        text = await _pick(db, user_id, model_config, go_deeper.pick_prompt(context[:200], "beginner", [candidate], context))
        pick = (go_deeper.parse_picks(text or "", [candidate]) or [pick])[0]
    item = go_deeper.to_item(candidate, pick)
    if pick.get("chapter") is None and start:
        item["video"]["start"] = start
    return (await go_deeper.finish([item], user_id))[0]


def video_block(item: dict) -> dict:
    """The chat block for a video item (ai/schemas/blocks.py VideoBlock)."""
    return {"type": "video", "title": item["title"], "url": item["url"], "attribution": item.get("attribution"), **item["video"]}


@router.post("/videos/resolve")
async def resolve_video(
    payload: ResolveVideo, current_user: dict = Depends(ai_user), db: AsyncSession = Depends(get_db)
) -> dict:
    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)
    return {"item": await video_item(payload.url, payload.context, model_config, db, current_user["id"])}


@router.post("/sources/report")
async def report_source(
    payload: ReportSource,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    db.add(SourceReport(user_id=current_user["id"], url=payload.url, reason=payload.reason))
    await db.commit()
    return {"reported": True, "message": "Thanks — we'll look at it. Sources that break the rules are blocked for everyone."}
