"""add ai_spend_limits (a student's own monthly AI spending cap)

Revision ID: e7b2c4d81a36
Revises: d3a9e6b15f42
Create Date: 2026-10-20

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'e7b2c4d81a36'
down_revision: Union[str, Sequence[str], None] = 'd3a9e6b15f42'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'ai_spend_limits',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('monthly_limit_cents', sa.Integer(), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_ai_spend_limits_user_id', 'ai_spend_limits', ['user_id'], unique=True)


def downgrade() -> None:
    op.drop_index('ix_ai_spend_limits_user_id', table_name='ai_spend_limits')
    op.drop_table('ai_spend_limits')
