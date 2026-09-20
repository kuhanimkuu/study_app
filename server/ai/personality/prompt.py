"""
Translates a PersonalityProfile into a natural-language style instruction
for the LLM prompt. Small, explicit per-dimension mapping functions, not
one opaque formatter — makes it obvious what each dimension actually does
to the prompt, and easy to adjust one dimension's wording without
touching the others.

Style ONLY — this must never be able to change WHAT gets taught, only HOW
(tone/verbosity/examples). See explain.py for where this is appended:
always AFTER the substance instructions (depth/misconception/memory), so
it can't override them — see this session's Phase 3 entries for why that
ordering is the whole point.
"""
from __future__ import annotations

from .models import PersonalityProfile

_TONE_PHRASES = {
    "friendly": "warm and friendly",
    "neutral": "even and neutral",
    "formal": "formal and professional",
    "playful": "upbeat and playful",
}

_FORMALITY_PHRASES = {
    "casual": "casual, conversational language",
    "neutral": "plain, everyday language",
    "formal": "formal, precise language",
}

_VERBOSITY_PHRASES = {
    "concise": "Keep it brief — 1-2 sentences, no elaboration.",
    "moderate": "Keep it to a few sentences — enough to explain clearly, no more.",
    "detailed": "Feel free to go into more depth and cover multiple angles.",
}

_TEACHING_STYLE_PHRASES = {
    "example_first": "Lead with a concrete example before any abstract explanation.",
    "theory_first": "Establish the general principle first, then illustrate it.",
    "socratic": "Where natural, prompt the student to reason toward the answer rather than stating it outright.",
    "story_driven": "Frame the explanation as a short narrative or scenario.",
}


def _bucket(value: float, low_phrase: str, mid_phrase: str, high_phrase: str) -> str:
    if value < 0.34:
        return low_phrase
    if value < 0.67:
        return mid_phrase
    return high_phrase


def build_style_instruction(profile: PersonalityProfile) -> str:
    tone = _TONE_PHRASES.get(profile.tone, profile.tone)
    formality = _FORMALITY_PHRASES.get(profile.formality, profile.formality)
    humor = _bucket(
        profile.humor,
        "Keep it fully serious, no humor.",
        "A touch of light humor is fine, but don't force it.",
        "Feel free to be genuinely playful and humorous.",
    )
    encouragement = _bucket(
        profile.encouragement,
        "Skip cheerleading — just explain.",
        "Include a brief note of encouragement.",
        "Be warmly encouraging throughout.",
    )
    directness = _bucket(
        profile.directness,
        "Ease into the point gently.",
        "Get to the point at a natural pace.",
        "Be direct — lead with the answer, then explain.",
    )
    challenge = _bucket(
        profile.challenge_level,
        "Keep this comfortably easy to follow, no extra difficulty.",
        "A moderate level of challenge is fine.",
        "Don't shy away from pushing the student a bit harder here.",
    )
    verbosity = _VERBOSITY_PHRASES.get(profile.verbosity, "")
    teaching_style = _TEACHING_STYLE_PHRASES.get(profile.teaching_style, "")

    return (
        f" Style: be {tone}, using {formality}. {humor} {encouragement} {directness} {challenge} "
        f"{verbosity} {teaching_style}"
    ).strip()
