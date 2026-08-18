"""
Group Reminders — per-group, with multi-user targeting + notifications
======================================================================
"""

from typing import List, Optional
from datetime import datetime, date, timezone, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from pydantic import BaseModel

from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import GroupReminder, User, GroupMember

router = APIRouter(prefix="/api/chat/groups", tags=["Group Reminders"])


# ── Schemas ──────────────────────────────────────────────
class ReminderCreate(BaseModel):
    name: str
    remind_to: Optional[int] = None               # legacy single user (kept for compat)
    remind_to_ids: Optional[List[int]] = None     # NEW: list of target user IDs
    remind_date: str                              # 'YYYY-MM-DD'
    remind_time: str                              # 'HH:MM' (24h format)
    description: Optional[str] = None
    media_url: Optional[str] = None
    media_name: Optional[str] = None
    status: Optional[str] = "set"


class ReminderUpdate(BaseModel):
    name: Optional[str] = None
    remind_to: Optional[int] = None
    remind_to_ids: Optional[List[int]] = None
    remind_date: Optional[str] = None
    remind_time: Optional[str] = None
    description: Optional[str] = None
    media_url: Optional[str] = None
    media_name: Optional[str] = None
    status: Optional[str] = None


class ReminderOut(BaseModel):
    id: int
    group_id: int
    created_by: int
    created_by_name: Optional[str] = None
    remind_to: Optional[int] = None
    remind_to_name: Optional[str] = None
    remind_to_ids: Optional[List[int]] = None
    remind_to_names: Optional[List[str]] = None
    name: str
    description: Optional[str] = None
    media_url: Optional[str] = None
    media_name: Optional[str] = None
    remind_date: str
    remind_time: str
    status: str
    created_at: datetime


# ── Helpers ──────────────────────────────────────────────
async def check_member(user_id: int, group_id: int, db: AsyncSession):
    r = await db.execute(
        select(GroupMember).where(GroupMember.user_id == user_id, GroupMember.group_id == group_id)
    )
    if not r.scalar_one_or_none():
        raise HTTPException(403, "Not a member of this group.")


# IST timezone (UTC+05:30)
IST = timezone(timedelta(hours=5, minutes=30))


def is_past(remind_date: str, remind_time: str) -> bool:
    """Check if a reminder date+time is in the past (IST timezone)."""
    try:
        dt = datetime.strptime(f"{remind_date} {remind_time}", "%Y-%m-%d %H:%M")
        now_ist = datetime.now(IST).replace(tzinfo=None)
        return dt < now_ist
    except:
        return False


def parse_remind_to_ids(r) -> List[int]:
    """Parse the remind_to_ids column (comma-separated string) to list of ints."""
    if not r.remind_to_ids:
        # Fallback to single remind_to for legacy data
        return [r.remind_to] if r.remind_to else []
    try:
        return [int(x.strip()) for x in r.remind_to_ids.split(",") if x.strip()]
    except:
        return [r.remind_to] if r.remind_to else []


def user_is_target(r, user_id: int) -> bool:
    """Check if a user is one of the targets of this reminder."""
    ids = parse_remind_to_ids(r)
    return user_id in ids


def serialize_reminder(r, user_map: dict) -> dict:
    creator = user_map.get(r.created_by)
    target_ids = parse_remind_to_ids(r)
    target_names = []
    for tid in target_ids:
        u = user_map.get(tid)
        if u:
            target_names.append(u.full_name or u.email)

    # Legacy single target (first in list for backward compat)
    first_target = user_map.get(target_ids[0]) if target_ids else None

    return {
        "id": r.id,
        "group_id": r.group_id,
        "created_by": r.created_by,
        "created_by_name": (creator.full_name or creator.email) if creator else None,
        "remind_to": target_ids[0] if target_ids else None,
        "remind_to_name": (first_target.full_name or first_target.email) if first_target else None,
        "remind_to_ids": target_ids if target_ids else None,
        "remind_to_names": target_names if target_names else None,
        "name": r.name,
        "description": r.description,
        "media_url": r.media_url,
        "media_name": r.media_name,
        "remind_date": r.remind_date,
        "remind_time": r.remind_time,
        "status": r.status,
        "created_at": r.created_at,
    }


