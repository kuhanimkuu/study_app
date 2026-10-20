"""add client_errors (the app's crash reports)

Revision ID: f4c8a2e65b19
Revises: e7b2c4d81a36
Create Date: 2026-10-20

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'f4c8a2e65b19'
down_revision: Union[str, Sequence[str], None] = 'e7b2c4d81a36'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'client_errors',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('fingerprint', sa.String(length=64), nullable=False),
        sa.Column('app_version', sa.String(length=40), nullable=False),
        sa.Column('platform', sa.String(length=60), nullable=False),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('stack', sa.Text(), nullable=False),
        sa.Column('count', sa.Integer(), nullable=False),
        sa.Column('first_seen', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_seen', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_client_errors_user_id', 'client_errors', ['user_id'])
    op.create_index('ix_client_errors_fingerprint', 'client_errors', ['fingerprint'])
    op.create_index('ix_client_errors_last_seen', 'client_errors', ['last_seen'])


def downgrade() -> None:
    op.drop_index('ix_client_errors_last_seen', table_name='client_errors')
    op.drop_index('ix_client_errors_fingerprint', table_name='client_errors')
    op.drop_index('ix_client_errors_user_id', table_name='client_errors')
    op.drop_table('client_errors')
