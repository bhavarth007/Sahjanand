"""
Job Card Voucher API — CRUD for production job cards
"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime

from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import JobCard, User

router = APIRouter(prefix="/api/job-cards", tags=["Job Cards"])


class JobCardCreate(BaseModel):
    job_name: Optional[str] = None
    j_card_no: Optional[str] = None
    p_name: Optional[str] = None
    so_no: Optional[str] = None
    quality: Optional[str] = None
    design_no: Optional[str] = None
    total_card: Optional[str] = None
    g_pick: Optional[str] = None
    jc_date: Optional[str] = None
    j_ord_no: Optional[str] = None
    repeat_mtr: Optional[str] = None
    repeat_pcs: Optional[str] = None
    total_pcs: Optional[str] = None
    weight_per_pcs: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    op_name: Optional[str] = None
    remark: Optional[str] = None
    supervisor_sign: Optional[str] = None
    program_matching: Optional[str] = None
    taka_rows: Optional[str] = None
    image_url: Optional[str] = None


class JobCardOut(BaseModel):
    id: int
    user_id: int
    job_name: Optional[str] = None
    j_card_no: Optional[str] = None
    p_name: Optional[str] = None
    so_no: Optional[str] = None
    quality: Optional[str] = None
    design_no: Optional[str] = None
    total_card: Optional[str] = None
    g_pick: Optional[str] = None
    jc_date: Optional[str] = None
    j_ord_no: Optional[str] = None
    repeat_mtr: Optional[str] = None
    repeat_pcs: Optional[str] = None
    total_pcs: Optional[str] = None
    weight_per_pcs: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    op_name: Optional[str] = None
    remark: Optional[str] = None
    supervisor_sign: Optional[str] = None
    program_matching: Optional[str] = None
    taka_rows: Optional[str] = None
    image_url: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


# ── GET all job cards ──
@router.get("/", response_model=List[JobCardOut])
async def list_job_cards(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(JobCard).order_by(JobCard.created_at.desc())
    )
    return result.scalars().all()


# ── GET single job card ──
@router.get("/{jid}", response_model=JobCardOut)
async def get_job_card(
    jid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")
    return card


# ── POST create job card ──
@router.post("/", response_model=JobCardOut, status_code=201)
async def create_job_card(
    body: JobCardCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not body.image_url:
        raise HTTPException(400, "Image is required. Please upload an image first.")

    card = JobCard(user_id=current_user.id, **body.model_dump())
    db.add(card)
    await db.flush()
    await db.refresh(card)
    return card


# ── PATCH update job card ──
@router.patch("/{jid}", response_model=JobCardOut)
async def update_job_card(
    jid: int,
    body: JobCardCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if value is not None:
            setattr(card, field, value)

    await db.flush()
    await db.refresh(card)
    return card


# ── DELETE job card ──
@router.delete("/{jid}")
async def delete_job_card(
    jid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")
    await db.delete(card)
    await db.flush()
    return {"ok": True}
