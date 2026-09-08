"""
Projects — organizes material into a named project (Thermodynamics,
Fluid Mechanics, ...) as a structured, persistent knowledge base.

INPUT (JSON) — what this engine receives:
{
    "project": "thermodynamics",
    "material": ["<raw document text 1>", "<raw document text 2>"],
    "projects_dir": "projects"   // optional, defaults to a "projects" folder next to this engine.py
}

OUTPUT (JSON) — what this engine returns:
{
    "project": "thermodynamics",
    "status": "created" | "updated",
    "chunks": 340
}

Status: later phase
Composes rag/indexing (chunk + embed) rather than reimplementing it, loaded
via importlib file-path loading (same pattern as document_engine/
searchable_knowledge, input_pipeline/pdf_input, moderator). New material is
indexed and *appended* to the project's existing index, persisted to a JSON
file per project — so re-running the server doesn't lose prior indexing
work, and a project accumulates material across multiple calls.

This engine only manages storage/updates. To search within a project, load
its persisted index file (same shape rag/indexing itself returns) and pass
it straight to rag/semantic_search's "index" input — no separate search
function is needed here.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/
DEFAULT_PROJECTS_DIR = _HERE / "projects"


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "rag_projects_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_rag_indexing = _load_sibling_engine("rag/indexing/engine.py")


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"project": str, "material": list[str], "projects_dir"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    project: str = kwargs["project"]
    material: list[str] = kwargs["material"]
    projects_dir = Path(kwargs.get("projects_dir", DEFAULT_PROJECTS_DIR))
    projects_dir.mkdir(parents=True, exist_ok=True)

    project_file = projects_dir / f"{project}.json"
    existing = _load_project(project_file)
    status = "updated" if existing is not None else "created"

    new_result = await _rag_indexing.run(documents=material)
    new_index = new_result["index"]

    if existing is None:
        merged = new_index
    else:
        merged = {
            "chunks": existing["chunks"] + new_index["chunks"],
            "vectors": existing["vectors"] + new_index["vectors"],
            "model": new_index["model"],
        }

    project_file.write_text(json.dumps(merged), encoding="utf-8")

    return {"project": project, "status": status, "chunks": len(merged["chunks"])}


# --- private helpers ---


def _load_project(project_file: Path) -> dict | None:
    if not project_file.exists():
        return None
    return json.loads(project_file.read_text(encoding="utf-8"))


if __name__ == "__main__":
    import asyncio
    import shutil

    async def demo() -> None:
        demo_dir = _HERE / "projects_demo"
        shutil.rmtree(demo_dir, ignore_errors=True)

        first = await run(
            project="thermodynamics",
            material=["Entropy is a measure of disorder in a thermodynamic system."],
            projects_dir=demo_dir,
        )
        print("after 1st material batch:", first)

        second = await run(
            project="thermodynamics",
            material=["The second law of thermodynamics states entropy never decreases in an isolated system."],
            projects_dir=demo_dir,
        )
        print("after 2nd material batch (should accumulate):", second)

        shutil.rmtree(demo_dir, ignore_errors=True)

    asyncio.run(demo())
