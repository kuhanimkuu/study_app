"""
Depth decision (pure, no LLM) + explanation generation (LLM, with a
fallback) for a single Concept, adapted to a StudentState snapshot.

`generate_explanation` mirrors `features/moderator/engine.py`'s
`_author_text()` shape deliberately: build a prompt around real computed
facts, call model_router, fall back to a plain templated message if the
call fails for any reason — not a hard error. That's the right shape here
(unlike last slice's short-answer *grading*, where no safe fallback exists
for judging correctness): an explanation can honestly degrade to the
concept's own stored description rather than block the student entirely.
"""
from __future__ import annotations

from ... import engines
from ...domains.learning.models import Concept
from .student_state import StudentState
from .style import build_adaptive_style_note, verbosity_max_tokens

_LOW_MASTERY_THRESHOLD = 0.3
_HIGH_MASTERY_THRESHOLD = 0.7


def decide_depth(state: StudentState) -> str:
    """An active misconception forces "reinforcement" regardless of
    mastery — correcting it is the honest priority, not advancing past it
    just because the raw mastery number looks fine."""
    if state.has_active_misconception:
        return "reinforcement"
    if state.attempts == 0 or state.mastery < _LOW_MASTERY_THRESHOLD:
        return "introductory"
    if state.mastery <= _HIGH_MASTERY_THRESHOLD:
        return "reinforcement"
    return "advanced"


_DEPTH_INSTRUCTIONS = {
    "introductory": (
        "The student has not yet mastered this concept. Explain it from first "
        "principles, in plain language, with a concrete example. Avoid jargon "
        "unless you define it."
    ),
    "reinforcement": (
        "The student has partial understanding of this concept. Reinforce the "
        "core idea, address common mix-ups directly, and check understanding "
        "with a clarifying point."
    ),
    "advanced": (
        "The student has strong mastery of this concept already. Go beyond the "
        "basics: mention a nuance, edge case, or connection to a related idea "
        "rather than re-explaining fundamentals they already know."
    ),
}


async def generate_explanation(
    concept: Concept, state: StudentState, depth: str, model_config: dict
) -> tuple[str, str]:
    """Returns (explanation_text, reasoning)."""
    reasoning_bits = [f"mastery={state.mastery}", f"attempts={state.attempts}"]
    if state.has_active_misconception:
        reasoning_bits.append("active misconception detected")
    if state.relevant_memories:
        reasoning_bits.append(f"{len(state.relevant_memories)} stated preference(s) applied")
    reasoning_bits.append(f"personality: tone={state.personality.tone}, verbosity={state.personality.verbosity}")
    reasoning = f"depth={depth} ({', '.join(reasoning_bits)})"

    misconception_note = (
        " The student has recently and repeatedly gotten this wrong; specifically address: "
        f"{'; '.join(state.misconception_notes)}."
        if state.has_active_misconception
        else ""
    )
    # Adaptive (personality + memory) note comes LAST, after every
    # substance instruction above — it can change HOW this is said
    # (tone/verbosity/examples, including length), never WHAT gets said.
    # See style.py for why this is shared with ordinary chat now too.
    adaptive_note = build_adaptive_style_note(state.personality, state.relevant_memories)
    prompt = (
        f"You are a tutor explaining the concept '{concept.name}' to a student. "
        f"{_DEPTH_INSTRUCTIONS[depth]}{misconception_note}{adaptive_note}"
    )
    max_tokens = verbosity_max_tokens(state.personality)
    try:
        result = await engines.model_router.run(prompt=prompt, max_tokens=max_tokens, **model_config)
        text = result["text"].strip()
        if text:
            return text, reasoning
    except Exception:
        pass
    return _fallback_explanation(concept), reasoning


def _fallback_explanation(concept: Concept) -> str:
    if concept.description:
        return f"{concept.name}: {concept.description}"
    return f"{concept.name} — no stored description, and the explanation model is unavailable right now."
