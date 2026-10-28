"""The document template system (2026-10-28): every doc_type renders a
real, designed PDF from the AI's JSON, maths is typeset instead of
printed as LaTeX source, and replies that aren't clean JSON still work.

Reads every PDF back with PyMuPDF rather than trusting "a file exists".

Run with: python -m pytest server/tests/test_document_templates.py -v
"""
from __future__ import annotations

import fitz
import pytest

from server import engines
import features.moderator.engine as moderator_engine

gd = engines.generate_docs

# Bare backslashes on purpose: models often forget to escape LaTeX for
# JSON, and json.loads alone would read "\frac" as a form feed + "rac".
_REPLY = r"""Here you go:
```json
{"title": "Kinematics", "subtitle": "Motion in a straight line",
 "intro": "How things move.", "objectives": ["Use the SUVAT equations"],
 "sections": [{"heading": "Velocity", "blocks": [
   {"type": "paragraph", "text": "Velocity is $v = \frac{ds}{dt}$ & speed < 300."},
   {"type": "definition", "term": "Displacement", "text": "Distance in a direction"},
   {"type": "formula", "label": "SUVAT", "latex": "s = ut + \frac{1}{2}at^2", "note": "where $\theta$ is unused"},
   {"type": "warning", "text": "Pick a positive direction first."},
   {"type": "table", "header": ["Symbol", "Unit"], "rows": [["s", "m"], ["", ""]]},
   {"type": "question", "text": "Which is a vector?", "options": ["Speed", "Velocity", "Time", "Mass"], "marks": 1},
   {"type": "card", "front": "Unit of velocity?", "back": "m/s"},
   {"type": "blank", "label": "Your hypothesis", "lines": 2}
 ]}],
 "answers": [{"q": 1, "answer": "Velocity", "explanation": "It has a direction."}]}
```"""


def _pdf_text(path) -> str:
    with fitz.open(path) as doc:
        return "\n".join(page.get_text() for page in doc)


def test_parse_spec_survives_fences_and_unescaped_latex():
    spec = gd.parse_spec(_REPLY)
    assert spec is not None
    paragraph = spec["sections"][0]["blocks"][0]["text"]
    assert r"\frac{ds}{dt}" in paragraph
    assert "\x0c" not in paragraph
    assert gd.parse_spec("not json at all") is None


@pytest.mark.parametrize("doc_type", sorted(gd.DOC_TYPES))
async def test_every_template_renders_a_real_pdf(doc_type, tmp_path):
    out = tmp_path / f"{doc_type}.pdf"
    await gd.run(spec=gd.parse_spec(_REPLY), doc_type=doc_type, output_path=str(out))
    text = _pdf_text(out)
    assert "Kinematics" in text
    assert gd.TEMPLATES[doc_type]["kicker"].upper().replace(" ", "") in text.replace(" ", "").upper()
    assert "speed < 300" in text  # escaped, not parsed as markup
    assert "frac" not in text and "$" not in text  # maths drawn, not printed as source
    assert "Velocity" in text
    answers_title = gd.TEMPLATES[doc_type].get("answers_title", "Answers")
    assert answers_title in text


async def test_markdown_reply_still_becomes_a_document(tmp_path):
    spec = gd.spec_from_markdown("# Cells\n## Organelles\n- Mitochondria make ATP\n## Answer key\n- Q1. ATP", "study_guide")
    assert spec["title"] == "Cells"
    assert spec["sections"][0]["blocks"][0]["items"] == ["Mitochondria make ATP"]
    assert spec["answers"] == [{"q": 1, "answer": "ATP"}]
    out = tmp_path / "md.pdf"
    await gd.run(spec=spec, doc_type="study_guide", output_path=str(out))
    assert "Mitochondria make ATP" in _pdf_text(out)


@pytest.mark.parametrize("doc_type", ["study_guide", "flashcards", "practice_exam"])
async def test_without_ai_the_material_uses_the_same_template(doc_type, tmp_path):
    out = tmp_path / f"{doc_type}.pdf"
    material = ["## Heat", "Entropy is a measure of disorder.", "Heat flows from hot to cold."]
    await gd.run(material=material, doc_type=doc_type, title="Thermo", output_path=str(out))
    text = _pdf_text(out)
    assert "Thermo" in text and "without AI" in text


@pytest.mark.parametrize(
    "request_text, doc_type",
    [
        ("revision notes on cell biology as a pdf", "revision_notes"),
        ("summarise photosynthesis in a pdf", "summary"),
        ("a formula sheet for kinematics pdf", "formula_sheet"),
        ("pdf cheat sheet for trigonometry", "formula_sheet"),
        ("make a worksheet on fractions as a pdf", "worksheet"),
        ("practice exam on genetics pdf", "practice_exam"),
        ("lab report on titration pdf", "lab_report"),
        ("pdf guide to thermodynamics", "study_guide"),
    ],
)
def test_chat_pdf_requests_pick_the_right_template(request_text, doc_type):
    assert moderator_engine._requested_doc_type(request_text) == doc_type
