"""SQLAlchemy declarative base — every domain's models.py inherits from
this so Alembic's autogenerate can discover all tables from one place
(see alembic/env.py, which imports every domains/*/models.py before
calling target_metadata=Base.metadata).

The naming_convention gives every constraint (not just primary keys, which
Postgres/SQLAlchemy already name deterministically) a predictable,
autogenerate-friendly name instead of leaving it to Postgres's own default
(e.g. `<table>_<column>_fkey`, which Alembic can only render into a
migration as a post-hoc "detected" string, not something it can reliably
regenerate for a brand-new constraint — found the hard way: autogenerating
a migration that alters an existing FK's ondelete rendered `create_foreign_
key(None, ...)`, which is fine for upgrade() but makes downgrade()
unrunnable, since the new constraint's name doesn't exist yet at migration-
authoring time). This only affects constraints created from here on;
existing ones keep their Postgres-assigned names until they're next
altered."""
from __future__ import annotations

from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

_NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=_NAMING_CONVENTION)
