# Shared widgets

Status: **implemented, minimally** (2026-09-17).

`AsyncListView<T>` — the loading/error/empty/list 4-branch pattern every
list screen in this app (Concepts, Flashcards, Notes, Goals, Projects,
...) already wrote by hand, extracted once it was clearly the same shape
everywhere. Adopted in Flashcards and Notes; older list screens are
untouched, working code, not retrofitted just to use this.

`GradientButton` — the one primary-action button style in the design
system (see `app/theme.dart`), filled with `StudyOsColors.brandGradient`.
Reserved for the single most important action on a screen (log in, sign
up, start a quiz/guided session) — every other button stays a plain
themed `ElevatedButton`/`OutlinedButton`/`TextButton` so the gradient
stays a signal, not decoration.

`ListItemCard` — the icon-led row anatomy for list screens (Projects,
Flashcards, Notes, Goals, Home's goal list); `EmptyState` — the
icon+message shape for a single informational message on its own
screen/tab, no list involved (`AsyncListView` has the same shape built
in for list screens). `BrandWordmark` — the app's name in the brand
gradient, for the few places it appears as a heading (Chat's AppBar,
the splash screen).

Blueprint reference: Section 29 (Flutter Product Structure) of
`STUDY_OS_PRODUCTION_BLUEPRINT.md`.
