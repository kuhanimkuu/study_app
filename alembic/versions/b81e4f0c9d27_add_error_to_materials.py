"""add error to materials (background indexing failures)

Revision ID: b81e4f0c9d27
Revises: a7c3d91e2b44
Create Date: 2026-10-07

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'b81e4f0c9d27'
down_revision: Union[str, Sequence[str], None] = 'a7c3d91e2b44'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('materials', sa.Column('error', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('materials', 'error')
