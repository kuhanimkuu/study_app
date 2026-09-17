# Shared widgets

Status: **implemented, minimally** (2026-09-16).

`AsyncListView<T>` — the loading/error/empty/list 4-branch pattern every
list screen in this app (Concepts, Flashcards, Notes, Goals, Projects,
...) already wrote by hand, extracted once it was clearly the same shape
everywhere. Adopted in Flashcards and Notes; older list screens are
untouched, working code, not retrofitted just to use this.

Blueprint reference: Section 29 (Flutter Product Structure) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
