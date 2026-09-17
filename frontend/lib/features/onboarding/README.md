# Onboarding

Status: **implemented** (2026-09-16).

A skippable first-run screen (`OnboardingScreen`), shown once immediately
after signup — `AuthGate` checks `AuthService.justSignedUp` (set only by
a real `signup()` call in the current app session, never by `login()` or
session restore, so a returning user never sees it again). Reuses the
exact same `updateStudentProfile()` the Account screen's "Student
profile" section already calls — this is the same data, filled in now or
later, not a separate onboarding-only record.

Every field is optional; "Skip" and an empty "Get started" both do the
same thing (dismiss without saving).

Blueprint reference: Section 5 (Student Profile) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md` — "a student should be able to sign in
and immediately start studying."
