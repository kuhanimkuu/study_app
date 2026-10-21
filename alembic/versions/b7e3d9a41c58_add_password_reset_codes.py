"""add password_reset_codes (forgot password by email)

Revision ID: b7e3d9a41c58
Revises: a1d5f3c97e20
Create Date: 2026-10-21

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'b7e3d9a41c58'
down_revision: Union[str, Sequence[str], None] = 'a1d5f3c97e20'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'password_reset_codes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('code_hash', sa.String(length=64), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_password_reset_codes_user_id', 'password_reset_codes', ['user_id'], unique=True)
    op.create_index('ix_password_reset_codes_expires_at', 'password_reset_codes', ['expires_at'])


def downgrade() -> None:
    op.drop_index('ix_password_reset_codes_expires_at', table_name='password_reset_codes')
    op.drop_index('ix_password_reset_codes_user_id', table_name='password_reset_codes')
    op.drop_table('password_reset_codes')
