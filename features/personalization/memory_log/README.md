# Memory log

> Status: ⏳ later phase

- **Input:** activity events
- **Output:** labelled memory log (subjects, topics, weak areas, quiz performance, study history)

## JSON shape

Input: `{ "event": "quiz", "topic": "thermodynamics", "score": 0.4, "labels": ["struggle", "thermo", "quiz"], "db_path": "memory.db" }` (`topic`/`score`/`labels`/`db_path` optional)
Output: `{ "status": "logged", "event_id": 7 }`

## Notes

- Built on stdlib `sqlite3` — this is the real, persistent version of the in-memory stub `PATHWAY.md` explicitly sanctions for the moderator's own state ("Memory log: in-memory list -> SQLite/JSON file later"). **This is wired in for real now** — `features/moderator/engine.py`'s `_log_event` calls this engine after every successfully resolved request (not clarifications), replacing the in-memory `_memory_log` list that used to be there.
- `personalization/query_memory` reads from the same database file (default `memory.db` next to this `engine.py`) — a shared datastore, not a shared import, same as any two services backed by the same DB.
- Tested standalone: logged 3 events to a scratch DB, confirmed all 3 persisted correctly via a direct SQL read.
