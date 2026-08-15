"""Add job_cards table

Revision ID: 0003
Revises: 0002
Create Date: 2026-08-14
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as sa_inspect

revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def _table_exists(conn, table_name):
    insp = sa_inspect(conn)
    return insp.has_table(table_name)


def upgrade() -> None:
    conn = op.get_bind()

    if not _table_exists(conn, 'job_cards'):
        op.create_table(
            'job_cards',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('job_name', sa.String(100), nullable=True),
            sa.Column('j_card_no', sa.String(50), nullable=True),
            sa.Column('p_name', sa.String(255), nullable=True),
            sa.Column('so_no', sa.String(50), nullable=True),
            sa.Column('quality', sa.String(255), nullable=True),
            sa.Column('design_no', sa.String(100), nullable=True),
            sa.Column('total_card', sa.String(50), nullable=True),
            sa.Column('g_pick', sa.String(50), nullable=True),
            sa.Column('jc_date', sa.String(20), nullable=True),
            sa.Column('j_ord_no', sa.String(50), nullable=True),
            sa.Column('repeat_mtr', sa.String(50), nullable=True),
            sa.Column('repeat_pcs', sa.String(50), nullable=True),
            sa.Column('total_pcs', sa.String(50), nullable=True),
            sa.Column('weight_per_pcs', sa.String(50), nullable=True),
            sa.Column('start_date', sa.String(20), nullable=True),
            sa.Column('end_date', sa.String(20), nullable=True),
            sa.Column('op_name', sa.String(255), nullable=True),
            sa.Column('remark', sa.Text(), nullable=True),
            sa.Column('supervisor_sign', sa.String(255), nullable=True),
            sa.Column('image_url', sa.String(500), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_job_cards_id', 'job_cards', ['id'], unique=False)


def downgrade() -> None:
    op.drop_table('job_cards')
