"""
Indexing (chunking + embedding + vector index) — turns documents into a
searchable index for local RAG.

INPUT (JSON) — what this engine receives:
{
    "documents": ["<full document text 1>", "<full document text 2>"],
    "chunk_size": 500,     // optional, characters per chunk (default 500)
    "chunk_overlap": 50    // optional, characters of overlap between chunks (default 50)
}

Note: unlike the original skeleton's sample (which implied documents already
arrive pre-chunked), this engine does the chunking itself — that's what
"chunking + embedding + vector index" as a single feature actually means,
and it means callers (e.g. searchable_knowledge) can just hand over raw
document text instead of re-implementing chunking themselves.

OUTPUT (JSON) — what this engine returns:
{
    "index": {
        "chunks": ["<chunk text 1>", "<chunk text 2>", ...],
        "vectors": [[0.01, -0.02, ...], [...], ...],
        "model": "sentence-transformers/all-MiniLM-L6-v2"
    },
    "chunks": 1200
}

"index" is fully JSON-serializable (plain lists/dicts/floats) — no live
handles or DB connections — so it can be persisted or passed straight back
into rag/semantic_search's "index" input.

Status: later phase
Built on fastembed (ONNX runtime, no PyTorch) for embeddings — a real,
locally-run embedding model, not a keyword/TF-IDF stand-in.
"""
from __future__ import annotations

import sys
import types
from typing import Any

from fastembed import TextEmbedding

MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"

# --- memory (2026-10-07) ---
# Measured locally: embedding 400 chunks with fastembed's default
# batch_size (256) grew the process by ~858 MB; 16 by ~95 MB (same speed);
# 8 by ~51 MB (~35% slower). On Render's 512 MB instance the default crashed
# the server ("exceeded its memory limit") on a student's second PDF upload,
# and 16 still left only ~25 MB of headroom in a chat-then-upload worst case.
EMBED_BATCH_SIZE = 8

# This engine is loaded by file path from several places (server/engines.py,
# moderator, rag/projects, searchable_knowledge), and each load is a separate
# module with its own globals — so a per-module "singleton" meant up to five
# copies of the same ~100 MB model in one process. The registry lives in
# sys.modules, which every copy shares.
_REGISTRY_NAME = "_study_os_embedding_models"


def _shared_model(model_name: str) -> "TextEmbedding":
    registry = sys.modules.get(_REGISTRY_NAME)
    if registry is None:
        registry = types.ModuleType(_REGISTRY_NAME)
        registry.models = {}
        sys.modules[_REGISTRY_NAME] = registry
    model = registry.models.get(model_name)
    if model is None:
        model = TextEmbedding(model_name=model_name)
        registry.models[model_name] = model
    return model


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"documents": [...], "chunk_size"?: int, "chunk_overlap"?: int}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    documents = kwargs["documents"]
    chunk_size = kwargs.get("chunk_size", 500)
    chunk_overlap = kwargs.get("chunk_overlap", 50)

    chunks: list[str] = []
    for doc in documents:
        chunks.extend(_chunk_text(doc, chunk_size, chunk_overlap))

    vectors = _embed(chunks)

    return {
        "index": {"chunks": chunks, "vectors": vectors, "model": MODEL_NAME},
        "chunks": len(chunks),
    }


# --- private helpers ---


def _chunk_text(text: str, chunk_size: int, chunk_overlap: int) -> list[str]:
    """Fixed-size sliding-window chunking on word boundaries."""
    words = text.split()
    if not words:
        return []

    chunks = []
    start = 0
    while start < len(words):
        piece = []
        length = 0
        end = start
        while end < len(words) and length < chunk_size:
            length += len(words[end]) + 1
            piece.append(words[end])
            end += 1
        chunks.append(" ".join(piece))
        if end >= len(words):
            break
        # step forward, leaving `chunk_overlap` chars worth of words as overlap
        overlap_words = 0
        overlap_len = 0
        i = end - 1
        while i > start and overlap_len < chunk_overlap:
            overlap_len += len(words[i]) + 1
            overlap_words += 1
            i -= 1
        start = max(end - overlap_words, start + 1)
    return chunks


def _get_model() -> TextEmbedding:
    return _shared_model(MODEL_NAME)


def _embed(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    model = _get_model()
    return [vec.tolist() for vec in model.embed(texts, batch_size=EMBED_BATCH_SIZE)]


if __name__ == "__main__":
    import asyncio

    sample_docs = [
        "Entropy is a measure of disorder in a thermodynamic system. "
        "The second law of thermodynamics states that total entropy of an "
        "isolated system never decreases over time.",
        "Photosynthesis is the process by which green plants convert light "
        "energy into chemical energy stored in glucose, using carbon dioxide "
        "and water as inputs, releasing oxygen as a byproduct.",
    ]
    result = asyncio.run(run(documents=sample_docs, chunk_size=80, chunk_overlap=15))
    print("chunks:", result["chunks"])
    for i, chunk in enumerate(result["index"]["chunks"]):
        print(f"  [{i}] ({len(result['index']['vectors'][i])}-dim) {chunk[:70]}...")
