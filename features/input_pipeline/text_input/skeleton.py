"""
Text input — accepts a typed string and normalizes it for the moderator.

Python structure + JSON contract for this feature.

INPUT (JSON) — what the input layer receives:
{
    "content": "2x + 3 = 7",   # the typed string
    "source": "text"            # origin: text
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "text",
    "content": "2x + 3 = 7"
}

Status: ✅ core v1
Note: JSON shapes are proposed, not final (see json.md).
"""
from __future__ import annotations

from typing import Any


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

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
