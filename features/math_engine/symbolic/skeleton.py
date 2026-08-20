"""
Symbolic math — arithmetic, algebra, calculus, differentiation, integration,
equations, matrices. Solves symbolically and returns steps.

Python structure + JSON contract for this feature.

INPUT (JSON) — what this engine receives:
{
    "expression": "2*x + 3 = 7",
    "variable": "x"
}

OUTPUT (JSON) — what this engine returns:
{
    "answer": "2",
    "latex": "x = 2",
    "steps": [
        "Subtract 3 from both sides: 2x = 4",
        "Divide both sides by 2: x = 2"
    ]
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
