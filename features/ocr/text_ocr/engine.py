"""
Text OCR (printed) — extracts printed text from a standalone image.

INPUT (JSON) — what this engine receives:
{
    "image": "<path to image file>"
}

OUTPUT (JSON) — what this engine returns:
{
    "text": "The second law of thermodynamics states...",
    "confidence": 0.98
}

"confidence" is the mean of Tesseract's per-word confidences (0-100, scaled
to 0-1 here), excluding words Tesseract couldn't score (conf == -1, usually
whitespace/non-text regions). It's a genuine measure from the OCR engine
itself, not a guess.

Status: core v1
Built on pytesseract + the real Tesseract binary (same as
document_engine/scanned_ocr — this is the standalone-image counterpart;
scanned_ocr is specifically for image-only PDF pages).
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

    text = pytesseract.image_to_string(image).strip()
    confidence = _average_confidence(image)

    return {"text": text, "confidence": confidence}


# --- private helpers ---


def _average_confidence(image: Image.Image) -> float:
    data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT)
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
            print(
                f"[{__name__}] Tesseract binary not found on PATH — install it "
                "(https://github.com/tesseract-ocr/tesseract) to run this demo."
            )
        else:
            enc = sys.stdout.encoding or "utf-8"
            print("confidence:", result["confidence"])
            print("text:", result["text"].encode(enc, errors="replace").decode(enc))
