"""
Job Card Voucher API — CRUD + Workflow Management
==================================================
Workflow stages (in order):
  NEW → SUPERVISOR_CLEARANCE → MANDING_DEPARTMENT → BUTTA_CUTTING → MILL → BORDER → FINAL → COMPLETED

Additional state: CANCELLED (can return to NEW via re-accept)

Endpoints:
  GET    /api/job-cards/                  → list job cards (paginated, filterable by status)
  GET    /api/job-cards/next-number       → get next auto-increment j_card_no
  GET    /api/job-cards/{jid}             → get single job card
  POST   /api/job-cards/                  → create new job card (status=NEW)
  PATCH  /api/job-cards/{jid}             → update job card fields
  DELETE /api/job-cards/{jid}             → delete job card
  POST   /api/job-cards/{jid}/transition  → move job card to next workflow stage
  POST   /api/job-cards/{jid}/cancel      → cancel job card (with reason)
  POST   /api/job-cards/{jid}/border      → save border form data and move to FINAL
"""
import json
import logging
from typing import List, Optional
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func as sa_func
from pydantic import BaseModel

from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import JobCard, User

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/job-cards", tags=["Job Cards"])

# ═══════════════════════════════════════════════════════════════
# Workflow constants
# ═══════════════════════════════════════════════════════════════
WORKFLOW_STAGES = [
    "NEW",
    "SUPERVISOR_CLEARANCE",
    "MANDING_DEPARTMENT",
    "BUTTA_CUTTING",
    "MILL",
    "BORDER",
    "FINAL",
    "COMPLETED",
]

# Valid transitions: from_status → [allowed next statuses]
VALID_TRANSITIONS = {
    "NEW": ["SUPERVISOR_CLEARANCE"],
    "SUPERVISOR_CLEARANCE": ["MANDING_DEPARTMENT"],
    "MANDING_DEPARTMENT": ["BUTTA_CUTTING"],
    "BUTTA_CUTTING": ["MILL"],
    "MILL": ["BORDER"],
    "BORDER": ["FINAL"],
    "FINAL": ["COMPLETED"],
    # CANCELLED can go back to SUPERVISOR_CLEARANCE (re-accept from ALL JOB CARDS)
    "CANCELLED": ["SUPERVISOR_CLEARANCE"],
}


# ═══════════════════════════════════════════════════════════════
# Pydantic schemas
# ═══════════════════════════════════════════════════════════════
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
    workflow_status: str = "NEW"
    # Border fields
    border_job_m: Optional[str] = None
    border_work_m: Optional[str] = None
    border_lapet_m: Optional[str] = None
    border_blause_m: Optional[str] = None
    border_total_cut_m: Optional[str] = None
    border_rs_inch: Optional[str] = None
    border_description: Optional[str] = None
    # Cancellation
    cancel_reason: Optional[str] = None
    cancel_stage: Optional[str] = None
    cancelled_at: Optional[datetime] = None
    cancellation_history: Optional[str] = None
    # Final confirmation
    confirmed_by_name: Optional[str] = None
    confirmed_at: Optional[datetime] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class TransitionRequest(BaseModel):
    target_status: str


class CancelRequest(BaseModel):
    reason: str


class BorderFormData(BaseModel):
    border_job_m: str
    border_work_m: str
    border_lapet_m: str
    border_blause_m: str
    border_total_cut_m: str
    border_rs_inch: str
    border_description: str


class PaginatedResponse(BaseModel):
    items: List[JobCardOut]
    total: int
    page: int
    page_size: int
    total_pages: int


# ═══════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════
async def _next_j_card_no(db: AsyncSession) -> str:
    """Returns the next auto-incremented j_card_no (as string), starting from 1."""
    result = await db.execute(select(JobCard.j_card_no))
    all_numbers = result.scalars().all()
    max_val = 0
    for val in all_numbers:
        if val:
            try:
                num = int(val)
                if num > max_val:
                    max_val = num
            except (ValueError, TypeError):
                pass
    return str(max_val + 1)


# ═══════════════════════════════════════════════════════════════
# GET endpoints
# ═══════════════════════════════════════════════════════════════

