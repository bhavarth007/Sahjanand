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

        # ── Default Sales Chat Group ──
        gq = await db.execute(select(ChatGroup).where(ChatGroup.name == "Sales Chat"))
        group = gq.scalar_one_or_none()
        if not group:
            group = ChatGroup(name="Sales Chat", created_by=admin.id)
            db.add(group)
            await db.flush()
            await db.refresh(group)
            print("✅ Sales Chat group created.")

        # ── Ensure admin is member of Sales Chat Group ──
        mq = await db.execute(
            select(GroupMember).where(GroupMember.group_id == group.id, GroupMember.user_id == admin.id)
        )
        if not mq.scalar_one_or_none():
            db.add(GroupMember(group_id=group.id, user_id=admin.id, added_by=admin.id))
            await db.flush()
            print("✅ Admin added to Sales Group.")

        await db.commit()
        print("✅ Seed complete.")


async def main():
    await init_db()
    await seed()


if __name__ == "__main__":
    asyncio.run(main())
