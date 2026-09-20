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

from typing import Any

import numpy as np
from fastembed import TextEmbedding

_model: TextEmbedding | None = None  # lazy singleton — loading it is expensive


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
    global _model
    if _model is None:
        _model = TextEmbedding(model_name="sentence-transformers/all-MiniLM-L6-v2")
    return _model


def _embed(texts: list[str]) -> list[list[float]]:
    model = _get_model()
    return [vec.tolist() for vec in model.embed(texts)]


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
