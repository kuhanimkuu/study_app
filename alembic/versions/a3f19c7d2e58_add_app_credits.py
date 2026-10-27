"""add app credits: ledger feature, ai_usage credits

Revision ID: a3f19c7d2e58
Revises: e796b4921c8c
Create Date: 2026-10-27 22:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'a3f19c7d2e58'
down_revision: Union[str, Sequence[str], None] = 'e796b4921c8c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('ledger_entries', sa.Column('feature', sa.String(length=20), nullable=True))
    op.add_column('ai_usage', sa.Column('credits', sa.Integer(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('ai_usage', 'credits')
    op.drop_column('ledger_entries', 'feature')
