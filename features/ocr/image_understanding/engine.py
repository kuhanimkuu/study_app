"""
Image understanding — produces a semantic description of a general image.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "description": "A 1200x900 image, mostly blue tones, bright lighting, simple composition. No readable text detected."
}

Status: deferred / optional

HONESTY NOTE, the most important one in this whole project: this is NOT
image captioning/understanding. "A photo of a bridge under tension" (the
original feature description's example) requires a real vision-language
model (BLIP, CLIP+LLM, or — confirmed during this project's Android
capability research — ML Kit's GenAI "Image Description" API, which is
Gemini-Nano-backed and flagship-device-only). None of that is installed
here: it would mean a multi-GB model dependency for a feature marked
deferred/optional in this project's own features.md. Instead, this builds
a template sentence from real, measurable facts this project already knows
how to compute (dimensions, dominant color via k-means, brightness,
edge-density as a rough "simple vs busy" proxy, and OCR text via
ocr/text_ocr if any is found) — it describes measurable properties of the
pixels, not what the image depicts or means. Calling this "understanding"
at all is generous; it's here because the task was to attempt every
remaining feature best-effort, not because this is a real solution.
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
    module_name = "image_understanding_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_text_ocr = _load_sibling_engine("ocr/text_ocr/engine.py")

_COLOR_NAMES = {
    "red": (0, 0, 255), "green": (0, 255, 0), "blue": (255, 0, 0),
    "yellow": (0, 255, 255), "white": (255, 255, 255), "black": (0, 0, 0),
    "gray": (128, 128, 128),
}


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path: str = kwargs["image"]
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"could not read image: {image_path}")

    height, width = image.shape[:2]
    dominant_color = _dominant_color_name(image)
    brightness = _brightness_description(image)
    composition = _composition_description(image)

    ocr_result = await _text_ocr.run(image=image_path)
    text_note = (
        f" Contains readable text: \"{ocr_result['text'][:80]}\"."
        if ocr_result["text"].strip()
        else " No readable text detected."
    )

    description = (
        f"A {width}x{height} image, mostly {dominant_color} tones, {brightness} lighting, "
        f"{composition} composition.{text_note}"
    )
    return {"description": description}


# --- private helpers ---


def _dominant_color_name(image: np.ndarray) -> str:
    small = cv2.resize(image, (50, 50))
    pixels = small.reshape(-1, 3).astype(np.float32)
    mean_bgr = pixels.mean(axis=0)

    best_name, best_dist = "gray", float("inf")
    for name, bgr in _COLOR_NAMES.items():
        dist = np.linalg.norm(mean_bgr - np.array(bgr, dtype=np.float32))
        if dist < best_dist:
            best_name, best_dist = name, dist
    return best_name


def _brightness_description(image: np.ndarray) -> str:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    mean_brightness = gray.mean()
    if mean_brightness < 60:
        return "dark"
    if mean_brightness > 200:
        return "bright"
    return "moderate"


def _composition_description(image: np.ndarray) -> str:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    density = np.count_nonzero(edges) / edges.size
    return "busy/detailed" if density > 0.08 else "simple"


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        result = asyncio.run(run(image=image_path))
        print(result["description"])
