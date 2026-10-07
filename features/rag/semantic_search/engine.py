"""
Semantic search — finds the most relevant chunks for a query over the index
built by rag/indexing.

INPUT (JSON) — what this engine receives:
{
    "index": { "chunks": [...], "vectors": [[...], ...], "model": "..." },  // from rag/indexing's output
    "query": "what is entropy?",
    "top_k": 5
}

OUTPUT (JSON) — what this engine returns:
{
    "results": [
        {"chunk": "<text>", "score": 0.91},
        {"chunk": "<text>", "score": 0.87}
    ]
}

Status: later phase
Built on fastembed (ONNX runtime, no PyTorch) — embeds the query with the
same model rag/indexing used, then ranks chunks by cosine similarity.

Note: duplicates a small amount of embedding code from rag/indexing/engine.py
rather than importing it — per features/README.md, feature folders don't
import each other yet (that's added once the moderator starts wiring
engines together).
"""
from __future__ import annotations

import sys
import types
from typing import Any

import numpy as np
from fastembed import TextEmbedding

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

    Args (kwargs): {"index": {...}, "query": "...", "top_k"?: int}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    index = kwargs["index"]
    query = kwargs["query"]
    top_k = kwargs.get("top_k", 5)

    chunks: list[str] = index["chunks"]
    vectors: list[list[float]] = index["vectors"]

    if not chunks:
        return {"results": []}

    query_vector = _embed([query])[0]
    scores = _cosine_similarities(query_vector, vectors)

    ranked = sorted(zip(chunks, scores), key=lambda pair: pair[1], reverse=True)
    top = ranked[:top_k]

    return {"results": [{"chunk": chunk, "score": score} for chunk, score in top]}


# --- private helpers ---


def _get_model() -> TextEmbedding:
    return _shared_model("sentence-transformers/all-MiniLM-L6-v2")


def _embed(texts: list[str]) -> list[list[float]]:
    model = _get_model()
    return [vec.tolist() for vec in model.embed(texts, batch_size=EMBED_BATCH_SIZE)]


def _cosine_similarities(query_vector: list[float], vectors: list[list[float]]) -> list[float]:
    q = np.array(query_vector)
    m = np.array(vectors)
    q_norm = q / np.linalg.norm(q)
    m_norms = m / np.linalg.norm(m, axis=1, keepdims=True)
    return (m_norms @ q_norm).tolist()


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        sample_docs = [
            "Entropy is a measure of disorder in a thermodynamic system. "
            "The second law of thermodynamics states that total entropy of an "
            "isolated system never decreases over time.",
            "Photosynthesis is the process by which green plants convert light "
            "energy into chemical energy stored in glucose, using carbon dioxide "
            "and water as inputs, releasing oxygen as a byproduct.",
        ]
        # Build a tiny index inline (rag/indexing's own chunker, duplicated
        # minimally here just for this demo — see rag/indexing/engine.py for
        # the real chunking implementation).
        chunks = sample_docs
        vectors = _embed(chunks)
        index = {"chunks": chunks, "vectors": vectors, "model": "sentence-transformers/all-MiniLM-L6-v2"}

        result = await run(index=index, query="what does the second law of thermodynamics say?", top_k=2)
        for r in result["results"]:
            print(f"  score={r['score']:.3f}  {r['chunk'][:80]}...")

    asyncio.run(demo())
