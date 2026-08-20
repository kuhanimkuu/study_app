"""
Moderator — the "real brain" / chef. Understands intent, decides the output
format, picks the engines (tools), authors the explanation prose, assembles
the blocks, and manages state (pending context + memory log).

Python structure + JSON contract for this feature.

INPUT (JSON) — what the moderator receives from the input engine:
{
    "input_type": "text",
    "content": "2x + 3 = 7",
    "task": "solve",
    "requested_format": null
}

OUTPUT (JSON) — what the moderator returns (the response):
{
    "blocks": [
        {"type": "text",     "content": "Here's how...", "source": "moderator"},
        {"type": "equation", "latex": "x = 2",          "source": "math_engine"}
    ]
}

Status: ⏳ later phase (rule-based stub first, LLM later)
Note: JSON shapes are proposed, not final (see json.md).
"""
from __future__ import annotations

from typing import Any


async def run(**kwargs: Any) -> dict:
    """Sole entry point the app calls.

    The moderator is itself an orchestrator coroutine (PATHWAY.md §0): it
    calls engines, may wait on dependent results, and assembles the response.

    Args (kwargs): keys match INPUT above.
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    raise NotImplementedError(f"{__name__}: implement in engine.py")


# --- private helpers (add as needed) ---
# decide_format(), pick_engines(), author_explanation(), assemble_blocks()


if __name__ == "__main__":
    import asyncio

    print(f"[{__name__}] TODO — feed sample INPUT, print OUTPUT.")
