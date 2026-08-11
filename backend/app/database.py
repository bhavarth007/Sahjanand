from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.config import get_settings

settings = get_settings()

db_url = settings.async_database_url

# SQLite needs check_same_thread=False
connect_args = {"check_same_thread": False} if "sqlite" in db_url else {}

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

    db_type = "SQLite (local dev)" if "sqlite" in db_url else "PostgreSQL (production)"
    print(f"✅ Database connected [{db_type}] — tables ready.")


async def close_db():
    await engine.dispose()
    print("🔌 Database connection closed.")
