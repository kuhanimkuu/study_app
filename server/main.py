"""
Study OS — HTTP server.

Exposes the engines built under features/ over HTTP for the Flutter app (or
anything else) to call. This is the "server-hosted backend" side of the
architecture decision made mid-build (see README.md's "Architecture note"
and document_engine/scanned_ocr/README.md for the research behind it) — the
Flutter app becomes a thin client that uploads text/images/PDFs/audio/URLs
here and renders back whatever `blocks` come back.

Auth is REQUIRED for every /api/ask/* and /api/account endpoint (JWT
bearer token, see core/security.py).

Architecture note (data ownership — updated 2026-09-14, see
STUDY_OS_PROGRESS.md): earlier versions of this server were local-first —
device as source of truth, server storing only auth essentials. That's
been superseded: the HelioHost deployment target isn't offline-capable, so
**server-side PostgreSQL is now the source of truth** going forward
(no sync engine needed). This pass migrated auth (domains/identity) and
Knowledge Spaces / "projects" (domains/knowledge) onto Postgres.
Chat history/progress/mastery storage is NOT built server-side yet — ask.py's
`local_events`/`activity` flow is unchanged this pass (still client-submitted,
still not persisted here) — that's a later-phase domain (see
server/domains/tutor/README.md, server/domains/progress/README.md), not a
contradiction of the decision above.

This file only creates the app, configures CORS/static mounts, and wires
up domains/ + routers/ — no endpoint logic lives here directly.
  - health.py                    — liveness check
  - domains/identity/router.py   — signup / login / current-user / account
                                    (Postgres-backed)
  - domains/knowledge/router.py  — Knowledge Space ("project") CRUD +
                                    material upload + Studio docs
                                    (Postgres-backed identity/metadata;
                                    chunk storage still JSON-file based)
  - domains/learning/router.py   — Concepts + Mastery (FSRS-based)
  - domains/assessment/router.py — Question authoring/practice + grading +
                                    misconceptions
  - domains/billing/router.py    — hosted pay-as-you-go AI tier: wallet
                                    balance, top-ups, usage ledger
                                    (blueprint Section 42.1)
  - routers/ask.py               — the actual study-question endpoints
                                    (not migrated to a domain yet)

domains/learning and domains/assessment are mounted under /api/v1 (blueprint
Section 36) — the FIRST versioned endpoints in this server. Existing
endpoints (everything above) stay unversioned; versioning starts fresh for
new endpoint groups rather than retrofitting old ones, see
STUDY_OS_PROGRESS.md, 2026-09-14.

Run with: uvicorn server.main:app --reload --port 8000
"""
from __future__ import annotations

# First: sets CPU-thread limits before numpy/torch/ONNX load (see that module).
from .core import runtime_env  # noqa: F401  isort: skip

import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.gzip import DEFAULT_EXCLUDED_CONTENT_TYPES

from .ai.memory.router import router as memory_router
from .ai.moderator.router import router as moderator_router
from .ai.personality.router import router as personality_router
from .core.config import get_settings
from .domains.assessment.router import router as assessment_router
from .domains.billing.router import router as billing_router
from .domains.diagnostics.router import router as diagnostics_router
from .domains.identity.router import router as identity_router
from .domains.knowledge.files_router import router as files_router
from .domains.knowledge.notes_router import router as notes_router
from .domains.knowledge.router import mark_interrupted_indexing_failed
from .domains.knowledge.router import router as knowledge_router
from .domains.knowledge.search_router import router as search_router
from .domains.learning.router import router as learning_router
from .domains.planning.router import router as planning_router
from .domains.tutor.router import router as tutor_router
from .routers import ai_check, ask, health
from .workers.cleanup import cleanup_loop

FEATURES_ROOT = Path(__file__).resolve().parent.parent / "features"

# Where the moderator writes generated artifacts (images, GIFs, GLB models,
# PDFs from visual_explanation/document_generation routes) — see
# moderator/engine.py's _GENERATED_DIR doc comment. Mounted below at
# "/generated" so a block's "content" (a "/generated/<file>" URL path) is
# directly fetchable by the client, not just a server-local path.
GENERATED_DIR = FEATURES_ROOT / "moderator" / "generated"
GENERATED_DIR.mkdir(parents=True, exist_ok=True)


class _ImmutableStaticFiles(StaticFiles):
    """Every generated file gets a fresh uuid name and is never rewritten,
    so the client may cache it for good — reopening a PDF or image no
    longer re-downloads it over the student's mobile data (2026-10-19)."""

    def file_response(self, *args, **kwargs):
        response = super().file_response(*args, **kwargs)
        response.headers["Cache-Control"] = "private, max-age=31536000, immutable"
        return response


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Uploads index in the background (domains/knowledge/router.py) — any
    # left "indexing" from before this start were cut off by the restart.
    await mark_interrupted_indexing_failed()
    # Deletes old uploads/generated files every few hours (workers/cleanup.py).
    cleaner = asyncio.create_task(cleanup_loop())
    yield
    cleaner.cancel()


app = FastAPI(title="Study OS", lifespan=lifespan)

# CORS_ALLOWED_ORIGINS in .env (server/core/config.py) — defaults to "*"
# (every origin) so local dev against the Flutter app needs no setup; set
# it to a real comma-separated origin list before deployment. allow_
# credentials only makes sense with a real origin list — CORSMiddleware
# itself refuses "*" + credentials, and this app uses a bearer token (not
# cookies) anyway, so credentials stay off regardless of origin config.
_cors_origins = get_settings().cors_allowed_origins_list
app.add_middleware(
    CORSMiddleware, allow_origins=_cors_origins, allow_methods=["*"], allow_headers=["*"]
)
# Compresses JSON replies (chat blocks, material lists, flashcards) —
# usually several times smaller over a phone's connection (2026-10-19).
# Level 6, not Starlette's default 9: nearly the same size for much less CPU
# on Render's fraction-of-a-core. PDFs join Starlette's own skip list
# (images, audio, zips) — already compressed, so gzip would burn CPU for
# nothing.
app.add_middleware(
    GZipMiddleware,
    minimum_size=1000,
    compresslevel=6,
    exclude_content_types=(*DEFAULT_EXCLUDED_CONTENT_TYPES, "application/pdf", "model/gltf-binary"),
)
app.mount("/generated", _ImmutableStaticFiles(directory=GENERATED_DIR), name="generated")

app.include_router(health.router)
app.include_router(identity_router)
app.include_router(knowledge_router)
app.include_router(files_router)
app.include_router(notes_router)
app.include_router(search_router)
app.include_router(ask.router)
app.include_router(ai_check.router)
app.include_router(learning_router)
app.include_router(assessment_router)
app.include_router(planning_router)
app.include_router(tutor_router)
app.include_router(moderator_router)
app.include_router(memory_router)
app.include_router(personality_router)
app.include_router(billing_router)
app.include_router(diagnostics_router)
