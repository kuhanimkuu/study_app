"""
Database — SQLite storage for user accounts and project metadata.

Mostly deliberately minimal: per the project's local-first architecture
decision, the server stores ONLY what auth requires (email, password hash,
display name) plus each user's own encryption key (see crypto.py) — NOT
chat history, memory log/progress, or BYOK model settings. Those live on
the device; the server only ever sees them ephemerally, per-request, when
a specific request needs server-side processing (e.g. a BYOK API call).

`projects` is the one deliberate exception to "server stores nothing of
the user's own content." Unlike chat/BYOK, a project's material has to be
embedded (rag/indexing, via fastembed) to be searchable at all — that's
real, non-trivial compute this server already does, so the resulting index
naturally lives where it was computed rather than being shipped back to
the device just to satisfy a purity rule. This table only holds each
project's identity (id/slug/display name/owner); the actual indexed
material stays in JSON files under rag/projects/projects/user_<id>/ (see
routers/projects.py and moderator/engine.py's _user_projects_dir).

`generated_artifacts` is the same exception applied to Studio documents
(routers/projects.py's /api/projects/{slug}/studio) — tracks which
generated PDF belongs to which project/user; the PDF itself lives under
features/moderator/generated/user_<id>/, same per-user namespacing
pattern as projects.

Lives in server/, not features/<category>/, because authentication is
HTTP/session infrastructure, not a content-processing "engine" like
everything under features/ — deliberately doesn't fit that folder
convention, not an oversight.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent / "users.db"


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            display_name TEXT,
            encryption_key TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id),
            slug TEXT NOT NULL,
            display_name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(user_id, slug)
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS generated_artifacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id),
            project_slug TEXT NOT NULL,
            doc_type TEXT NOT NULL,
            title TEXT NOT NULL,
            url_path TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    return conn


def public_user(row: sqlite3.Row | dict) -> dict:
    """User fields safe to send to the client on ROUTINE calls (e.g.
    /api/auth/me, PATCH /api/account) — never the password hash, never the
    encryption key repeatedly. Use auth_user() instead for the one-time
    signup/login response, which does include the key (the device needs it
    at least once to persist locally)."""
    return {
        "id": row["id"],
        "email": row["email"],
        "display_name": row["display_name"],
    }


def auth_user(row: sqlite3.Row | dict) -> dict:
    """Signup/login response shape — includes encryption_key so the device
    can store it (secure on-device storage) for encrypting its local data
    and for encrypting anything it later sends the server that needs
    per-request decryption (see crypto.py, routers/ask.py)."""
    return {**public_user(row), "encryption_key": row["encryption_key"]}


def public_project(row: sqlite3.Row | dict) -> dict:
    return {
        "id": row["id"],
        "slug": row["slug"],
        "display_name": row["display_name"],
        "created_at": row["created_at"],
    }


def public_artifact(row: sqlite3.Row | dict) -> dict:
    return {
        "id": row["id"],
        "doc_type": row["doc_type"],
        "title": row["title"],
        "url": row["url_path"],
        "created_at": row["created_at"],
    }
