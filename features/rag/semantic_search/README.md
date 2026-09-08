# Semantic search

> Status: ⏳ later phase

- **Input:** query
- **Output:** relevant chunks

## JSON shape

Input:
```json
{ "index": { "chunks": ["..."], "vectors": [["..."]], "model": "..." }, "query": "what is entropy?", "top_k": 5 }
```
`index` is exactly what `rag/indexing` returns as its `index` field. `top_k` is optional (default 5).

Output:
```json
{ "results": [ { "chunk": "<text>", "score": 0.91 }, { "chunk": "<text>", "score": 0.87 } ] }
```
`results` is sorted by `score` descending (cosine similarity, roughly -1 to 1 in practice mostly 0-1 for real text).

## Notes

- Built on `fastembed` (ONNX runtime, no PyTorch) — embeds the query with the same `sentence-transformers/all-MiniLM-L6-v2` model `rag/indexing` used, then ranks stored chunk vectors by cosine similarity (`numpy`).
- Deliberately duplicates the small embedding-loading code from `rag/indexing/engine.py` rather than importing it — per `features/README.md`, feature folders don't import each other yet (that's added once the moderator starts wiring engines together).
- Runs as an ordinary server-side Python dependency — no Chaquopy/Android on-device constraint applies (project direction is a server-hosted backend).
- Tested standalone and end-to-end with `rag/indexing`: correctly ranked a mechanics-related chunk far above an unrelated thermodynamics chunk for a Newton's-law query (0.70 vs 0.19).
