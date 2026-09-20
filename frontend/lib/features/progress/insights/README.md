# Progress insights

Status: **implemented, folded into Progress** (2026-09-16).

Study streak, this-week accuracy, and a 7-day practice-activity bar
chart (`fl_chart`, already a dependency) — a new "Insights" section in
`../presentation/screens/progress_screen.dart`, computed entirely
client-side from the same merged activity feed the "Recent activity"
section already renders.

**Deliberately not a mastery-trend-over-time chart** — that would need
periodic mastery snapshots this project doesn't store yet (Mastery's
FSRS state is live-computed, not historized). These insights are
honestly derivable from existing timestamped data (`GET /api/v1/attempts`,
`GET /api/v1/study-sessions`), not a stand-in for real trend analysis.

Blueprint reference: Section 39 (Progress) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
