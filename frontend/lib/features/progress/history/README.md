# Progress history (target location)

Status: **implemented** — a different, real activity feed than originally anticipated here. `../presentation/screens/progress_screen.dart`'s "Recent activity" section shows a merged, reverse-chronological feed of `GET /api/v1/study-sessions` + the new `GET /api/v1/attempts`, reached via the Planner tab's 3rd "Progress" sub-tab.

This is NOT the same thing as `lib/features/history/` (unrenamed) — that screen is the on-device local-activity/`memory_query` chat feature and is untouched; the rename/move of that screen to this folder is still a separate, deliberately deferred cosmetic refactor (see `STUDY_OS_PROGRESS.md`).

Blueprint reference: Section 39 (Progress) of `STUDY_OS_PRODUCTION_BLUEPRINT.md`.
