"""
Model router — routes a task to the right model tier.

Tiers:
  - Tiny model  (~0.3–0.6B): classification, routing, extraction
  - Main model  (~1–2B):      tutoring, Q&A, summaries, authors explanations
  - Specialized:              OCR, vision, speech, embeddings

Python structure + JSON contract for this feature.

INPUT (JSON) — what this engine receives:
{
    "task": "classify_intent",
    "text": "2x + 3 = 7"
}

OUTPUT (JSON) — what this engine returns:
{
    "model": "tiny",
    "reason": "classification task"
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
