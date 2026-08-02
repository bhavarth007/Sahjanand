"""
SQLAlchemy ORM table definitions for PostgreSQL.
These map directly to database tables.
"""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text, Boolean, Numeric
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id         = Column(Integer, primary_key=True, index=True)
    email      = Column(String(255), unique=True, nullable=False, index=True)
    password   = Column(String(255), nullable=False)
    full_name  = Column(String(255), nullable=True)
    is_active  = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    sales     = relationship("Sale",     back_populates="user", cascade="all, delete-orphan")
    reminders = relationship("Reminder", back_populates="user", cascade="all, delete-orphan")
    samples   = relationship("Sample",   back_populates="user", cascade="all, delete-orphan")


class Sale(Base):
    __tablename__ = "sales"

    id           = Column(Integer, primary_key=True, index=True)
    user_id      = Column(Integer, ForeignKey("users.id"), nullable=False)
    customer     = Column(String(255), nullable=False)
    product      = Column(String(255), nullable=False)
    amount       = Column(Numeric(12, 2), nullable=False)
    status       = Column(String(50), default="pending")  # pending, completed, cancelled
    notes        = Column(Text, nullable=True)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="sales")


class Reminder(Base):
    __tablename__ = "reminders"

    id           = Column(Integer, primary_key=True, index=True)
    user_id      = Column(Integer, ForeignKey("users.id"), nullable=False)
    title        = Column(String(255), nullable=False)
    description  = Column(Text, nullable=True)
    remind_at    = Column(DateTime(timezone=True), nullable=False)
    is_done      = Column(Boolean, default=False)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="reminders")


class Sample(Base):
    __tablename__ = "samples"

    id           = Column(Integer, primary_key=True, index=True)
    user_id      = Column(Integer, ForeignKey("users.id"), nullable=False)
    name         = Column(String(255), nullable=False)
    description  = Column(Text, nullable=True)
    image_url    = Column(String(500), nullable=True)   # Cloudinary URL
    public_id    = Column(String(255), nullable=True)   # Cloudinary public_id
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="samples")
