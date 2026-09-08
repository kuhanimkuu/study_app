# Searchable knowledge

> Status: ⏳ later phase

- **Input:** PDF + query
- **Output:** "summarize ch 3" / "find everything about entropy" / "explain pages 42-47" / "answer Q8"

## JSON shape

Input:
```json
{ "pdf": "<path to pdf file>", "query": "find everything about entropy", "top_k": 5 }
```
`top_k` is optional (default 5, only used for the semantic-search path).

Output:
```json
{ "answer": "Found 3 relevant passage(s) for 'entropy' (top match score 0.71). See chunks for the actual text.", "chunks": ["<chunk 1>", "<chunk 2>"] }
```
`answer` is a **template-generated factual summary, not authored prose** — per this project's own division of labour (engines return facts, the moderator writes the explanation), and there's no LLM in this phase to author one honestly. It says what was found, not what it means.

## Notes

- Composes three sibling engines rather than reimplementing their logic: `document_engine/pdf_processing` (text extraction), `rag/indexing` (chunk + embed), `rag/semantic_search` (rank by relevance). Loaded via `importlib.util.spec_from_file_location` directly from their file paths — feature folders don't import each other as packages yet (see `features/README.md`), but re-deriving PDF extraction + chunking + embedding from scratch here would mean duplicating three engines' worth of real logic, which is a worse tradeoff than this file-path-based loading.
- Two query intents are genuinely implemented:
  1. **Explicit page range** ("pages 42-47", "page 12") — direct text slice from `pdf_processing`'s per-page output, no semantic search involved.
  2. **Everything else** — full semantic search over the whole document via the RAG pipeline.
- Two intents from the original feature description are **not implemented, and say so explicitly** rather than faking a bad answer: "summarize ch 3" and "answer Q8" — both need real document-structure detection (chapter/heading boundaries, question numbering) that doesn't exist yet. A regex (`_UNSUPPORTED_INTENT_RE`) catches these and returns an honest "can't resolve yet" answer with empty `chunks`, instead of silently guessing.
- Every PDF query re-chunks and re-embeds the whole document from scratch (no caching of `rag/indexing`'s output across calls) — fine for a single-document demo, but worth revisiting once this is wired into a real request flow with repeat queries against the same PDF.
- Runs as ordinary server-side Python — no Chaquopy/Android on-device constraint applies (project direction is a server-hosted backend).
- Tested against `study_os_overview-v2.pdf` (the real 17-page spec doc) for all three paths: a semantic query ("what does the moderator do?") returned genuinely relevant passages about the moderator's role; an explicit page-range query ("explain pages 1-2") returned exactly those two pages' text; an unsupported-intent query ("summarize chapter 3") correctly declined instead of guessing.
