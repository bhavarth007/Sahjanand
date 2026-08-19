"""
FCM Push Notification sender.
Uses the Firebase Cloud Messaging HTTP v1 API (replaces deprecated Legacy API).
Requires a Firebase service account JSON file.
Set FIREBASE_CREDENTIALS_JSON env var to the path of the service account JSON file,
or set FIREBASE_CREDENTIALS_JSON_CONTENT to the raw JSON string (for cloud deployments).
"""
import json
import logging
import datetime
from typing import List, Optional
from pathlib import Path

import httpx
from google.oauth2 import service_account
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.db_models import FcmToken
from app.config import get_settings

logger = logging.getLogger(__name__)

# FCM v1 API endpoint template
FCM_V1_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
TOKEN_URL = "https://oauth2.googleapis.com/token"

# Cached state
_credentials = None
_project_id = None
_access_token = None
_token_expiry = None


def _load_credentials():
    """Load Firebase service account credentials from env."""
    global _credentials, _project_id

    if _credentials is not None:
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
    global _access_token, _token_expiry, _credentials

    # Return cached token if still valid (with 60s margin)
    if _access_token and _token_expiry:
        if datetime.datetime.utcnow() < _token_expiry - datetime.timedelta(seconds=60):
            return _access_token

    creds, _ = _load_credentials()
    if creds is None:
        return None

    try:
        # Create JWT assertion and exchange for access token
        # This uses google-auth's internal method to create the signed JWT
        assertion = creds._make_authorization_grant_assertion()

        # Exchange JWT assertion for access token using httpx (sync, quick call)
        response = httpx.post(
            TOKEN_URL,
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            },
            timeout=10.0,
        )

        if response.status_code == 200:
            token_data = response.json()
            _access_token = token_data["access_token"]
            expires_in = token_data.get("expires_in", 3600)
            _token_expiry = datetime.datetime.utcnow() + datetime.timedelta(seconds=expires_in)
            logger.info("FCM access token refreshed successfully")
            return _access_token
        else:
            logger.error(f"Failed to get FCM access token: {response.status_code} {response.text[:200]}")
            return None
    except Exception as e:
        logger.error(f"Failed to get FCM access token: {e}")
        return None


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
    collapse_key: Optional[str] = None,
    ttl_seconds: int = 3600,
) -> None:
    """
    Send push notification using NOTIFICATION+DATA hybrid message.
    Uses the FCM HTTP v1 API (OAuth2 authenticated).
    
    Strategy: NOTIFICATION + DATA hybrid (Telegram/WhatsApp approach)
    ─────────────────────────────────────────────────────────────────
    WHY hybrid instead of data-only:
    - Data-only messages require the Flutter background isolate to wake up
      and show a notification. On aggressive OEM phones (Xiaomi, Samsung, 
      Oppo, Vivo, Realme), the OS kills the app process completely and the
      background isolate NEVER starts → notification is silently lost.
    - With notification+data hybrid, Android OS ITSELF shows the notification
      from the 'notification' field even when the app is completely dead.
      The app doesn't need to be running at all.
    - When the app IS in foreground, we suppress the system notification
      (via setForegroundNotificationPresentationOptions) and show our own
      custom rich notification instead.
    
    Behavior by app state:
    - FOREGROUND: onMessage fires → we show custom notification (system suppressed)
    - BACKGROUND: System shows notification from 'notification' field + 
      onBackgroundMessage fires (we skip showing to avoid duplicates)
    - KILLED: System shows notification from 'notification' field.
      App doesn't need to wake up at all.
    
    This matches how Telegram works: notifications arrive even when app is
    force-stopped, because the OS handles display directly from FCM payload.
    """
    access_token = _get_access_token()
    if not access_token:
        return

    _, project_id = _load_credentials()
    if not project_id:
        return

    url = FCM_V1_URL.format(project_id=project_id)

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }

    # Build data payload — include title and body as data fields
    # FCM v1 requires all data values to be strings
    str_data = {k: str(v) for k, v in (data or {}).items()}
    str_data["title"] = title
    str_data["body"] = body
    # Add timestamp so client can detect stale messages
    str_data["sent_at"] = str(int(datetime.datetime.utcnow().timestamp()))

    # Determine notification channel based on type
    notif_type = (data or {}).get("type", "")
    if notif_type in ("reminder_alert", "reminder"):
        channel_id = "sahjanand_reminders"
        sound = "alarm_tone"
    else:
        channel_id = "sahjanand_chat"
        sound = "chat_tone"

    # Android config — high priority wakes device from Doze.
    # The 'notification' sub-object tells Android OS how to display when app is killed.
    # channel_id must match exactly what Flutter creates on the device.
    # sound is for Android 7 and below; Android 8+ uses the channel's sound setting.
    android_config = {
        "priority": "high",
        "ttl": f"{ttl_seconds}s",
        "direct_boot_ok": True,
        "notification": {
            "channel_id": channel_id,
            "sound": sound,
            "notification_priority": "PRIORITY_HIGH",
        },
    }
    if collapse_key:
        android_config["collapse_key"] = collapse_key

    invalid_tokens = []

    async with httpx.AsyncClient(timeout=15.0) as client:
        for token in tokens:
            # NOTIFICATION+DATA hybrid message:
            # - 'notification' field: shown by Android OS when app is background/killed
            # - 'data' field: available to the Flutter handler when app is alive
            # The Flutter foreground handler suppresses system notification and shows custom one.
            message = {
                "message": {
                    "token": token,
                    "notification": {
                        "title": title,
                        "body": body,
                    },
                    "data": str_data,
                    "android": android_config,
                }
            }

            try:
                resp = await client.post(url, json=message, headers=headers)
                if resp.status_code == 200:
                    logger.info(f"FCM v1 sent to ...{token[-8:]}")
                elif resp.status_code in (404, 400):
                    try:
                        error_data = resp.json()
                        error_msg = error_data.get("error", {}).get("message", "")
                        if "not found" in error_msg.lower() or "UNREGISTERED" in error_msg.upper():
                            invalid_tokens.append(token)
                            logger.info(f"FCM token unregistered: ...{token[-8:]}")
                        else:
                            logger.error(f"FCM v1 error ({resp.status_code}): {resp.text[:200]}")
                    except Exception:
                        logger.error(f"FCM v1 error ({resp.status_code}): {resp.text[:200]}")
                elif resp.status_code == 401:
                    # Access token expired mid-request, refresh and retry once
                    global _access_token, _token_expiry
                    _access_token = None
                    _token_expiry = None
                    new_token = _get_access_token()
                    if new_token:
                        headers["Authorization"] = f"Bearer {new_token}"
                        retry_resp = await client.post(url, json=message, headers=headers)
                        if retry_resp.status_code == 200:
                            logger.info(f"FCM v1 sent (refreshed) to ...{token[-8:]}")
                        else:
                            logger.error(f"FCM v1 retry error: {retry_resp.status_code}")
                else:
                    logger.error(f"FCM v1 error ({resp.status_code}): {resp.text[:200]}")
            except Exception as e:
                logger.error(f"FCM v1 send error for ...{token[-8:]}: {e}")

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


