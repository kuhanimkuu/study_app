"""Async SQLAlchemy engine + session factory, and the FastAPI dependency
every domain router uses to get a request-scoped session."""
from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from ..core.config import get_settings

_settings = get_settings()

engine = create_async_engine(_settings.database_url, pool_pre_ping=True)

async_session = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency: `db: AsyncSession = Depends(get_db)`."""
    async with async_session() as session:
        yield session
