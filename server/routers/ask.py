"""
/api/ask/* — the actual study-question endpoints. Every one requires auth
(Depends(security.get_current_user)).

Local-first architecture (see README.md's "Architecture note"): the
device, not this server, is the source of truth for BYOK model settings
and chat history/progress. Both are sent PER-REQUEST by the client, never
read from server storage:
  - `model_config` — the caller's chosen backend; `encrypted_api_key`
    (if backend != "local") is decrypted here using that user's own
    encryption_key (crypto.py, generated at signup) and used for exactly
    this one call, never persisted.
  - `local_events` — the client's own locally-stored activity log,
    forwarded to the moderator's memory_query route ("what did I struggle
    with") so it can answer without this server keeping a copy.

Each endpoint does exactly two things: run the matching input_pipeline
engine to normalize the input, then call the moderator. No classification
logic lives in this file — that's the input engines' job, per
PATHWAY.md's architecture.
"""
from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, ConfigDict, Field

from .. import crypto, engines, security

router = APIRouter()

UPLOADS_DIR = Path(__file__).resolve().parent.parent / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)


def _save_upload(file: UploadFile, session_id: str) -> Path:
    session_dir = UPLOADS_DIR / session_id
    session_dir.mkdir(parents=True, exist_ok=True)
    dest = session_dir / f"{uuid.uuid4().hex}_{file.filename}"
    with dest.open("wb") as f:
        f.write(file.file.read())
    return dest


class ModelConfig(BaseModel):
    backend: str = "local"  # "local" | "anthropic" | "openai"
    model_name: str | None = None
    # AES-256-GCM ciphertext (see crypto.py), encrypted client-side with
    # this user's own key before it ever left the device — required when
    # backend != "local".
    encrypted_api_key: str | None = None


def _resolve_model_config(model_config: ModelConfig | None, current_user: dict) -> dict:
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


class TextAsk(BaseModel):
    content: str
    task: str | None = None
    requested_format: str | None = None
    # Structured arguments for the moderator's explicit-task-only routes
    # (numeric_*, generate_doc, diagram, animation, interactive_3d,
    # simulation) — matches the target engine's own input contract
    # directly. See moderator/README.md's "Structured routes" table.
    params: dict | None = None
    # "model_config_": pydantic v2 reserves the literal name "model_config"
    # on BaseModel itself (it's the class-level ConfigDict), so the field
    # is named with a trailing underscore and aliased back to the wire
    # name clients actually send.
    model_config_: ModelConfig | None = Field(default=None, alias="model_config")
    local_events: list[dict] | None = None
    session_id: str = "default"

    model_config = ConfigDict(populate_by_name=True)


@router.post("/api/ask/text")
async def ask_text(payload: TextAsk, current_user: dict = Depends(security.get_current_user)) -> dict:
    classified = await engines.text_input.run(content=payload.content)
    return await engines.moderator.run(
        input_type=classified["input_type"],
        content=classified["content"],
        detected=classified.get("detected", []),
        task=payload.task,
        requested_format=payload.requested_format,
        params=payload.params or {},
        session_id=payload.session_id,
        user_id=current_user["id"],
        model_config=_resolve_model_config(payload.model_config_, current_user),
        local_events=payload.local_events or [],
    )


@router.post("/api/ask/image")
async def ask_image(
    file: UploadFile = File(...),
    session_id: str = Form("default"),
    current_user: dict = Depends(security.get_current_user),
) -> dict:
    path = _save_upload(file, session_id)
    try:
        classified = await engines.image_input.run(content=str(path), source="upload")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"could not read image: {exc}") from exc

    return await engines.moderator.run(
        input_type=classified["input_type"],
        content=classified["content"],
        detected=classified.get("detected", []),
        session_id=session_id,
        user_id=current_user["id"],
        model_config={"backend": "local", "tier": "tiny"},
    )


@router.post("/api/ask/pdf")
async def ask_pdf(
    file: UploadFile | None = File(None),
    query: str | None = Form(None),
    session_id: str = Form("default"),
    current_user: dict = Depends(security.get_current_user),
) -> dict:
    """`file` is required on the first call in a session; a follow-up call
    (answering the moderator's "what would you like me to do with it?"
    clarification) only needs `query` — the moderator's own pending-context
    resume logic recovers the stored pdf_path, no need to re-upload."""
    model_config = {"backend": "local", "tier": "tiny"}
    if file is not None:
        path = _save_upload(file, session_id)
        try:
            classified = await engines.pdf_input.run(content=str(path))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"could not read PDF: {exc}") from exc
        return await engines.moderator.run(
            input_type="pdf", content=classified["content"], query=query,
            pdf_path=str(path), session_id=session_id,
            user_id=current_user["id"], model_config=model_config,
        )

    if query is None:
        raise HTTPException(status_code=400, detail="either 'file' (first call) or 'query' (follow-up) is required")
    return await engines.moderator.run(
        input_type="pdf", content="", query=query, session_id=session_id,
        user_id=current_user["id"], model_config=model_config,
    )


@router.post("/api/ask/audio")
async def ask_audio(
    file: UploadFile = File(...),
    session_id: str = Form("default"),
    current_user: dict = Depends(security.get_current_user),
) -> dict:
    path = _save_upload(file, session_id)
    try:
        transcribed = await engines.audio_input.run(content=str(path))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"could not transcribe audio: {exc}") from exc

    classified = await engines.text_input.run(content=transcribed["content"])
    return await engines.moderator.run(
        input_type=classified["input_type"],
        content=classified["content"],
        detected=classified.get("detected", []),
        session_id=session_id,
        user_id=current_user["id"],
        model_config={"backend": "local", "tier": "tiny"},
    )


class WebAsk(BaseModel):
    url: str
    kind: str = "url"
    session_id: str = "default"


@router.post("/api/ask/web")
async def ask_web(payload: WebAsk, current_user: dict = Depends(security.get_current_user)) -> dict:
    """Fetches and returns the page content directly, NOT routed through
    the moderator — the moderator has no web-content route implemented,
    so pretending it "understands" fetched web content would produce a
    confusing wrong answer most of the time. Honest scope boundary, see
    moderator/README.md."""
    try:
        fetched = await engines.web_input.run(content=payload.url, kind=payload.kind)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"could not fetch URL: {exc}") from exc

    return {
        "blocks": [{"type": "source", "content": fetched["content"], "source": fetched["source_url"]}],
        "session_id": payload.session_id,
    }


class ProjectAsk(BaseModel):
    content: str = ""
    project: str | None = None
    query: str | None = None
    session_id: str = "default"


@router.post("/api/ask/project")
async def ask_project(payload: ProjectAsk, current_user: dict = Depends(security.get_current_user)) -> dict:
    """Mirrors /api/ask/pdf's shape: first call names a project (no query
    yet) and gets back a clarification; the follow-up call sends `query`
    (same session_id) to actually search it."""
    return await engines.moderator.run(
        input_type="project",
        content=payload.content,
        project=payload.project,
        query=payload.query,
        session_id=payload.session_id,
        user_id=current_user["id"],
        model_config={"backend": "local", "tier": "tiny"},
    )
