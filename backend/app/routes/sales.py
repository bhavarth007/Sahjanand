from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import Optional
from pydantic import BaseModel
from decimal import Decimal
from datetime import datetime
from app.auth import get_current_user
from app.database import get_db
from app.models.db_models import Sale, User

router = APIRouter(prefix="/api/sales", tags=["Sales"])


# ── Schemas ──
class SaleCreate(BaseModel):
    customer: str
    product: str
    amount: Decimal
    status: Optional[str] = "pending"
    notes: Optional[str] = None


class SaleOut(BaseModel):
    id: int
    customer: str
    product: str
    amount: Decimal
    status: str
    notes: Optional[str]
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Routes ──
@router.get("/")
async def get_sales(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Sale)
        .where(Sale.user_id == current_user.id)
        .order_by(Sale.created_at.desc())
    )
    items = result.scalars().all()

    total = sum(s.amount for s in items)
    return {
        "total": float(total),
        "count": len(items),
        "items": [SaleOut.model_validate(s) for s in items],
    }


@router.post("/", response_model=SaleOut, status_code=status.HTTP_201_CREATED)
async def create_sale(
    data: SaleCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sale = Sale(user_id=current_user.id, **data.model_dump())
    db.add(sale)
    await db.flush()
    await db.refresh(sale)
    return sale


@router.patch("/{sale_id}", response_model=SaleOut)
async def update_sale(
    sale_id: int,
    data: SaleCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Sale).where(Sale.id == sale_id, Sale.user_id == current_user.id)
    )
    sale = result.scalar_one_or_none()
    if not sale:
        raise HTTPException(status_code=404, detail="Sale not found")

    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(sale, field, value)
    await db.flush()
    await db.refresh(sale)
    return sale


@router.delete("/{sale_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sale(
    sale_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Sale).where(Sale.id == sale_id, Sale.user_id == current_user.id)
    )
    sale = result.scalar_one_or_none()
    if not sale:
        raise HTTPException(status_code=404, detail="Sale not found")
    await db.delete(sale)
