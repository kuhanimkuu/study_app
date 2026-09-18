"""Tests for the write_doc route (features/moderator/engine.py, 2026-09-18)
and the clarification-loop fix it shipped alongside.

Three real bugs, found via live testing with real input, covered here:
  1. "make me a PDF guide" used to crash — _infer_task routed ANY message
     containing "pdf" to static_image (graph-a-math-expression-to-PDF),
     so a whole sentence with no math expression at all got handed to
     sympy as an "expression" and failed with a syntax error. write_doc
     is the actual free-text "author a document" route _infer_task should
     have picked instead.
  2. Once a clarification was asked, every later message in that session
     got treated as a reply to it forever, even a genuinely new question —
     see the loop-fix test below for the exact repro.
  3. (Covered in test_moderator_model_unavailable.py, not here) DeepSeek's
     reasoner model returns empty replies at this app's token budgets.

Mocks _model_router.run directly — no real LLM call, same convention as
test_moderator_explain.py / test_moderator_model_unavailable.py.

Run with: python -m pytest server/tests/test_moderator_write_doc.py -v
"""
from __future__ import annotations

import pytest

import features.moderator.engine as moderator_engine


async def _fake_intent_no_external(**kwargs: object) -> dict:
    return {"needs_external": False}


@pytest.mark.parametrize(
    "content, detected, expected_task",
    [
        (
            "Give me sort of overview of thermodynamics something that can act as a guide, "
            "submit it in pdf form",
            [],
            "write_doc",
        ),
        (
            "make a pdf study guide on the first law, including dU = Q - W",
            [],
            "write_doc",
        ),
        (
            "pdf notes on integration by parts",
            ["math"],
            "write_doc",
        ),
        (
            "graph y=3x+2 as a pdf",
            [],
            "static_image",
        ),
        (
            "generate a pdf of sin(x)",
            ["math"],
            "static_image",
        ),
    ],
)
def test_infer_task_disambiguates_pdf_requests(content, detected, expected_task):
    assert moderator_engine._infer_task(content, detected) == expected_task


@pytest.mark.asyncio
async def test_write_doc_end_to_end_produces_a_real_pdf(monkeypatch):
    # Deliberately includes '<', '>', and '&' — reportlab's Paragraph
    # parses its input as markup, so unescaped XML special characters
    # break doc.build() outright rather than just rendering oddly.
    fake_guide = (
        "# Thermodynamics Study Guide\n"
        "## First Law\n"
        "- Energy is conserved: dU = Q - W\n"
        "- Ideal gas behavior assumes T < 0 is impossible & pressure P > 0 always holds\n"
        "## Key formulas\n"
        "- PV = nRT\n"
        "## Common mistakes\n"
        "- Confusing heat and work\n"
    )
    captured_kwargs: dict = {}

    async def fake_model_router_run(**kwargs: object) -> dict:
        captured_kwargs.update(kwargs)
        return {"text": fake_guide, "tier": kwargs.get("tier", "tiny"), "backend": kwargs.get("backend", "local")}

    monkeypatch.setattr(moderator_engine._model_router, "run", fake_model_router_run)

    result = await moderator_engine.run(
        input_type="text",
        content="Give me a pdf study guide on thermodynamics",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-write-doc-e2e",
    )

    assert [b["type"] for b in result["blocks"]] == ["text", "pdf"]
    assert captured_kwargs["max_tokens"] >= 1000

    pdf_url = result["blocks"][1]["content"]
    filename = pdf_url.rsplit("/", 1)[-1]
    pdf_path = moderator_engine._GENERATED_DIR / filename
    try:
        assert pdf_path.exists()
        assert pdf_path.read_bytes().startswith(b"%PDF")
    finally:
        pdf_path.unlink(missing_ok=True)


@pytest.mark.asyncio
async def test_write_doc_byok_failure_returns_model_unavailable_with_real_error(monkeypatch):
    async def fake_model_router_failure(**kwargs: object) -> dict:
        raise RuntimeError("simulated deepseek failure")

    monkeypatch.setattr(moderator_engine._model_router, "run", fake_model_router_failure)

    result = await moderator_engine.run(
        input_type="text",
        content="Give me a pdf study guide on thermodynamics",
        model_config={"backend": "deepseek", "api_key": "bad-key"},
        session_id="test-write-doc-byok-fail",
    )

    assert result["blocks"][0]["type"] == "model_unavailable"
    assert "simulated deepseek failure" in result["blocks"][0]["message"]
    assert "suggested_backend" not in result["blocks"][0]


@pytest.mark.asyncio
async def test_clarification_loop_does_not_get_stuck_on_a_new_unrelated_question(monkeypatch):
    """Repro of the real bug: a clarification's session used to answer
    EVERY later message with the exact same clarification, because the
    old code always resumed the pending context (overwriting the new
    message's content with the old, already-failed content) regardless
    of whether the reply actually matched a known follow-up keyword."""
    monkeypatch.setattr(moderator_engine._intent_analysis, "run", _fake_intent_no_external)

    call_log: list[dict] = []

    async def fake_model_router_sequence(**kwargs: object) -> dict:
        call_log.append(dict(kwargs))
        if len(call_log) == 1:
            # First call: empty reply -> _author_general_reply returns
            # None -> the caller falls through to a genuine clarification
            # (not a failure — this exercises the ambiguous-input path,
            # not ModelUnavailable).
            return {"text": "", "tier": kwargs.get("tier", "tiny"), "backend": kwargs.get("backend", "local")}
        return {
            "text": "Entropy is a measure of disorder in a system.",
            "tier": kwargs.get("tier", "tiny"),
            "backend": kwargs.get("backend", "local"),
        }

    monkeypatch.setattr(moderator_engine._model_router, "run", fake_model_router_sequence)

    session_id = "test-clarification-loop"
    first_message = "asdlkfj this is some rambling first message"
    first = await moderator_engine.run(
        input_type="text",
        content=first_message,
        model_config={"backend": "local", "tier": "tiny"},
        session_id=session_id,
    )
    assert first["blocks"][0]["type"] == "clarification"

    second = await moderator_engine.run(
        input_type="text",
        content="What is entropy",
        model_config={"backend": "local", "tier": "tiny"},
        session_id=session_id,
    )

    assert second["blocks"][0]["type"] == "text"
    assert len(call_log) == 2
    second_prompt = call_log[1]["prompt"]
    assert "What is entropy" in second_prompt
    assert first_message not in second_prompt
