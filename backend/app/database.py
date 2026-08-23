from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.config import get_settings

settings = get_settings()

db_url = settings.async_database_url

# SQLite needs check_same_thread=False
# PostgreSQL pooler needs prepared_statement_cache_size=0
if "sqlite" in db_url:
    connect_args = {"check_same_thread": False}
elif "pooler.supabase" in db_url:
    # Supabase session pooler doesn't support prepared statements
    connect_args = {"prepared_statement_cache_size": 0, "statement_cache_size": 0}
else:
    connect_args = {}

engine = create_async_engine(
    db_url,
    echo=False,
    pool_pre_ping=True,
    connect_args=connect_args,
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def init_db():
    """
    Creates all tables on startup.
    Used for local dev (SQLite) and initial deploy.
    In production, Alembic migrations handle schema changes.
    """
    from sqlalchemy import text, inspect as sa_inspect

    async with engine.begin() as conn:
        # Migrate: drop old group_reminders if it has old schema (missing remind_date column)
        def _check_and_drop(sync_conn):
            insp = sa_inspect(sync_conn)
            if insp.has_table("group_reminders"):
                cols = [c["name"] for c in insp.get_columns("group_reminders")]
                if "remind_date" not in cols:
                    sync_conn.execute(text("DROP TABLE group_reminders"))
                    print("🔄 Migrated group_reminders table (schema update).")

        await conn.run_sync(_check_and_drop)
        await conn.run_sync(Base.metadata.create_all)

    # Auto-migrate: add new columns to existing tables if they don't exist
    # (create_all only creates new tables, not new columns on existing ones)
    async with engine.begin() as conn:
        def _add_missing_columns(sync_conn):
            insp = sa_inspect(sync_conn)
            if insp.has_table("job_cards"):
                cols = [c["name"] for c in insp.get_columns("job_cards")]
                new_cols = {
                    "workflow_status": "VARCHAR(30) NOT NULL DEFAULT 'NEW'",
                    "border_job_m": "VARCHAR(50)",
                    "border_work_m": "VARCHAR(50)",
                    "border_lapet_m": "VARCHAR(50)",
                    "border_blause_m": "VARCHAR(50)",
                    "border_total_cut_m": "VARCHAR(50)",
                    "border_rs_inch": "VARCHAR(50)",
                    "border_description": "TEXT",
                    "cancel_reason": "TEXT",
                    "cancelled_by": "INTEGER",
                    "cancelled_at": "TIMESTAMP WITH TIME ZONE",
                    "cancel_stage": "VARCHAR(30)",
                    "cancellation_history": "TEXT",
                    "confirmed_by": "INTEGER",
                    "confirmed_by_name": "VARCHAR(255)",
                    "confirmed_at": "TIMESTAMP WITH TIME ZONE",
                }
                for col_name, col_type in new_cols.items():
                    if col_name not in cols:
                        try:
                            sync_conn.execute(text(f"ALTER TABLE job_cards ADD COLUMN {col_name} {col_type}"))
                            print(f"  ✅ Added column job_cards.{col_name}")
                        except Exception as e:
                            print(f"  ⚠️ Column job_cards.{col_name}: {e}")

            # Add plain_password to users table if missing
            if insp.has_table("users"):
                user_cols = [c["name"] for c in insp.get_columns("users")]
                if "plain_password" not in user_cols:
                    try:
                        sync_conn.execute(text("ALTER TABLE users ADD COLUMN plain_password VARCHAR(255)"))
                        print("  ✅ Added column users.plain_password")
                    except Exception as e:
                        print(f"  ⚠️ Column users.plain_password: {e}")

        await conn.run_sync(_add_missing_columns)

    db_type = "SQLite (local dev)" if "sqlite" in db_url else "PostgreSQL (production)"
    print(f"✅ Database connected [{db_type}] — tables ready.")


async def close_db():
    await engine.dispose()
    print("🔌 Database connection closed.")
