"""Add workflow status, border fields, and cancellation tracking to job_cards.

Revision ID: 0008
Revises: 0007
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers
revision = '0008'
down_revision = '0007'
branch_labels = None
depends_on = None


def _column_exists(table, column):
    """Check if a column already exists in a table (for idempotent migrations)."""
    from sqlalchemy import inspect
    bind = op.get_bind()
    inspector = inspect(bind)
    columns = [c['name'] for c in inspector.get_columns(table)]
    return column in columns


def upgrade():
    # Workflow status
    if not _column_exists('job_cards', 'workflow_status'):
        op.add_column('job_cards', sa.Column('workflow_status', sa.String(30), nullable=False, server_default='NEW'))

    # Border stage fields
    if not _column_exists('job_cards', 'border_job_m'):
        op.add_column('job_cards', sa.Column('border_job_m', sa.String(50), nullable=True))
    if not _column_exists('job_cards', 'border_work_m'):
        op.add_column('job_cards', sa.Column('border_work_m', sa.String(50), nullable=True))
    if not _column_exists('job_cards', 'border_lapet_m'):
        op.add_column('job_cards', sa.Column('border_lapet_m', sa.String(50), nullable=True))
    if not _column_exists('job_cards', 'border_blause_m'):
        op.add_column('job_cards', sa.Column('border_blause_m', sa.String(50), nullable=True))
    if not _column_exists('job_cards', 'border_total_cut_m'):
        op.add_column('job_cards', sa.Column('border_total_cut_m', sa.String(50), nullable=True))
    if not _column_exists('job_cards', 'border_rs_inch'):
        op.add_column('job_cards', sa.Column('border_rs_inch', sa.String(50), nullable=True))
    if not _column_exists('job_cards', 'border_description'):
        op.add_column('job_cards', sa.Column('border_description', sa.Text(), nullable=True))

    # Cancellation tracking
    if not _column_exists('job_cards', 'cancel_reason'):
        op.add_column('job_cards', sa.Column('cancel_reason', sa.Text(), nullable=True))
    if not _column_exists('job_cards', 'cancelled_by'):
        op.add_column('job_cards', sa.Column('cancelled_by', sa.Integer(), nullable=True))
    if not _column_exists('job_cards', 'cancelled_at'):
        op.add_column('job_cards', sa.Column('cancelled_at', sa.DateTime(timezone=True), nullable=True))
    if not _column_exists('job_cards', 'cancel_stage'):
        op.add_column('job_cards', sa.Column('cancel_stage', sa.String(30), nullable=True))
    if not _column_exists('job_cards', 'cancellation_history'):
        op.add_column('job_cards', sa.Column('cancellation_history', sa.Text(), nullable=True))


def downgrade():
    op.drop_column('job_cards', 'cancellation_history')
    op.drop_column('job_cards', 'cancel_stage')
    op.drop_column('job_cards', 'cancelled_at')
    op.drop_column('job_cards', 'cancelled_by')
    op.drop_column('job_cards', 'cancel_reason')
    op.drop_column('job_cards', 'border_description')
    op.drop_column('job_cards', 'border_rs_inch')
    op.drop_column('job_cards', 'border_total_cut_m')
    op.drop_column('job_cards', 'border_blause_m')
    op.drop_column('job_cards', 'border_lapet_m')
    op.drop_column('job_cards', 'border_work_m')
    op.drop_column('job_cards', 'border_job_m')
    op.drop_column('job_cards', 'workflow_status')
