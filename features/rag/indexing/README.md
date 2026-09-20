# Chunking + embedding + vector index

> Status: ⏳ later phase

- **Input:** documents
- **Output:** searchable index

## JSON shape

Input:
```json
{ "documents": ["<full document text 1>", "<full document text 2>"], "chunk_size": 500, "chunk_overlap": 50 }
```
`chunk_size`/`chunk_overlap` are optional (defaults 500/50, in characters). Unlike the original skeleton's sample input (which implied documents arrive pre-chunked), this engine does the chunking itself — that's what "chunking + embedding + vector index" as one feature actually means, and it saves every caller from reimplementing chunking.

Output:
```json
{
    "index": {
        "chunks": ["<chunk text 1>", "<chunk text 2>", "..."],
        "vectors": [[0.01, -0.02, "..."], ["..."]],
        "model": "sentence-transformers/all-MiniLM-L6-v2"
    },
    "chunks": 1200
}
```
`index` is fully JSON-serializable (plain lists/floats, no live handles) so it can be persisted or handed straight to `rag/semantic_search`'s `index` input.

## Notes

- Real embeddings, not a keyword/TF-IDF stand-in — uses `fastembed` (ONNX runtime, no PyTorch dependency, much lighter/faster to install than `sentence-transformers`) running `sentence-transformers/all-MiniLM-L6-v2` locally (384-dim vectors).
- Chunking (`_chunk_text`) is a fixed-size sliding window on word boundaries with overlap — simple by design; no sentence/paragraph-aware splitting yet.
- The embedding model is a lazy module-level singleton (`_get_model`) — first call downloads/loads it (~90MB, one-time, took ~4.5 min on this machine's connection), subsequent calls in the same process reuse it.
- Runs as an ordinary server-side Python dependency — no Chaquopy/Android on-device constraint applies (project direction is a server-hosted backend, not embedded Python on the phone).
- Tested standalone (`python engine.py`) and end-to-end with `rag/semantic_search` — a Newton's-law query against indexed thermodynamics/photosynthesis/mechanics text correctly ranked the mechanics chunk highest (score 0.70 vs 0.19).
