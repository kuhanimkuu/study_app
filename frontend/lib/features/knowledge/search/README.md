# Knowledge search

Status: **implemented, scoped down** (2026-09-16).

A standalone semantic search UI within a Knowledge Space — a 7th tab on
`ProjectWorkspaceScreen` (`KnowledgeSearchScreen`). Hits
`GET /api/v1/knowledge-spaces/{slug}/search` and renders raw ranked
chunks directly (chunk text + match %), unlike the Chat tab's
`/api/ask/project` which returns a conversational response over the same
material.

**Scoped down from blueprint Section 13's full "Hybrid Retrieval"**:
semantic search only (fastembed cosine similarity over the existing
per-space chunk index) — no keyword search, metadata filtering,
reranking, or knowledge-graph-relationship blending yet. Those remain
real, named gaps, not silently dropped.

See `STUDY_OS_PROGRESS.md`'s 2026-09-16 entry for what shipped.
