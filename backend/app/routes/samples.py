from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import cloudinary
import cloudinary.uploader
from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import Sample, User
from app.config import get_settings

settings = get_settings()
router = APIRouter(prefix="/api/samples", tags=["Samples"])

cloudinary.config(
    cloud_name=settings.CLOUDINARY_CLOUD_NAME,
    api_key=settings.CLOUDINARY_API_KEY,
    api_secret=settings.CLOUDINARY_API_SECRET,
)


# ── Schemas ──
class SampleOut(BaseModel):
    id: int
    name: str
    description: Optional[str]
    image_url: Optional[str]
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Routes ──
@router.get("/", response_model=list[SampleOut])
async def get_samples(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Sample)
        .where(Sample.user_id == current_user.id)
        .order_by(Sample.created_at.desc())
    )
    return result.scalars().all()


@router.post("/upload", response_model=SampleOut, status_code=status.HTTP_201_CREATED)
async def upload_sample(
    file: UploadFile = File(...),
    name: str = "Sample",
    description: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    contents = await file.read()

    # Upload to Cloudinary
    upload_result = cloudinary.uploader.upload(
        contents,
        folder="sahjanand/samples",
        public_id=f"sample_{current_user.id}_{file.filename}",
    )

    sample = Sample(
        user_id=current_user.id,
        name=name,
        description=description,
        image_url=upload_result["secure_url"],
        public_id=upload_result["public_id"],
    )
    db.add(sample)
    await db.flush()
    await db.refresh(sample)
    return sample


@router.delete("/{sample_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sample(
    sample_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Sample).where(
            Sample.id == sample_id,
            Sample.user_id == current_user.id,
        )
    )
    sample = result.scalar_one_or_none()
    if not sample:
        raise HTTPException(status_code=404, detail="Sample not found")

    # Remove from Cloudinary too
    if sample.public_id:
        cloudinary.uploader.destroy(sample.public_id)

    await db.delete(sample)