async def send_topic_notification(
    topic: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
    ttl_seconds: int = 3600,
) -> None:
    """
    Send a push notification to an FCM topic (all devices subscribed to it).
    
    This is the secondary delivery path inspired by Tinode's approach:
    - Primary: send to individual device tokens (fast, direct)
    - Secondary: send to topic (reliable, FCM manages delivery internally)
    
    FCM topics guarantee delivery to ALL subscribed devices, even those that
    were offline when the message was sent (up to TTL). This covers the case
    where a device's individual token push was lost but the device later
    reconnects and receives the topic message.
    
    NOTE: Topic messages are received by ALL devices subscribed to the topic,
    including the sender's device. The client-side code must handle deduplication
    (skip showing notification for own messages).
    """
    access_token = _get_access_token()
    if not access_token:
        return

    _, project_id = _load_credentials()
    if not project_id:
        return

    url = FCM_V1_URL.format(project_id=project_id)

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }

    # Build data payload
    str_data = {k: str(v) for k, v in (data or {}).items()}
    str_data["title"] = title
    str_data["body"] = body
    str_data["sent_at"] = str(int(datetime.datetime.utcnow().timestamp()))

    message = {
        "message": {
            "topic": topic,
            "data": str_data,
            "android": {
                "priority": "high",
                "ttl": f"{ttl_seconds}s",
                "direct_boot_ok": True,
            },
        }
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, json=message, headers=headers)
            if resp.status_code == 200:
                logger.info(f"[FCM Topic] Sent to topic '{topic}'")
            elif resp.status_code == 401:
                global _access_token, _token_expiry
                _access_token = None
                _token_expiry = None
                new_token = _get_access_token()
                if new_token:
                    headers["Authorization"] = f"Bearer {new_token}"
                    retry_resp = await client.post(url, json=message, headers=headers)
                    if retry_resp.status_code == 200:
                        logger.info(f"[FCM Topic] Sent (refreshed) to topic '{topic}'")
                    else:
                        logger.error(f"[FCM Topic] Retry error: {retry_resp.status_code}")
            else:
                logger.error(f"[FCM Topic] Error ({resp.status_code}): {resp.text[:200]}")
    except Exception as e:
        logger.error(f"[FCM Topic] Send error for topic '{topic}': {e}")


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
    group_id: int = 0,
    message_id: int = 0,
) -> None:
    """Send push notification for new chat messages to all group members except sender.
    
    Includes message_id in data payload so the receiving client can send a delivery
    acknowledgement back to the server (triggering the double-grey tick for the sender).
    
    Uses collapse_key per group so rapid messages don't get rate-limited by FCM.
    TTL of 3600s (1 hour) ensures messages are queued and delivered even if the
    device is in Doze mode or the app is killed — FCM will hold the message and
    deliver it when the device next connects (up to 1 hour).
    """
    target_ids = [uid for uid in recipient_user_ids if uid != sender_id]
    if not target_ids:
        logger.debug(f"[Chat Push] No offline targets for group '{group_name}' (sender={sender_id})")
        return

    tokens = await get_multiple_users_fcm_tokens(target_ids, db)
    if not tokens:
        logger.debug(f"[Chat Push] No FCM tokens for {len(target_ids)} offline users in '{group_name}'")
        return

    logger.info(f"[Chat Push] Sending to {len(tokens)} tokens for {len(target_ids)} offline users in '{group_name}' (sender={sender_name})")

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
        data={
            "type": "chat",
            "group_name": group_name,
            "group_id": str(group_id),
            "sender_id": str(sender_id),
            "message_id": str(message_id),  # For delivery ACK
        },
        # collapse_key groups by chat group — prevents FCM rate-limiting
        # when many messages are sent rapidly in one group
        collapse_key=f"chat_group_{group_id}",
        # 1 hour TTL — message survives Doze mode and app-killed state
        ttl_seconds=3600,
    )

    # NOTE: Topic notification removed — with hybrid notification+data approach,
    # individual token messages are now reliably delivered by the OS even when app
    # is killed. Topic messages would cause duplicates (both topic AND token arrive).
    # The individual push is sufficient and more reliable.


