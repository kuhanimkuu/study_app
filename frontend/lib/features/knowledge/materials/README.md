# Materials browser

Status: **implemented, read-only** (2026-09-16).

Upload history (filename/type/upload date) now lists at the bottom of the
existing Sources tab in `project_workspace_screen.dart`, backed by
`GET /api/projects/{slug}/materials`.

**Deliberately no delete-per-material**: a material's chunks live merged
into this space's shared search index (`features/rag/projects`), not
tagged by which upload they came from — deleting the metadata row without
also removing its chunks would be misleading (the UI would say it's gone
while its content still answers searches). A real gap, not an oversight;
would need the chunk-storage format to track a source material id first.

Blueprint reference: Section 12 (RAG Strategy) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
