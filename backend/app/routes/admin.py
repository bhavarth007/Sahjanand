"""
Admin — User Access Rights Management
=======================================
Only users with is_admin=True can access these endpoints.
"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel

from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import User

router = APIRouter(prefix="/api/admin", tags=["Admin"])


# ── Schemas ─────────────────────────────────────────────────────
class UserAccessOut(BaseModel):
    id:                 int
    email:              str
    full_name:          Optional[str]
    is_admin:           bool
    is_active:          bool
    chat_can_send:      bool
    designation:        Optional[str] = None
    mobile_no:          Optional[str] = None
    plain_password:     Optional[str] = None  # visible to admin only
    can_view_sales:     bool
    can_view_reminders: bool
    can_view_samples:   bool
    can_view_chat:      bool

    model_config = {"from_attributes": True}


class AccessUpdate(BaseModel):
    can_view_sales:     Optional[bool] = None
    can_view_reminders: Optional[bool] = None
    can_view_samples:   Optional[bool] = None
    can_view_chat:      Optional[bool] = None
    chat_can_send:      Optional[bool] = None


# ── Helper — enforce admin ──────────────────────────────────────
def require_admin(user: User):
    if not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required.",
        )


# ── GET /api/admin/users ────────────────────────────────────────
@router.get("/users", response_model=List[UserAccessOut])
async def list_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_admin(current_user)
    result = await db.execute(
        select(User).where(User.is_active == True).order_by(User.full_name)
    )
    return result.scalars().all()


# ── PATCH /api/admin/users/{uid}/access ─────────────────────────
@router.patch("/users/{uid}/access", response_model=UserAccessOut)
async def update_user_access(
    uid: int,
    body: AccessUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_admin(current_user)

    result = await db.execute(select(User).where(User.id == uid))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="User not found.")

    # Update only the fields that are provided
    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(target, field, value)

    await db.flush()
    await db.refresh(target)
    return target

# ══════════════════════════════════════════════════════════════════
# User CRUD — Admin can add, edit, and delete users
# ══════════════════════════════════════════════════════════════════

from pydantic import EmailStr
from app.auth import hash_password


class UserCreateByAdmin(BaseModel):
    email: EmailStr
    password: str
    full_name: Optional[str] = None
    designation: Optional[str] = None
    mobile_no: Optional[str] = None


class UserEditByAdmin(BaseModel):
    email:       Optional[EmailStr] = None
    password:    Optional[str] = None
    full_name:   Optional[str] = None
    designation: Optional[str] = None
    mobile_no:   Optional[str] = None


# ── POST /api/admin/users — create a new user ──────────────────
@router.post("/users", response_model=UserAccessOut, status_code=status.HTTP_201_CREATED)
async def create_user(
    body: UserCreateByAdmin,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_admin(current_user)

    # Check duplicate email
    result = await db.execute(select(User).where(User.email == body.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered.")

    # Validate mobile_no: exactly 10 digits, unique
    mobile = None
    if body.mobile_no:
        cleaned = body.mobile_no.strip().replace(" ", "")
        if not cleaned.isdigit() or len(cleaned) != 10:
            raise HTTPException(status_code=400, detail="Mobile number must be exactly 10 digits.")
        dup = await db.execute(select(User).where(User.mobile_no == cleaned))
        if dup.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Mobile number already registered.")
        mobile = cleaned

    new_user = User(
        email=body.email,
        password=hash_password(body.password),
        plain_password=body.password,  # Store plain for admin visibility
        full_name=body.full_name or "",
        designation=body.designation,
        mobile_no=mobile,
        is_active=True,
    )
    db.add(new_user)
    await db.flush()
    await db.refresh(new_user)
    return new_user


# ── PATCH /api/admin/users/{uid} — edit user (name/email/password) ─
@router.patch("/users/{uid}", response_model=UserAccessOut)
async def edit_user(
    uid: int,
    body: UserEditByAdmin,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_admin(current_user)

    result = await db.execute(select(User).where(User.id == uid))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="User not found.")

    if body.email is not None and body.email != target.email:
        # Check duplicate
        dup = await db.execute(select(User).where(User.email == body.email))
        if dup.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Email already in use.")
        target.email = body.email

    if body.full_name is not None:
        target.full_name = body.full_name

    if body.designation is not None:
        target.designation = body.designation

    if body.mobile_no is not None:
        cleaned = body.mobile_no.strip().replace(" ", "")
        if cleaned == "":
            target.mobile_no = None
        else:
            if not cleaned.isdigit() or len(cleaned) != 10:
                raise HTTPException(status_code=400, detail="Mobile number must be exactly 10 digits.")
            dup = await db.execute(select(User).where(User.mobile_no == cleaned, User.id != uid))
            if dup.scalar_one_or_none():
                raise HTTPException(status_code=400, detail="Mobile number already in use.")
            target.mobile_no = cleaned

    if body.password is not None and body.password.strip():
        target.password = hash_password(body.password)
        target.plain_password = body.password.strip()  # Update plain text copy

    await db.flush()
    await db.refresh(target)
    return target


# ── DELETE /api/admin/users/{uid} — soft-delete (deactivate) ────
@router.delete("/users/{uid}", status_code=status.HTTP_200_OK)
async def delete_user(
    uid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_admin(current_user)

    if uid == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete yourself.")

    result = await db.execute(select(User).where(User.id == uid))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="User not found.")

    target.is_active = False
    await db.flush()
    return {"ok": True, "message": f"User {target.email} deactivated."}
