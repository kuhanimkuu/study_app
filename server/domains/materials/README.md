# Materials domain

Status: **not yet implemented** (placeholder from the target project structure).

Will eventually own material versions/sources beyond the metadata rows added this pass in domains/knowledge (Material model) — full RAG pipeline (validate -> security scan -> extract -> chunk -> embed -> index) formalization, including the Postgres+pgvector migration of chunk storage (currently still JSON+fastembed via features/rag/).

Blueprint reference: Section 12 (RAG Strategy) of `STUDY_OS_PRODUCTION_BLUEPRINT.md`.
See `STUDY_OS_PROGRESS.md` for the staged build order this fits into.
