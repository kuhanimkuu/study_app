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

import asyncio
import json
import logging
import re
import uuid
import weakref
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ... import engines
from ...core import security
from ...db.session import async_session, get_db
from . import index_store
from .files_router import store_file
from .models import GeneratedArtifact, KnowledgeSpace, Material, ProjectIndex, StoredFile

logger = logging.getLogger(__name__)
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
        await index_store.ensure_index_file(db, current_user["id"], space.slug)
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
    # Stored files hang off the user, not the space (SET NULL on the
    # material/artifact side), so they'd outlive the project otherwise.
    file_ids = [
        *(await db.scalars(select(Material.file_id).where(Material.knowledge_space_id == space.id))).all(),
        *(await db.scalars(select(GeneratedArtifact.file_id).where(GeneratedArtifact.knowledge_space_id == space.id))).all(),
    ]
    await db.delete(space)
    file_ids = [f for f in file_ids if f is not None]
    if file_ids:
        await db.execute(delete(StoredFile).where(StoredFile.id.in_(file_ids)))
    await db.commit()

    projects_dir = engines.moderator._user_projects_dir(current_user["id"])
    (projects_dir / f"{slug}.json").unlink(missing_ok=True)
    return {"deleted": slug}


@router.get("/api/projects/{slug}/materials")
async def list_materials(
    slug: str,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Per-upload metadata (blueprint Section 12) — distinct from the
    aggregate `chunk_count` on GET /api/projects. Deliberately read-only:
    a material's chunks live merged into rag_projects' shared per-space
    JSON index (chunks+vectors appended together, not tagged by which
    upload they came from — see that engine's docstring), so there is no
    honest way to delete just one material's searchable content without
    re-architecting that storage. Deleting a material ROW here without
    also removing its chunks would be misleading (the UI would say it's
    gone while its content still answers searches), so no DELETE exists
    yet — a real, named gap, not an oversight."""
    space = await get_space_or_404(db, current_user["id"], slug)
    materials = (
        await db.scalars(
            select(Material).where(Material.knowledge_space_id == space.id).order_by(Material.created_at.desc())
        )
    ).all()
    return {"materials": [m.public() for m in materials]}


# Uploads are indexed in a background task since 2026-10-07. Indexing a PDF
# (text extraction + embedding every chunk) is minutes of CPU on Render's
# fractional-CPU free instance; done inside the request it blocked the
# server so completely that Render's health check got "connection reset"
# and the instance was restarted mid-upload. Tests set this to False
# (server/tests/conftest.py) so an upload is indexed by the time the
# request returns.
INDEX_IN_BACKGROUND = True

# Strong references to running jobs (asyncio only keeps weak ones), and one
# indexing job at a time per event loop — two concurrent uploads would
# otherwise double the embedding memory on a 512 MB instance.
_background_jobs: set[asyncio.Task] = set()
_index_locks: "weakref.WeakKeyDictionary[asyncio.AbstractEventLoop, asyncio.Lock]" = weakref.WeakKeyDictionary()


def _index_lock() -> asyncio.Lock:
    loop = asyncio.get_running_loop()
    lock = _index_locks.get(loop)
    if lock is None:
        lock = asyncio.Lock()
        _index_locks[loop] = lock
    return lock


@router.post("/api/projects/{slug}/material")
async def add_material(
    slug: str,
    file: UploadFile | None = File(None),
    text: str | None = Form(None),
    url: str | None = Form(None),
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Accepts `file` (.pdf or .txt), `text` (pasted), or `url` (a web page,
    fetched via the same web_input engine chat's "add a link" uses),
    records a Material row with status "indexing", and indexes it into
    this space via rag/projects in the background — poll GET .../materials
    for "indexed" / "failed" (with `error`)."""
    space = await get_space_or_404(db, current_user["id"], slug)
    filename, mime_type, material_text, pdf_path, source_url = await _receive_material(
        file, text, url, current_user["id"], slug
    )

    # Keep the original so it can be opened from Sources later (a web link
    # opens its source_url instead).
    stored = None
    if pdf_path is not None:
        stored = await store_file(db, current_user["id"], filename, mime_type, pdf_path.read_bytes())
    elif source_url is None and material_text is not None:
        stored = await store_file(db, current_user["id"], filename, "text/plain; charset=utf-8", material_text.encode("utf-8"))

    material = Material(
        knowledge_space_id=space.id, filename=filename, mime_type=mime_type,
        source_url=source_url, status="indexing", file_id=stored.id if stored else None,
    )
    db.add(material)
    await db.commit()
    await db.refresh(material)

    job = _index_material(material.id, space.id, current_user["id"], slug, material_text, pdf_path)
    if INDEX_IN_BACKGROUND:
        task = asyncio.create_task(job)
        _background_jobs.add(task)
        task.add_done_callback(_background_jobs.discard)
        return {"material": material.public(), "status": "indexing"}

    chunks = await job
    await db.refresh(material)
    if material.status == "failed":
        raise HTTPException(status_code=400, detail=material.error or "indexing failed")
    return {"material": material.public(), "status": material.status, "chunks": chunks}


async def _receive_material(
    file: UploadFile | None, text: str | None, url: str | None, user_id: int, slug: str
) -> tuple[str, str, str | None, Path | None, str | None]:
    """The fast part, done inside the request: returns (filename,
    mime_type, text, pdf_path, source_url) — exactly one of text/pdf_path
    is set. PDF text extraction is left to the background job."""
    if text is not None and text.strip():
        return "pasted_text.txt", "text/plain", text, None, None

    if url is not None and url.strip():
        try:
            fetched = await engines.web_input.run(content=url.strip())
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"could not fetch URL: {exc}") from exc
        return url.strip(), "text/html", fetched["content"], None, fetched["source_url"]

    if file is None:
        raise HTTPException(status_code=400, detail="one of 'file', 'text', or 'url' is required")

    uploads_dir = Path(__file__).resolve().parent.parent.parent / "uploads" / "projects" / f"user_{user_id}"
    uploads_dir.mkdir(parents=True, exist_ok=True)
    filename = file.filename or "upload"
    dest = uploads_dir / f"{slug}_{uuid.uuid4().hex[:8]}_{filename}"
    with dest.open("wb") as f:
        f.write(await file.read())

    if dest.suffix.lower() == ".pdf":
        return filename, "application/pdf", None, dest, None
    try:
        return filename, "text/plain", dest.read_text(encoding="utf-8", errors="replace"), None, None
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"could not read file as text: {exc}") from exc


