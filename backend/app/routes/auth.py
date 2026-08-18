from fastapi import APIRouter, HTTPException, status, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.user import UserCreate, UserLogin, Token, UserOut, UserUpdate, ForgotPasswordRequest
from app.models.db_models import User
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

    token = create_access_token({"sub": user.email})
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
