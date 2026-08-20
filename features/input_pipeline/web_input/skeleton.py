"""
Web input — accepts a URL / search query / YouTube link and fetches content.

Python structure + JSON contract for this feature.

INPUT (JSON) — what the input layer receives:
{
    "content": "https://example.com/article",
    "kind": "url"                # url | search | youtube
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "web",
    "content": "fetched text...",
    "source_url": "https://example.com/article"
}

Status: ⏳ later phase
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
