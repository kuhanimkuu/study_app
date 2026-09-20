"""
PDF processing — extracts everything useful from a PDF into structured form.

INPUT (JSON) — what this engine receives:
{
    "pdf": "<pdf path / reference>"
}

OUTPUT (JSON) — what this engine returns:
{
    "metadata": {"title": "...", "author": "..."},
    "text": "full extracted text...",
    "pages": [{"number": 1, "text": "..."}],
    "tables": [],
    "equations": []
}

Status: core v1
Built on PyMuPDF (fitz).
"""
from __future__ import annotations

from typing import Any

import fitz  # PyMuPDF


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"pdf": "<path to pdf file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    pdf_path = kwargs["pdf"]

    doc = fitz.open(pdf_path)
    try:
        metadata = _extract_metadata(doc)
        pages = _extract_pages(doc)
        text = "\n".join(page["text"] for page in pages)
        tables = _extract_tables(doc)
    finally:
        doc.close()

    return {
        "metadata": metadata,
        "text": text,
        "pages": pages,
        "tables": tables,
        "equations": [],  # not implemented — needs math OCR (features/ocr/math_ocr)
    }


# --- private helpers ---


def _extract_metadata(doc: "fitz.Document") -> dict:
    meta = doc.metadata or {}
    return {
        "title": meta.get("title") or "",
        "author": meta.get("author") or "",
        "subject": meta.get("subject") or "",
        "page_count": doc.page_count,
    }


def _extract_pages(doc: "fitz.Document") -> list[dict]:
    pages = []
    for i, page in enumerate(doc):
        pages.append({"number": i + 1, "text": page.get_text().strip()})
    return pages


def _extract_tables(doc: "fitz.Document") -> list[dict]:
    tables: list[dict] = []
    for i, page in enumerate(doc):
        finder = page.find_tables()
        for table in finder.tables:
            tables.append({"page": i + 1, "rows": table.extract()})
    return tables


if __name__ == "__main__":
    import asyncio
    import sys

    pdf_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not pdf_path:
        print(f"[{__name__}] usage: python engine.py <path-to-pdf>")
    else:
        result = asyncio.run(run(pdf=pdf_path))
        print("metadata:", result["metadata"])
        print("pages:", len(result["pages"]))
        print("tables found:", len(result["tables"]))
        print("--- first 500 chars of text ---")
        snippet = result["text"][:500]
        print(snippet.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(sys.stdout.encoding or "utf-8"))
