"""Regression tests for the 2026-10-06 "make every feature actually work"
pass — each one a real bug found by driving /api/ask/text live:

  1. A `model_unavailable` block (the free model is down — e.g. on Render,
     which has no torch installed) wasn't in ModeratorResponse's block
     union, so FastAPI's response validation turned every such reply into
     a bare HTTP 500. test_moderator_model_unavailable.py only ever
     called moderator.run() directly, never through the response schema,
     which is how this slipped past it.
  2. "draw a diagram of the water cycle" went to the sympy plotter and
     failed with "Cannot convert expression to float" — now
     concept_diagram.
  3. "create flashcards on X" just chatted about flashcards — now a real
     flashcards route (table + PDF).
  4. "practice exam ... as a pdf" produced a study guide.
  5. "x^2" was parsed as bitwise XOR by every math engine.

Mocks _model_router.run directly — no real LLM call, same convention as
test_moderator_write_doc.py.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

import features.moderator.engine as moderator_engine
from server.ai.schemas.blocks import ModeratorResponse

_REPO = Path(__file__).resolve().parents[2]


def _fake_model(text: str, captured: dict | None = None):
    async def run(**kwargs: object) -> dict:
        if captured is not None:
            captured.update(kwargs)
        return {"text": text, "tier": "tiny", "backend": kwargs.get("backend", "local")}

    return run


def _cleanup_generated(blocks: list[dict]) -> None:
    for b in blocks:
        content = str(b.get("content", ""))
        if content.startswith("/generated/"):
            (moderator_engine._GENERATED_DIR / content.rsplit("/", 1)[-1]).unlink(missing_ok=True)


@pytest.mark.asyncio
async def test_model_unavailable_reply_passes_the_http_response_schema(monkeypatch):
    async def fail(**kwargs: object) -> dict:
        raise ModuleNotFoundError("No module named 'torch'")

    monkeypatch.setattr(moderator_engine._model_router, "run", fail)
    result = await moderator_engine.run(
        input_type="text",
        content="make me a pdf study guide on photosynthesis",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-mu-schema",
    )
    assert result["blocks"][0]["type"] == "model_unavailable"
    # The real assertion: this used to raise, which FastAPI reported as a 500.
    ModeratorResponse.model_validate(result)


@pytest.mark.parametrize(
    "content, detected, expected",
    [
        ("draw a diagram of the water cycle", ["text"], "concept_diagram"),
        ("make a flow chart of mitosis", ["text"], "concept_diagram"),
        ("label the parts of a plant cell", ["text"], "concept_diagram"),
        ("draw y = x^2", ["text"], "static_image"),
        ("draw sin(x)", ["text"], "static_image"),
        ("picture of 2x+1", ["text"], "static_image"),
        ("graph y=3x+2 as a pdf", [], "static_image"),
        ("create flashcards on the french revolution", ["text"], "flashcards"),
        ("make me 10 flashcards about mitosis as a pdf", ["text"], "flashcards"),
        ("give me a practice exam on cell biology as a pdf", ["text"], "write_doc"),
        ("make notes on photosynthesis as a pdf", ["text"], "write_doc"),
    ],
)
def test_infer_task_routes_visual_and_study_requests(content, detected, expected):
    assert moderator_engine._infer_task(content, detected) == expected


@pytest.mark.asyncio
async def test_concept_diagram_end_to_end_dedupes_and_closes_cycles(monkeypatch):
    reply = (
        "Sure! Here are the stages:\n"
        "1. Evaporation — water turns to vapour\n"
        "2. Condensation — vapour forms clouds\n"
        "3. Precipitation — water falls as rain\n"
        "4. Evaporation — repeated by the model\n"
        "5. Collection: water gathers in oceans\n"
    )
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model(reply))
    result = await moderator_engine.run(
        input_type="text",
        content="draw a diagram of the water cycle",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-diagram",
    )
    ModeratorResponse.model_validate(result)
    diagram = next(b for b in result["blocks"] if b["type"] == "diagram")
    labels = [e["label"] for e in diagram["elements"]]
    assert labels == ["Evaporation", "Condensation", "Precipitation", "Collection"]
    assert diagram["kind"] == "cycle"
    assert [3, 0] in diagram["relationships"]


@pytest.mark.asyncio
async def test_flashcards_end_to_end_returns_table_and_real_pdf(monkeypatch):
    # '&' and '<' on purpose — the flashcards PDF builder used to pass text
    # to reportlab unescaped, which aborts doc.build().
    reply = (
        "Q: What is the Estates-General? | A: France's assembly of clergy, nobles & commoners.\n"
        "Q: When did the Bastille fall?\nA: 14 July 1789\n"
        "Q: Bread prices < wages meant? | A: Widespread hunger.\n"
    )
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model(reply))
    result = await moderator_engine.run(
        input_type="text",
        content="create flashcards on the french revolution",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-flashcards",
    )
    try:
        ModeratorResponse.model_validate(result)
        types = [b["type"] for b in result["blocks"]]
        assert types == ["text", "table", "pdf"]
        table = result["blocks"][1]
        assert table["headers"] == ["Front", "Back"]
        assert table["rows"][1] == ["When did the Bastille fall?", "14 July 1789"]
        pdf = moderator_engine._GENERATED_DIR / result["blocks"][2]["content"].rsplit("/", 1)[-1]
        assert pdf.read_bytes().startswith(b"%PDF")
    finally:
        _cleanup_generated(result["blocks"])


@pytest.mark.asyncio
async def test_practice_exam_pdf_uses_the_exam_prompt(monkeypatch):
    captured: dict = {}
    reply = "# Cell Biology Exam\n## Questions\n- Q1. What organelle makes ATP?\n## Answer key\n- Q1. Mitochondria."
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model(reply, captured))
    result = await moderator_engine.run(
        input_type="text",
        content="give me a practice exam on cell biology as a pdf",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-exam",
    )
    try:
        assert "practice exam" in captured["prompt"].lower()
        assert result["blocks"][1]["doc_type"] == "practice_exam"
    finally:
        _cleanup_generated(result["blocks"])


@pytest.mark.parametrize(
    "path",
    [
        "features/math_engine/graphing/engine.py",
        "features/math_engine/numeric/engine.py",
        "features/math_engine/symbolic/engine.py",
        "features/ocr/math_ocr/engine.py",
    ],
)
def test_math_engines_read_caret_as_power(path):
    spec = importlib.util.spec_from_file_location(f"_caret_{Path(path).parent.name}", _REPO / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    import sympy

    parsed = sympy.parsing.sympy_parser.parse_expr("x^2", transformations=module._TRANSFORMATIONS)
    assert parsed == sympy.Symbol("x") ** 2


@pytest.mark.asyncio
async def test_flashcards_honour_a_requested_count(monkeypatch):
    captured: dict = {}
    reply = "\n".join(f"Q: question {i}? | A: answer {i}" for i in range(10))
    monkeypatch.setattr(moderator_engine._model_router, "run", _fake_model(reply, captured))
    result = await moderator_engine.run(
        input_type="text",
        content="make 4 flashcards on osmosis",
        model_config={"backend": "local", "tier": "tiny"},
        session_id="test-flashcards-count",
    )
    try:
        assert "exactly 4" in captured["prompt"]
        assert len(result["blocks"][1]["rows"]) == 4
    finally:
        _cleanup_generated(result["blocks"])
