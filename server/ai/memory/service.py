"""Episodic memory creation — the one place `type="episodic"` rows get
written, called from the two real trigger points that produce them
(server/domains/assessment/router.py: misconception resolution, and a
genuine mastery-threshold crossing) rather than each call site building
its own Memory row inline."""
from __future__ import annotations

from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from .models import Memory


async def create_episodic_memory(db: AsyncSession, user_id: int, key: str, value: dict[str, Any]) -> Memory:
    """Confidence is always 1.0 here — these are real, observed events
    (a misconception resolving, mastery crossing a threshold), not
    probabilistic inferences about the student."""
    memory = Memory(user_id=user_id, type="episodic", key=key, value=value, source="system_derived", confidence=1.0)
    db.add(memory)
    await db.flush()
    return memory
