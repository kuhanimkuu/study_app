"""
Memory log — records labelled activity events for personalization
("quiz me on what I struggled with yesterday").

INPUT (JSON) — what this engine receives:
{
    "event": "quiz",
    "topic": "thermodynamics",
    "score": 0.4,
    "labels": ["struggle", "thermo", "quiz"],
    "user_id": 7,                // optional — scopes the entry to a real account (server/db.py's users table)
    "db_path": "memory.db"       // optional, defaults to this folder's memory.db
}

OUTPUT (JSON) — what this engine returns:
{
    "status": "logged",
    "event_id": 7
}

Status: later phase
Built on stdlib sqlite3 — this is the real, persistent version of the
in-memory stub PATHWAY.md sanctions for the moderator's own state
("Memory log: in-memory list -> SQLite/JSON file later"). This engine IS
that "later". personalization/query_memory reads from the same database
file (default "memory.db" next to this engine.py) rather than importing
this module — sharing a datastore, not sharing code, same as any two
services backed by the same DB.

`user_id` is nullable — this engine and its schema predate real user
accounts (added when server/'s auth system was built) and stayed
independently testable/usable without one; a None user_id just means the
entry isn't tied to any account (e.g. this file's own __main__ demo).
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_DB_PATH = Path(__file__).resolve().parent / "memory.db"


def _connect(db_path: str | Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event TEXT NOT NULL,
            topic TEXT,
            score REAL,
            labels TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            user_id INTEGER
        )
        """
    )
    try:
        # migrates a pre-accounts database created before user_id existed
        conn.execute("ALTER TABLE events ADD COLUMN user_id INTEGER")
    except sqlite3.OperationalError:
        pass  # column already exists — the CREATE TABLE above already covers fresh databases
    return conn


async def run(**kwargs: Any) -> dict:
    """Sole entry point the moderator calls.

    Args (kwargs): {"event": str, "topic"?: str, "score"?: float, "labels"?: list[str],
                     "user_id"?: int, "db_path"?: str}
    Returns: dict matching OUTPUT above — always JSON-serializable.
    """
    event: str = kwargs["event"]
    topic: str | None = kwargs.get("topic")
    score: float | None = kwargs.get("score")
    labels: list[str] = kwargs.get("labels", [])
    user_id: int | None = kwargs.get("user_id")
    db_path = kwargs.get("db_path", DEFAULT_DB_PATH)

    timestamp = datetime.now(timezone.utc).isoformat()

    conn = _connect(db_path)
    try:
        cursor = conn.execute(
            "INSERT INTO events (event, topic, score, labels, timestamp, user_id) VALUES (?, ?, ?, ?, ?, ?)",
            (event, topic, score, json.dumps(labels), timestamp, user_id),
        )
        conn.commit()
        event_id = cursor.lastrowid
    finally:
        conn.close()

    return {"status": "logged", "event_id": event_id}


if __name__ == "__main__":
    import asyncio

    async def demo() -> None:
        test_db = Path(__file__).resolve().parent / "memory_demo.db"
        test_db.unlink(missing_ok=True)  # clean slate for a repeatable demo

        events = [
            {"event": "quiz", "topic": "thermodynamics", "score": 0.4, "labels": ["struggle", "thermo", "quiz"], "user_id": 1},
            {"event": "quiz", "topic": "fluid_mechanics", "score": 0.9, "labels": ["quiz"], "user_id": 1},
            {"event": "solve", "topic": "algebra", "score": None, "labels": ["math"], "user_id": 2},
        ]
        for e in events:
            result = await run(db_path=test_db, **e)
            print(result)

        conn = sqlite3.connect(test_db)
        rows = conn.execute("SELECT id, event, topic, score, labels, timestamp, user_id FROM events").fetchall()
        conn.close()
        print(f"\n{len(rows)} rows persisted in {test_db.name}:")
        for row in rows:
            print(" ", row)

        test_db.unlink(missing_ok=True)  # demo cleanup — a real deployment keeps the db

    asyncio.run(demo())
