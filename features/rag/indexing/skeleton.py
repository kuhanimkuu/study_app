"""
Indexing (chunking + embedding + vector index) — turns documents into a
searchable index for local RAG.

Python structure + JSON contract for this feature.

INPUT (JSON) — what this engine receives:
{
    "documents": ["<text chunk 1>", "<text chunk 2>"]
}

OUTPUT (JSON) — what this engine returns:
{
    "index": "<vector index reference>",
    "chunks": 1200
}

Status: ⏳ later phase
Note: JSON shapes are proposed, not final (see json.md).
"""
from __future__ import annotations

from typing import Any


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Engines are resumable coroutines (PATHWAY.md §0): they may pause/yield
    and resume, so the scheduler can interleave them.

    Args (kwargs): keys match INPUT above.
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    raise NotImplementedError(f"{__name__}: implement in engine.py")


# --- private helpers (add as needed) ---


if __name__ == "__main__":
    import asyncio

    print(f"[{__name__}] TODO — feed sample INPUT, print OUTPUT.")
