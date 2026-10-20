"""
Prints the app's crash reports, most frequent first. On the server:

    study-os-errors            # last 7 days
    study-os-errors 30         # last 30 days

(the same as: cd /opt/study_os && .venv/bin/python -m server.domains.diagnostics.report)
"""
from __future__ import annotations

import asyncio
import datetime
import sys

from sqlalchemy import func, select

from ...db.session import async_session
from ..identity import models as _identity_models  # noqa: F401  (users table, for the foreign key)
from .models import ClientError


async def main(days: int) -> None:
    since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
    async with async_session() as db:
        rows = (await db.execute(
            select(
                ClientError.fingerprint,
                func.sum(ClientError.count).label("times"),
                func.count(func.distinct(ClientError.user_id)).label("students"),
                func.max(ClientError.last_seen).label("last"),
                func.max(ClientError.app_version).label("version"),
                func.min(ClientError.message).label("message"),
                func.min(ClientError.stack).label("stack"),
            )
            .where(ClientError.last_seen >= since)
            .group_by(ClientError.fingerprint)
            .order_by(func.sum(ClientError.count).desc())
        )).all()

    if not rows:
        print(f"No app errors reported in the last {days} days.")
        return
    print(f"App errors in the last {days} days ({len(rows)} distinct):\n")
    for r in rows:
        print(f"[{r.times}x, {r.students} signed-in student(s), last {r.last:%Y-%m-%d %H:%M} UTC, v{r.version}]")
        print("  " + r.message.strip().splitlines()[0][:300])
        for line in r.stack.strip().splitlines()[:5]:
            print("    " + line[:200])
        print()


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]) if len(sys.argv) > 1 else 7))
