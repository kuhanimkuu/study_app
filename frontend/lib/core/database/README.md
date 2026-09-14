# Database (local cache)

Status: **not yet implemented** (placeholder from the target project structure).

Given this session's data-ownership decision (server-side Postgres is the source of truth, no sync engine), local storage here is a thin cache/offline-read convenience at most, not the source of truth the current lib/features/*/local_db.dart files assume - to be reconciled when the frontend restructure happens.

Blueprint reference: Decision log: STUDY_OS_PROGRESS.md, 2026-09-14 data-ownership entry of `STUDY_OS_PRODUCTION_BLUEPRINT.md`.
See `STUDY_OS_PROGRESS.md` for the staged build order this fits into.
