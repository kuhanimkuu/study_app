# Calendar

Status: **implemented** (2026-09-16).

A month-grid calendar (`PlannerCalendarScreen`) — a 4th tab on
`PlannerScreen`, alongside Plan/Goals/Progress. Marks Goal deadlines
(orange), Concept review dates from Mastery's FSRS `next_review` (theme
color), and Flashcard due dates (blue). Tapping a marked day lists
what's due.

Plain custom `GridView`, not a calendar package — no such dependency
existed yet and a month grid doesn't need one (blueprint Section 55.12,
"don't overengineer").

One small backend addition: `GET /api/v1/flashcards` (account-wide, every
card regardless of due status — a one-line sibling of the existing
due-only `GET /api/v1/flashcards/due`), since the calendar needs to plot
*upcoming* reviews, not just ones already due today.

Blueprint reference: Section 22 (Planner) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
