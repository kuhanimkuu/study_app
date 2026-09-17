# Flashcards

Status: **implemented** (2026-09-16).

Spaced-repetition flashcard review UI — a 5th tab on `ProjectWorkspaceScreen`
(`FlashcardsListScreen`: create/list/delete) plus `FlashcardReviewScreen`
(flip-card review, rated on the full FSRS scale: Again/Hard/Good/Easy).

Backend: `server/domains/learning/models.py`'s `Flashcard` +
`flashcard_scheduler.py`, endpoints under `/api/v1/knowledge-spaces/{slug}/
flashcards` and `/api/v1/flashcards/*`.

Blueprint reference: Sections 17 (Spaced Repetition) and 27 (Generated
Study Content) of `STUDY_OS_PRODUCTION_BLUEPRINT.md`. See
`STUDY_OS_PROGRESS.md`'s 2026-09-16 entry for what shipped and what was
deliberately deferred (no separate `flashcard_reviews` history table,
no AI-generation of cards from material this pass — authored manually only).
