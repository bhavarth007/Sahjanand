"""
Run once to create the default admin user.
Usage:  python -m app.seed
"""
import asyncio
from app.database import init_db, AsyncSessionLocal
from app.models.db_models import User
from app.auth import hash_password
from sqlalchemy import select


async def seed():
    await init_db()

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.email == "admin@gmail.com"))
        existing = result.scalar_one_or_none()

        if existing:
            print("✅ Admin user already exists — skipping seed.")
            return

        admin = User(
            email="admin@gmail.com",
            password=hash_password("admin"),
            full_name="Admin",
            is_active=True,
        )
        db.add(admin)
        await db.commit()
        print("✅ Admin user created: admin@gmail.com / admin")


if __name__ == "__main__":
    asyncio.run(seed())
