"""
Query memory — answers personalization queries over activity events
("quiz me on what I struggled with yesterday").

INPUT (JSON) — what this engine receives, EITHER:
{
    "query": "what I struggled with yesterday",
    "events": [{"topic": "thermodynamics", "score": 0.4, "labels": ["struggle"], "timestamp": "2026-..."}]
}
(the project's local-first mode — the client submits its own locally-stored
events per-request; nothing server-side is read at all), OR the original
standalone/db-backed mode:
{
    "query": "what I struggled with yesterday",
    "user_id": 7,                // optional — scopes to one user's events
    "db_path": "memory.db"       // optional, defaults to personalization/memory_log/memory.db
}

OUTPUT (JSON) — what this engine returns:
{
    "events": [
        {"topic": "thermodynamics", "score": 0.4, "labels": ["struggle"]}
    ]
}

Status: later phase

ARCHITECTURE NOTE: this project moved to a local-first model where the
device (not the server) is the source of truth for chat history/progress
— see moderator/README.md's "local-first data" section. `events` is now
the primary way this engine gets called (features/moderator/engine.py's
memory_query route passes the client's submitted `local_events` straight
through); the `db_path` mode is kept because it's still real and correct
(and this file's own __main__ demo still exercises it), useful for
standalone testing or a future server-side admin/analytics use case, but
it's no longer what a live user-facing request goes through.

Query understanding is rule-based (regex/keyword matching), same honesty
level as the moderator's own intent inference:
  - a time phrase ("today" / "yesterday" / "this week" / "last week")
    filters by timestamp; no time phrase means all time.
  - "struggle"/"struggled"/"weak" filters to score < 0.6 or a "struggle" label.
  - any word matching an existing topic in the events matches by that topic.
"""
from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "memory_log" / "memory.db"

_STRUGGLE_RE = re.compile(r"\b(struggl\w*|weak|difficult|hard|confus\w*)\b", re.IGNORECASE)
_STRUGGLE_SCORE_THRESHOLD = 0.6


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"query": str, "events"?: list[dict]} (local-first mode)
                    or {"query": str, "user_id"?: int, "db_path"?: str} (db mode)
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    query: str = kwargs["query"]
    events_in: list[dict] | None = kwargs.get("events")

    if events_in is not None:
        rows = [(e.get("topic"), e.get("score"), e.get("labels") or [], e.get("timestamp")) for e in events_in]
    else:
        rows = _read_from_db(kwargs.get("user_id"), kwargs.get("db_path", DEFAULT_DB_PATH))

    known_topics = {r[0] for r in rows if r[0]}
    date_range = _parse_time_range(query)
    wants_struggles = bool(_STRUGGLE_RE.search(query))
    topic_filter = _match_topic(query, known_topics)

    events = []
    for topic, score, labels, timestamp in rows:
        if date_range is not None and timestamp is not None:
            event_date = datetime.fromisoformat(timestamp).date()
            if not (date_range[0] <= event_date <= date_range[1]):
                continue
        if wants_struggles and not ("struggle" in labels or (score is not None and score < _STRUGGLE_SCORE_THRESHOLD)):
            continue
        if topic_filter is not None and topic != topic_filter:
            continue

        events.append({"topic": topic, "score": score, "labels": labels})

    return {"events": events}


# --- private helpers ---


def _read_from_db(user_id: int | None, db_path: str | Path) -> list[tuple]:
    if not Path(db_path).exists():
        return []
    conn = sqlite3.connect(db_path)
    try:
        if user_id is not None:
            raw = conn.execute(
                "SELECT topic, score, labels, timestamp FROM events WHERE user_id = ?", (user_id,)
            ).fetchall()
        else:
            raw = conn.execute("SELECT topic, score, labels, timestamp FROM events").fetchall()
    finally:
        conn.close()
    return [(topic, score, json.loads(labels_json), timestamp) for topic, score, labels_json, timestamp in raw]


def _parse_time_range(query: str) -> tuple | None:
    query_lower = query.lower()
    now = datetime.now(timezone.utc)
    today = now.date()

    if "yesterday" in query_lower:
        d = today - timedelta(days=1)
        return (d, d)
    if "today" in query_lower:
        return (today, today)
    if "last week" in query_lower:
        start_of_this_week = today - timedelta(days=today.weekday())
        start_of_last_week = start_of_this_week - timedelta(days=7)
        end_of_last_week = start_of_this_week - timedelta(days=1)
        return (start_of_last_week, end_of_last_week)
    if "this week" in query_lower:
        start_of_this_week = today - timedelta(days=today.weekday())
        return (start_of_this_week, today)
    return None


def _match_topic(query: str, known_topics: set[str]) -> str | None:
    query_lower = query.lower()
    for topic in known_topics:
        if topic and topic.lower().replace("_", " ") in query_lower:
            return topic
    return None


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        # --- local-first mode: events submitted directly, no DB at all ---
        yesterday_iso = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        events = [
            {"topic": "thermodynamics", "score": 0.4, "labels": ["struggle", "thermo"], "timestamp": yesterday_iso},
            {"topic": "fluid_mechanics", "score": 0.9, "labels": ["quiz"], "timestamp": datetime.now(timezone.utc).isoformat()},
        ]
        for query in ["what did I struggle with yesterday?", "how did fluid mechanics go?", "everything"]:
            result = await run(query=query, events=events)
            print(f"(submitted-events mode) {query!r} -> {result['events']}")

        # --- db mode: still real, still tested (standalone/admin use case) ---
        import sys

        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "memory_log"))
        import engine as memory_log  # sibling engine, loaded directly for this demo only

        test_db = Path(__file__).resolve().parent / "query_memory_demo.db"
        test_db.unlink(missing_ok=True)
        await memory_log.run(db_path=test_db, event="quiz", topic="thermodynamics", score=0.4, labels=["struggle", "thermo"])
        import sqlite3 as _sqlite3

        conn = _sqlite3.connect(test_db)
        conn.execute("UPDATE events SET timestamp = ? WHERE topic = 'thermodynamics'", (yesterday_iso,))
        conn.commit()
        conn.close()
        result = await run(db_path=test_db, query="what did I struggle with yesterday?")
        print(f"(db mode) -> {result['events']}")
        test_db.unlink(missing_ok=True)

    asyncio.run(demo())