async def notify_reminder_created(
    creator_name: str,
    reminder_name: str,
    remind_date: str,
    remind_time: str,
    target_user_ids: List[int],
    db: AsyncSession,
) -> None:
    """Send push notification when a new reminder is created.
    
    Uses a longer TTL (7200s = 2 hours) since reminder creation is a one-time
    event that users should always see, even if their device is temporarily offline.
    """
    if not target_user_ids:
        return

    tokens = await get_multiple_users_fcm_tokens(target_user_ids, db)
    if not tokens:
        logger.debug(f"[Reminder Push] No FCM tokens for {len(target_user_ids)} target users")
        return

    logger.info(f"[Reminder Push] Sending 'created' notification to {len(tokens)} tokens — '{reminder_name}' by {creator_name}")

    await send_push_notification(
        tokens=tokens,
        title=f"\U0001f514 New Reminder from {creator_name}",
        body=f"{reminder_name} \u2014 {remind_date} at {remind_time}",
        data={"type": "reminder", "title": reminder_name},
        collapse_key="reminder_created",
        ttl_seconds=7200,  # 2 hours — user should always see reminder creation
    )


async def notify_reminder_due(
    reminder_name: str,
    creator_name: str,
    target_user_ids: List[int],
    db: AsyncSession,
) -> None:
    """Send push notification when a reminder is due (2 min before or at deadline).
    
    Uses NO collapse_key so each reminder alert is delivered individually.
    TTL of 600s (10 minutes) — reminder alerts are time-sensitive; no point
    delivering them hours after they were due. Short TTL ensures the device
    gets it soon or the alarm backup handles it.
    """
    if not target_user_ids:
        return

    tokens = await get_multiple_users_fcm_tokens(target_user_ids, db)
    if not tokens:
        logger.debug(f"[Reminder Push] No FCM tokens for {len(target_user_ids)} target users (due alert)")
        return

    logger.info(f"[Reminder Push] Sending DUE alert to {len(tokens)} tokens — '{reminder_name}'")

    await send_push_notification(
        tokens=tokens,
        title="\u26a1 Reminder Alert!",
        body=f"{reminder_name} (set by {creator_name}) is due NOW!",
        data={"type": "reminder_alert", "title": reminder_name},
        # No collapse_key — each reminder alert should be delivered individually
        collapse_key=None,
        # 10 minutes — reminder alerts are time-sensitive
        ttl_seconds=600,
    )
