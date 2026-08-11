"""
Run once to create the default admin user + default Sales Group.
Usage:  python -m app.seed
"""
import asyncio
from app.database import init_db, AsyncSessionLocal
from app.models.db_models import User, GroupMember, ChatGroup
from app.auth import hash_password
from sqlalchemy import select


async def seed():
    async with AsyncSessionLocal() as db:
        # ── Admin user ──
        result = await db.execute(select(User).where(User.email == "admin@gmail.com"))
        admin = result.scalar_one_or_none()

        if admin:
            admin.is_admin = True
            admin.chat_can_send = True
            await db.flush()
            print("✅ Admin user already exists — updated.")
        else:
            admin = User(
                email="admin@gmail.com",
                password=hash_password("admin"),
                full_name="Admin",
                is_active=True,
                is_admin=True,
                chat_can_send=True,
            )
            db.add(admin)
            await db.flush()
            await db.refresh(admin)
            print("✅ Admin user created: admin@gmail.com / admin")

        await db.commit()
        print("✅ Seed complete.")


async def main():
    await init_db()
    await seed()


if __name__ == "__main__":
    asyncio.run(main())
