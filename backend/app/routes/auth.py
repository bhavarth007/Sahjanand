from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete as sa_delete
from pydantic import BaseModel
from typing import Optional
from app.models.user import UserCreate, UserLogin, Token, UserOut, UserUpdate, ForgotPasswordRequest
from app.models.db_models import User, FcmToken
from app.auth import hash_password, verify_password, create_access_token, get_current_user
from app.database import get_db

router = APIRouter(prefix="/api/auth", tags=["Authentication"])


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(user: UserCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == user.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    new_user = User(
        email=user.email,
        password=hash_password(user.password),
        full_name=user.full_name or "",
    )
    db.add(new_user)
    await db.flush()   # get the generated ID before commit
    await db.refresh(new_user)
    return new_user


@router.post("/login", response_model=Token)
async def login(credentials: UserLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == credentials.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(credentials.password, user.password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = create_access_token({"sub": user.email, "user_id": user.id})
    return Token(access_token=token, user=UserOut.model_validate(user))


@router.post("/forgot-password")
async def forgot_password(
    request: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()
    # Always return success — prevents email enumeration
    if user:
        # TODO: send reset email via SMTP
        pass
    return {"message": "If this email exists, a reset link has been sent."}


@router.get("/me", response_model=UserOut)
async def get_me(current_user: User = Depends(get_current_user)):
    return current_user


@router.put("/profile", response_model=UserOut)
async def update_profile(
    payload: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Validate mobile_no if provided
    if payload.mobile_no is not None:
        mobile = payload.mobile_no.strip()
        if mobile:
            if not mobile.isdigit() or len(mobile) != 10:
                raise HTTPException(status_code=400, detail="Mobile number must be exactly 10 digits")
            # Check uniqueness (exclude current user)
            result = await db.execute(
                select(User).where(User.mobile_no == mobile, User.id != current_user.id)
            )
            if result.scalar_one_or_none():
                raise HTTPException(status_code=400, detail="This mobile number is already registered to another user")
            current_user.mobile_no = mobile
        else:
            current_user.mobile_no = None

    if payload.full_name is not None:
        current_user.full_name = payload.full_name.strip()

    await db.flush()
    await db.refresh(current_user)
    return current_user


# ═══════════════════════════════════════════════════════════════
# FCM Token registration
# ═══════════════════════════════════════════════════════════════
class FcmTokenRequest(BaseModel):
    fcm_token: str
    device_info: Optional[str] = None


@router.post("/fcm-token")
async def register_fcm_token(
    payload: FcmTokenRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    token_str = payload.fcm_token.strip()
    if not token_str:
        raise HTTPException(status_code=400, detail="FCM token is required")

    # Check if token already exists
    result = await db.execute(select(FcmToken).where(FcmToken.token == token_str))
    existing = result.scalar_one_or_none()

    if existing:
        # Update ownership if token moved to a different user (device re-login)
        if existing.user_id != current_user.id:
            existing.user_id = current_user.id
            existing.device_info = payload.device_info
            await db.flush()
        return {"status": "updated"}

    # Create new token entry
    new_token = FcmToken(
        user_id=current_user.id,
        token=token_str,
        device_info=payload.device_info,
    )
    db.add(new_token)
    await db.flush()
    return {"status": "registered"}


@router.delete("/fcm-token")
async def remove_fcm_token(
    payload: FcmTokenRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove FCM token on logout."""
    await db.execute(
        sa_delete(FcmToken).where(
            FcmToken.token == payload.fcm_token.strip(),
            FcmToken.user_id == current_user.id,
        )
    )
    return {"status": "removed"}


# ═══════════════════════════════════════════════════════════════
# FCM Diagnostics — check if push notifications are configured
# ═══════════════════════════════════════════════════════════════
@router.get("/fcm-status")
async def fcm_status(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Diagnostic endpoint to check FCM configuration status.
    Returns whether Firebase credentials are configured, tokens registered, etc.
    """
    from app.notifications import _load_credentials, get_user_fcm_tokens
    from app.config import get_settings

    settings = get_settings()

    # Check Firebase credentials
    creds, project_id = _load_credentials()
    firebase_configured = creds is not None and project_id is not None

    # Check if FIREBASE_CREDENTIALS_JSON_CONTENT is set
    has_json_content = bool(settings.FIREBASE_CREDENTIALS_JSON_CONTENT)
    has_json_file = bool(settings.FIREBASE_CREDENTIALS_JSON)

    # Check user's FCM tokens
    tokens = await get_user_fcm_tokens(current_user.id, db)

    # Check total tokens in system
    total_result = await db.execute(select(FcmToken))
    total_tokens = len(total_result.all())

    return {
        "firebase_configured": firebase_configured,
        "firebase_project_id": project_id or "NOT SET",
        "credentials_source": "JSON_CONTENT env var" if has_json_content else ("JSON file" if has_json_file else "NOT CONFIGURED"),
        "your_user_id": current_user.id,
        "your_fcm_tokens_count": len(tokens),
        "your_fcm_tokens_preview": [f"...{t[-12:]}" for t in tokens],
        "total_fcm_tokens_in_db": total_tokens,
        "status": "READY" if (firebase_configured and len(tokens) > 0) else "NOT READY",
        "issues": _get_fcm_issues(firebase_configured, has_json_content, has_json_file, tokens),
    }


def _get_fcm_issues(firebase_configured, has_json_content, has_json_file, tokens):
    """List issues preventing FCM from working."""
    issues = []
    if not firebase_configured:
        if not has_json_content and not has_json_file:
            issues.append("FIREBASE_CREDENTIALS_JSON_CONTENT env var is not set on the server. You must set it to the Firebase service account JSON.")
        elif has_json_file:
            issues.append("FIREBASE_CREDENTIALS_JSON file path is set but the file might not exist or is invalid.")
        else:
            issues.append("Firebase credentials are set but failed to load (invalid JSON or missing project_id).")
    if not tokens:
        issues.append("No FCM device tokens registered for your account. The app must register its token after login.")
    if not issues:
        issues.append("None — FCM is fully configured and ready.")
    return issues


@router.post("/fcm-test")
async def test_fcm_notification(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Send a test push notification to the current user's devices.
    Use this to verify the entire FCM pipeline works.
    """
    from app.notifications import get_user_fcm_tokens, send_push_notification

    tokens = await get_user_fcm_tokens(current_user.id, db)
    if not tokens:
        raise HTTPException(400, "No FCM tokens registered for your account. Open the app first to register.")

    try:
        await send_push_notification(
            tokens=tokens,
            title="Test Notification",
            body=f"Hello {current_user.full_name or current_user.email}! FCM is working.",
            data={
                "type": "chat",
                "group_id": "0",
                "sender_id": "0",
                "message_id": "0",
            },
        )
        return {
            "status": "sent",
            "tokens_count": len(tokens),
            "message": f"Test notification sent to {len(tokens)} device(s). Check your phone.",
        }
    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "message": "Failed to send test notification. Check server logs.",
        }
