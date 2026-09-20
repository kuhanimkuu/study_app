"""
Math OCR — extracts a math expression from an image and converts it to LaTeX.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "latex": "2x + 3 = 7",
    "confidence": 0.91
}

Status: later phase (hard — this project's own docs flag it explicitly:
"the Photomath problem. Attempt, learn, fail, iterate.")

HONESTY NOTE: Tesseract has no concept of 2D mathematical layout (fractions,
exponents as superscripts, square roots, matrices, integral bounds) — it
reads left-to-right like prose. This only has a real chance of working on
simple, linear, single-line expressions typed/printed plainly (like
"2x + 3 = 7"). Anything with real 2D math notation will likely produce
garbage. A real solution needs a model trained specifically for math
recognition (e.g. an image-to-LaTeX transformer) — not attempted here.

Approach: OCR with Tesseract -> a few honest, narrow character-confusion
fixes common in OCR'd math (not a general cleanup) -> attempt to parse the
result with sympy (reusing the same parser math_engine/symbolic uses). If
it parses, `confidence` reflects genuine success (it's valid math) and
`latex` is real sympy-rendered LaTeX. If parsing fails, `latex` falls back
to the raw cleaned OCR text (which is NOT valid LaTeX) with `confidence: 0`
— an honest failure signal, not a disguised guess.
"""
from __future__ import annotations

import re
from typing import Any

import pytesseract
import sympy
from PIL import Image
from sympy.parsing.sympy_parser import (
    implicit_multiplication_application,
    standard_transformations,
    parse_expr,
)

_TRANSFORMATIONS = standard_transformations + (implicit_multiplication_application,)

# Narrow, evidence-based OCR misread fixes for math contexts (not a general
# text cleanup) — e.g. "x" is sometimes read as the multiplication sign
# mangled into other characters near digits; low confidence Tesseract
# often confuses these specific character pairs in short math strings.
_CLEANUP_RULES = [
    (re.compile(r"(?<=\d)O(?=\d)"), "0"),  # letter O between digits -> zero
    (re.compile(r"(?<=\d)l(?=\d)"), "1"),  # letter l between digits -> one
    (re.compile(r"\s+"), " "),
]


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path: str = kwargs["image"]
    image = Image.open(image_path)

    raw_text = pytesseract.image_to_string(image, config="--psm 7").strip()
    cleaned = _clean(raw_text)

    parsed = _try_parse(cleaned)
    if parsed is not None:
        return {"latex": sympy.latex(parsed), "confidence": 0.75}

    return {"latex": cleaned, "confidence": 0.0}


# --- private helpers ---


def _clean(text: str) -> str:
    for pattern, replacement in _CLEANUP_RULES:
        text = pattern.sub(replacement, text)
    return text.strip()


def _try_parse(text: str):
    if not text:
        return None
    try:
        if "=" in text:
            lhs_str, rhs_str = text.split("=", 1)
            return sympy.Eq(parse_expr(lhs_str, transformations=_TRANSFORMATIONS), parse_expr(rhs_str, transformations=_TRANSFORMATIONS))
        return parse_expr(text, transformations=_TRANSFORMATIONS)
    except Exception:
        return None


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print(result)
