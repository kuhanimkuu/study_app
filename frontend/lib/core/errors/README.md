# Error handling

Status: **implemented, minimally** (2026-09-16).

`error_presentation.dart`'s `showApiError(context, error)` — every screen
already caught `ApiException` and showed its `.message` in a SnackBar by
hand; this is that one line, named, so new screens reuse it instead of
reinventing it. Adopted in the two newest list screens (Flashcards,
Notes) as the real "not over-specialized to one call site" check; older
screens are untouched, working code, not retrofitted just to use this.

Deliberately not a bigger error-classification system (retry policies,
offline banners) — this app has no offline mode to design around.

Blueprint reference: Section 29 (Flutter Product Structure) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
