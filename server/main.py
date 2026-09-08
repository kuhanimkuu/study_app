"""
Study OS — HTTP server.

Exposes the engines built under features/ over HTTP for the Flutter app (or
anything else) to call. This is the "server-hosted backend" side of the
architecture decision made mid-build (see README.md's "Architecture note"
and document_engine/scanned_ocr/README.md for the research behind it) — the
Flutter app becomes a thin client that uploads text/images/PDFs/audio/URLs
here and renders back whatever `blocks` come back.

Auth is REQUIRED for every /api/ask/* and /api/account endpoint (JWT
bearer token, see security.py).

Architecture note (local-first pivot): this server is intentionally
"dumb" about user content. It stores ONLY auth essentials (email,
password_hash, display_name) plus a per-user encryption key (crypto.py)
— never chat history, progress, or BYOK API keys at rest. The Flutter
client is the source of truth for all of that; it sends whatever a given
/api/ask/* call needs (a BYOK model_config, or local_events for memory
queries) per-request, and this server never persists it. There is
deliberately no /api/history endpoint — history lives on the device.

This file only creates the app, configures CORS/static mounts, and wires
up the routers/ package — no endpoint logic lives here directly. Each
routers/*.py module owns one area:
  - health.py    — liveness check
  - auth.py      — signup / login / current-user
  - account.py   — display name only
  - ask.py       — the actual study-question endpoints
  - projects.py  — project ("notebook") CRUD + material upload — the one
                    deliberate exception to the local-first rule above,
                    see db.py's module docstring for why

Run with: uvicorn server.main:app --reload --port 8000
"""
from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .routers import account, ask, auth, health, projects

FEATURES_ROOT = Path(__file__).resolve().parent.parent / "features"

# Where the moderator writes generated artifacts (images, GIFs, GLB models,
# PDFs from visual_explanation/document_generation routes) — see
# moderator/engine.py's _GENERATED_DIR doc comment. Mounted below at
# "/generated" so a block's "content" (a "/generated/<file>" URL path) is
# directly fetchable by the client, not just a server-local path.
GENERATED_DIR = FEATURES_ROOT / "moderator" / "generated"
GENERATED_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Study OS")

# Dev-permissive CORS — tighten this (specific origins, not "*") before any
# real deployment; fine for local development against a Flutter client.
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)
app.mount("/generated", StaticFiles(directory=GENERATED_DIR), name="generated")

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(account.router)
app.include_router(projects.router)
app.include_router(ask.router)
