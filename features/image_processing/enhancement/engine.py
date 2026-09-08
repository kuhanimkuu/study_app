"""
Adaptive enhancement — cleans up an image before OCR/vision, conditionally
applying only the corrections the image actually needs.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>",
    "quality": { "blur": 0.2, "noise": 0.1, "lighting": "dark" }   // optional; computed via
                                                                     // image_processing/quality_analysis if omitted
}

OUTPUT (JSON) — what this engine returns:
{
    "image": "<path to enhanced image file>",
    "applied": ["denoise", "perspective_correct", "crop", "sharpen", "contrast"]
}

Status: core v1
Built on OpenCV. Reuses image_processing/quality_analysis (loaded via
importlib, same pattern as elsewhere in this project) for both the quality
metrics (if not already provided) and its document-boundary contour
detection, rather than re-implementing contour finding a second time.

Honesty note: "deblur"/"sharpen" here means unsharp-mask edge sharpening,
NOT true deconvolution-based deblurring (which needs a known/estimated blur
kernel and is a much harder inverse problem — not attempted). The original
feature list called this "deblur"; the applied-step name is "sharpen" to
not overclaim what it does.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any

import cv2
import numpy as np

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "enhancement_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_quality_analysis = _load_sibling_engine("image_processing/quality_analysis/engine.py")

BLUR_THRESHOLD = 0.5
NOISE_THRESHOLD = 0.3


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path>", "quality"?: dict}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path: str = kwargs["image"]
    quality: dict = kwargs.get("quality") or (await _quality_analysis.run(image=image_path))["quality"]

    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")

    applied: list[str] = []

    if quality.get("noise", 0) > NOISE_THRESHOLD:
        image = cv2.fastNlMeansDenoisingColored(image, None, 10, 10, 7, 21)
        applied.append("denoise")

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    contour = _quality_analysis._find_document_contour(gray)
    if contour is not None:
        image = _perspective_correct_and_crop(image, contour)
        applied.append("perspective_correct")
        applied.append("crop")

    if quality.get("blur", 0) > BLUR_THRESHOLD:
        image = _sharpen(image)
        applied.append("sharpen")

    lighting = quality.get("lighting", "ok")
    if lighting != "ok":
        image = _adjust_contrast(image, lighting)
        applied.append("contrast")

    output_path = _output_path(image_path)
    cv2.imwrite(output_path, image)

    return {"image": output_path, "applied": applied}


# --- private helpers ---


def _perspective_correct_and_crop(image: np.ndarray, corners: np.ndarray) -> np.ndarray:
    """Warps the detected quadrilateral to a straight rectangle — this
    subsumes deskewing too, a proper 4-point perspective warp already
    straightens any rotation, so no separate rotate-only deskew step
    is needed when a document boundary was found."""
    pts = _order_corners(corners.astype(np.float32))
    (tl, tr, br, bl) = pts

    width = int(max(np.linalg.norm(br - bl), np.linalg.norm(tr - tl)))
    height = int(max(np.linalg.norm(tr - br), np.linalg.norm(tl - bl)))
    width, height = max(width, 1), max(height, 1)

    dst = np.array([[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]], dtype=np.float32)
    matrix = cv2.getPerspectiveTransform(pts, dst)
    return cv2.warpPerspective(image, matrix, (width, height))


def _order_corners(pts: np.ndarray) -> np.ndarray:
    """Orders 4 points as top-left, top-right, bottom-right, bottom-left."""
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1).flatten()
    top_left = pts[np.argmin(s)]
    bottom_right = pts[np.argmax(s)]
    top_right = pts[np.argmin(diff)]
    bottom_left = pts[np.argmax(diff)]
    return np.array([top_left, top_right, bottom_right, bottom_left], dtype=np.float32)


def _sharpen(image: np.ndarray) -> np.ndarray:
    """Unsharp mask: original + (original - blurred) * amount."""
    blurred = cv2.GaussianBlur(image, (0, 0), sigmaX=3)
    return cv2.addWeighted(image, 1.5, blurred, -0.5, 0)


def _adjust_contrast(image: np.ndarray, lighting: str) -> np.ndarray:
    """CLAHE (contrast-limited adaptive histogram equalization) on the L
    channel in LAB space — real, standard technique, not a flat brightness
    add (which would clip highlights/shadows instead of expanding them)."""
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    l_channel = clahe.apply(l_channel)
    if lighting == "dark":
        l_channel = cv2.convertScaleAbs(l_channel, alpha=1.3, beta=20)
    elif lighting == "bright":
        l_channel = cv2.convertScaleAbs(l_channel, alpha=0.8, beta=-10)
    merged = cv2.merge((l_channel, a_channel, b_channel))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def _output_path(image_path: str) -> str:
    path = Path(image_path)
    return str(path.with_name(f"{path.stem}_enhanced{path.suffix}"))


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print(result)
