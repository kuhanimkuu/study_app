"""
PDF input — accepts a PDF file and extracts text + structure for the moderator.

INPUT (JSON) — what the input layer receives:
{
    "content": "<pdf path / file reference>"
}

OUTPUT (JSON) — what this engine returns to the moderator:
{
    "input_type": "pdf",
    "content": "extracted text...",
    "structure": {"pages": 42, "tables": [], "equations": []}
}

Status: core v1
Composes document_engine/pdf_processing rather than re-implementing PDF
extraction — loaded via importlib from its file path directly (feature
folders don't import each other as packages yet, see features/README.md;
same pattern already used by document_engine/searchable_knowledge).
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    path = _FEATURES_ROOT / relative_path
    module_name = "pdf_input_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_pdf_processing = _load_sibling_engine("document_engine/pdf_processing/engine.py")


async def run(**kwargs: Any) -> dict:
    """Sole entry point the input layer calls.

    Args (kwargs): {"content": "<path to pdf file>"}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    content: str = kwargs["content"]

    pdf_result = await _pdf_processing.run(pdf=content)

    structure = {
        "pages": pdf_result["metadata"]["page_count"],
        "tables": pdf_result["tables"],
        "equations": pdf_result["equations"],
    }
    return {"input_type": "pdf", "content": pdf_result["text"], "structure": structure}


if __name__ == "__main__":
    import asyncio
    import sys

    pdf_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not pdf_path:
        print(f"[{__name__}] usage: python engine.py <path-to-pdf>")
    else:
        result = asyncio.run(run(content=pdf_path))
        print("structure:", result["structure"])
        enc = sys.stdout.encoding or "utf-8"
        print("content (first 300 chars):", result["content"][:300].encode(enc, errors="replace").decode(enc))
