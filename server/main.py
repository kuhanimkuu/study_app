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

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .ai.memory.router import router as memory_router
from .ai.moderator.router import router as moderator_router
from .ai.personality.router import router as personality_router
from .core.config import get_settings
from .domains.assessment.router import router as assessment_router
from .domains.identity.router import router as identity_router
from .domains.knowledge.router import router as knowledge_router
from .domains.learning.router import router as learning_router
from .domains.planning.router import router as planning_router
from .routers import ask, health

FEATURES_ROOT = Path(__file__).resolve().parent.parent / "features"

# Where the moderator writes generated artifacts (images, GIFs, GLB models,
# PDFs from visual_explanation/document_generation routes) — see
# moderator/engine.py's _GENERATED_DIR doc comment. Mounted below at
# "/generated" so a block's "content" (a "/generated/<file>" URL path) is
# directly fetchable by the client, not just a server-local path.
GENERATED_DIR = FEATURES_ROOT / "moderator" / "generated"
GENERATED_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Study OS")

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
app.mount("/generated", StaticFiles(directory=GENERATED_DIR), name="generated")

app.include_router(health.router)
app.include_router(identity_router)
app.include_router(knowledge_router)
app.include_router(ask.router)
app.include_router(learning_router)
app.include_router(assessment_router)
app.include_router(planning_router)
app.include_router(moderator_router)
app.include_router(memory_router)
app.include_router(personality_router)
