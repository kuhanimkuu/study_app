# Projects

> Status: ✅ wired up — reachable via `server/routers/projects.py`'s `/api/projects/{slug}/material` endpoint (the moderator's `_route_project` only ever queried this engine's output before; creating/updating a project now has a real caller)

- **Input:** material
- **Output:** organized knowledge (Thermodynamics, Fluid Mechanics...)

## JSON shape

Input: `{ "project": "thermodynamics", "material": ["<doc 1>", "<doc 2>"], "projects_dir": "projects" }` (`projects_dir` optional)
Output: `{ "project": "thermodynamics", "status": "created" | "updated", "chunks": 340 }`

## Notes

- Composes `rag/indexing` (loaded via `importlib`, same pattern used elsewhere in this project) rather than reimplementing chunking/embedding.
- **Persistent and additive**, unlike a bare `rag/indexing` call: each project's index is saved to `<projects_dir>/<project>.json` (same shape `rag/indexing` returns internally) and new material is *appended* to what's already there, not replaced — a project accumulates across multiple calls/server restarts.
- This engine only manages storage/updates. To search within a project, load its persisted JSON file and pass it straight to `rag/semantic_search`'s `index` input — no separate search function is needed here, `rag/semantic_search` already does that job generically.
- Tested standalone: indexing two separate material batches into the same project correctly went `created` (1 chunk) then `updated` (2 chunks, accumulated) rather than overwriting.
- **Now called for real, per-user-scoped.** `server/routers/projects.py` calls this with `projects_dir` set to `rag/projects/projects/user_<id>/` (via `moderator/engine.py`'s `_user_projects_dir`), not the module-level default — so two different users can both have a project named "thermodynamics" without collision. Verified end-to-end over real HTTP: create → add text → add more text (accumulates: 1 chunk → 2) → query via `/api/ask/project` (correctly ranked the entropy chunk above the unrelated enthalpy chunk for "what is entropy?") → delete (removes both the DB row and the JSON file) → a second user creating an identically-named project confirmed no cross-user collision.
