"""
Diagram understanding — extracts a structured description from a diagram image.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "diagram": {
        "kind": "flowchart-like",
        "elements": ["rectangle", "rectangle", "line"],
        "relationships": []
    }
}

Status: later phase (hard — PATHWAY.md explicitly flags real vision
understanding as Phase 4 territory needing a different model family;
this is a best-effort placeholder, not that)

HONESTY NOTE: this does NOT recognize domain-specific symbols. The
original feature description's example ("resistor", "capacitor") would be
outright fabrication without a trained symbol classifier — there is no way
to tell a resistor symbol from a capacitor symbol via generic shape
detection. Instead, `elements` lists real, generically-detected geometric
primitives (circle, rectangle, triangle, line) via OpenCV contour analysis
— true facts about the image's shapes, not guessed domain semantics.
`kind` is a coarse, low-confidence guess from the primitive mix (e.g. many
rectangles + connecting lines -> "flowchart-like"), explicitly hedged with
"-like" rather than asserted as a real classification. `relationships` is
always empty — inferring which elements connect to which needs graph
analysis of the line endpoints against shape boundaries, not attempted.
"""
from __future__ import annotations

from typing import Any

import cv2
import numpy as np


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path: str = kwargs["image"]
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    elements = _detect_shapes(gray)
    kind = _guess_kind(elements)

    return {"diagram": {"kind": kind, "elements": elements, "relationships": []}}


# --- private helpers ---


def _detect_shapes(gray: np.ndarray) -> list[str]:
    edges = cv2.Canny(gray, 50, 150)
    edges = cv2.dilate(edges, None, iterations=1)
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    min_area = gray.shape[0] * gray.shape[1] * 0.001  # ignore noise-sized contours
    elements = []
    for contour in contours:
        area = cv2.contourArea(contour)
        if area < min_area:
            continue
        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.03 * perimeter, True)
        vertex_count = len(approx)

        if vertex_count == 3:
            elements.append("triangle")
        elif vertex_count == 4:
            elements.append("rectangle")
        else:
            # anything else (5+ vertices) is classified circle vs. line by
            # circularity, not a fixed vertex-count cutoff — a thin-stroke
            # circle's contour can approximate to as few as ~8 vertices, so
            # gating on ">8" (an earlier version of this check) missed real
            # circles; deferring to circularity for all non-triangle/quad
            # shapes is what this engine's own test suite caught and fixed
            circularity = 4 * np.pi * area / (perimeter**2 + 1e-6)
            elements.append("circle" if circularity > 0.7 else "line")

    return elements


def _guess_kind(elements: list[str]) -> str:
    if not elements:
        return "unknown"
    counts = {shape: elements.count(shape) for shape in set(elements)}
    rectangles = counts.get("rectangle", 0)
    circles = counts.get("circle", 0)
    lines = counts.get("line", 0)

    if rectangles >= 2 and lines >= 1:
        return "flowchart-like"
    if circles >= 2 and lines >= 1:
        return "network-or-circuit-like"
    if rectangles >= 1 and circles == 0:
        return "structural-like"
    return "unknown"


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print(result["diagram"])
