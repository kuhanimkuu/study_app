"""
POST /api/v1/ai/check — "Test and save" in the app's AI setup (2026-10-21).

Most students have never made an API key. Before this, a key pasted wrong,
or a provider account with no credit yet, only showed up later as Sage
"not working". This makes one tiny real call with the key the app is about
to save, and answers in plain words what's wrong, if anything.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from .. import engines
from ..core.model_config import ModelConfig, resolve_model_config_async
from ..core.rate_limit import per_user_limit
from ..db.session import get_db
from ..domains.billing import service as billing_service

router = APIRouter(prefix="/api/v1")

# A handful of tries is plenty for setting up a key.
_check_user = per_user_limit("ai_check", 10, 10 * 60)

_PROVIDER_NAMES = {"anthropic": "Anthropic", "openai": "OpenAI", "deepseek": "DeepSeek"}


class AiCheck(BaseModel):
    model_config_: ModelConfig = Field(alias="model_config")

    model_config = ConfigDict(populate_by_name=True)


def explain_failure(provider: str, exc: Exception) -> str:
    """The provider SDKs' errors, in words a student can act on."""
    name = _PROVIDER_NAMES.get(provider, provider)
    status = getattr(exc, "status_code", None) or getattr(getattr(exc, "response", None), "status_code", None)
    text = str(exc).lower()
    if status == 401 or "authentication" in text or "invalid x-api-key" in text or "incorrect api key" in text:
        return f"{name} didn't accept that key. Copy it again from {name}'s API keys page — the whole thing, no spaces."
    if status == 402 or "insufficient balance" in text or "insufficient_quota" in text or "credit balance" in text:
        return f"The key works, but your {name} account has no credit yet. Top it up on {name}'s website, then test again."
    if status == 403 or "permission" in text:
        return f"{name} says this key isn't allowed to use the model. Check the key's permissions on {name}'s website."
    if status == 429 or "rate limit" in text:
        return f"{name} is limiting requests right now. Wait a minute and test again."
    return f"{name} didn't answer: {exc}"


@router.post("/ai/check")
async def check_ai(
    payload: AiCheck,
    current_user: dict = Depends(_check_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if payload.model_config_.backend == "local":
        raise HTTPException(status_code=400, detail="Choose a provider (DeepSeek, OpenAI or Anthropic) and add its key.")
    model_config = await resolve_model_config_async(payload.model_config_, current_user, db)
    provider = model_config.get("hosted_provider") or model_config.get("backend", "")
    try:
        result = await engines.model_router.run(prompt="Reply with the single word OK.", max_tokens=5, **model_config)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=explain_failure(provider, exc)) from exc
    await billing_service.record_ai_usage(db, current_user["id"], model_config, result.get("usage"), "check")
    await db.commit()
    return {"ok": True, "provider": _PROVIDER_NAMES.get(provider, provider)}
