"""Initial schema — users, sales, reminders, samples

Revision ID: 0001
Revises:
Create Date: 2026-08-02
"""
from alembic import op
import sqlalchemy as sa

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── users ──────────────────────────────────────────────
    op.create_table(
        'users',
        sa.Column('id',         sa.Integer(),     nullable=False),
        sa.Column('email',      sa.String(255),   nullable=False),
        sa.Column('password',   sa.String(255),   nullable=False),
        sa.Column('full_name',  sa.String(255),   nullable=True),
        sa.Column('is_active',  sa.Boolean(),     nullable=True,  server_default=sa.text('true')),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_users_id',    'users', ['id'],    unique=False)
    op.create_index('ix_users_email', 'users', ['email'], unique=True)

    # ── sales ──────────────────────────────────────────────
    op.create_table(
        'sales',
        sa.Column('id',         sa.Integer(),       nullable=False),
        sa.Column('user_id',    sa.Integer(),       nullable=False),
        sa.Column('customer',   sa.String(255),     nullable=False),
        sa.Column('product',    sa.String(255),     nullable=False),
        sa.Column('amount',     sa.Numeric(12, 2),  nullable=False),
        sa.Column('status',     sa.String(50),      nullable=True, server_default=sa.text("'pending'")),
        sa.Column('notes',      sa.Text(),          nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_sales_id', 'sales', ['id'], unique=False)

    # ── reminders ──────────────────────────────────────────
    op.create_table(
        'reminders',
        sa.Column('id',          sa.Integer(),    nullable=False),
        sa.Column('user_id',     sa.Integer(),    nullable=False),
        sa.Column('title',       sa.String(255),  nullable=False),
        sa.Column('description', sa.Text(),       nullable=True),
        sa.Column('remind_at',   sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_done',     sa.Boolean(),    nullable=True, server_default=sa.text('false')),
        sa.Column('created_at',  sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_reminders_id', 'reminders', ['id'], unique=False)

    # ── samples ────────────────────────────────────────────
    op.create_table(
        'samples',
        sa.Column('id',          sa.Integer(),    nullable=False),
        sa.Column('user_id',     sa.Integer(),    nullable=False),
        sa.Column('name',        sa.String(255),  nullable=False),
        sa.Column('description', sa.Text(),       nullable=True),
        sa.Column('image_url',   sa.String(500),  nullable=True),
        sa.Column('public_id',   sa.String(255),  nullable=True),
        sa.Column('created_at',  sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_samples_id', 'samples', ['id'], unique=False)


def downgrade() -> None:
    op.drop_table('samples')
    op.drop_table('reminders')
    op.drop_table('sales')
    op.drop_table('users')
