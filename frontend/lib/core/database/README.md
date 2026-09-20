# Database (local cache)

Status: **superseded — not planned** (updated 2026-09-16).

This placeholder described local storage as a thin cache under a
local-first architecture. That architecture was explicitly overridden
(STUDY_OS_PROGRESS.md, 2026-09-14): server-side Postgres is the source
of truth, and the app is not offline-capable at all. There is no
"local cache" concept left to build here — this isn't deferred work,
it's a stale placeholder for a plan that isn't happening.

The existing `lib/features/*/local_db.dart` files (chat history,
on-device activity events, BYOK settings) remain real, on-device state
by design — see `server/main.py`'s architecture note — just not a
"cache" of anything server-authoritative.
