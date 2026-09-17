# Quizzes

Status: **implemented** (2026-09-16).

Sequential multi-question quiz flow (`QuizRunnerScreen`) — reuses
`QuestionAnswerInput` (extracted from `question_practice_screen.dart`)
per question and the existing `submitAttempt` grading path; no new
backend endpoint, this is purely a client-side sequencing feature over
the same per-question grading every other practice UI already uses.

Entry point: a "Start quiz" button on `ConceptDetailScreen`, shown once a
concept has 2+ authored questions. Ends with a correct/total summary
snackbar back on the concept screen.

Blueprint reference: Section 18 (Assessment Engine) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
