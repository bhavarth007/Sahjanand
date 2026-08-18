"""
FCM Push Notification sender.
Uses the Firebase Cloud Messaging HTTP v1 API (replaces deprecated Legacy API).
Requires a Firebase service account JSON file.
Set FIREBASE_CREDENTIALS_JSON env var to the path of the service account JSON file,
or set FIREBASE_CREDENTIALS_JSON_CONTENT to the raw JSON string (for cloud deployments).
"""
import json
import logging
import time
from typing import List, Optional
from pathlib import Path

import httpx
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleAuthRequest
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.db_models import FcmToken
from app.config import get_settings

logger = logging.getLogger(__name__)

# FCM v1 API endpoint template
FCM_V1_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# Cached credentials
_credentials = None
_project_id = None


def _get_credentials():
    """Load and cache Firebase service account credentials."""
    global _credentials, _project_id

    if _credentials is not None and _credentials.valid:
        return _credentials, _project_id

    settings = get_settings()

    # Try loading from JSON content (environment variable with raw JSON)
    json_content = settings.FIREBASE_CREDENTIALS_JSON_CONTENT
    if json_content:
        try:
            service_info = json.loads(json_content)
        except json.JSONDecodeError:
            logger.error("FIREBASE_CREDENTIALS_JSON_CONTENT is not valid JSON")
            return None, None
    else:
        # Try loading from file path
        json_path = settings.FIREBASE_CREDENTIALS_JSON
        if not json_path:
            logger.warning("No Firebase credentials configured — push notifications disabled")
            return None, None

        path = Path(json_path)
        if not path.exists():
            logger.error(f"Firebase credentials file not found: {json_path}")
            return None, None

        with open(path) as f:
            service_info = json.load(f)

    _project_id = service_info.get("project_id")
    if not _project_id:
        logger.error("Firebase service account JSON missing 'project_id'")
        return None, None

    _credentials = service_account.Credentials.from_service_account_info(
        service_info,
        scopes=["https://www.googleapis.com/auth/firebase.messaging"],
    )

    return _credentials, _project_id


def _get_access_token() -> Optional[str]:
    """Get a valid OAuth2 access token for FCM v1 API."""
    creds, _ = _get_credentials()
    if creds is None:
        return None

    # Refresh if expired
    if not creds.valid:
        creds.refresh(GoogleAuthRequest())

    return creds.token


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
    Uses the FCM HTTP v1 API (OAuth2 authenticated).
    Sends one request per token (v1 API doesn't support multicast directly).
    """
    access_token = _get_access_token()
    if not access_token:
        return

    _, project_id = _get_credentials()
    if not project_id:
        return

    url = FCM_V1_URL.format(project_id=project_id)

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }

    # Ensure all data values are strings (FCM v1 requirement)
    str_data = {k: str(v) for k, v in (data or {}).items()}

    invalid_tokens = []

    async with httpx.AsyncClient(timeout=10.0) as client:
        for token in tokens:
            message = {
                "message": {
                    "token": token,
                    "notification": {
                        "title": title,
                        "body": body,
                    },
                    "data": str_data,
                    "android": {
                        "priority": "high",
                        "notification": {
                            "channel_id": "sahjanand_reminders",
                            "sound": "default",
                            "priority": "high",
                        },
                    },
                }
            }

            try:
                resp = await client.post(url, json=message, headers=headers)
                if resp.status_code == 200:
                    logger.info(f"FCM v1 sent successfully to token ...{token[-8:]}")
                elif resp.status_code == 404 or resp.status_code == 400:
                    # Token is invalid or unregistered
                    error_data = resp.json()
                    error_code = error_data.get("error", {}).get("details", [{}])[0].get("errorCode", "")
                    if error_code in ("UNREGISTERED", "INVALID_ARGUMENT"):
                        invalid_tokens.append(token)
                        logger.info(f"FCM token invalid/unregistered: ...{token[-8:]}")
                    else:
                        logger.error(f"FCM v1 error ({resp.status_code}): {resp.text[:200]}")
                elif resp.status_code == 401:
                    # Token expired, refresh and retry once
                    global _credentials
                    _credentials = None
                    new_token = _get_access_token()
                    if new_token:
                        headers["Authorization"] = f"Bearer {new_token}"
                        retry_resp = await client.post(url, json=message, headers=headers)
                        if retry_resp.status_code == 200:
                            logger.info(f"FCM v1 sent (after refresh) to ...{token[-8:]}")
                        else:
                            logger.error(f"FCM v1 retry failed: {retry_resp.status_code}")
                else:
                    logger.error(f"FCM v1 error ({resp.status_code}): {resp.text[:200]}")
            except Exception as e:
                logger.error(f"FCM v1 send failed for token ...{token[-8:]}: {e}")

    # Cleanup invalid tokens
    if invalid_tokens:
        await _cleanup_invalid_tokens(invalid_tokens)


async def _cleanup_invalid_tokens(tokens: List[str]) -> None:
    """Remove tokens that FCM reports as invalid."""
    from app.database import AsyncSessionLocal
    try:
        async with AsyncSessionLocal() as db:
            from sqlalchemy import delete as sa_delete
            await db.execute(
                sa_delete(FcmToken).where(FcmToken.token.in_(tokens))
            )
            await db.commit()
            logger.info(f"Cleaned up {len(tokens)} invalid FCM tokens")
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
        body_text = "\U0001f4f7 Photo"
    elif msg_type == "video":
        body_text = "\U0001f3ac Video"
    elif msg_type == "voice":
        body_text = "\U0001f3a4 Voice note"
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
        title=f"\U0001f514 New Reminder from {creator_name}",
        body=f"{reminder_name} \u2014 {remind_date} at {remind_time}",
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
        title="\u26a1 Reminder Alert!",
        body=f"{reminder_name} (set by {creator_name}) is due NOW!",
        data={"type": "reminder_alert", "title": reminder_name},
    )
