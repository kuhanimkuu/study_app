"""
/api/projects — project ("notebook") management: create, list, delete, and
add material to a user's own projects.

Projects are the one deliberate exception to this server's local-first
"stores nothing of the user's own content" rule — see db.py's module
docstring for why (the embedding compute has to happen somewhere, and it
already happens here, via rag/indexing). This router only manages a
project's identity and its material; *querying* a project is a separate
endpoint (`/api/ask/project` in ask.py), since that flow already existed
and matches the `/api/ask/*` request/response shape everything else uses.

Reuses `engines.moderator._user_projects_dir()` (rather than recomputing
the per-user storage path here) specifically so the directory a project's
material gets written to and the directory a query reads from can never
drift apart.
"""
from __future__ import annotations

import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from .. import db, engines, security

router = APIRouter()

_SLUG_RE = re.compile(r"[^a-z0-9]+")

# document_generation/generate_docs' real, honestly-documented doc types —
# see that engine's module docstring for exactly what each one does (most
# compile the project's chunks under a titled document; flashcards and
# practice_exam do real, if simple, per-chunk transforms).
_DOC_TYPES = {
    "study_guide",
    "revision_notes",
    "summary",
    "formula_sheet",
    "worksheet",
    "flashcards",
    "practice_exam",
    "lab_report",
}

_GENERATED_ROOT = Path(__file__).resolve().parent.parent.parent / "features" / "moderator" / "generated"


def _user_generated_dir(user_id: int) -> Path:
    d = _GENERATED_ROOT / f"user_{user_id}"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _slugify(name: str) -> str:
    slug = _SLUG_RE.sub("_", name.strip().lower()).strip("_")
    if not slug:
        raise HTTPException(status_code=400, detail="project name must contain at least one letter or number")
    return slug


def _get_project_row(conn, user_id: int, slug: str):
    row = conn.execute("SELECT * FROM projects WHERE user_id = ? AND slug = ?", (user_id, slug)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail=f"no project named {slug!r}")
    return row


class CreateProject(BaseModel):
    display_name: str


@router.post("/api/projects")
async def create_project(payload: CreateProject, current_user: dict = Depends(security.get_current_user)) -> dict:
    slug = _slugify(payload.display_name)
    conn = db.get_connection()
    try:
        existing = conn.execute(
            "SELECT id FROM projects WHERE user_id = ? AND slug = ?", (current_user["id"], slug)
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail=f"you already have a project named {slug!r}")
        cursor = conn.execute(
            "INSERT INTO projects (user_id, slug, display_name, created_at) VALUES (?, ?, ?, ?)",
            (current_user["id"], slug, payload.display_name, datetime.now(timezone.utc).isoformat()),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM projects WHERE id = ?", (cursor.lastrowid,)).fetchone()
    finally:
        conn.close()
    return db.public_project(row)


@router.get("/api/projects")
async def list_projects(current_user: dict = Depends(security.get_current_user)) -> dict:
    conn = db.get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM projects WHERE user_id = ? ORDER BY created_at DESC", (current_user["id"],)
        ).fetchall()
    finally:
        conn.close()

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    projects = []
    for row in rows:
        project = db.public_project(row)
        project["chunk_count"] = _chunk_count(projects_dir, row["slug"])
        projects.append(project)
    return {"projects": projects}


@router.delete("/api/projects/{slug}")
async def delete_project(slug: str, current_user: dict = Depends(security.get_current_user)) -> dict:
    conn = db.get_connection()
    try:
        row = _get_project_row(conn, current_user["id"], slug)
        conn.execute("DELETE FROM projects WHERE id = ?", (row["id"],))
        conn.commit()
    finally:
        conn.close()

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    (projects_dir / f"{slug}.json").unlink(missing_ok=True)
    return {"deleted": slug}


@router.post("/api/projects/{slug}/material")
async def add_material(
    slug: str,
    file: UploadFile | None = File(None),
    text: str | None = Form(None),
    current_user: dict = Depends(security.get_current_user),
) -> dict:
    """Extracts text from whichever of `file` (.pdf or .txt) or `text`
    (pasted text) was sent, then indexes it into this project via
    rag/projects — the one engine call this whole router exists to reach,
    everything else here is just CRUD around it."""
    conn = db.get_connection()
    try:
        _get_project_row(conn, current_user["id"], slug)
    finally:
        conn.close()

    material = await _extract_material(file, text, current_user["id"], slug)
    if not material.strip():
        raise HTTPException(status_code=400, detail="no text content found in the upload")

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    return await engines.rag_projects.run(project=slug, material=[material], projects_dir=projects_dir)


