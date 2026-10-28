"""
Document generation — produces designed PDFs: study guides, revision
notes, summaries, formula sheets, worksheets, flashcards, practice exams
and lab reports.

INPUT (JSON) — what this engine receives, one of:
{
    "spec": { ...templates.SPEC_SCHEMA... },   // content written by the AI
    "doc_type": "revision_notes",
    "output_path": "output.pdf"                // optional
}
{
    "material": ["<chunk 1>", "<chunk 2>"],    // raw text, no AI
    "doc_type": "study_guide",
    "title": "My Study Guide",                 // optional
    "output_path": "output.pdf"                // optional
}

OUTPUT (JSON) — what this engine returns:
{
    "document": "<path to generated pdf file>",
    "doc_type": "study_guide"
}

How it works (redesigned 2026-10-28): a template system. Each doc_type
has a template (templates.py) that says what the AI should write, as
JSON in one shared shape, and how it is laid out; render.py draws it with
reportlab: a coloured title band, numbered sections, callout boxes,
glossary tables, typeset maths, questions with answer lines, cut-out
flashcards, an answer key on its own page. Callers get the prompt from
build_prompt(), the model's reply back through parse_spec(), and pass the
spec to run().

Without AI ("material" only — a free local model that can't answer) the
same templates are used with the material as-is: chunks become
paragraphs under their headings, flashcards split each chunk at its first
sentence, and the practice exam blanks out the longest word of each chunk
(cloze questions). The cover says it was compiled without AI.
"""
from __future__ import annotations

import importlib.util
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent


