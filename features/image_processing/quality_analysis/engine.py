"""
Quality analysis — inspects an image and reports quality + "is it a document?".

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "quality": {
        "blur": 0.2,              // 0 (sharp) - 1 (very blurry)
        "noise": 0.1,              // 0 (clean) - 1 (very noisy)
        "resolution": "1080x1920",
        "lighting": "ok",          // dark | ok | bright
        "perspective": 0.0,        // 0 (square-on) - 1 (heavily skewed quadrilateral), or null if no document boundary found
        "rotation": 1.5,           // degrees of estimated skew
        "is_document": true
    }
}

Status: core v1
Built on OpenCV. Every metric below is a real, named, standard computer-
vision technique (cited in comments) — not a black box, and not a trained
classifier (no ML model here, just measurable image statistics).
"""
from __future__ import annotations

import math
from typing import Any

import cv2
import numpy as np


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path = kwargs["image"]
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    height, width = gray.shape

    contour = _find_document_contour(gray)

    quality = {
        "blur": _blur_score(gray),
        "noise": _noise_score(gray),
        "resolution": f"{width}x{height}",
        "lighting": _lighting(gray),
        "perspective": _perspective_score(contour) if contour is not None else None,
        "rotation": _rotation_degrees(contour) if contour is not None else 0.0,
        "is_document": _is_document(contour, width, height),
    }
    return {"quality": quality}


# --- private helpers ---


def _blur_score(gray: np.ndarray) -> float:
    """Variance of the Laplacian, normalized by the image's own pixel
    variance — a standard sharpness measure (Pech-Pacheco et al., 2000),
    with the normalization added to make it scale-invariant to brightness/
    contrast (raw Laplacian variance alone shrinks proportionally to k^2
    when pixel values are scaled by k, e.g. a darkened photo, so an
    unnormalized version incorrectly reports a darker-but-equally-sharp
    image as blurrier — caught by this engine's own test suite). Low ratio
    = few sharp edges relative to overall contrast = blurry."""
    REFERENCE_RATIO = 0.5  # calibrated empirically against this engine's own test images (see README)
    laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
    image_var = gray.astype(np.float64).var() + 1e-6
    ratio = laplacian_var / image_var
    return float(max(0.0, min(1.0, 1.0 - ratio / REFERENCE_RATIO)))


def _noise_score(gray: np.ndarray) -> float:
    """Fast noise variance estimation (Immerkaer, 1996) — convolves with a
    Laplacian-like kernel that cancels smooth/linear content, leaving mostly
    noise energy. Normalized against an empirical reference."""
    REFERENCE_NOISE_SIGMA = 15.0
    h, w = gray.shape
    kernel = np.array([[1, -2, 1], [-2, 4, -2], [1, -2, 1]], dtype=np.float64)
    conv = cv2.filter2D(gray.astype(np.float64), -1, kernel)
    sigma = np.sum(np.abs(conv)) * math.sqrt(0.5 * math.pi) / (6 * (w - 2) * (h - 2))
    return float(max(0.0, min(1.0, sigma / REFERENCE_NOISE_SIGMA)))


def _lighting(gray: np.ndarray) -> str:
    mean_brightness = float(gray.mean())
    if mean_brightness < 60:
        return "dark"
    if mean_brightness > 200:
        return "bright"
    return "ok"


def _find_document_contour(gray: np.ndarray) -> np.ndarray | None:
    """Finds the largest 4-point contour in the image (typical of a page/
    document boundary against a background), via edge detection + contour
    approximation. Returns None if nothing quadrilateral-shaped and large
    enough was found — an honest "couldn't detect a document boundary",
    not a guess."""
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150)
    edges = cv2.dilate(edges, None, iterations=2)

    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    largest = max(contours, key=cv2.contourArea)
    image_area = gray.shape[0] * gray.shape[1]
    if cv2.contourArea(largest) < 0.15 * image_area:
        return None  # nothing big enough to plausibly be "the document"

    perimeter = cv2.arcLength(largest, True)
    approx = cv2.approxPolyDP(largest, 0.02 * perimeter, True)
    if len(approx) != 4:
        return None  # not a clean quadrilateral

    return approx.reshape(4, 2)


def _perspective_score(corners: np.ndarray) -> float:
    """0 = a perfect rectangle (square-on), 1 = heavily skewed quadrilateral.
    Measured as the mean deviation of the quadrilateral's interior angles
    from 90 degrees, normalized to [0, 1]."""
    angles = []
    for i in range(4):
        p0, p1, p2 = corners[i - 1], corners[i], corners[(i + 1) % 4]
        v1, v2 = p0 - p1, p2 - p1
        cos_angle = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9)
        angle = math.degrees(math.acos(np.clip(cos_angle, -1.0, 1.0)))
        angles.append(abs(angle - 90))
    mean_deviation = sum(angles) / 4
    return float(max(0.0, min(1.0, mean_deviation / 45.0)))


def _rotation_degrees(corners: np.ndarray) -> float:
    """Skew angle of the document boundary's longest edge relative to horizontal."""
    rect = cv2.minAreaRect(corners.astype(np.float32))
    angle = rect[-1]
    if angle < -45:
        angle += 90
    return float(angle)


def _is_document(contour: np.ndarray | None, width: int, height: int) -> bool:
    return contour is not None


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print(result["quality"])
