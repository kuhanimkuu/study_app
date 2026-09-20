"""
Shared "adaptive style" building blocks — personality + explicit memory,
both user/account-scoped (apply to *any* explanation, not one specific
Concept — unlike mastery-based depth or misconception-awareness, which
stay local to explain.py since they need a specific concept to make
sense). Extracted from explain.py so both `/explain` and ordinary chat
(`features/moderator/engine.py`, via `server/routers/ask.py`) share one
implementation instead of two copies that can drift apart.
"""
from __future__ import annotations

from ..personality.models import PersonalityProfile
from ..personality.prompt import build_style_instruction

VERBOSITY_MAX_TOKENS = {"concise": 70, "moderate": 220, "detailed": 400}


def build_adaptive_style_note(personality: PersonalityProfile, memories: list[dict]) -> str:
    """A trailing prompt fragment. Callers must append this AFTER any
    substance instructions (what must be taught, correctness) — it can
    only change HOW something is said, never WHAT, and placement is what
    enforces that, not anything in this function itself."""
    memory_note = (
        " The student has told you the following about themselves — follow it: "
        + "; ".join(f"{m['key']}: {m['value']}" for m in memories)
        + "."
        if memories
        else ""
    )
    return f"{memory_note}{build_style_instruction(personality)}"


def verbosity_max_tokens(personality: PersonalityProfile, default: int = 220) -> int:
    """See explain.py's history for why this is mechanical (max_tokens),
    not just a prompt instruction: the real local model didn't reliably
    self-terminate early even when told to be concise."""
    return VERBOSITY_MAX_TOKENS.get(personality.verbosity, default)
