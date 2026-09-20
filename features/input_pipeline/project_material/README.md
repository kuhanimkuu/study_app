# Project material

> Status: ⏳ later phase

- **Input:** project reference ("my Fluid Mechanics project")
- **Output:** stored knowledge context

## JSON shape

Input: `{ "content": "my Fluid Mechanics project", "project": "fluid_mechanics", "projects_dir": "projects" }` (`projects_dir` optional)
Output: `{ "input_type": "project", "content": "my Fluid Mechanics project", "project": "fluid_mechanics", "context": ["<chunks>"] }`

## Notes

- Reads the same project file `rag/projects` writes to (default `rag/projects/projects/<project>.json`) — a shared datastore, not a shared import, same convention as `personalization/query_memory` reading `personalization/memory_log`'s database.
- Resolving `"my Fluid Mechanics project"` -> `"fluid_mechanics"` (the `project` field) is assumed already done by the caller — this engine doesn't attempt name-resolution/fuzzy-matching, only accepts an already-resolved slug.
- An unknown project returns `context: []` rather than an error — honest "nothing stored yet."
- Tested end-to-end: created a `fluid_mechanics` project via `rag/projects` with one material chunk, then resolved it here — the exact chunk came back correctly.
