"""
Background scheduler that checks for due reminders and sends FCM push notifications.
Runs every 30 seconds during app lifespan.
"""
import asyncio
import logging
from datetime import datetime, timedelta
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.db_models import GroupReminder, User
from app.notifications import notify_reminder_due

logger = logging.getLogger(__name__)

# Track which reminders we've already alerted (avoid duplicates)
_alerted_reminders: set = set()
_scheduler_task: asyncio.Task = None


def parse_remind_to_ids(reminder) -> list:
    """Parse the comma-separated remind_to_ids string."""
    if reminder.remind_to_ids:
        try:
            return [int(x.strip()) for x in reminder.remind_to_ids.split(",") if x.strip()]
        except ValueError:
            pass
    if reminder.remind_to:
        return [reminder.remind_to]
    return []


async def check_due_reminders():
    """Check for reminders that are due within the next 2 minutes and send push notifications."""
    try:
        async with AsyncSessionLocal() as db:
            # Get all pending reminders
            result = await db.execute(
                select(GroupReminder).where(GroupReminder.status == "set")
            )
            reminders = result.scalars().all()

            now = datetime.now()

            for r in reminders:
                try:
                    reminder_dt = datetime.strptime(f"{r.remind_date}T{r.remind_time}", "%Y-%m-%dT%H:%M")
                except (ValueError, TypeError):
                    continue

                diff = (reminder_dt - now).total_seconds()

                # Alert at 2 minutes before (between 90 and 150 seconds before)
                alert_key_2min = f"2min_{r.id}"
                if 90 < diff <= 150 and alert_key_2min not in _alerted_reminders:
                    _alerted_reminders.add(alert_key_2min)
                    target_ids = parse_remind_to_ids(r)
                    # Also notify the creator
                    all_notify_ids = list(set(target_ids + [r.created_by]))

                    # Get creator name
                    creator = await db.get(User, r.created_by)
                    creator_name = (creator.full_name or creator.email) if creator else "Someone"

                    await notify_reminder_due(
                        reminder_name=r.name,
                        creator_name=creator_name,
                        target_user_ids=all_notify_ids,
                        db=db,
                    )
                    logger.info(f"[Scheduler] 2-min alert sent for reminder #{r.id}: {r.name}")

                # Alert at deadline (between -30 and +30 seconds of the time)
                alert_key_now = f"now_{r.id}"
                if -30 <= diff <= 30 and alert_key_now not in _alerted_reminders:
                    _alerted_reminders.add(alert_key_now)
                    target_ids = parse_remind_to_ids(r)
                    all_notify_ids = list(set(target_ids + [r.created_by]))

                    creator = await db.get(User, r.created_by)
                    creator_name = (creator.full_name or creator.email) if creator else "Someone"

                    await notify_reminder_due(
                        reminder_name=r.name,
                        creator_name=creator_name,
                        target_user_ids=all_notify_ids,
                        db=db,
                    )
                    logger.info(f"[Scheduler] Deadline alert sent for reminder #{r.id}: {r.name}")

            # Cleanup old alert keys (reminders more than 1 hour past)
            to_remove = set()
            for key in _alerted_reminders:
                try:
                    rid = int(key.split("_")[1])
                    # Find if this reminder is still relevant
                    r_check = await db.get(GroupReminder, rid)
                    if r_check:
                        r_dt = datetime.strptime(f"{r_check.remind_date}T{r_check.remind_time}", "%Y-%m-%dT%H:%M")
                        if (now - r_dt).total_seconds() > 3600:
                            to_remove.add(key)
                    else:
                        to_remove.add(key)
                except (ValueError, TypeError):
                    to_remove.add(key)

            _alerted_reminders.difference_update(to_remove)

    except Exception as e:
        logger.error(f"[Scheduler] Error checking reminders: {e}")


async def scheduler_loop():
    """Main scheduler loop — runs every 30 seconds."""
    logger.info("[Scheduler] Reminder notification scheduler started")
    while True:
        await check_due_reminders()
        await asyncio.sleep(30)


def start_scheduler():
    """Start the background scheduler task."""
    global _scheduler_task
    _scheduler_task = asyncio.create_task(scheduler_loop())
    return _scheduler_task


def stop_scheduler():
    """Stop the background scheduler task."""
    global _scheduler_task
    if _scheduler_task and not _scheduler_task.done():
        _scheduler_task.cancel()
        _scheduler_task = None