@router.get("/next-number")
async def get_next_number(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get next auto-increment J.Card number for frontend display."""
    return {"next_number": await _next_j_card_no(db)}


@router.get("/", response_model=PaginatedResponse)
async def list_job_cards(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    status: Optional[str] = Query(None, description="Filter by workflow_status (comma-separated for multiple)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(5, ge=1, le=50),
):
    """
    List job cards with pagination and optional status filter.
    - status=NEW → only NEW cards
    - status=NEW,CANCELLED → NEW and CANCELLED cards
    - No status → all cards
    Sorted by created_at DESC (newest first).
    """
    query = select(JobCard).order_by(JobCard.created_at.desc())
    count_query = select(sa_func.count(JobCard.id))

    if status:
        statuses = [s.strip().upper() for s in status.split(",")]
        query = query.where(JobCard.workflow_status.in_(statuses))
        count_query = count_query.where(JobCard.workflow_status.in_(statuses))

    # Get total count
    total_result = await db.execute(count_query)
    total = total_result.scalar() or 0

    # Paginate
    offset = (page - 1) * page_size
    query = query.offset(offset).limit(page_size)

    result = await db.execute(query)
    items = result.scalars().all()

    total_pages = max(1, (total + page_size - 1) // page_size)

    return PaginatedResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/{jid}", response_model=JobCardOut)
async def get_job_card(
    jid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a single job card by ID."""
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")
    return card


# ═══════════════════════════════════════════════════════════════
# POST / PATCH / DELETE — CRUD
# ═══════════════════════════════════════════════════════════════

@router.post("/", response_model=JobCardOut, status_code=201)
async def create_job_card(
    body: JobCardCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new job card. Status starts as NEW."""
    if not body.image_url:
        raise HTTPException(400, "Image is required. Please upload an image first.")

    body_data = body.model_dump()
    body_data["j_card_no"] = await _next_j_card_no(db)

    card = JobCard(user_id=current_user.id, workflow_status="NEW", **body_data)
    db.add(card)
    await db.flush()
    await db.refresh(card)
    return card


@router.patch("/{jid}", response_model=JobCardOut)
async def update_job_card(
    jid: int,
    body: JobCardCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update job card fields. Only allowed when status is NEW or CANCELLED."""
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")

    if card.workflow_status not in ("NEW", "CANCELLED"):
        raise HTTPException(400, f"Cannot edit job card in '{card.workflow_status}' stage. Only NEW or CANCELLED cards can be edited.")

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if value is not None:
            setattr(card, field, value)

    await db.flush()
    await db.refresh(card)
    return card


@router.delete("/{jid}")
async def delete_job_card(
    jid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a job card. Allowed from ALL JOB CARDS (NEW/CANCELLED) and FINAL stage."""
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")

    if card.workflow_status not in ("NEW", "CANCELLED", "FINAL"):
        raise HTTPException(400, f"Cannot delete job card in '{card.workflow_status}' stage.")

    await db.delete(card)
    await db.flush()
    return {"ok": True}


# ═══════════════════════════════════════════════════════════════
# WORKFLOW TRANSITION
# ═══════════════════════════════════════════════════════════════

@router.post("/{jid}/transition", response_model=JobCardOut)
async def transition_job_card(
    jid: int,
    body: TransitionRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Move a job card to the next workflow stage.
    Validates that the transition is allowed.
    
    Valid transitions:
    NEW → SUPERVISOR_CLEARANCE (Accept)
    SUPERVISOR_CLEARANCE → MANDING_DEPARTMENT (Confirm)
    MANDING_DEPARTMENT → BUTTA_CUTTING (Confirm)
    BUTTA_CUTTING → MILL (Confirm)
    MILL → BORDER (Confirm)
    BORDER → FINAL (handled by /border endpoint instead)
    FINAL → COMPLETED (Final Confirm)
    CANCELLED → SUPERVISOR_CLEARANCE (Re-accept)
    """
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")

    target = body.target_status.strip().upper()
    current = card.workflow_status

    # Validate transition
    allowed = VALID_TRANSITIONS.get(current, [])
    if target not in allowed:
        raise HTTPException(
            400,
            f"Invalid transition: '{current}' → '{target}'. "
            f"Allowed: {allowed}"
        )

    # If re-accepting from CANCELLED, clear cancellation markers
    if current == "CANCELLED" and target == "SUPERVISOR_CLEARANCE":
        card.cancel_reason = None
        card.cancel_stage = None
        card.cancelled_at = None
        card.cancelled_by = None
        # Keep cancellation_history — it's append-only

    # If finalizing (FINAL → COMPLETED), save who confirmed it
    if current == "FINAL" and target == "COMPLETED":
        card.confirmed_by = current_user.id
        card.confirmed_by_name = current_user.full_name or current_user.email
        card.confirmed_at = datetime.now(timezone.utc)

    card.workflow_status = target
    await db.flush()
    await db.refresh(card)

    logger.info(f"[Workflow] Job Card #{card.j_card_no} (id={jid}): {current} → {target} by user {current_user.id}")
    return card


# ═══════════════════════════════════════════════════════════════
# CANCELLATION (from Supervisor Clearance)
# ═══════════════════════════════════════════════════════════════

@router.post("/{jid}/cancel", response_model=JobCardOut)
async def cancel_job_card(
    jid: int,
    body: CancelRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Cancel a job card from SUPERVISOR_CLEARANCE stage.
    Requires a reason. Moves status to CANCELLED.
    The card will appear in ALL JOB CARDS with RED indication.
    Can be re-accepted to restart workflow.
    """
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")

    if card.workflow_status != "SUPERVISOR_CLEARANCE":
        raise HTTPException(400, f"Can only cancel from SUPERVISOR_CLEARANCE stage. Current: {card.workflow_status}")

    reason = body.reason.strip()
    if not reason:
        raise HTTPException(400, "Cancellation reason is required.")

    # Save cancellation info
    card.cancel_reason = reason
    card.cancel_stage = "SUPERVISOR_CLEARANCE"
    card.cancelled_by = current_user.id
    card.cancelled_at = datetime.now(timezone.utc)
    card.workflow_status = "CANCELLED"

    # Append to cancellation history (JSON array)
    history = []
    if card.cancellation_history:
        try:
            history = json.loads(card.cancellation_history)
        except (json.JSONDecodeError, TypeError):
            history = []

    history.append({
        "stage": "SUPERVISOR_CLEARANCE",
        "reason": reason,
        "user_id": current_user.id,
        "user_name": current_user.full_name or current_user.email,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })
    card.cancellation_history = json.dumps(history)

    await db.flush()
    await db.refresh(card)

    logger.info(f"[Workflow] Job Card #{card.j_card_no} CANCELLED by {current_user.full_name}: {reason}")
    return card


# ═══════════════════════════════════════════════════════════════
# BORDER FORM (save border data + transition to FINAL)
# ═══════════════════════════════════════════════════════════════

@router.post("/{jid}/border", response_model=JobCardOut)
async def save_border_and_confirm(
    jid: int,
    body: BorderFormData,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Save Border form data and move the job card to FINAL stage.
    All border fields are required.
    Only allowed when status is BORDER.
    """
    result = await db.execute(select(JobCard).where(JobCard.id == jid))
    card = result.scalar_one_or_none()
    if not card:
        raise HTTPException(404, "Job card not found.")

    if card.workflow_status != "BORDER":
        raise HTTPException(400, f"Can only save border data when status is BORDER. Current: {card.workflow_status}")

    # Validate all fields are non-empty
    for field_name in ["border_job_m", "border_work_m", "border_lapet_m", "border_blause_m", "border_total_cut_m", "border_rs_inch", "border_description"]:
        value = getattr(body, field_name, "").strip()
        if not value:
            raise HTTPException(400, f"Field '{field_name}' is required.")

    # Validate numeric fields
    numeric_fields = ["border_job_m", "border_work_m", "border_lapet_m", "border_blause_m", "border_total_cut_m", "border_rs_inch"]
    for field_name in numeric_fields:
        value = getattr(body, field_name, "").strip()
        try:
            float(value)
        except (ValueError, TypeError):
            raise HTTPException(400, f"Field '{field_name}' must be a valid number.")

    # Save border data
    card.border_job_m = body.border_job_m.strip()
    card.border_work_m = body.border_work_m.strip()
    card.border_lapet_m = body.border_lapet_m.strip()
    card.border_blause_m = body.border_blause_m.strip()
    card.border_total_cut_m = body.border_total_cut_m.strip()
    card.border_rs_inch = body.border_rs_inch.strip()
    card.border_description = body.border_description.strip()

    # Transition to FINAL
    card.workflow_status = "FINAL"
    await db.flush()
    await db.refresh(card)

    logger.info(f"[Workflow] Job Card #{card.j_card_no} BORDER completed → FINAL by user {current_user.id}")
    return card
