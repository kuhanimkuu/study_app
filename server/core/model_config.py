"""
Shared BYOK/hosted model-config resolution — extracted from routers/ask.py
(which was the sole consumer until server/domains/assessment/router.py's
short-answer grading became a second one, see STUDY_OS_PROGRESS.md,
2026-09-14). `routers/ask.py` imports from here now instead of defining
its own copy.

"hosted" (blueprint Section 42.1, added 2026-09-20) is a third path
alongside "local" (free, on this server) and BYOK (anthropic/openai/
deepseek with the user's own key): Study OS's own pooled provider key,
paid for via the wallet in server/domains/billing/. Deliberately does NOT
accept a client-supplied model_name override the way BYOK does — pricing
(billing/pricing.py) only has real numbers for the fixed default model per
provider, so honoring an arbitrary override here would risk silently
charging $0 for a real call. sqlalchemy session access is required to
check the wallet balance, unlike the BYOK/local paths, which are pure.
"""
from __future__ import annotations

from fastapi import HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from .. import crypto
from ..domains.billing import service as billing_service
from .config import get_settings

_HOSTED_PROVIDERS = ("anthropic", "openai", "deepseek")


class ModelConfig(BaseModel):
    backend: str = "local"  # "local" | "anthropic" | "openai" | "deepseek" | "hosted"
    model_name: str | None = None
    # AES-256-GCM ciphertext (see crypto.py), encrypted client-side with
    # this user's own key before it ever left the device — required when
    # backend is a BYOK provider (never used for "hosted").
    encrypted_api_key: str | None = None
    # Ignored since 2026-10-27 (the server picks the hosted model); still
    # accepted so older apps that send it keep working.
    hosted_provider: str | None = None


def resolve_model_config(model_config: ModelConfig | None, current_user: dict) -> dict:
    """The local/BYOK cases are synchronous and unchanged. "hosted" needs a
    DB session (to check the wallet balance) that this function's existing
    callers don't pass in — use resolve_model_config_async below for any
    caller that might see backend="hosted"; this sync version raises
    clearly if it does, rather than silently skipping the balance check."""
    if model_config is None or model_config.backend == "local":
        return {"backend": "local", "tier": "tiny"}

    if model_config.backend == "hosted":
        raise HTTPException(
            status_code=500,
            detail="backend='hosted' requires resolve_model_config_async (a DB session "
            "is needed to check the wallet balance) — this call site hasn't been updated",
        )

    if not model_config.encrypted_api_key:
        raise HTTPException(
            status_code=400,
            detail=f"backend={model_config.backend!r} requires encrypted_api_key",
        )
    try:
        api_key = crypto.decrypt_for_user(current_user["encryption_key"], model_config.encrypted_api_key)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"could not decrypt api key: {exc}") from exc

    config = {"backend": model_config.backend, "tier": "tiny", "api_key": api_key}
    if model_config.model_name:
        config["model_name"] = model_config.model_name
    return config


async def resolve_model_config_async(
    model_config: ModelConfig | None, current_user: dict, db: AsyncSession
) -> dict:
    """Same as resolve_model_config, plus the "hosted" case. Every /api/ask/*
    and BYOK call site should use this version now that "hosted" exists —
    resolve_model_config stays for now only as the explicit "not updated
    yet" guard above, not as a second real code path to keep in sync."""
    # The student's own monthly dollar cap is for their own keys; hosted
    # calls are paid in credits, with the hidden allowance behind them.
    if model_config is not None and model_config.backend not in ("local", "hosted"):
        await billing_service.enforce_spend_limit(db, current_user["id"])

    if model_config is not None and model_config.backend == "hosted":
        # The server picks the model (2026-10-27): credits are priced for it,
        # so whatever hosted_provider an older app still sends is ignored.
        settings = get_settings()
        provider = settings.hosted_default_provider
        if provider not in _HOSTED_PROVIDERS or not getattr(settings, f"hosted_{provider}_api_key"):
            raise HTTPException(
                status_code=503,
                detail="Study OS AI isn't available on this server right now — use your own AI key "
                "(Profile → Set up AI) for now.",
            )
        api_key = getattr(settings, f"hosted_{provider}_api_key")
        wallet = await billing_service.get_or_create_wallet(db, current_user["id"])
        if wallet.balance_cents <= 0:
            raise HTTPException(
                status_code=402,
                detail="You're out of Study OS credits. Add more in Profile → AI model.",
            )
        await billing_service.enforce_hosted_allowance(db, current_user["id"])
        # No model_name override honored here — see this module's
        # docstring. hosted_provider carries the billing identity
        # ("hosted") separately from backend (the real provider
        # model_router.run() needs), so call sites can tell this was a
        # pooled-key call and debit for it after the generation completes.
        return {"backend": provider, "tier": "tiny", "api_key": api_key, "hosted_provider": provider}

    return resolve_model_config(model_config, current_user)
