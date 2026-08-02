from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from pydantic import BaseModel
from datetime import datetime
from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import Reminder, User

router = APIRouter(prefix="/api/reminders", tags=["Reminders"])


# ── Schemas ──
class ReminderCreate(BaseModel):
    title: str
    description: Optional[str] = None
    remind_at: datetime


class ReminderOut(BaseModel):
    id: int
    title: str
    description: Optional[str]
    remind_at: datetime
    is_done: bool
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Routes ──
@router.get("/", response_model=list[ReminderOut])
async def get_reminders(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Reminder)
        .where(Reminder.user_id == current_user.id)
        .order_by(Reminder.remind_at.asc())
    )
    return result.scalars().all()


@router.post("/", response_model=ReminderOut, status_code=status.HTTP_201_CREATED)
async def create_reminder(
    data: ReminderCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    reminder = Reminder(user_id=current_user.id, **data.model_dump())
    db.add(reminder)
    await db.flush()
    await db.refresh(reminder)
    return reminder


@router.patch("/{reminder_id}/done", response_model=ReminderOut)
async def mark_done(
    reminder_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Reminder).where(
            Reminder.id == reminder_id,
            Reminder.user_id == current_user.id,
        )
    )
    reminder = result.scalar_one_or_none()
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    reminder.is_done = True
    await db.flush()
    await db.refresh(reminder)
    return reminder


@router.delete("/{reminder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reminder(
    reminder_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Reminder).where(
            Reminder.id == reminder_id,
            Reminder.user_id == current_user.id,
        )
    )
    reminder = result.scalar_one_or_none()
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    await db.delete(reminder)
