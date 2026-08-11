"""Add chat tables, admin columns, group reminders

Revision ID: 0002
Revises: 0001
Create Date: 2026-08-11
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect as sa_inspect

revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def _table_exists(conn, table_name):
    insp = sa_inspect(conn)
    return insp.has_table(table_name)


def _column_exists(conn, table_name, column_name):
    insp = sa_inspect(conn)
    if not insp.has_table(table_name):
        return False
    cols = [c['name'] for c in insp.get_columns(table_name)]
    return column_name in cols


def upgrade() -> None:
    conn = op.get_bind()

    # ── Add missing columns to users table ──
    if not _column_exists(conn, 'users', 'is_admin'):
        op.add_column('users', sa.Column('is_admin', sa.Boolean(), server_default=sa.text('false')))
    if not _column_exists(conn, 'users', 'chat_can_send'):
        op.add_column('users', sa.Column('chat_can_send', sa.Boolean(), server_default=sa.text('true')))
    if not _column_exists(conn, 'users', 'designation'):
        op.add_column('users', sa.Column('designation', sa.String(255), nullable=True))
    if not _column_exists(conn, 'users', 'can_view_sales'):
        op.add_column('users', sa.Column('can_view_sales', sa.Boolean(), server_default=sa.text('true')))
    if not _column_exists(conn, 'users', 'can_view_reminders'):
        op.add_column('users', sa.Column('can_view_reminders', sa.Boolean(), server_default=sa.text('true')))
    if not _column_exists(conn, 'users', 'can_view_samples'):
        op.add_column('users', sa.Column('can_view_samples', sa.Boolean(), server_default=sa.text('true')))
    if not _column_exists(conn, 'users', 'can_view_chat'):
        op.add_column('users', sa.Column('can_view_chat', sa.Boolean(), server_default=sa.text('true')))

    # ── chat_groups ──
    if not _table_exists(conn, 'chat_groups'):
        op.create_table(
            'chat_groups',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('name', sa.String(255), nullable=False),
            sa.Column('created_by', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(['created_by'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_chat_groups_id', 'chat_groups', ['id'], unique=False)

    # ── group_members ──
    if not _table_exists(conn, 'group_members'):
        op.create_table(
            'group_members',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('group_id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('added_by', sa.Integer(), nullable=True),
            sa.Column('added_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(['group_id'], ['chat_groups.id']),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.ForeignKeyConstraint(['added_by'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_group_members_id', 'group_members', ['id'], unique=False)

    # ── chat_messages ──
    if not _table_exists(conn, 'chat_messages'):
        op.create_table(
            'chat_messages',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('group_id', sa.Integer(), nullable=False),
            sa.Column('sender_id', sa.Integer(), nullable=False),
            sa.Column('msg_type', sa.String(20), server_default=sa.text("'text'")),
            sa.Column('content', sa.Text(), nullable=True),
            sa.Column('media_url', sa.String(500), nullable=True),
            sa.Column('media_name', sa.String(255), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(['group_id'], ['chat_groups.id']),
            sa.ForeignKeyConstraint(['sender_id'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_chat_messages_id', 'chat_messages', ['id'], unique=False)

    # ── group_reminders ──
    if not _table_exists(conn, 'group_reminders'):
        op.create_table(
            'group_reminders',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('group_id', sa.Integer(), nullable=False),
            sa.Column('created_by', sa.Integer(), nullable=False),
            sa.Column('remind_to', sa.Integer(), nullable=True),
            sa.Column('remind_to_ids', sa.Text(), nullable=True),
            sa.Column('name', sa.String(255), nullable=False),
            sa.Column('description', sa.Text(), nullable=True),
            sa.Column('media_url', sa.String(500), nullable=True),
            sa.Column('media_name', sa.String(255), nullable=True),
            sa.Column('remind_date', sa.String(20), nullable=False),
            sa.Column('remind_time', sa.String(10), nullable=False),
            sa.Column('status', sa.String(20), server_default=sa.text("'set'")),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(['group_id'], ['chat_groups.id']),
            sa.ForeignKeyConstraint(['created_by'], ['users.id']),
            sa.ForeignKeyConstraint(['remind_to'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_group_reminders_id', 'group_reminders', ['id'], unique=False)


def downgrade() -> None:
    op.drop_table('group_reminders')
    op.drop_table('chat_messages')
    op.drop_table('group_members')
    op.drop_table('chat_groups')
    op.drop_column('users', 'can_view_chat')
    op.drop_column('users', 'can_view_samples')
    op.drop_column('users', 'can_view_reminders')
    op.drop_column('users', 'can_view_sales')
    op.drop_column('users', 'designation')
    op.drop_column('users', 'chat_can_send')
    op.drop_column('users', 'is_admin')
