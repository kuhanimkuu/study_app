"""add stored_files; file_id + chunk range on materials, file_id on generated_artifacts

Revision ID: c5f2a8e71d03
Revises: b81e4f0c9d27
Create Date: 2026-10-07

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'c5f2a8e71d03'
down_revision: Union[str, Sequence[str], None] = 'b81e4f0c9d27'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'stored_files',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('filename', sa.String(length=500), nullable=False),
        sa.Column('mime_type', sa.String(length=100), nullable=False),
        sa.Column('size', sa.Integer(), nullable=False),
        sa.Column('data', sa.LargeBinary(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_stored_files_user_id', 'stored_files', ['user_id'])
    op.add_column('materials', sa.Column('file_id', sa.Integer(), nullable=True))
    op.add_column('materials', sa.Column('chunk_start', sa.Integer(), nullable=True))
    op.add_column('materials', sa.Column('chunk_count', sa.Integer(), nullable=True))
    op.create_foreign_key('fk_materials_file_id', 'materials', 'stored_files', ['file_id'], ['id'], ondelete='SET NULL')
    op.add_column('generated_artifacts', sa.Column('file_id', sa.Integer(), nullable=True))
    op.create_foreign_key(
        'fk_generated_artifacts_file_id', 'generated_artifacts', 'stored_files', ['file_id'], ['id'], ondelete='SET NULL'
    )


def downgrade() -> None:
    op.drop_constraint('fk_generated_artifacts_file_id', 'generated_artifacts', type_='foreignkey')
    op.drop_column('generated_artifacts', 'file_id')
    op.drop_constraint('fk_materials_file_id', 'materials', type_='foreignkey')
    op.drop_column('materials', 'chunk_count')
    op.drop_column('materials', 'chunk_start')
    op.drop_column('materials', 'file_id')
    op.drop_index('ix_stored_files_user_id', table_name='stored_files')
    op.drop_table('stored_files')
