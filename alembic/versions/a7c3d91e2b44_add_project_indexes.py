"""add project_indexes (durable copy of each Knowledge Space's RAG index)

Revision ID: a7c3d91e2b44
Revises: e31e0280538f
Create Date: 2026-10-07

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'a7c3d91e2b44'
down_revision: Union[str, Sequence[str], None] = 'e31e0280538f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'project_indexes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('knowledge_space_id', sa.Integer(), nullable=False),
        sa.Column('data', sa.Text(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['knowledge_space_id'], ['knowledge_spaces.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('knowledge_space_id'),
    )


def downgrade() -> None:
    op.drop_table('project_indexes')
