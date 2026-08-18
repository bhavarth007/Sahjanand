"""Add fcm_tokens table for push notifications

Revision ID: 0005
Revises: 0004
Create Date: 2026-08-18
"""
from alembic import op
import sqlalchemy as sa

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'fcm_tokens',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('token', sa.String(500), nullable=False, unique=True, index=True),
        sa.Column('device_info', sa.String(255), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_fcm_tokens_user_id', 'fcm_tokens', ['user_id'])


def downgrade():
    op.drop_index('ix_fcm_tokens_user_id', table_name='fcm_tokens')
    op.drop_table('fcm_tokens')
