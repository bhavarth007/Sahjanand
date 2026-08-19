"""Add message_reads table for WhatsApp-style read receipts

Revision ID: 0006
Revises: 0005
Create Date: 2026-08-19
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as sa_inspect

revision = '0006'
down_revision = '0005'
branch_labels = None
depends_on = None


def _table_exists(conn, table_name):
    return sa_inspect(conn).has_table(table_name)


def upgrade() -> None:
    conn = op.get_bind()
    if not _table_exists(conn, 'message_reads'):
        op.create_table(
            'message_reads',
            sa.Column('id', sa.Integer(), primary_key=True, index=True),
            sa.Column('message_id', sa.Integer(), sa.ForeignKey('chat_messages.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
            sa.Column('read_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index('ix_message_reads_msg_user', 'message_reads', ['message_id', 'user_id'], unique=True)


def downgrade() -> None:
    op.drop_index('ix_message_reads_msg_user', table_name='message_reads')
    op.drop_table('message_reads')
