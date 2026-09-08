"""
Handwriting recognition — extracts handwritten text from an image.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "text": "Solve for x",
    "confidence": 0.87
}

Status: later phase

HONESTY NOTE: this is plain Tesseract (same engine as ocr/text_ocr), not a
specialized handwriting model — Tesseract's handwriting support is weak by
design, it's trained primarily on printed fonts. This is expected to
perform poorly on real cursive/handwriting; it will do reasonably on very
clean, printed-style handwriting and badly on anything else. A real
solution needs a dedicated handwriting model (e.g. a transformer-based one
like TrOCR) — not installed here given scope/resource constraints. ML Kit's
Digital Ink Recognition (confirmed during this project's Android capability
research) does NOT solve this either — it recognizes live stylus/touch
strokes, not photographs of handwriting on paper.

The one real adjustment made versus text_ocr: `--psm 6` (assume a single
uniform block of text) instead of Tesseract's default page-segmentation
mode, which tends to fare a little better on a single handwritten note than
the default "automatic page segmentation" mode tuned for printed documents.
"""
from __future__ import annotations

from typing import Any

import pytesseract
from PIL import Image


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"image": "<path to image file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    image_path = kwargs["image"]
    image = Image.open(image_path)

    config = "--psm 6"
    text = pytesseract.image_to_string(image, config=config).strip()
    confidence = _average_confidence(image, config)

    return {"text": text, "confidence": confidence}


def _average_confidence(image: Image.Image, config: str) -> float:
    data = pytesseract.image_to_data(image, config=config, output_type=pytesseract.Output.DICT)
    scores = [int(c) for c in data["conf"] if int(c) >= 0]
    if not scores:
        return 0.0
    return (sum(scores) / len(scores)) / 100.0


if __name__ == "__main__":
    import asyncio
    import sys

    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not image_path:
        print(f"[{__name__}] usage: python engine.py <path-to-image>")
    else:
        try:
            result = asyncio.run(run(image=image_path))
        except pytesseract.TesseractNotFoundError:
            print(f"[{__name__}] Tesseract binary not found on PATH.")
        else:
            enc = sys.stdout.encoding or "utf-8"
            print("confidence:", result["confidence"])
            print("text:", result["text"].encode(enc, errors="replace").decode(enc))
