# Query memory

> Status: ⏳ later phase

- **Input:** query ("quiz me on what I struggled with yesterday")
- **Output:** quiz (from memory)

## JSON shape

Input: `{ "query": "what I struggled with yesterday", "db_path": "memory.db" }` (`db_path` optional, defaults to `personalization/memory_log/memory.db`)
Output: `{ "events": [ { "topic": "thermodynamics", "score": 0.4, "labels": ["struggle"] } ] }`

## Notes

- Reads the same database `personalization/memory_log` writes to — shared datastore, not a shared import (feature folders don't import each other's code yet, see `features/README.md`).
- Query understanding is rule-based, same honesty level as the moderator's own intent inference — no LLM in this phase:
  - a time phrase (`"today"`/`"yesterday"`/`"this week"`/`"last week"`) filters by timestamp; no time phrase means all time.
  - `"struggle"`/`"struggled"`/`"weak"`/`"difficult"`/`"confused"` filters to events with a `"struggle"` label or `score < 0.6`.
  - any word in the query matching an existing topic in the database filters by that topic.
- Tested standalone against a 2-event scratch DB with one event backdated to "yesterday": `"what did I struggle with yesterday?"` correctly returned only the backdated, low-score, struggle-labelled event; a topic-specific query and an unfiltered query both returned correctly too.