async def _extract_material(file: UploadFile | None, text: str | None, user_id: int, slug: str) -> str:
    if text is not None and text.strip():
        return text
    if file is None:
        raise HTTPException(status_code=400, detail="either 'file' or 'text' is required")

    uploads_dir = Path(__file__).resolve().parent.parent / "uploads" / "projects" / f"user_{user_id}"
    uploads_dir.mkdir(parents=True, exist_ok=True)
    dest = uploads_dir / f"{slug}_{file.filename or 'upload'}"
    with dest.open("wb") as f:
        f.write(file.file.read())

    if dest.suffix.lower() == ".pdf":
        try:
            extracted = await engines.pdf_input.run(content=str(dest))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"could not read PDF: {exc}") from exc
        return extracted["content"]

    try:
        return dest.read_text(encoding="utf-8", errors="replace")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"could not read file as text: {exc}") from exc


def _chunk_count(projects_dir: Path, slug: str) -> int:
    project_file = projects_dir / f"{slug}.json"
    if not project_file.exists():
        return 0
    try:
        return len(json.loads(project_file.read_text(encoding="utf-8"))["chunks"])
    except Exception:
        return 0


# --- Studio: generated documents (study guides, flashcards, etc.) over a
# project's material. Tracked in db.py's generated_artifacts table — see
# that table's doc comment for why this, unlike everything else the
# moderator's structured routes generate, gets real ownership tracking. ---


class GenerateStudioDoc(BaseModel):
    doc_type: str
    title: str | None = None


@router.post("/api/projects/{slug}/studio")
async def generate_studio_doc(
    slug: str, payload: GenerateStudioDoc, current_user: dict = Depends(security.get_current_user)
) -> dict:
    if payload.doc_type not in _DOC_TYPES:
        raise HTTPException(status_code=400, detail=f"doc_type must be one of {sorted(_DOC_TYPES)}")

    conn = db.get_connection()
    try:
        _get_project_row(conn, current_user["id"], slug)
    finally:
        conn.close()

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    index = engines.moderator._load_project_index(slug, projects_dir)
    if index is None or not index.get("chunks"):
        raise HTTPException(status_code=400, detail="this project has no material yet — add some in Sources first")

    title = payload.title or payload.doc_type.replace("_", " ").title()
    filename = f"{uuid.uuid4().hex}.pdf"
    dest = _user_generated_dir(current_user["id"]) / filename
    try:
        await engines.generate_docs.run(
            material=index["chunks"], doc_type=payload.doc_type, title=title, output_path=str(dest)
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"could not generate document: {exc}") from exc
    url_path = f"/generated/user_{current_user['id']}/{filename}"

    conn = db.get_connection()
    try:
        cursor = conn.execute(
            "INSERT INTO generated_artifacts (user_id, project_slug, doc_type, title, url_path, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (current_user["id"], slug, payload.doc_type, title, url_path, datetime.now(timezone.utc).isoformat()),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM generated_artifacts WHERE id = ?", (cursor.lastrowid,)).fetchone()
    finally:
        conn.close()
    return db.public_artifact(row)


@router.get("/api/projects/{slug}/studio")
async def list_studio_docs(slug: str, current_user: dict = Depends(security.get_current_user)) -> dict:
    conn = db.get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM generated_artifacts WHERE user_id = ? AND project_slug = ? ORDER BY created_at DESC",
            (current_user["id"], slug),
        ).fetchall()
    finally:
        conn.close()
    return {"artifacts": [db.public_artifact(row) for row in rows]}


@router.delete("/api/projects/{slug}/studio/{artifact_id}")
async def delete_studio_doc(
    slug: str, artifact_id: int, current_user: dict = Depends(security.get_current_user)
) -> dict:
    conn = db.get_connection()
    try:
        row = conn.execute(
            "SELECT * FROM generated_artifacts WHERE id = ? AND user_id = ? AND project_slug = ?",
            (artifact_id, current_user["id"], slug),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        conn.execute("DELETE FROM generated_artifacts WHERE id = ?", (artifact_id,))
        conn.commit()
    finally:
        conn.close()

    fs_path = _user_generated_dir(current_user["id"]) / Path(row["url_path"]).name
    fs_path.unlink(missing_ok=True)
    return {"deleted": artifact_id}
