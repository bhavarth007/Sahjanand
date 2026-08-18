"""
FCM Push Notification sender.
Uses the Firebase Legacy HTTP API (simpler setup, no OAuth required).
Requires FCM_SERVER_KEY in .env (from Firebase Console → Project Settings → Cloud Messaging).
"""
import httpx
import logging
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.db_models import FcmToken
from app.config import get_settings

logger = logging.getLogger(__name__)

FCM_URL = "https://fcm.googleapis.com/fcm/send"


async def get_user_fcm_tokens(user_id: int, db: AsyncSession) -> List[str]:
    """Get all FCM tokens for a user."""
    result = await db.execute(
        select(FcmToken.token).where(FcmToken.user_id == user_id)
    )
    return [row[0] for row in result.all()]


async def get_multiple_users_fcm_tokens(user_ids: List[int], db: AsyncSession) -> List[str]:
    """Get all FCM tokens for multiple users."""
    if not user_ids:
        return []
    result = await db.execute(
        select(FcmToken.token).where(FcmToken.user_id.in_(user_ids))
    )
    return [row[0] for row in result.all()]


async def send_push_notification(
    tokens: List[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> None:
    """
    Send push notification to one or more FCM tokens.
    Uses the FCM legacy HTTP API.
    """
    settings = get_settings()
    server_key = settings.FCM_SERVER_KEY
    if not server_key:
        logger.warning("FCM_SERVER_KEY not set — skipping push notification")
        return

    if not tokens:
        return

    headers = {
        "Authorization": f"key={server_key}",
        "Content-Type": "application/json",
    }

    # FCM supports up to 1000 tokens per request
    payload = {
        "registration_ids": tokens[:1000],
        "notification": {
            "title": title,
            "body": body,
            "sound": "default",
            "priority": "high",
            "channel_id": "sahjanand_reminders",
        },
        "data": data or {},
        "priority": "high",
        "android": {
            "priority": "high",
        },
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(FCM_URL, json=payload, headers=headers)
            if resp.status_code == 200:
                result = resp.json()
                # Remove invalid tokens
                if result.get("failure", 0) > 0:
                    await _cleanup_invalid_tokens(tokens, result.get("results", []))
                logger.info(f"FCM sent: success={result.get('success')}, failure={result.get('failure')}")
            else:
                logger.error(f"FCM error: {resp.status_code} — {resp.text[:200]}")
    except Exception as e:
        logger.error(f"FCM send failed: {e}")


async def _cleanup_invalid_tokens(tokens: List[str], results: list) -> None:
    """Remove tokens that FCM reports as invalid."""
    from app.database import AsyncSessionLocal
    invalid_tokens = []
    for i, result in enumerate(results):
        if i < len(tokens) and result.get("error") in (
            "NotRegistered", "InvalidRegistration", "MismatchSenderId"
        ):
            invalid_tokens.append(tokens[i])

    if invalid_tokens:
        try:
            async with AsyncSessionLocal() as db:
                from sqlalchemy import delete as sa_delete
                await db.execute(
                    sa_delete(FcmToken).where(FcmToken.token.in_(invalid_tokens))
                )
                await db.commit()
                logger.info(f"Cleaned up {len(invalid_tokens)} invalid FCM tokens")
        except Exception as e:
            logger.error(f"Failed to cleanup tokens: {e}")


# ═══════════════════════════════════════════════════════════════
# High-level notification helpers
# ═══════════════════════════════════════════════════════════════

async def notify_new_chat_message(
    sender_name: str,
    msg_type: str,
    content: str,
    group_name: str,
    recipient_user_ids: List[int],
    sender_id: int,
    db: AsyncSession,
) -> None:
    """Send push notification for new chat messages to all group members except sender."""
    target_ids = [uid for uid in recipient_user_ids if uid != sender_id]
    if not target_ids:
        return

    tokens = await get_multiple_users_fcm_tokens(target_ids, db)
    if not tokens:
        return

    # Build message body based on type
    if msg_type == "image":
        body_text = "📷 Photo"
    elif msg_type == "video":
        body_text = "🎬 Video"
    elif msg_type == "voice":
        body_text = "🎤 Voice note"
    else:
        body_text = content[:100] if content else "New message"

    await send_push_notification(
        tokens=tokens,
        title=f"{sender_name} in {group_name}",
        body=body_text,
        data={"type": "chat", "group_name": group_name},
    )


async def notify_reminder_created(
    creator_name: str,
    reminder_name: str,
    remind_date: str,
    remind_time: str,
    target_user_ids: List[int],
    db: AsyncSession,
) -> None:
    """Send push notification when a new reminder is created."""
    if not target_user_ids:
        return

    tokens = await get_multiple_users_fcm_tokens(target_user_ids, db)
    if not tokens:
        return

    await send_push_notification(
        tokens=tokens,
        title=f"🔔 New Reminder from {creator_name}",
        body=f"{reminder_name} — {remind_date} at {remind_time}",
        data={"type": "reminder", "title": reminder_name},
    )


async def notify_reminder_due(
    reminder_name: str,
    creator_name: str,
    target_user_ids: List[int],
    db: AsyncSession,
) -> None:
    """Send push notification when a reminder is due (2 min before or at deadline)."""
    if not target_user_ids:
        return

    tokens = await get_multiple_users_fcm_tokens(target_user_ids, db)
    if not tokens:
        return

    await send_push_notification(
        tokens=tokens,
        title="⚡ Reminder Alert!",
        body=f"{reminder_name} (set by {creator_name}) is due NOW!",
        data={"type": "reminder_alert", "title": reminder_name},
    )