def _run_engine_in_thread(engine_run, **kwargs) -> dict:
    """Engines are `async def` with synchronous bodies (pdf_input's
    extraction is pure CPU) — run one on its own loop in a worker thread so
    the server's event loop stays free."""
    return asyncio.run(engine_run(**kwargs))


async def _index_material(
    material_id: int, space_id: int, user_id: int, slug: str, text: str | None, pdf_path: Path | None
) -> int | None:
    """Extracts (for a PDF), indexes, saves the durable index copy, and
    marks the Material "indexed" or "failed". Never raises — a background
    task's exception would otherwise vanish. Returns the space's chunk
    count on success."""
    async with _index_lock():
        error: str | None = None
        chunks: int | None = None
        try:
            if pdf_path is not None:
                try:
                    extracted = await asyncio.to_thread(_run_engine_in_thread, engines.pdf_input.run, content=str(pdf_path))
                except Exception as exc:
                    raise ValueError(f"could not read PDF: {exc}") from exc
                text = extracted["content"]
            if not text or not text.strip():
                raise ValueError(
                    "no text found in this file — if it's a scanned PDF (photos of pages), "
                    "uploads can't read it yet; try a text-based PDF or paste the text"
                )
            # rag/projects APPENDS to the on-disk index — if a restart wiped
            # the file, it would start a fresh index holding only this
            # upload, and save_index() below would then overwrite the
            # durable copy with it, losing every earlier upload.
            async with async_session() as restore_db:
                await index_store.ensure_index_file(restore_db, user_id, slug)
            projects_dir = engines.moderator._user_projects_dir(user_id)
            chunk_start = _chunk_count(projects_dir, slug)
            result = await engines.rag_projects.run(project=slug, material=[text], projects_dir=projects_dir)
            chunks = result["chunks"]
        except Exception as exc:
            error = str(exc)[:1000]

        try:
            async with async_session() as db:
                material = await db.get(Material, material_id)
                if material is None:  # project deleted while indexing
                    return chunks
                if error is None:
                    await index_store.save_index(db, space_id, user_id, slug)
                material.status = "failed" if error else "indexed"
                material.error = error
                if error is None:
                    material.chunk_start = chunk_start
                    material.chunk_count = chunks - chunk_start
                await db.commit()
        except Exception:
            logger.exception("could not record indexing result for material %s", material_id)
        return chunks


