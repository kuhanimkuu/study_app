"""add ai_usage (the student-facing token meter)

Revision ID: d3a9e6b15f42
Revises: c5f2a8e71d03
Create Date: 2026-10-20

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'd3a9e6b15f42'
down_revision: Union[str, Sequence[str], None] = 'c5f2a8e71d03'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'ai_usage',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('provider', sa.String(length=20), nullable=False),
        sa.Column('model_name', sa.String(length=100), nullable=False),
        sa.Column('source', sa.String(length=20), nullable=False),
        sa.Column('hosted', sa.Boolean(), nullable=False),
        sa.Column('input_tokens', sa.Integer(), nullable=False),
        sa.Column('output_tokens', sa.Integer(), nullable=False),
        sa.Column('cost_micro_usd', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_ai_usage_user_id', 'ai_usage', ['user_id'])
    op.create_index('ix_ai_usage_created_at', 'ai_usage', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_ai_usage_created_at', table_name='ai_usage')
    op.drop_index('ix_ai_usage_user_id', table_name='ai_usage')
    op.drop_table('ai_usage')
