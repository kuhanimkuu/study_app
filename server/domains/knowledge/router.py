"""
/api/projects — Knowledge Space management: create, list, delete, add
material, and Studio document generation. Same URL paths, request/response
shapes as the old server/routers/projects.py (the "project" vocabulary
stays in the URLs/JSON for Flutter compatibility; internally this is now
the Knowledge Space domain — see models.py). Only the identity/metadata
storage moved to Postgres; material chunk storage/search still goes
through the existing features/rag/projects + features/rag/semantic_search
engines (JSON file per space) — deliberately not migrated this pass, see
STUDY_OS_PROGRESS.md, 2026-09-14.

Reuses `engines.moderator._user_projects_dir()` (rather than recomputing
the per-user storage path here) specifically so the directory a space's
material gets written to and the directory a query reads from can never
drift apart — same reasoning as the file this replaces.
"""
from __future__ import annotations

import json
import re
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ... import engines
from ...core import security
from ...db.session import get_db
from .models import GeneratedArtifact, KnowledgeSpace, Material

router = APIRouter()

_SLUG_RE = re.compile(r"[^a-z0-9]+")

# document_generation/generate_docs' real, honestly-documented doc types —
# see that engine's module docstring for exactly what each one does.
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

_GENERATED_ROOT = Path(__file__).resolve().parent.parent.parent.parent / "features" / "moderator" / "generated"


def _user_generated_dir(user_id: int) -> Path:
    d = _GENERATED_ROOT / f"user_{user_id}"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _slugify(name: str) -> str:
    slug = _SLUG_RE.sub("_", name.strip().lower()).strip("_")
    if not slug:
        raise HTTPException(status_code=400, detail="project name must contain at least one letter or number")
    return slug


async def get_space_or_404(db: AsyncSession, user_id: int, slug: str) -> KnowledgeSpace:
    space = await db.scalar(
        select(KnowledgeSpace).where(KnowledgeSpace.user_id == user_id, KnowledgeSpace.slug == slug)
    )
    if space is None:
        raise HTTPException(status_code=404, detail=f"no project named {slug!r}")
    return space


class CreateProject(BaseModel):
    display_name: str


@router.post("/api/projects")
async def create_project(
    payload: CreateProject,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    slug = _slugify(payload.display_name)
    existing = await db.scalar(
        select(KnowledgeSpace).where(KnowledgeSpace.user_id == current_user["id"], KnowledgeSpace.slug == slug)
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail=f"you already have a project named {slug!r}")

    space = KnowledgeSpace(user_id=current_user["id"], slug=slug, display_name=payload.display_name)
    db.add(space)
    await db.commit()
    await db.refresh(space)
    return space.public()


@router.get("/api/projects")
async def list_projects(
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    spaces = (
        await db.scalars(
            select(KnowledgeSpace)
            .where(KnowledgeSpace.user_id == current_user["id"])
            .order_by(KnowledgeSpace.created_at.desc())
        )
    ).all()

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    projects = []
    for space in spaces:
        project = space.public()
        project["chunk_count"] = _chunk_count(projects_dir, space.slug)
        projects.append(project)
    return {"projects": projects}


@router.delete("/api/projects/{slug}")
async def delete_project(
    slug: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    await db.delete(space)
    await db.commit()

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    (projects_dir / f"{slug}.json").unlink(missing_ok=True)
    return {"deleted": slug}


@router.post("/api/projects/{slug}/material")
async def add_material(
    slug: str,
    file: UploadFile | None = File(None),
    text: str | None = Form(None),
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Extracts text from whichever of `file` (.pdf or .txt) or `text`
    (pasted text) was sent, indexes it into this space via rag/projects
    (JSON file, unchanged), and records a Material metadata row in
    Postgres — new: the old version tracked zero metadata per upload."""
    space = await get_space_or_404(db, current_user["id"], slug)

    filename, mime_type, material_text = await _extract_material(file, text, current_user["id"], slug)
    if not material_text.strip():
        raise HTTPException(status_code=400, detail="no text content found in the upload")

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    result = await engines.rag_projects.run(project=slug, material=[material_text], projects_dir=projects_dir)

    db.add(Material(knowledge_space_id=space.id, filename=filename, mime_type=mime_type))
    await db.commit()

    return result


async def _extract_material(
    file: UploadFile | None, text: str | None, user_id: int, slug: str
) -> tuple[str, str, str]:
    """Returns (filename, mime_type, extracted_text)."""
    if text is not None and text.strip():
        return "pasted_text.txt", "text/plain", text
    if file is None:
        raise HTTPException(status_code=400, detail="either 'file' or 'text' is required")

    uploads_dir = Path(__file__).resolve().parent.parent.parent / "uploads" / "projects" / f"user_{user_id}"
    uploads_dir.mkdir(parents=True, exist_ok=True)
    filename = file.filename or "upload"
    dest = uploads_dir / f"{slug}_{filename}"
    with dest.open("wb") as f:
        f.write(file.file.read())

    if dest.suffix.lower() == ".pdf":
        try:
            extracted = await engines.pdf_input.run(content=str(dest))
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"could not read PDF: {exc}") from exc
        return filename, "application/pdf", extracted["content"]

    try:
        return filename, "text/plain", dest.read_text(encoding="utf-8", errors="replace")
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
# space's material. Tracked in the generated_artifacts table — see
# models.py's GeneratedArtifact for why this, unlike everything else the
# moderator's structured routes generate, gets real ownership tracking. ---


class GenerateStudioDoc(BaseModel):
    doc_type: str
    title: str | None = None


@router.post("/api/projects/{slug}/studio")
async def generate_studio_doc(
    slug: str,
    payload: GenerateStudioDoc,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    if payload.doc_type not in _DOC_TYPES:
        raise HTTPException(status_code=400, detail=f"doc_type must be one of {sorted(_DOC_TYPES)}")

    space = await get_space_or_404(db, current_user["id"], slug)

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

    artifact = GeneratedArtifact(knowledge_space_id=space.id, doc_type=payload.doc_type, title=title, url_path=url_path)
    db.add(artifact)
    await db.commit()
    await db.refresh(artifact)
    return artifact.public()


@router.get("/api/projects/{slug}/studio")
async def list_studio_docs(
    slug: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    artifacts = (
        await db.scalars(
            select(GeneratedArtifact)
            .where(GeneratedArtifact.knowledge_space_id == space.id)
            .order_by(GeneratedArtifact.created_at.desc())
        )
    ).all()
    return {"artifacts": [a.public() for a in artifacts]}


@router.delete("/api/projects/{slug}/studio/{artifact_id}")
async def delete_studio_doc(
    slug: str,
    artifact_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    space = await get_space_or_404(db, current_user["id"], slug)
    artifact = await db.scalar(
        select(GeneratedArtifact).where(
            GeneratedArtifact.id == artifact_id, GeneratedArtifact.knowledge_space_id == space.id
        )
    )
    if artifact is None:
        raise HTTPException(status_code=404, detail="artifact not found")

    fs_path = _user_generated_dir(current_user["id"]) / Path(artifact.url_path).name
    await db.delete(artifact)
    await db.commit()

    fs_path.unlink(missing_ok=True)
    return {"deleted": artifact_id}
