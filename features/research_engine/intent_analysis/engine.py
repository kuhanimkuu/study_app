"""
Intent analysis — decides whether a query needs external (internet) info.

INPUT (JSON) — what this engine receives:
{
    "query": "latest research on quantum computing"
}

OUTPUT (JSON) — what this engine returns:
{
    "needs_external": true,
    "reason": "asks for recent/current information"
}

Status: later phase
Rule-based (regex/keyword matching), same honesty level as the moderator's
own intent inference — no LLM in this phase, and this is a genuinely hard
problem to solve perfectly with keyword rules (telling "explain entropy"
apart from "explain the current administration's energy policy" needs real
understanding of whether the material is timeless vs. time-sensitive/
external). This gets the obvious cases right and is upfront about the rest.
"""
from __future__ import annotations

import re
from typing import Any

_RECENCY_RE = re.compile(
    r"\b(latest|recent(ly)?|current(ly)?|this (year|week|month)|news|202\d)\b",
    re.IGNORECASE,
)
_EXTERNAL_ENTITY_RE = re.compile(
    r"\b(who is|what happened|stock price|weather|score|election|released|announced)\b",
    re.IGNORECASE,
)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"query": str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    query: str = kwargs["query"]

    if _RECENCY_RE.search(query):
        return {"needs_external": True, "reason": "asks for recent/current information"}
    if _EXTERNAL_ENTITY_RE.search(query):
        return {"needs_external": True, "reason": "asks about a real-world event/entity, not timeless material"}
    return {"needs_external": False, "reason": "no recency or external-event signal found; likely answerable from provided material or general knowledge"}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        for query in [
            "latest research on quantum computing",
            "explain the second law of thermodynamics",
            "what happened in the 2024 election",
            "solve 2x + 3 = 7",
        ]:
            result = await run(query=query)
            print(f"{query!r} -> {result}")

    asyncio.run(demo())
