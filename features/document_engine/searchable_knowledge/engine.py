"""
Searchable knowledge — answers queries over an indexed PDF
("find everything about entropy", "explain pages 42-47").

INPUT (JSON) — what this engine receives:
{
    "pdf": "<pdf reference>",
    "query": "find everything about entropy",
    "top_k": 5
}
"top_k" is optional (default 5) — only used for the semantic-search path.

OUTPUT (JSON) — what this engine returns:
{
    "answer": "Found 3 relevant passage(s) for 'entropy' (top match score 0.71). ...",
    "chunks": ["<relevant text chunk 1>", "<chunk 2>"]
}

"answer" here is a template-generated factual summary, not authored prose —
this project's own division of labour (README.md / PATHWAY.md) says engines
return raw facts and the moderator writes the explanation. There's no LLM
in this phase, so "answer" stays honest about being a template rather than
faking a written explanation.

Two query intents are handled for real:
  1. Explicit page range ("pages 42-47", "page 12") -> direct text slice,
     no semantic search needed.
  2. Everything else -> semantic search over the whole document.

Two intents from the original feature description are NOT implemented and
say so explicitly rather than faking a bad answer:
  - "summarize ch 3" (needs real chapter/heading structure detection)
  - "answer Q8" (needs real question-boundary detection)

Status: later phase
Composes three sibling engines (pdf_processing, rag/indexing,
rag/semantic_search) by loading their engine.py files directly via
importlib — feature folders don't import each other as packages yet (see
features/README.md), but re-deriving PDF extraction + chunking + embedding
from scratch here would just be duplicating three engines' worth of logic,
which is a worse tradeoff than the small duplication rag/semantic_search
already accepted. See this folder's README for the reasoning.
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path
from types import ModuleType
from typing import Any

_HERE = Path(__file__).resolve().parent
_FEATURES_ROOT = _HERE.parent.parent  # features/


def _load_sibling_engine(relative_path: str) -> ModuleType:
    """Load another feature's engine.py as a standalone module (no shared package)."""
    path = _FEATURES_ROOT / relative_path
    module_name = "searchable_knowledge_dep_" + relative_path.replace("/", "_")
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_pdf_processing = _load_sibling_engine("document_engine/pdf_processing/engine.py")
_rag_indexing = _load_sibling_engine("rag/indexing/engine.py")
_rag_semantic_search = _load_sibling_engine("rag/semantic_search/engine.py")

_PAGE_RANGE_RE = re.compile(r"\bpages?\s+(\d+)\s*(?:-|to|through)\s*(\d+)\b", re.IGNORECASE)
_SINGLE_PAGE_RE = re.compile(r"\bpage\s+(\d+)\b", re.IGNORECASE)
_UNSUPPORTED_INTENT_RE = re.compile(
    r"\b(?:summar\w*\s+(?:ch(?:apter)?|section)\b|\bch(?:apter)?\.?\s*\d+\b|\bq(?:uestion)?\.?\s*\d+\b)",
    re.IGNORECASE,
)


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"pdf": "<path>", "query": "...", "top_k"?: int}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    pdf_path = kwargs["pdf"]
    query = kwargs["query"]
    top_k = kwargs.get("top_k", 5)

    pdf_result = await _pdf_processing.run(pdf=pdf_path)
    pages: list[dict] = pdf_result["pages"]

    page_range = _parse_page_range(query)
    if page_range is not None:
        return _answer_page_range(pages, query, page_range)

    if _UNSUPPORTED_INTENT_RE.search(query):
        return {
            "answer": (
                f"'{query}' looks like a chapter- or question-numbered request, which this "
                "engine can't resolve yet, it has no chapter/heading or question-boundary "
                "detection. Falling back isn't attempted because a wrong page-based guess "
                "would be worse than saying so."
            ),
            "chunks": [],
        }

    return await _answer_semantic(pages, query, top_k)


# --- private helpers ---


def _parse_page_range(query: str) -> tuple[int, int] | None:
    match = _PAGE_RANGE_RE.search(query)
    if match:
        a, b = int(match.group(1)), int(match.group(2))
        return (a, b) if a <= b else (b, a)
    match = _SINGLE_PAGE_RE.search(query)
    if match:
        n = int(match.group(1))
        return (n, n)
    return None


def _answer_page_range(pages: list[dict], query: str, page_range: tuple[int, int]) -> dict:
    start, end = page_range
    selected = [p for p in pages if start <= p["number"] <= end]
    chunks = [p["text"] for p in selected if p["text"].strip()]
    answer = (
        f"Pages {start}-{end}: {len(chunks)} page(s) with text extracted directly "
        "(explicit page range, no semantic search needed)."
        if chunks
        else f"Pages {start}-{end}: no extractable text found on those pages."
    )
    return {"answer": answer, "chunks": chunks}


async def _answer_semantic(pages: list[dict], query: str, top_k: int) -> dict:
    documents = [p["text"] for p in pages if p["text"].strip()]
    if not documents:
        return {"answer": "This PDF has no extractable text to search.", "chunks": []}

    index_result = await _rag_indexing.run(documents=documents)
    search_result = await _rag_semantic_search.run(index=index_result["index"], query=query, top_k=top_k)
    results = search_result["results"]

    if not results:
        return {"answer": f"No relevant passages found for '{query}'.", "chunks": []}

    top_score = results[0]["score"]
    answer = (
        f"Found {len(results)} relevant passage(s) for '{query}' "
        f"(top match score {top_score:.2f}). See chunks for the actual text."
    )
    return {"answer": answer, "chunks": [r["chunk"] for r in results]}


if __name__ == "__main__":
    import asyncio
    import sys

    pdf_path = sys.argv[1] if len(sys.argv) > 1 else None
    query = sys.argv[2] if len(sys.argv) > 2 else None
    if not pdf_path or not query:
        print(f"[{__name__}] usage: python engine.py <path-to-pdf> \"<query>\"")
    else:
        result = asyncio.run(run(pdf=pdf_path, query=query))
        print("answer:", result["answer"])
        print("chunks returned:", len(result["chunks"]))
        enc = sys.stdout.encoding or "utf-8"
        for i, chunk in enumerate(result["chunks"]):
            snippet = chunk[:100].encode(enc, errors="replace").decode(enc)
            print(f"  [{i}] {snippet}...")
