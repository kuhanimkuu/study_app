"""add users.token_version (sign out everywhere / password change)

Revision ID: a1d5f3c97e20
Revises: f4c8a2e65b19
Create Date: 2026-10-21

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'a1d5f3c97e20'
down_revision: Union[str, Sequence[str], None] = 'f4c8a2e65b19'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('token_version', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('users', 'token_version')
