"""
Graphing — generates plot data/points for an expression.

Python structure + JSON contract for this feature.

INPUT (JSON) — what this engine receives:
{
    "expression": "x**2",
    "range": [-5, 5]
}

OUTPUT (JSON) — what this engine returns:
{
    "points": {"x": [-5, -4, ...], "y": [25, 16, ...]},
    "latex": "y = x^2"
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
