"""
Project material — resolves a project reference ("my Fluid Mechanics project")
to the stored knowledge context for that project.

INPUT (JSON) — what the input layer receives:
{
    "content": "my Fluid Mechanics project",
    "project": "fluid_mechanics",    # resolved reference
    "projects_dir": "projects"       // optional, defaults to rag/projects' own default location
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "project",
    "content": "my Fluid Mechanics project",
    "project": "fluid_mechanics",
    "context": ["<chunks from the project's knowledge base>"]
}

Status: later phase
Reads the same project file rag/projects writes to (default
rag/projects/projects/<project>.json) — a shared datastore, not a shared
import, same convention as personalization/query_memory reading
personalization/memory_log's database. Resolving "my Fluid Mechanics
project" -> "fluid_mechanics" (the `project` field) is assumed to already
be done by the caller — that's a name-resolution/fuzzy-matching problem
this engine doesn't attempt; it only accepts the already-resolved slug.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_FEATURES_ROOT = Path(__file__).resolve().parent.parent.parent  # features/
DEFAULT_PROJECTS_DIR = _FEATURES_ROOT / "rag" / "projects" / "projects"


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

    Args (kwargs): {"content": str, "project": str, "projects_dir"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    content: str = kwargs["content"]
    project: str = kwargs["project"]
    projects_dir = Path(kwargs.get("projects_dir", DEFAULT_PROJECTS_DIR))

    project_file = projects_dir / f"{project}.json"
    if not project_file.exists():
        return {"input_type": "project", "content": content, "project": project, "context": []}

    index = json.loads(project_file.read_text(encoding="utf-8"))
    return {"input_type": "project", "content": content, "project": project, "context": index["chunks"]}


if __name__ == "__main__":
    import asyncio
    import shutil
    import sys

    async def demo() -> None:
        sys.path.insert(0, str(_FEATURES_ROOT / "rag" / "projects"))
        import engine as rag_projects  # sibling engine, loaded directly for this demo only

        demo_dir = _FEATURES_ROOT / "input_pipeline" / "project_material" / "projects_demo"
        shutil.rmtree(demo_dir, ignore_errors=True)

        await rag_projects.run(
            project="fluid_mechanics",
            material=["Bernoulli's principle relates pressure and velocity in a flowing fluid."],
            projects_dir=demo_dir,
        )

        result = await run(
            content="my Fluid Mechanics project", project="fluid_mechanics", projects_dir=demo_dir
        )
        print(result)

        shutil.rmtree(demo_dir, ignore_errors=True)

    asyncio.run(demo())
