# Study sessions UI

Status: **implemented** (2026-09-16).

`GuidedSessionRunnerScreen` turns a `StudySession`'s static phase/concept
list into an actual walkthrough — per concept: explain it
(`explainConcept`), then practice up to 2 of its existing questions
(`listQuestions` + `submitAttempt`), then move to the next concept. Ends
by marking the session complete. No new backend capability — this is
pure client-side orchestration of endpoints that already existed
(explain/questions/attempts/complete), not a new Moderator-driven
"teaching" capability on the server.

Entry point: "Start guided session" on `study_session_screen.dart`,
alongside the existing plain "Mark complete" action (kept, for a student
who wants to skip straight to marking a session done).

**Deliberately capped at 2 practice questions per concept** — a session
whose length scaled with however many questions a concept happened to
have would make total session time unpredictable. A real, named scope
boundary, not an oversight.

Blueprint reference: Section 21 (Study Sessions) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
