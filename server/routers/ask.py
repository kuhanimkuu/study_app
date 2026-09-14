"""
/api/ask/* — the actual study-question endpoints. Every one requires auth
(Depends(security.get_current_user)).

`model_config` — the caller's chosen BYOK backend; `encrypted_api_key`
(if backend != "local") is decrypted here using that user's own
encryption_key (crypto.py, generated at signup) and used for exactly this
one call, never persisted.

`local_events` (ask_text only) — the client's own locally-stored activity
log, still accepted for backward compatibility, but no longer the only
source for the moderator's memory_query route ("what did I struggle
with"): as of 2026-09-14 (see STUDY_OS_PROGRESS.md), ask_text also merges
in real server-side signal from Mastery/Misconceptions (server/ai/moderator/
server_events.py) — the local-first framing this docstring used to have
("device is the source of truth... never read from server storage") no
longer fully applies to this one route now that Postgres is the actual
source of truth for learning data.

ask_text also passes the user's PersonalityProfile + explicit Memory
(server/ai/moderator/style.py) through to the moderator as an optional
`personality_style` prompt fragment + `personality_max_tokens` cap — the
same adaptive style `/explain` uses, now reaching ordinary chat too. Not
mastery-aware depth or misconception-awareness, though — those need a
specific Concept, which free-text chat doesn't resolve to one (see
STUDY_OS_PROGRESS.md's 2026-09-14 entry for that scope boundary).

Each endpoint does exactly two things: run the matching input_pipeline
engine to normalize the input, then call the moderator. No classification
logic lives in this file — that's the input engines' job, per
PATHWAY.md's architecture.
"""
from __future__ import annotations

import re
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import engines
from ..ai.memory.models import Memory
from ..ai.moderator.server_events import get_server_side_events
from ..ai.moderator.style import build_adaptive_style_note, verbosity_max_tokens
from ..ai.personality.router import get_or_create_personality
from ..ai.schemas import ModeratorResponse
from ..core import security
from ..core.model_config import ModelConfig, resolve_model_config
from ..db.session import get_db

router = APIRouter()

UPLOADS_DIR = Path(__file__).resolve().parent.parent / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

# session_id is client-supplied and was previously joined into a filesystem
# path unsanitized (UPLOADS_DIR / session_id) — a value like "../../x" would
# escape UPLOADS_DIR. Restricting to a safe charset closes that off.
_SAFE_SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")

# Extension allowlist per input kind — also closes the same traversal issue
# from the OTHER side: file.filename was previously appended to the dest
# path as-is (f"{uuid}_{file.filename}"), so a filename containing "/" or
# ".." components split into real path segments once joined, letting a
# crafted multipart filename write outside UPLOADS_DIR. The fix below never
# uses the client-supplied filename in the destination path at all — only
# its (allowlisted) extension.
_ALLOWED_EXTENSIONS: dict[str, set[str]] = {
    "image": {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"},
    "pdf": {".pdf"},
    "audio": {".mp3", ".wav", ".m4a", ".ogg", ".webm", ".flac"},
}

_MAX_UPLOAD_BYTES = 25 * 1024 * 1024  # 25 MB
_READ_CHUNK_BYTES = 1024 * 1024


def _validate_session_id(session_id: str) -> str:
    if not _SAFE_SESSION_ID_RE.match(session_id):
        raise HTTPException(status_code=400, detail="invalid session_id")
    return session_id


def _save_upload(file: UploadFile, session_id: str, kind: str) -> Path:
    session_id = _validate_session_id(session_id)

    # .name drops any directory components the client's filename smuggled
    # in; only the (allowlisted) suffix from it is ever used below.
    extension = Path(file.filename or "").name
    extension = Path(extension).suffix.lower()
    allowed = _ALLOWED_EXTENSIONS[kind]
    if extension not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"unsupported file type {extension or '(none)'!r} for {kind}; allowed: {', '.join(sorted(allowed))}",
        )

    session_dir = UPLOADS_DIR / session_id
    session_dir.mkdir(parents=True, exist_ok=True)
    dest = session_dir / f"{uuid.uuid4().hex}{extension}"

    size = 0
    try:
        with dest.open("wb") as f:
            while chunk := file.file.read(_READ_CHUNK_BYTES):
                size += len(chunk)
                if size > _MAX_UPLOAD_BYTES:
                    raise HTTPException(
                        status_code=413,
                        detail=f"file exceeds maximum size of {_MAX_UPLOAD_BYTES // (1024 * 1024)} MB",
                    )
                f.write(chunk)
    except HTTPException:
        dest.unlink(missing_ok=True)
        raise
    return dest


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


@router.post("/api/ask/text", response_model=ModeratorResponse)
async def ask_text(
    payload: TextAsk,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    classified = await engines.text_input.run(content=payload.content)
    # Merges the client's own local_events with real server-side signal
    # (Mastery/Misconceptions) so "what did I struggle with" answers from
    # actual data, not only whatever the client happened to submit — see
    # server/ai/moderator/server_events.py for why this lives there rather
    # than inside the moderator itself.
    server_events = await get_server_side_events(db, current_user["id"])

    # Personality + explicit memory now reach ordinary chat too (2026-09-14
    # — see STUDY_OS_PROGRESS.md), not just /api/v1/concepts/{id}/explain.
    # Both are user-scoped (not concept-scoped), which is exactly what
    # makes them applicable here where there's no specific Concept in play.
    personality = await get_or_create_personality(db, current_user["id"])
    explicit_memories = (
        await db.scalars(select(Memory).where(Memory.user_id == current_user["id"], Memory.type == "explicit"))
    ).all()
    await db.commit()  # persists a just-created default personality, if any
    personality_style = build_adaptive_style_note(
        personality, [{"key": m.key, "value": m.value} for m in explicit_memories]
    )
    personality_max_tokens = verbosity_max_tokens(personality)

    return await engines.moderator.run(
        input_type=classified["input_type"],
        content=classified["content"],
        detected=classified.get("detected", []),
        task=payload.task,
        requested_format=payload.requested_format,
        params=payload.params or {},
        session_id=payload.session_id,
        user_id=current_user["id"],
        model_config=resolve_model_config(payload.model_config_, current_user),
        local_events=(payload.local_events or []) + server_events,
        personality_style=personality_style,
        personality_max_tokens=personality_max_tokens,
    )


@router.post("/api/ask/image", response_model=ModeratorResponse)
async def ask_image(
    file: UploadFile = File(...),
    session_id: str = Form("default"),
    current_user: dict = Depends(security.get_current_user),
) -> dict:
    path = _save_upload(file, session_id, kind="image")
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


@router.post("/api/ask/pdf", response_model=ModeratorResponse)
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
        path = _save_upload(file, session_id, kind="pdf")
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


@router.post("/api/ask/audio", response_model=ModeratorResponse)
async def ask_audio(
    file: UploadFile = File(...),
    session_id: str = Form("default"),
    current_user: dict = Depends(security.get_current_user),
) -> dict:
    path = _save_upload(file, session_id, kind="audio")
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


@router.post("/api/ask/web", response_model=ModeratorResponse)
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


@router.post("/api/ask/project", response_model=ModeratorResponse)
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
