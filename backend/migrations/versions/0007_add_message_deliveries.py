"""Add message_deliveries table for WhatsApp-style delivery tracking

Revision ID: 0007
Revises: 0006
Create Date: 2026-08-19

Tracks which users' devices have RECEIVED a message (delivery ACK).
Separate from message_reads (which tracks opened/read).
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as sa_inspect

revision = '0007'
down_revision = '0006'
branch_labels = None
depends_on = None


def _table_exists(conn, table_name):
    return sa_inspect(conn).has_table(table_name)


def upgrade() -> None:
    conn = op.get_bind()
    if not _table_exists(conn, 'message_deliveries'):
        op.create_table(
            'message_deliveries',
            sa.Column('id', sa.Integer(), primary_key=True, index=True),
            sa.Column('message_id', sa.Integer(), sa.ForeignKey('chat_messages.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
            sa.Column('delivered_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index('ix_message_deliveries_msg_user', 'message_deliveries', ['message_id', 'user_id'], unique=True)


def downgrade() -> None:
    op.drop_index('ix_message_deliveries_msg_user', table_name='message_deliveries')
    op.drop_table('message_deliveries')
