# Background workers

Status: one worker so far — `cleanup.py` (2026-10-19), a periodic in-process task started from `server/main.py`'s lifespan that deletes old uploads and chat-generated files and orphaned per-user folders. A real queue/worker system is still not implemented (placeholder from the target project structure).

Queue/worker system for long-running work (PDF processing, OCR, embeddings, transcription, document generation) once request volume justifies moving it out of the HTTP request path.

Blueprint reference: Section 34 (Background Jobs) of `STUDY_OS_PRODUCTION_BLUEPRINT.md`.
See `STUDY_OS_PROGRESS.md` for the staged build order this fits into.
