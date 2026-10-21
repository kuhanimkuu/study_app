"""GET /api/account/export — "download my data" (2026-10-21). The privacy
policy promises students their data; Kenya's Data Protection Act (s. 26)
and the GDPR give them the right to a copy.

Walks every table instead of listing them, so a table added later is
exported without anyone remembering to add it here: a row belongs to the
student when its user_id is theirs, or when it hangs off a row that does
(a concept in their space, a question on their concept, ...).

Left out on purpose:
  - secrets: the password hash, the per-user encryption key and the
    token version;
  - the bytes of uploaded files (listed by name and size; they open from
    the app) and the search index, which is rebuilt from the materials."""
from __future__ import annotations

import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...db.base import Base

_SKIP_TABLES = {"users"}  # exported separately, without its secrets
_SKIP_COLUMNS = {
    "stored_files": {"data"},
    "project_indexes": {"data"},
}


def _jsonable(value):
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    return value


async def export_user_data(db: AsyncSession, user) -> dict:
    owned: dict[str, set[int]] = {"users": {user.id}}
    tables: dict[str, list[dict]] = {}
    for table in Base.metadata.sorted_tables:  # parents before children
        if table.name in _SKIP_TABLES:
            continue
        # The first foreign key that points at rows this student owns.
        link = next(
            (
                (column, owned[fk.column.table.name])
                for column in table.columns
                for fk in column.foreign_keys
                if fk.column.table.name in owned and column.name != "parent_id"
            ),
            None,
        )
        if link is None:
            continue
        column, parent_ids = link
        rows = (await db.execute(select(table).where(column.in_(parent_ids)))).mappings().all()
        skip = _SKIP_COLUMNS.get(table.name, set())
        tables[table.name] = [
            {key: _jsonable(value) for key, value in row.items() if key not in skip} for row in rows
        ]
        if "id" in table.columns:
            owned[table.name] = {row["id"] for row in rows}

    return {
        "exported_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "account": {**user.public(), "created_at": user.created_at.isoformat(), "google_linked": user.google_sub is not None},
        "tables": tables,
        "not_included": (
            "Your password and encryption key (secrets, never exported), the contents of uploaded "
            "files (listed under stored_files; open them from the app) and the search index "
            "(rebuilt from your materials)."
        ),
    }
