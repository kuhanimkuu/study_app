"""
OCR on scanned pages — extracts text from image-based (scanned) PDF pages.

INPUT (JSON) — what this engine receives:
{
    "pdf": "<scanned pdf reference>",
    "pages": [3, 4, 5]
}

"pages" is optional — a hint restricting which pages to consider. If omitted,
every page in the document is checked.

OUTPUT (JSON) — what this engine returns:
{
    "text": {"3": "page 3 text...", "4": "page 4 text..."}
}

Only pages that were actually detected as scanned (image-only, no usable
text layer) and OCR'd appear in "text" — a page with a normal text layer is
skipped (that's pdf_processing's job, not this engine's).

Status: later phase
Built on PyMuPDF (fitz) for detection/rasterization + pytesseract for OCR.
Requires the Tesseract engine binary to be installed and on PATH
(https://github.com/tesseract-ocr/tesseract) — pytesseract is just a wrapper
around it.
"""
from __future__ import annotations

from typing import Any

import fitz  # PyMuPDF
import pytesseract
from PIL import Image

TEXT_LAYER_THRESHOLD = 20  # fewer than this many chars of real text -> treat page as scanned
RENDER_ZOOM = 2.0  # upscale factor when rasterizing a page; higher = better OCR, slower


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"pdf": "<path to pdf file>", "pages": [optional list of 1-indexed page numbers]}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    pdf_path = kwargs["pdf"]
    requested_pages = kwargs.get("pages")

    doc = fitz.open(pdf_path)
    try:
        candidate_indices = _resolve_page_indices(doc, requested_pages)

        text: dict[str, str] = {}
        for i in candidate_indices:
            page = doc[i]
            if not _is_scanned_page(page):
                continue
            image = _render_page(page)
            page_text = _ocr_image(image)
            text[str(i + 1)] = page_text
    finally:
        doc.close()

    return {"text": text}


# --- private helpers ---


def _resolve_page_indices(doc: "fitz.Document", requested_pages: list[int] | None) -> list[int]:
    if not requested_pages:
        return list(range(doc.page_count))
    return [p - 1 for p in requested_pages if 0 <= p - 1 < doc.page_count]


def _is_scanned_page(page: "fitz.Page") -> bool:
    has_text = len(page.get_text().strip()) >= TEXT_LAYER_THRESHOLD
    if has_text:
        return False
    return len(page.get_images()) > 0


def _render_page(page: "fitz.Page") -> Image.Image:
    matrix = fitz.Matrix(RENDER_ZOOM, RENDER_ZOOM)
    pixmap = page.get_pixmap(matrix=matrix)
    return Image.frombytes("RGB", (pixmap.width, pixmap.height), pixmap.samples)


def _ocr_image(image: Image.Image) -> str:
    return pytesseract.image_to_string(image).strip()


if __name__ == "__main__":
    import asyncio
    import sys

    pdf_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not pdf_path:
        print(f"[{__name__}] usage: python engine.py <path-to-scanned-pdf> [page numbers...]")
    else:
        pages = [int(p) for p in sys.argv[2:]] or None
        try:
            result = asyncio.run(run(pdf=pdf_path, pages=pages))
        except pytesseract.TesseractNotFoundError:
            print(
                f"[{__name__}] Tesseract binary not found on PATH — install it "
                "(https://github.com/tesseract-ocr/tesseract) to run this demo."
            )
        else:
            print("scanned pages found:", len(result["text"]))
            for page_num, page_text in result["text"].items():
                print(f"--- page {page_num} (first 300 chars) ---")
                snippet = page_text[:300]
                print(snippet.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(sys.stdout.encoding or "utf-8"))
