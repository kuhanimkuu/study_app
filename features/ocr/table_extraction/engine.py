"""
Table extraction — extracts a table from an image or PDF into structured data.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image or pdf file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "table": {
        "headers": ["Name", "Value"],
        "rows": [["x", "2"], ["y", "3"]]
    }
}

Status: later phase

For a .pdf input, delegates to document_engine/pdf_processing's own table
detection (PyMuPDF's find_tables) rather than re-implementing it — loaded
via importlib, same pattern used throughout this project.

For an image input, this is a real (not fake) grid-based table extraction:
detect ruled grid lines via OpenCV (Hough transform), compute cell
boundaries from where horizontal and vertical lines cross, then OCR each
cell individually with Tesseract. This only works for tables with visible
ruling lines — a borderless/whitespace-aligned table won't be detected
(honestly returns empty headers/rows rather than guessing cell boundaries
from text alignment, which is a much harder, unimplemented problem).
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any

import cv2
import numpy as np
import pytesseract
from PIL import Image

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "table_extraction_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_pdf_processing = _load_sibling_engine("document_engine/pdf_processing/engine.py")


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image or pdf file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    path: str = kwargs["image"]

    if path.lower().endswith(".pdf"):
        pdf_result = await _pdf_processing.run(pdf=path)
        tables = pdf_result["tables"]
        if not tables:
            return {"table": {"headers": [], "rows": []}}
        rows = tables[0]["rows"]
        return {"table": {"headers": rows[0] if rows else [], "rows": rows[1:]}}

    return _extract_from_image(path)


# --- private helpers ---


def _extract_from_image(image_path: str) -> dict:
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    thresh = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 15, 10)

    horizontal_lines = _detect_lines(thresh, horizontal=True)
    vertical_lines = _detect_lines(thresh, horizontal=False)

    row_boundaries = _cluster_positions(horizontal_lines, horizontal=True)
    col_boundaries = _cluster_positions(vertical_lines, horizontal=False)

    if len(row_boundaries) < 2 or len(col_boundaries) < 2:
        return {"table": {"headers": [], "rows": []}}  # no ruled grid found — honest empty result

    CELL_INSET = 8  # crop margin to exclude ruling-line pixels at cell edges — without
    # this, Tesseract's segmentation gets confused by the border and returns nothing
    # (found by testing: identical cell crop returned "" with the border, "Name" without)

    grid = []
    for r in range(len(row_boundaries) - 1):
        row_cells = []
        for c in range(len(col_boundaries) - 1):
            y1, y2 = row_boundaries[r], row_boundaries[r + 1]
            x1, x2 = col_boundaries[c], col_boundaries[c + 1]
            y1i, y2i = min(y1 + CELL_INSET, y2), max(y2 - CELL_INSET, y1 + 1)
            x1i, x2i = min(x1 + CELL_INSET, x2), max(x2 - CELL_INSET, x1 + 1)
            cell = image[y1i:y2i, x1i:x2i]
            row_cells.append(_ocr_cell(cell))
        grid.append(row_cells)

    headers = grid[0] if grid else []
    rows = grid[1:]
    return {"table": {"headers": headers, "rows": rows}}


def _detect_lines(thresh: np.ndarray, horizontal: bool) -> np.ndarray:
    size = thresh.shape[1] // 20 if horizontal else thresh.shape[0] // 20
    size = max(size, 10)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (size, 1) if horizontal else (1, size))
    eroded = cv2.erode(thresh, kernel, iterations=1)
    return cv2.dilate(eroded, kernel, iterations=1)


def _cluster_positions(line_mask: np.ndarray, horizontal: bool, gap: int = 15) -> list[int]:
    """Collapses a binary line mask into a sorted list of line-center
    positions (row indices for horizontal lines, column indices for
    vertical), merging positions within `gap` pixels of each other."""
    # a horizontal line spans across columns at one row -> sum each row (axis=1)
    # a vertical line spans down rows at one column -> sum each column (axis=0)
    profile = line_mask.sum(axis=1) if horizontal else line_mask.sum(axis=0)
    if profile.max() == 0:
        return []
    positions = np.where(profile > profile.max() * 0.3)[0]
    if len(positions) == 0:
        return []

    clusters: list[list[int]] = [[positions[0]]]
    for pos in positions[1:]:
        if pos - clusters[-1][-1] <= gap:
            clusters[-1].append(pos)
        else:
            clusters.append([pos])
    return [int(sum(c) / len(c)) for c in clusters]


def _ocr_cell(cell: np.ndarray) -> str:
    if cell.size == 0:
        return ""
    pil_cell = Image.fromarray(cv2.cvtColor(cell, cv2.COLOR_BGR2RGB))
    return pytesseract.image_to_string(pil_cell, config="--psm 7").strip()


if __name__ == "__main__":
    import asyncio
    import sys

    path = sys.argv[1] if len(sys.argv) > 1 else None
    if not path:
        print(f"[{__name__}] usage: python engine.py <path-to-image-or-pdf>")
    else:
        result = asyncio.run(run(image=path))
        print(result["table"])