# ── GET reminders ──
@router.get("/{gid}/reminders", response_model=List[ReminderOut])
async def get_reminders(
    gid: int,
    tab: str = Query("pending"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await check_member(current_user.id, gid, db)

    result = await db.execute(
        select(GroupReminder).where(GroupReminder.group_id == gid).order_by(GroupReminder.remind_date, GroupReminder.remind_time)
    )
    all_reminders = result.scalars().all()

    # Separate pending vs history
    pending = []
    history = []
    for r in all_reminders:
        if is_past(r.remind_date, r.remind_time):
            history.append(r)
        else:
            pending.append(r)

    if tab == "pending":
        items = pending
    else:
        # HISTORY: only show reminders created by OR targeted at the current user
        items = [
            r for r in history
            if r.created_by == current_user.id or user_is_target(r, current_user.id)
        ]

    # Resolve user names
    user_ids = set()
    for r in items:
        user_ids.add(r.created_by)
        for tid in parse_remind_to_ids(r):
            user_ids.add(tid)
    user_map = {}
    if user_ids:
        uq = await db.execute(select(User).where(User.id.in_(user_ids)))
        user_map = {u.id: u for u in uq.scalars().all()}

    return [serialize_reminder(r, user_map) for r in items]


# ── GET notifications for current user (pending reminders targeted at them) ──
@router.get("/{gid}/my-reminders", response_model=List[ReminderOut])
async def get_my_reminders(
    gid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get pending reminders targeted at the current user (for notification popup)."""
    result = await db.execute(
        select(GroupReminder).where(GroupReminder.group_id == gid)
    )
    all_items = result.scalars().all()
    # Filter to those targeting current user and still pending
    items = [r for r in all_items if user_is_target(r, current_user.id) and not is_past(r.remind_date, r.remind_time)]

    user_ids = set()
    for r in items:
        user_ids.add(r.created_by)
        for tid in parse_remind_to_ids(r):
            user_ids.add(tid)
    user_map = {}
    if user_ids:
        uq = await db.execute(select(User).where(User.id.in_(user_ids)))
        user_map = {u.id: u for u in uq.scalars().all()}
    return [serialize_reminder(r, user_map) for r in items]


# ── POST create ──
@router.post("/{gid}/reminders", response_model=ReminderOut, status_code=201)
async def create_reminder(
    gid: int,
    body: ReminderCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await check_member(current_user.id, gid, db)

    # Build remind_to_ids string from the list (or fall back to single remind_to)
    target_ids_list = body.remind_to_ids or ([body.remind_to] if body.remind_to else [])
    remind_to_ids_str = ",".join(str(x) for x in target_ids_list) if target_ids_list else None
    first_target = target_ids_list[0] if target_ids_list else None

    reminder = GroupReminder(
        group_id=gid,
        created_by=current_user.id,
        remind_to=first_target,
        remind_to_ids=remind_to_ids_str,
        name=body.name.strip(),
        description=body.description,
        media_url=body.media_url,
        media_name=body.media_name,
        remind_date=body.remind_date,
        remind_time=body.remind_time,
        status=body.status or "set",
    )
    db.add(reminder)
    await db.flush()
    await db.refresh(reminder)

    # Resolve names for response
    user_ids = {reminder.created_by}
    for tid in target_ids_list:
        user_ids.add(tid)
    uq = await db.execute(select(User).where(User.id.in_(user_ids)))
    user_map = {u.id: u for u in uq.scalars().all()}

    # Send push notification to targeted users
    try:
        from app.notifications import notify_reminder_created
        await notify_reminder_created(
            creator_name=current_user.full_name or current_user.email,
            reminder_name=reminder.name,
            remind_date=reminder.remind_date,
            remind_time=reminder.remind_time,
            target_user_ids=target_ids_list,
            db=db,
        )
    except Exception:
        pass  # Don't fail reminder creation if push fails

    return serialize_reminder(reminder, user_map)


# ── PATCH update ──
@router.patch("/{gid}/reminders/{rid}", response_model=ReminderOut)
async def update_reminder(
    gid: int, rid: int,
    body: ReminderUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await check_member(current_user.id, gid, db)
    result = await db.execute(
        select(GroupReminder).where(GroupReminder.id == rid, GroupReminder.group_id == gid)
    )
    reminder = result.scalar_one_or_none()
    if not reminder:
        raise HTTPException(404, "Reminder not found.")

    # Handle multi-select remind_to_ids
    if body.remind_to_ids is not None:
        remind_to_ids_str = ",".join(str(x) for x in body.remind_to_ids) if body.remind_to_ids else None
        reminder.remind_to_ids = remind_to_ids_str
        reminder.remind_to = body.remind_to_ids[0] if body.remind_to_ids else None
    elif body.remind_to is not None:
        reminder.remind_to = body.remind_to
        reminder.remind_to_ids = str(body.remind_to) if body.remind_to else None

    for field in ["name", "remind_date", "remind_time", "description", "media_url", "media_name", "status"]:
        val = getattr(body, field, None)
        if val is not None:
            setattr(reminder, field, val.strip() if isinstance(val, str) else val)

    await db.flush()
    await db.refresh(reminder)

    user_ids = {reminder.created_by}
    for tid in parse_remind_to_ids(reminder):
        user_ids.add(tid)
    uq = await db.execute(select(User).where(User.id.in_(user_ids)))
    user_map = {u.id: u for u in uq.scalars().all()}
    return serialize_reminder(reminder, user_map)


# ── DELETE ──
@router.delete("/{gid}/reminders/{rid}")
async def delete_reminder(
    gid: int, rid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await check_member(current_user.id, gid, db)
    result = await db.execute(
        select(GroupReminder).where(GroupReminder.id == rid, GroupReminder.group_id == gid)
    )
    reminder = result.scalar_one_or_none()
    if not reminder:
        raise HTTPException(404, "Reminder not found.")
    await db.delete(reminder)
    await db.flush()
    return {"ok": True}


# ── GET all pending reminders for the current user (across ALL groups) ──
# NOTE: This uses a different path prefix — registered separately in main.py
global_reminder_router = APIRouter(prefix="/api/chat", tags=["Group Reminders"])


@global_reminder_router.get("/my-all-reminders", response_model=List[ReminderOut])
async def get_all_my_reminders(
    tab: str = Query("pending"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns reminders targeted at OR created by the current user, across all groups.
    tab=pending returns future reminders, tab=history returns past ones.
    """
    result = await db.execute(
        select(GroupReminder).order_by(GroupReminder.remind_date, GroupReminder.remind_time)
    )
    all_reminders = result.scalars().all()

    # Filter: user is creator or target
    user_reminders = [
        r for r in all_reminders
        if r.created_by == current_user.id or user_is_target(r, current_user.id)
    ]

    # Split by pending/history
    if tab == "history":
        items = [r for r in user_reminders if is_past(r.remind_date, r.remind_time)]
    else:
        items = [r for r in user_reminders if not is_past(r.remind_date, r.remind_time)]

    # Resolve user names
    user_ids = set()
    for r in items:
        user_ids.add(r.created_by)
        for tid in parse_remind_to_ids(r):
            user_ids.add(tid)
    user_map = {}
    if user_ids:
        uq = await db.execute(select(User).where(User.id.in_(user_ids)))
        user_map = {u.id: u for u in uq.scalars().all()}

    return [serialize_reminder(r, user_map) for r in items]
