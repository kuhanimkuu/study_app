"""
One template per document type: what the AI is asked to write (the plan
of sections and which blocks to use) and how render.py lays it out
(colours, numbering, answer page, lines to write on). The AI only ever
fills in content; the design lives here and in render.py, so every
revision sheet looks like a revision sheet whichever model wrote it.

To add a type: add an entry here, and to _DOC_TYPES in
server/domains/knowledge/router.py and the Studio list in the app.
"""
from __future__ import annotations

# The JSON every template asks for. render.py reads exactly these fields
# and ignores anything else.
SPEC_SCHEMA = """{
  "title": "short, specific title",
  "subtitle": "one line: what this covers",
  "intro": "optional short opening paragraph",
  "objectives": ["optional list of what the student will be able to do"],
  "sections": [
    {"heading": "section heading", "blocks": [ ...blocks... ]}
  ],
  "answers": [{"q": 1, "answer": "the answer", "explanation": "why / marking points"}]
}

Block types (each block is a JSON object with a "type"):
  {"type": "paragraph", "text": "..."}
  {"type": "bullets", "items": ["...", "..."]}
  {"type": "steps", "items": ["first do...", "then..."]}
  {"type": "definition", "term": "...", "text": "..."}
  {"type": "formula", "label": "name of the formula", "latex": "E = mc^2", "note": "where E is ... (units)"}
  {"type": "tip" | "warning" | "remember" | "example" | "key", "title": "optional", "text": "..."}
  {"type": "table", "title": "optional", "header": ["col 1", "col 2"], "rows": [["a", "b"]]}
  {"type": "question", "text": "...", "options": ["...", "...", "...", "..."], "marks": 2, "lines": 3}
  {"type": "card", "front": "question or term", "back": "answer"}
  {"type": "blank", "label": "what the student writes here", "lines": 4}"""

_RULES = """Rules:
- Output ONLY the JSON object. No preamble, no markdown code fences.
- Maths: write it in LaTeX. Inside any text use $...$ (e.g. "the gradient $\\\\frac{dy}{dx}$").
  In a formula block put the bare LaTeX in "latex" with no $ signs. Escape every backslash for JSON (write \\\\frac, \\\\alpha).
- Use **double asterisks** for the few words that matter most. Don't use any other markdown.
- Keep each bullet to one idea. Prefer bullets, tables and boxes over long paragraphs.
- Number questions in the order they appear across the whole document, starting at 1, and give "answers" in that same order.
- Be correct. Don't invent data, results, quotes or sources."""

