"""
Document generation — produces output documents: revision notes, formula
sheets, study guides, lab reports, summaries, practice exams, flashcards,
worksheets.

INPUT (JSON) — what this engine receives:
{
    "material": ["<chunk 1>", "<chunk 2>"],
    "doc_type": "study_guide",
    "title": "My Study Guide",       // optional
    "output_path": "output.pdf"      // optional
}

OUTPUT (JSON) — what this engine returns:
{
    "document": "<path to generated pdf file>",
    "doc_type": "study_guide"
}

Status: later phase
Built on reportlab — produces a real PDF file, not a placeholder reference.

HONESTY NOTE on doc_type handling: there's no LLM in this phase to write
real quiz questions or classify material into report sections, so:
  - "study_guide" / "revision_notes" / "summary" / "formula_sheet" /
    "worksheet" (and any unrecognized doc_type) compile the material chunks
    into a titled document, one bullet per chunk — a real, if simple,
    compiled document.
  - "flashcards" splits each chunk into front/back using a crude sentence
    heuristic (front = first sentence, back = the rest) — real work, not
    semantic Q&A generation.
  - "practice_exam" generates real cloze-deletion questions (blank out the
    longest word in each chunk, answer = the removed word) — a genuine,
    well-known simple quiz technique, not fabricated understanding.
  - "lab_report" compiles chunks under generic section headers (Objective /
    Notes / Discussion) since there's no way to classify which chunk
    belongs under which section without real content understanding — all
    material lands under "Notes".
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, ListFlowable, ListItem

_STYLES = getSampleStyleSheet()


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"material": list[str], "doc_type": str, "title"?: str, "output_path"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    material: list[str] = kwargs["material"]
    doc_type: str = kwargs["doc_type"]
    title: str = kwargs.get("title", doc_type.replace("_", " ").title())
    output_path: str = kwargs.get("output_path", f"{doc_type}.pdf")

    if doc_type == "flashcards":
        story = _build_flashcards(title, material)
    elif doc_type == "practice_exam":
        story = _build_practice_exam(title, material)
    elif doc_type == "lab_report":
        story = _build_lab_report(title, material)
    else:
        story = _build_compiled_document(title, material)

    doc = SimpleDocTemplate(output_path, pagesize=letter)
    doc.build(story)

    return {"document": output_path, "doc_type": doc_type}


# --- private helpers ---


def _build_compiled_document(title: str, material: list[str]) -> list:
    story = [Paragraph(title, _STYLES["Title"]), Spacer(1, 12)]
    items = [ListItem(Paragraph(chunk, _STYLES["Normal"])) for chunk in material]
    story.append(ListFlowable(items, bulletType="bullet"))
    return story


def _build_flashcards(title: str, material: list[str]) -> list:
    story = [Paragraph(title, _STYLES["Title"]), Spacer(1, 12)]
    for i, chunk in enumerate(material, start=1):
        front, back = _split_front_back(chunk)
        story.append(Paragraph(f"Card {i} — Front:", _STYLES["Heading3"]))
        story.append(Paragraph(front, _STYLES["Normal"]))
        story.append(Paragraph(f"Card {i} — Back:", _STYLES["Heading3"]))
        story.append(Paragraph(back, _STYLES["Normal"]))
        story.append(Spacer(1, 12))
    return story


def _build_practice_exam(title: str, material: list[str]) -> list:
    story = [Paragraph(title, _STYLES["Title"]), Spacer(1, 12)]
    for i, chunk in enumerate(material, start=1):
        question, answer = _cloze_question(chunk)
        story.append(Paragraph(f"Q{i}. {question}", _STYLES["Normal"]))
        story.append(Spacer(1, 6))
    story.append(Paragraph("Answer key:", _STYLES["Heading3"]))
    for i, chunk in enumerate(material, start=1):
        _, answer = _cloze_question(chunk)
        story.append(Paragraph(f"Q{i}: {answer}", _STYLES["Normal"]))
    return story


def _build_lab_report(title: str, material: list[str]) -> list:
    story = [Paragraph(title, _STYLES["Title"]), Spacer(1, 12)]
    story.append(Paragraph("Objective", _STYLES["Heading2"]))
    story.append(Paragraph("(not auto-generated — fill in manually)", _STYLES["Normal"]))
    story.append(Spacer(1, 8))
    story.append(Paragraph("Notes", _STYLES["Heading2"]))
    items = [ListItem(Paragraph(chunk, _STYLES["Normal"])) for chunk in material]
    story.append(ListFlowable(items, bulletType="bullet"))
    story.append(Spacer(1, 8))
    story.append(Paragraph("Discussion", _STYLES["Heading2"]))
    story.append(Paragraph("(not auto-generated — fill in manually)", _STYLES["Normal"]))
    return story


def _split_front_back(chunk: str) -> tuple[str, str]:
    for sep in [". ", "? ", "! "]:
        if sep in chunk:
            front, _, rest = chunk.partition(sep)
            return front.strip() + sep.strip(), rest.strip() or front.strip()
    return chunk.strip(), chunk.strip()  # no sentence break found — degenerate card


def _cloze_question(chunk: str) -> tuple[str, str]:
    words = chunk.split()
    if not words:
        return chunk, ""
    target_idx = max(range(len(words)), key=lambda i: len(words[i].strip(".,;:!?")))
    answer = words[target_idx].strip(".,;:!?")
    blanked = words.copy()
    blanked[target_idx] = "_____"
    return " ".join(blanked), answer


if __name__ == "__main__":
    import asyncio

    material = [
        "Entropy is a measure of disorder in a thermodynamic system.",
        "The second law of thermodynamics states that entropy never decreases in an isolated system.",
        "Heat flows spontaneously from hot to cold, never the reverse.",
    ]

    async def demo() -> None:
        for doc_type in ["study_guide", "flashcards", "practice_exam"]:
            result = await run(material=material, doc_type=doc_type, output_path=f"scratch_demo_{doc_type}.pdf")
            path = Path(result["document"])
            print(f"{doc_type}: {result} (exists={path.exists()}, size={path.stat().st_size if path.exists() else 0} bytes)")

    asyncio.run(demo())
