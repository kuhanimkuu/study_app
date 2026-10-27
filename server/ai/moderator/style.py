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

# --- answer lengths, in tokens: the one place to tune them (2026-10-27) ---
# Raised from 70/220/400, which were set for a tiny local model and left a
# hosted one (DeepSeek) no room for a worked example. Longer answers cost
# more: check `python -m server.scripts.teacher_eval` and the token meter
# before changing these.
VERBOSITY_MAX_TOKENS = {"concise": 300, "moderate": 900, "detailed": 1500}
# Chat answers follow the student's depth choice (the app's quick / full /
# exam-level switch), scaled by their verbosity setting.
DEPTH_MAX_TOKENS = {"quick": 350, "full": 1000, "exam": 1600}
_VERBOSITY_SCALE = {"concise": 0.7, "moderate": 1.0, "detailed": 1.4}
LESSON_MAX_TOKENS = 5000


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


def answer_max_tokens(personality: PersonalityProfile, depth: str = "full") -> int:
    """The length cap for a chat answer at this depth."""
    base = DEPTH_MAX_TOKENS.get(depth, DEPTH_MAX_TOKENS["full"])
    return int(base * _VERBOSITY_SCALE.get(personality.verbosity, 1.0))


def verbosity_max_tokens(personality: PersonalityProfile, default: int = 900) -> int:
    """See explain.py's history for why this is mechanical (max_tokens),
    not just a prompt instruction: the real local model didn't reliably
    self-terminate early even when told to be concise."""
    return VERBOSITY_MAX_TOKENS.get(personality.verbosity, default)