TEMPLATES: dict[str, dict] = {
    "study_guide": {
        "label": "Study guide",
        "kicker": "Study guide",
        "accent": "#4F46E5",
        "tint": "#EEF2FF",
        "objectives_title": "By the end of this guide you can",
        "answers_title": "Answers",
        "max_tokens": 5000,
        "plan": """A complete guide that teaches the topic from the start.
- "objectives": 3-5 things the student will be able to do.
- "intro": 2-3 sentences on why this topic matters.
- 4-7 sections in a sensible teaching order. In each section: a short paragraph explaining the idea,
  "definition" blocks for new terms, "bullets" for the key points, a "formula" block for every formula,
  and where it helps an "example" box (a worked example, with the steps on separate lines) and a "tip" or "warning".
- A last section "Check your understanding" with 4-6 "question" blocks (mix short answer and multiple choice), with "answers".""",
    },
    "revision_notes": {
        "label": "Revision notes",
        "kicker": "Revision notes",
        "accent": "#DB2777",
        "tint": "#FDF2F8",
        "body_size": 9.5,
        "objectives_title": "Must know",
        "answers_title": "Quick-test answers",
        "max_tokens": 4000,
        "plan": """Condensed notes to revise from the night before an exam. No long paragraphs.
- "objectives": the 4-6 things they absolutely must know, each one short.
- One section per topic. In each: "bullets" of must-know facts (each under 15 words), "definition" blocks for key terms,
  "formula" blocks, a "remember" box with a memory hook or mnemonic where a natural one exists,
  and a "warning" box with the common exam trap. Use a "table" to compare things that get confused.
- A last section "Quick self-test" with 5-8 short "question" blocks ("lines": 1), with "answers".""",
    },
    "summary": {
        "label": "Summary",
        "kicker": "Summary",
        "accent": "#0D9488",
        "tint": "#F0FDFA",
        "intro_box": "In short",
        "max_tokens": 2500,
        "plan": """A short summary that fits on one or two pages.
- "intro": the whole thing in 2-3 sentences (shown as an "In short" box).
- 3-5 sections, one per main idea, each a 1-3 sentence paragraph plus 2-4 bullets.
- A section "Key terms" with "definition" blocks.
- A last section "Key takeaways" with one "remember" box holding 3-5 lines starting with "- ".
- No questions, no "answers".""",
    },
    "formula_sheet": {
        "label": "Formula sheet",
        "kicker": "Formula sheet",
        "accent": "#2563EB",
        "tint": "#EFF6FF",
        "compact": True,
        "body_size": 9.5,
        "max_tokens": 3500,
        "plan": """A formula sheet: every formula, equation and law, grouped by topic. Almost no prose.
- One section per topic. Each formula is a "formula" block with a short "label", the "latex", and a "note"
  saying what each symbol means and its units.
- Where useful add a "table" of constants or units (with symbol, value, unit), and one "warning" box per section for
  the usual mistake (wrong units, sign conventions, when the formula doesn't apply).
- No questions, no "answers".""",
    },
    "worksheet": {
        "label": "Worksheet",
        "kicker": "Worksheet",
        "accent": "#EA580C",
        "tint": "#FFF7ED",
        "name_line": True,
        "number_sections": False,
        "default_lines": 3,
        "answers_title": "Answers and working",
        "max_tokens": 4500,
        "plan": """A practice worksheet that goes from easy to hard.
- "intro": one line of instructions.
- 3 sections: "Warm-up", "Practice", "Challenge". Each starts with a short "paragraph" saying what to do,
  then 4-6 "question" blocks. Mix fill-in-the-blank, short answer, calculation (more "lines") and multiple choice
  ("options", no lines). Give "marks" for each question.
- One "tip" box in the Practice section with a hint that helps without giving an answer away.
- "answers": one per question, with the worked steps in "explanation".""",
    },
    "flashcards": {
        "label": "Flashcards",
        "kicker": "Flashcards",
        "accent": "#7C3AED",
        "tint": "#F5F3FF",
        "number_sections": False,
        "cards_note": "Cut along the dashed lines, then fold each strip down the middle: question on the front, answer on the back.",
        "max_tokens": 3500,
        "plan": """Printable flashcards.
- 16-24 "card" blocks in total, grouped into sections by topic (3-8 cards per section).
- "front": one short question or a term. "back": the answer in under 30 words.
- Test one fact per card. Mix definitions, "why" questions and formulas.
- No other block types, no "answers".""",
    },
    "practice_exam": {
        "label": "Practice exam",
        "kicker": "Practice exam",
        "accent": "#334155",
        "tint": "#F1F5F9",
        "name_line": True,
        "number_sections": False,
        "intro_box": "Instructions",
        "default_lines": 4,
        "answers_title": "Mark scheme",
        "max_tokens": 5000,
        "plan": """An exam paper like a real one.
- "subtitle": the time allowed and total marks, e.g. "Time: 1 hour · Total: 50 marks".
- "intro": the instructions to candidates, as lines starting with "- ".
- "Section A: Multiple choice": 8-10 "question" blocks, exactly 4 "options" each, "marks": 1.
- "Section B: Short answer": 4-6 questions worth 2-4 marks, "lines" about 2 per mark.
- "Section C: Extended response": 1-2 questions worth 6-10 marks, "lines": 12.
- "answers": the mark scheme, one per question, with the marking points in "explanation".""",
    },
    "lab_report": {
        "label": "Lab report",
        "kicker": "Lab report",
        "accent": "#16A34A",
        "tint": "#F0FDF4",
        "name_line": True,
        "max_tokens": 3500,
        "plan": """A lab report template for the student to complete, pre-filled with what the material really says.
Never invent measurements or results.
- Sections in this order: "Aim", "Background theory", "Hypothesis", "Materials", "Method", "Results", "Analysis", "Conclusion".
- Background theory: a short paragraph, "definition" and "formula" blocks from the material.
- Materials and Method: "bullets" and "steps" only if the material describes the experiment; otherwise "blank" blocks.
- Hypothesis and Conclusion: "blank" blocks with a helpful "label" (e.g. "If ... then ... because ...").
- Results: a "table" with the right column headings (with units) and 5 empty rows (rows of empty strings).
- Analysis: 3-4 "question" blocks that guide the student's analysis, plus a "warning" box on sources of error.
- No "answers".""",
    },
}

DEFAULT_TYPE = "study_guide"


def template_for(doc_type: str) -> dict:
    return TEMPLATES.get(doc_type, TEMPLATES[DEFAULT_TYPE])


def build_prompt(doc_type: str, *, topic: str = "", material: str = "", focus: str = "", style: str = "") -> str:
    """The prompt for one document. `material` is the student's own source
    text (Studio); without it the model writes from its own knowledge of
    `topic` (a chat request)."""
    t = template_for(doc_type)
    parts = [
        f"You are writing a {t['label'].lower()} for a student. It will be laid out as a designed PDF, "
        "so you only write the content, as JSON.",
        f"What to write:\n{t['plan']}",
        f"JSON format:\n{SPEC_SCHEMA}",
        _RULES,
    ]
    if material:
        parts.append(
            "Base it on the student's material below. Cover what the material covers, use its terms and notation, "
            "and don't add topics it doesn't touch. You may add a short standard explanation where the material "
            "assumes knowledge, but never contradict it."
        )
    if focus:
        parts.append(f"Focus only on: {focus}")
    if topic:
        parts.append(f"Topic: {topic}")
    if style:
        parts.append(style.strip())
    if material:
        parts.append(f"Material:\n<<<\n{material}\n>>>")
    return "\n\n".join(parts)
