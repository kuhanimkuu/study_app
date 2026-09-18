"""
Shared BYOK model-config resolution — extracted from routers/ask.py (which
was the sole consumer until server/domains/assessment/router.py's
short-answer grading became a second one, see STUDY_OS_PROGRESS.md,
2026-09-14). `routers/ask.py` imports from here now instead of defining
its own copy.
"""
from __future__ import annotations

from fastapi import HTTPException
from pydantic import BaseModel

from .. import crypto


class ModelConfig(BaseModel):
    backend: str = "local"  # "local" | "anthropic" | "openai" | "deepseek"
    model_name: str | None = None
    # AES-256-GCM ciphertext (see crypto.py), encrypted client-side with
    # this user's own key before it ever left the device — required when
    # backend != "local".
    encrypted_api_key: str | None = None


def resolve_model_config(model_config: ModelConfig | None, current_user: dict) -> dict:
    if model_config is None or model_config.backend == "local":
        return {"backend": "local", "tier": "tiny"}

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