def _sibling(name: str):
    """This file is loaded by path (LazyEngine), not as a package, so its
    own helpers are loaded the same way."""
    key = f"generate_docs_{name}"
    if key not in sys.modules:
        spec = importlib.util.spec_from_file_location(key, _HERE / f"{name}.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[key] = module
        spec.loader.exec_module(module)
    return sys.modules[key]


templates = _sibling("templates")
render = _sibling("render")

TEMPLATES = templates.TEMPLATES
DOC_TYPES = set(TEMPLATES)


def build_prompt(doc_type: str, **kwargs: Any) -> str:
    return templates.build_prompt(doc_type, **kwargs)


def max_tokens_for(doc_type: str) -> int:
    return templates.template_for(doc_type).get("max_tokens", 4000)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"spec"?: dict, "material"?: list[str], "doc_type": str,
    "title"?: str, "output_path"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    doc_type: str = kwargs["doc_type"]
    output_path: str = kwargs.get("output_path", f"{doc_type}.pdf")
    spec = kwargs.get("spec")
    if not isinstance(spec, dict) or not spec.get("sections"):
        spec = spec_from_material(kwargs.get("material") or [], doc_type)
    title = kwargs.get("title")
    if title and not spec.get("title"):
        spec["title"] = title
    spec.setdefault("title", templates.template_for(doc_type)["label"])
    if not str(spec.get("title") or "").strip():
        spec["title"] = templates.template_for(doc_type)["label"]

    with tempfile.TemporaryDirectory(prefix="studyos_doc_") as folder:
        render.Renderer(templates.template_for(doc_type), Path(folder)).build(spec, output_path)

    return {"document": output_path, "doc_type": doc_type}


# --- turning model output into a spec ---

# A backslash starting a LaTeX command ("\frac") that the model forgot to
# escape for JSON. Left alone, json.loads reads "\f" as a form feed and
# "\b" as a backspace, and "\frac" prints as "rac".
_BARE_LATEX_BACKSLASH = re.compile(r'(?<!\\)\\(?=[A-Za-z]{2,})(?!u[0-9a-fA-F]{4})')


def parse_spec(text: str) -> dict | None:
    """The model's reply -> a spec, or None if it isn't the JSON asked
    for. Tolerates code fences and text around the object."""
    if not text:
        return None
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    raw = text[start:end + 1]
    for candidate in (_BARE_LATEX_BACKSLASH.sub(r"\\\\", raw), raw):
        try:
            spec = json.loads(candidate, strict=False)
        except ValueError:
            continue
        if isinstance(spec, dict) and isinstance(spec.get("sections"), list) and spec["sections"]:
            return spec
    return None


_HEADING_RE = re.compile(r"^(#{1,3})\s+(.*)$")
_BULLET_RE = re.compile(r"^(?:[-*•]|\d+[.)])\s+(.*)$")


def spec_from_markdown(text: str, doc_type: str) -> dict | None:
    """Fallback for a reply that came back as headings and bullets instead
    of JSON: "# " is the title, "## " starts a section, bullet lines become
    bullets (or questions, under a heading that says so)."""
    title = ""
    sections: list[dict] = []
    answers: list[dict] = []
    current: dict | None = None
    in_answers = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        heading = _HEADING_RE.match(line)
        if heading:
            hashes, heading_text = heading.groups()
            heading_text = heading_text.strip().replace("**", "")
            if hashes == "#" and not title:
                title = heading_text
                continue
            in_answers = bool(re.search(r"\b(answer|mark scheme|solutions?)\b", heading_text, re.I))
            if not in_answers:
                current = {"heading": heading_text, "blocks": []}
                sections.append(current)
            continue
        bullet = _BULLET_RE.match(line)
        item = bullet.group(1).strip() if bullet else line
        if in_answers:
            q = re.match(r"^Q?(\d+)[.):]\s*(.*)$", item)
            answers.append({"q": int(q.group(1)), "answer": q.group(2)} if q else {"answer": item})
            continue
        if current is None:
            current = {"heading": "", "blocks": []}
            sections.append(current)
        question = re.match(r"^Q\d+[.):]\s*(.*)$", item)
        if question:
            current["blocks"].append({"type": "question", "text": question.group(1)})
        elif bullet:
            if current["blocks"] and current["blocks"][-1]["type"] == "bullets":
                current["blocks"][-1]["items"].append(item)
            else:
                current["blocks"].append({"type": "bullets", "items": [item]})
        else:
            current["blocks"].append({"type": "paragraph", "text": item})
    sections = [s for s in sections if s["blocks"]]
    if not sections:
        return None
    return {"title": title, "sections": sections, "answers": answers}


def spec_from_material(material: list[str], doc_type: str) -> dict:
    """No AI: the student's own material, laid out in the same template.
    A chunk starting "## " starts a new section."""
    label = templates.template_for(doc_type)["label"]
    spec: dict = {"subtitle": "Compiled from your sources without AI. Set up AI for a fully written version."}
    chunks = [str(c).strip() for c in material if str(c).strip()]
    if doc_type == "flashcards":
        cards = [dict(zip(("front", "back"), _split_front_back(c))) for c in chunks if not c.startswith("## ")]
        spec["sections"] = [{"heading": "", "blocks": [{"type": "card", **card} for card in cards]}]
    elif doc_type in ("practice_exam", "worksheet"):
        pairs = [_cloze_question(c) for c in chunks if not c.startswith("## ")]
        spec["intro"] = "Fill in each blank with the missing word."
        spec["sections"] = [{"heading": "Fill in the blanks", "blocks": [
            {"type": "question", "text": q, "lines": 1} for q, _ in pairs
        ]}]
        spec["answers"] = [{"q": i, "answer": a} for i, (_, a) in enumerate(pairs, start=1)]
    else:
        sections: list[dict] = []
        current = {"heading": "From your sources", "blocks": []}
        for chunk in chunks:
            if chunk.startswith("## "):
                if current["blocks"]:
                    sections.append(current)
                current = {"heading": chunk[3:].strip(), "blocks": []}
            else:
                current["blocks"].append({"type": "paragraph", "text": chunk})
        if current["blocks"]:
            sections.append(current)
        spec["sections"] = sections
    spec["sections"] = [s for s in spec["sections"] if s["blocks"]] or [
        {"heading": label, "blocks": [{"type": "paragraph", "text": "No material yet."}]}
    ]
    return spec


FRONT_BACK_SEP = " || "


def _split_front_back(chunk: str) -> tuple[str, str]:
    # An explicit separator wins — the moderator's chat flashcard route
    # (2026-10-06) already knows each card's real front and back, and the
    # sentence heuristic below would split a term-style front like
    # "Mitochondria" wrongly.
    if FRONT_BACK_SEP in chunk:
        front, _, back = chunk.partition(FRONT_BACK_SEP)
        return front.strip(), back.strip() or front.strip()
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
