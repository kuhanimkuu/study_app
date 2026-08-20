"""
PDF processing — extracts everything useful from a PDF into structured form.

Python structure + JSON contract for this feature.

INPUT (JSON) — what this engine receives:
{
    "pdf": "<pdf path / reference>"
}

OUTPUT (JSON) — what this engine returns:
{
    "metadata": {"title": "...", "author": "..."},
    "text": "full extracted text...",
    "pages": [{"number": 1, "text": "..."}],
    "tables": [],
    "equations": []
}

Status: ✅ core v1
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
