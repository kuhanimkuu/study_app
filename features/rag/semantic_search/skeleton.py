"""
Semantic search — finds the most relevant chunks for a query over the index.

Python structure + JSON contract for this feature.

INPUT (JSON) — what this engine receives:
{
    "index": "<vector index reference>",
    "query": "what is entropy?",
    "top_k": 5
}

OUTPUT (JSON) — what this engine returns:
{
    "results": [
        {"chunk": "<text>", "score": 0.91},
        {"chunk": "<text>", "score": 0.87}
    ]
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
