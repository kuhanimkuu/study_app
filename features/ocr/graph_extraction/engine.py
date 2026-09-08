"""
Graph extraction — extracts data points from an image of a graph/plot.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "data": {"x": [0.0, 0.02, ...], "y": [0.8, 0.75, ...]},
    "axis": {"x_label": "t", "y_label": "v"}
}

Status: later phase

HONESTY NOTE: "data" is in NORMALIZED [0, 1] coordinates relative to the
detected plot area (bottom-left = (0, 0)), NOT calibrated to real axis
units. Converting to real units needs OCR'ing the numeric tick labels and
matching each one to its pixel position — genuinely harder (variable tick
spacing, rotated labels, scientific notation) and not attempted here.
Returning fabricated "real" numbers without that calibration would be
worse than being upfront that these are normalized pixel-derived
coordinates. `axis.x_label`/`y_label` are a best-effort OCR guess at any
text found near the axes, not guaranteed correct.

Built on OpenCV: detects the plot's x/y axes as the longest near-horizontal
and near-vertical lines (Hough transform), then finds the plotted curve by
looking for non-grayscale (colored) pixels within the axis-bounded plot
area — real curves are usually drawn in a distinct color, unlike black
axes/gridlines and white background. A black-and-white plot (e.g. a curve
drawn in plain black) won't be distinguishable from the axes/gridlines by
this method — a known, real limitation.
"""
from __future__ import annotations

import math
from typing import Any

import cv2
import numpy as np
import pytesseract
from PIL import Image


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path: str = kwargs["image"]
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")

    x_axis, y_axis = _find_axes(image)
    if x_axis is None or y_axis is None:
        return {"data": {"x": [], "y": []}, "axis": {"x_label": None, "y_label": None}}

    plot_box = _plot_area(x_axis, y_axis, image.shape)
    data = _extract_curve(image, plot_box)
    axis_labels = _read_axis_labels(image, plot_box)

    return {"data": data, "axis": axis_labels}


# --- private helpers ---


def _find_axes(image: np.ndarray) -> tuple[tuple, tuple] | tuple[None, None]:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=100, minLineLength=80, maxLineGap=10)
    if lines is None:
        return None, None

    best_h, best_h_len = None, 0
    best_v, best_v_len = None, 0
    for line in lines:
        x1, y1, x2, y2 = np.asarray(line).flatten()[:4]
        length = math.hypot(x2 - x1, y2 - y1)
        angle = abs(math.degrees(math.atan2(y2 - y1, x2 - x1)))
        if (angle < 10 or angle > 170) and length > best_h_len:
            best_h, best_h_len = (x1, y1, x2, y2), length
        elif 80 < angle < 100 and length > best_v_len:
            best_v, best_v_len = (x1, y1, x2, y2), length

    return best_h, best_v


def _plot_area(x_axis: tuple, y_axis: tuple, image_shape: tuple) -> dict:
    x1, y1, x2, y2 = x_axis
    vx1, vy1, vx2, vy2 = y_axis
    left = min(vx1, vx2)
    bottom = max(y1, y2)
    right = max(x1, x2)
    top = min(vy1, vy2)
    return {"left": left, "right": right, "top": top, "bottom": bottom}


def _extract_curve(image: np.ndarray, box: dict) -> dict:
    """Finds non-grayscale (colored) pixels per column within the plot
    area — the honest assumption is the curve is drawn in a color distinct
    from black axes/white background, not that it's black-on-white too."""
    region = image[box["top"] : box["bottom"], box["left"] : box["right"]]
    if region.size == 0:
        return {"x": [], "y": []}

    b, g, r = region[:, :, 0].astype(int), region[:, :, 1].astype(int), region[:, :, 2].astype(int)
    is_colored = (np.abs(b - g) > 30) | (np.abs(g - r) > 30) | (np.abs(b - r) > 30)

    height, width = region.shape[:2]
    xs, ys = [], []
    for col in range(width):
        rows = np.where(is_colored[:, col])[0]
        if len(rows) == 0:
            continue
        row = int(np.median(rows))
        xs.append(col / max(width - 1, 1))
        ys.append(1.0 - row / max(height - 1, 1))  # flip so bottom of plot = y 0

    return {"x": xs, "y": ys}


def _read_axis_labels(image: np.ndarray, box: dict) -> dict:
    height, width = image.shape[:2]
    below_x_axis = image[min(box["bottom"] + 5, height - 1) : height, box["left"] : box["right"]]
    left_of_y_axis = image[box["top"] : box["bottom"], 0 : max(box["left"] - 5, 1)]

    x_label = _ocr_label(below_x_axis)
    y_label = _ocr_label(left_of_y_axis)
    return {"x_label": x_label, "y_label": y_label}


def _ocr_label(region: np.ndarray) -> str | None:
    if region.size == 0:
        return None
    pil_region = Image.fromarray(cv2.cvtColor(region, cv2.COLOR_BGR2RGB))
    text = pytesseract.image_to_string(pil_region, config="--psm 7").strip()
    return text or None


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print("axis:", result["axis"])
        print("points extracted:", len(result["data"]["x"]))
        if result["data"]["x"]:
            print("first:", (result["data"]["x"][0], result["data"]["y"][0]))
            print("last: ", (result["data"]["x"][-1], result["data"]["y"][-1]))