@router.delete("/api/projects/{slug}/materials/{material_id}")
async def delete_material(
    slug: str,
    material_id: int,
    current_user: dict = Depends(security.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Removes an upload and exactly the index chunks it added (recorded as
    chunk_start/chunk_count when it was indexed) — no re-embedding; later
    uploads' slices shift down. Uploads from before that was recorded can
    only be removed when they're the space's only indexed material (then
    the whole index goes); otherwise their chunks can't be told apart from
    the others', and saying so beats deleting the wrong content."""
    space = await get_space_or_404(db, current_user["id"], slug)
    material = await db.scalar(
        select(Material).where(Material.id == material_id, Material.knowledge_space_id == space.id)
    )
    if material is None:
        raise HTTPException(status_code=404, detail="no such material in this project")
    if material.status == "indexing":
        raise HTTPException(status_code=409, detail="this file is still being indexed — try again once it's ready")

    async with _index_lock():
        if material.status == "indexed":
            await index_store.ensure_index_file(db, current_user["id"], slug)
            projects_dir = engines.moderator._user_projects_dir(current_user["id"])
            index_path = projects_dir / f"{slug}.json"
            others = (
                await db.scalars(
                    select(Material).where(
                        Material.knowledge_space_id == space.id, Material.status == "indexed", Material.id != material.id
                    )
                )
            ).all()
            if material.chunk_start is None:
                if others:
                    raise HTTPException(
                        status_code=409,
                        detail="this file was uploaded before individual files could be removed, so its content "
                        "can't be separated from the others' — delete and recreate the project to remove it",
                    )
                index_path.unlink(missing_ok=True)
                await db.execute(delete(ProjectIndex).where(ProjectIndex.knowledge_space_id == space.id))
            elif index_path.exists():
                index = json.loads(index_path.read_text(encoding="utf-8"))
                start, count = material.chunk_start, material.chunk_count or 0
                index["chunks"] = index["chunks"][:start] + index["chunks"][start + count:]
                index["vectors"] = index["vectors"][:start] + index["vectors"][start + count:]
                index_path.write_text(json.dumps(index), encoding="utf-8")
                for other in others:
                    if other.chunk_start is not None and other.chunk_start > start:
                        other.chunk_start -= count
                await index_store.save_index(db, space.id, current_user["id"], slug)

        file_id = material.file_id
        await db.delete(material)
        if file_id is not None:
            await db.execute(delete(StoredFile).where(StoredFile.id == file_id))
        await db.commit()
    return {"deleted": material_id}


async def mark_interrupted_indexing_failed() -> None:
    """Called at startup: a material still "indexing" means the process that
    was indexing it died (a restart, or running out of memory) — say so
    instead of leaving it spinning forever."""
    async with async_session() as db:
        await db.execute(
            update(Material)
            .where(Material.status == "indexing")
            .values(status="failed", error="indexing was interrupted by a server restart — please upload it again")
        )
        await db.commit()


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

    await index_store.ensure_index_file(db, current_user["id"], slug)
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

    stored = await store_file(db, current_user["id"], f"{title}.pdf", "application/pdf", dest.read_bytes())
    artifact = GeneratedArtifact(
        knowledge_space_id=space.id, doc_type=payload.doc_type, title=title, url_path=url_path,
        file_id=stored.id if stored else None,
    )
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
    file_id = artifact.file_id
    await db.delete(artifact)
    if file_id is not None:
        await db.execute(delete(StoredFile).where(StoredFile.id == file_id))
    await db.commit()

    fs_path.unlink(missing_ok=True)
    return {"deleted": artifact_id}
