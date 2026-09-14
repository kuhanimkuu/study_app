"""
Knowledge Spaces (blueprint Section 14) — formalizes the old sqlite3
`projects`/`generated_artifacts` tables. `parent_id` is new: a nullable
self-referencing FK enabling the nested hierarchy Section 14 describes
(e.g. "Mechanical Engineering" > "Fluid Mechanics") — the old flat
`projects` table had no such concept. No UI sets it yet (deliberately
deferred, see STUDY_OS_PROGRESS.md); it's cheap forward-compat, not
overbuilding.

`Material` is new too: the old system tracked ZERO metadata about
individual uploads — only the resulting text chunks, in a JSON file
(features/rag/projects/projects/user_<id>/<slug>.json, via
features/rag/projects's engine). That JSON file remains the actual chunk
storage/search mechanism this pass (Postgres+pgvector migration is
explicitly deferred); Material here only tracks "what was uploaded, when,
what kind" as real queryable rows — blueprint Section 32's `materials`
table, narrowed to what's needed now.
"""
from __future__ import annotations

import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ...db.base import Base


def _utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


class KnowledgeSpace(Base):
    __tablename__ = "knowledge_spaces"
    __table_args__ = (UniqueConstraint("user_id", "slug", name="uq_knowledge_spaces_user_slug"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    parent_id: Mapped[int | None] = mapped_column(
        ForeignKey("knowledge_spaces.id", ondelete="CASCADE"), nullable=True
    )
    slug: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    materials: Mapped[list["Material"]] = relationship(back_populates="knowledge_space", cascade="all, delete-orphan")
    artifacts: Mapped[list["GeneratedArtifact"]] = relationship(
        back_populates="knowledge_space", cascade="all, delete-orphan"
    )

    def public(self) -> dict:
        return {
            "id": self.id,
            "slug": self.slug,
            "display_name": self.display_name,
            "created_at": self.created_at.isoformat(),
        }


class Material(Base):
    __tablename__ = "materials"

    id: Mapped[int] = mapped_column(primary_key=True)
    knowledge_space_id: Mapped[int] = mapped_column(
        ForeignKey("knowledge_spaces.id", ondelete="CASCADE"), nullable=False, index=True
    )
    filename: Mapped[str] = mapped_column(String(500), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(100), nullable=False)
    status: Mapped[str] = mapped_column(String(50), nullable=False, default="indexed")
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    knowledge_space: Mapped[KnowledgeSpace] = relationship(back_populates="materials")

    def public(self) -> dict:
        return {
            "id": self.id,
            "filename": self.filename,
            "mime_type": self.mime_type,
            "status": self.status,
            "created_at": self.created_at.isoformat(),
        }


class GeneratedArtifact(Base):
    __tablename__ = "generated_artifacts"

    id: Mapped[int] = mapped_column(primary_key=True)
    knowledge_space_id: Mapped[int] = mapped_column(
        ForeignKey("knowledge_spaces.id", ondelete="CASCADE"), nullable=False, index=True
    )
    doc_type: Mapped[str] = mapped_column(String(50), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    url_path: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    knowledge_space: Mapped[KnowledgeSpace] = relationship(back_populates="artifacts")

    def public(self) -> dict:
        return {
            "id": self.id,
            "doc_type": self.doc_type,
            "title": self.title,
            "url": self.url_path,
            "created_at": self.created_at.isoformat(),
        }
