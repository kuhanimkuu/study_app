"""Tests for the model_unavailable block (features/moderator/engine.py,
2026-09-18) — general-conversation replies have no non-LLM template
fallback (unlike math's _author_text -> _author_symbolic_text), so a
failed model call used to surface as the same generic "I'm not sure what
you'd like me to do with this" clarification text regardless of *why* it
failed — ambiguous input, the free local model being down, or the
user's own BYOK key being wrong all looked identical. Verifies the real
distinction now made:
  - a failed *local* call gets an actionable block suggesting BYOK
  - a failed *BYOK* call gets its own actual error message back (not a
    "switch to BYOK" suggestion, since BYOK is what just failed) instead
    of being silently swallowed
  - genuinely empty (not failed) generations still fall through to the
    original generic clarification — that path is unrelated to backend
    availability

Mocks the sibling engines directly (no HTTP/DB needed for this path) —
same "don't call the real LLM in a fast/deterministic unit test"
convention as test_moderator_explain.py's module docstring.

Run with: python -m pytest server/tests/test_moderator_model_unavailable.py -v
"""
from __future__ import annotations

import pytest

import features.moderator.engine as moderator_engine


async def _fake_intent_no_external(**kwargs: object) -> dict:
    return {"needs_external": False}


async def _fake_model_router_failure(**kwargs: object) -> dict:
    raise RuntimeError("simulated model failure")


async def _fake_model_router_empty_text(**kwargs: object) -> dict:
    return {"text": "", "tier": kwargs.get("tier", "tiny"), "backend": kwargs.get("backend", "local")}


@pytest.mark.asyncio
async def test_local_model_failure_returns_actionable_model_unavailable_block(monkeypatch):
    monkeypatch.setattr(moderator_engine._intent_analysis, "run", _fake_intent_no_external)
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model_router_failure)

    result = await moderator_engine.run(
        input_type="text",
        content="hey, how's it going?",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-model-unavailable-local",
    )

    assert result["blocks"] == [
        {
            "type": "model_unavailable",
            "message": "The free local AI model is currently unavailable.",
            "attempted_backend": "local",
            "suggested_backend": "deepseek",
            "suggested_model": "deepseek-chat",
        }
    ]


@pytest.mark.asyncio
async def test_byok_failure_surfaces_the_real_error_not_a_generic_message(monkeypatch):
    monkeypatch.setattr(moderator_engine._intent_analysis, "run", _fake_intent_no_external)
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model_router_failure)

    result = await moderator_engine.run(
        input_type="text",
        content="hey, how's it going?",
        model_config={"backend": "deepseek", "api_key": "bad-or-expired-key"},
        session_id="test-model-unavailable-byok",
    )

    assert result["blocks"] == [
        {
            "type": "model_unavailable",
            "message": "Your deepseek backend didn't respond: simulated model failure",
            "attempted_backend": "deepseek",
        }
    ]
    # Never recommends the same backend that just failed.
    assert "suggested_backend" not in result["blocks"][0]


@pytest.mark.asyncio
async def test_empty_but_successful_generation_still_falls_through_to_clarification(monkeypatch):
    """Unrelated to backend availability — the model answered, it just
    returned nothing. Should not be mistaken for a failure."""
    monkeypatch.setattr(moderator_engine._intent_analysis, "run", _fake_intent_no_external)
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model_router_empty_text)

    result = await moderator_engine.run(
        input_type="text",
        content="hey, how's it going?",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-model-unavailable-empty",
    )

    assert len(result["blocks"]) == 1
    assert result["blocks"][0]["type"] == "clarification"
