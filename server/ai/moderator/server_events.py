"""
Builds "local_event"-shaped entries ({topic, score, labels, timestamp})
from real Postgres data (Mastery, Misconception) — feeds the existing
local-first `memory_query` route (`features/moderator/engine.py`'s
`_route_memory_query`, via `features/personalization/query_memory`) real
server-side signal, not just whatever the client happens to have
submitted as `local_events`.

This closes a real gap: `/api/ask/text`'s "what did I struggle with"
query only ever read client-submitted `local_events` — a local-first-era
design that predates this session's data-ownership decision (server-side
Postgres is now the source of truth). Rather than rewrite `query_memory`'s
already-correct query-understanding logic (time phrases, struggle
filtering, topic matching), this feeds it real data in the exact shape it
already expects — `server/routers/ask.py` merges this with the client's
own `local_events` before calling the moderator, so the query-parsing
logic itself is untouched.

Performance note (deliberate, not overlooked): this runs on every
`/api/ask/text` call, not only ones that turn out to be memory queries —
avoiding that would mean either duplicating `features/moderator/engine.py`'s
private `_MEMORY_QUERY_RE` detection here (fragile: two copies to keep in
sync) or changing the moderator's stable `run()` signature to accept a
lazy provider (a bigger, riskier change to a well-tested file). Two simple
indexed queries against one user's own (currently small) concept count is
cheap enough at this project's actual scale to not be worth either.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...domains.assessment.models import Misconception
from ...domains.learning.models import Concept, Mastery
from ...domains.learning.scheduler import mastery_score


async def get_server_side_events(db: AsyncSession, user_id: int) -> list[dict]:
    events: list[dict] = []

    mastery_rows = (
        await db.execute(
            select(Mastery, Concept.name)
            .join(Concept, Concept.id == Mastery.concept_id)
            .where(Mastery.user_id == user_id)
        )
    ).all()
    for mastery, concept_name in mastery_rows:
        if mastery.attempts == 0:
            continue
        score = mastery_score(mastery)
        last_touched = mastery.last_correct_at or mastery.last_incorrect_at
        events.append(
            {
                "topic": concept_name,
                "score": score,
                "labels": ["struggle"] if score < 0.5 else ["reviewed"],
                "timestamp": last_touched.isoformat() if last_touched else None,
            }
        )

    misconception_rows = (
        await db.execute(
            select(Misconception, Concept.name)
            .join(Concept, Concept.id == Misconception.concept_id)
            .where(Misconception.user_id == user_id, Misconception.resolved_at.is_(None))
        )
    ).all()
    for misconception, concept_name in misconception_rows:
        events.append(
            {
                "topic": concept_name,
                "score": 0.0,
                "labels": ["struggle", "misconception"],
                "timestamp": misconception.detected_at.isoformat(),
            }
        )

    return events
