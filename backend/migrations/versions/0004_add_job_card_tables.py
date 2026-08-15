"""Add program_matching and taka_rows to job_cards

Revision ID: 0004
Revises: 0003
Create Date: 2026-08-14
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as sa_inspect

revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def _column_exists(conn, table_name, column_name):
    insp = sa_inspect(conn)
    if not insp.has_table(table_name):
        return False
    cols = [c['name'] for c in insp.get_columns(table_name)]
    return column_name in cols


def upgrade() -> None:
    conn = op.get_bind()
    if not _column_exists(conn, 'job_cards', 'program_matching'):
        op.add_column('job_cards', sa.Column('program_matching', sa.Text(), nullable=True))
    if not _column_exists(conn, 'job_cards', 'taka_rows'):
        op.add_column('job_cards', sa.Column('taka_rows', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('job_cards', 'taka_rows')
    op.drop_column('job_cards', 'program_matching')
