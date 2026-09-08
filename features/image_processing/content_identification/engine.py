"""
Content identification (vision routing) — decides what kind of content an
image contains, so it can be routed to the right engine.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to enhanced image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "route": "math",              # text | handwriting | math | graph | diagram | table | photo
    "confidence": 0.93
}

Status: later phase

IMPORTANT HONESTY NOTE: this is a stack of cheap, real, measurable signals
(OCR confidence/text, edge density, Hough line geometry) combined with
hand-written rules — NOT a trained vision classifier. PATHWAY.md itself
flags real vision routing as Phase 4 hard-problem territory ("Vision
model... different model family — text models won't do this"), and this
session's own Android capability research found ML Kit Image Labeling is
the real, production-quality answer once there's a client to run it on.
Expect this heuristic to misfire, especially between "diagram"/"photo" and
"graph"/"table" — it's a best-effort placeholder, tested against a handful
of synthetic cases, not validated against real-world images at any scale.
"""
from __future__ import annotations

import importlib.util
import math
import re
from pathlib import Path
from types import ModuleType
from typing import Any

import cv2
import numpy as np

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "content_id_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_text_ocr = _load_sibling_engine("ocr/text_ocr/engine.py")

_MATH_HINT_RE = re.compile(
    r"\d\s*[+\-*/^=]\s*\d|[a-zA-Z]\s*=\s*[\d\-]|\b(sin|cos|tan|log|ln|sqrt|integral|derivative)\b",
    re.IGNORECASE,
)

TEXT_CONFIDENCE_THRESHOLD = 0.55
HANDWRITING_CONFIDENCE_BAND = (0.20, 0.55)
GRID_LINE_COUNT_THRESHOLD = 8


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path: str = kwargs["image"]

    ocr_result = await _text_ocr.run(image=image_path)
    text, confidence = ocr_result["text"].strip(), ocr_result["confidence"]

    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    horizontal_lines, vertical_lines = _count_axis_aligned_lines(gray)
    edge_density = _edge_density(gray)

    return _classify(text, confidence, horizontal_lines, vertical_lines, edge_density)


# --- private helpers ---


def _classify(
    text: str, confidence: float, horizontal_lines: int, vertical_lines: int, edge_density: float
) -> dict:
    has_text = len(text) >= 3

    if has_text and confidence >= TEXT_CONFIDENCE_THRESHOLD and _MATH_HINT_RE.search(text):
        return {"route": "math", "confidence": confidence}
    if has_text and confidence >= TEXT_CONFIDENCE_THRESHOLD:
        return {"route": "text", "confidence": confidence}
    if has_text and HANDWRITING_CONFIDENCE_BAND[0] <= confidence < HANDWRITING_CONFIDENCE_BAND[1]:
        return {"route": "handwriting", "confidence": 1.0 - confidence}  # low OCR confidence *is* the handwriting signal

    if horizontal_lines >= GRID_LINE_COUNT_THRESHOLD and vertical_lines >= GRID_LINE_COUNT_THRESHOLD:
        grid_strength = min(1.0, (horizontal_lines + vertical_lines) / (GRID_LINE_COUNT_THRESHOLD * 4))
        return {"route": "table", "confidence": grid_strength}
    if horizontal_lines >= 1 and vertical_lines >= 1:
        return {"route": "graph", "confidence": 0.5}

    if edge_density > 0.08:
        return {"route": "diagram", "confidence": min(1.0, edge_density * 5)}

    return {"route": "photo", "confidence": 1.0 - edge_density}


def _count_axis_aligned_lines(gray: np.ndarray) -> tuple[int, int]:
    edges = cv2.Canny(gray, 50, 150)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=80, minLineLength=40, maxLineGap=10)
    if lines is None:
        return 0, 0

    horizontal = vertical = 0
    for line in lines:
        x1, y1, x2, y2 = np.asarray(line).flatten()[:4]
        angle = abs(math.degrees(math.atan2(y2 - y1, x2 - x1)))
        if angle < 10 or angle > 170:
            horizontal += 1
        elif 80 < angle < 100:
            vertical += 1
    return horizontal, vertical


def _edge_density(gray: np.ndarray) -> float:
    edges = cv2.Canny(gray, 50, 150)
    return float(np.count_nonzero(edges) / edges.size)


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print(result)
