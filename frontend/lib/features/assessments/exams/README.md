# Exams

Status: **partially implemented as a display mode, not a new entity** (2026-09-16).

"Exam mode" is a toggle on `QuizRunnerScreen` (`../../practice/quizzes/`)
— per-question feedback is withheld until a final review screen at the
end, instead of shown immediately after each Submit. Entry point: an
"Exam mode" button next to "Start quiz" on `ConceptDetailScreen`.

**Deliberately not a real backend `Exam` entity** (grouped, timed,
formally graded as a distinct resource) — that's genuine new backend
scope, and overlaps with Quizzes in spirit. Every answer still grades
through the same `submitAttempt` call in real time; nothing is deferred
or graded differently server-side. A real gap if a true timed/formal
exam concept is wanted later, not silently dropped.

Blueprint reference: Section 18 (Assessment Engine) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
