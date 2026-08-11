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

    id             = Column(Integer, primary_key=True, index=True)
    email          = Column(String(255), unique=True, nullable=False, index=True)
    password       = Column(String(255), nullable=False)
    full_name      = Column(String(255), nullable=True)
    is_active      = Column(Boolean, default=True)
    is_admin       = Column(Boolean, default=False)   # can manage chat permissions
    chat_can_send  = Column(Boolean, default=True)    # allowed to send messages in group chat
    designation    = Column(String(255), nullable=True)  # e.g. "Sales Manager"

    # Section access rights (admin-controlled per user)
    can_view_sales     = Column(Boolean, default=True)
    can_view_reminders = Column(Boolean, default=True)
    can_view_samples   = Column(Boolean, default=True)
    can_view_chat      = Column(Boolean, default=True)

    created_at     = Column(DateTime(timezone=True), server_default=func.now())
    updated_at     = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    sales         = relationship("Sale",        back_populates="user", cascade="all, delete-orphan")
    reminders     = relationship("Reminder",    back_populates="user", cascade="all, delete-orphan")
    samples       = relationship("Sample",      back_populates="user", cascade="all, delete-orphan")
    chat_messages = relationship("ChatMessage", back_populates="sender", cascade="all, delete-orphan")


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


class ChatGroup(Base):
    """
    A chat group. Admin creates groups and adds members.
    """
    __tablename__ = "chat_groups"

    id          = Column(Integer, primary_key=True, index=True)
    name        = Column(String(255), nullable=False)
    created_by  = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at  = Column(DateTime(timezone=True), server_default=func.now())

    creator = relationship("User", foreign_keys=[created_by])
    members = relationship("GroupMember", back_populates="group", cascade="all, delete-orphan")
    messages = relationship("ChatMessage", back_populates="group", cascade="all, delete-orphan")


class GroupMember(Base):
    """
    Tracks which users are members of which group.
    """
    __tablename__ = "group_members"

    id        = Column(Integer, primary_key=True, index=True)
    group_id  = Column(Integer, ForeignKey("chat_groups.id"), nullable=False)
    user_id   = Column(Integer, ForeignKey("users.id"), nullable=False)
    added_by  = Column(Integer, ForeignKey("users.id"), nullable=True)
    added_at  = Column(DateTime(timezone=True), server_default=func.now())

    group     = relationship("ChatGroup", back_populates="members")
    user      = relationship("User", foreign_keys=[user_id])
    added_by_user = relationship("User", foreign_keys=[added_by])


class ChatMessage(Base):
    """
    A message in a group chat.
    msg_type: 'text' | 'image' | 'voice' | 'video'
    """
    __tablename__ = "chat_messages"

    id          = Column(Integer, primary_key=True, index=True)
    group_id    = Column(Integer, ForeignKey("chat_groups.id"), nullable=False)
    sender_id   = Column(Integer, ForeignKey("users.id"), nullable=False)
    msg_type    = Column(String(20), default="text")
    content     = Column(Text, nullable=True)
    media_url   = Column(String(500), nullable=True)
    media_name  = Column(String(255), nullable=True)
    created_at  = Column(DateTime(timezone=True), server_default=func.now())

    group  = relationship("ChatGroup", back_populates="messages")
    sender = relationship("User", back_populates="chat_messages")


class GroupReminder(Base):
    """
    Reminders linked to a chat group.
    Reminder to specific users, with description, optional media.
    """
    __tablename__ = "group_reminders"

    id           = Column(Integer, primary_key=True, index=True)
    group_id     = Column(Integer, ForeignKey("chat_groups.id"), nullable=False)
    created_by   = Column(Integer, ForeignKey("users.id"), nullable=False)
    remind_to    = Column(Integer, ForeignKey("users.id"), nullable=True)   # legacy single target
    remind_to_ids = Column(Text, nullable=True)              # comma-separated user IDs e.g. "1,3,5"
    name         = Column(String(255), nullable=False)       # label/title
    description  = Column(Text, nullable=True)               # free text
    media_url    = Column(String(500), nullable=True)        # attached image/voice
    media_name   = Column(String(255), nullable=True)
    remind_date  = Column(String(20), nullable=False)        # stored as 'YYYY-MM-DD'
    remind_time  = Column(String(10), nullable=False)        # stored as 'HH:MM' (24h)
    status       = Column(String(20), default="set")         # 'set' or 'not_set'
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

    group      = relationship("ChatGroup")
    creator    = relationship("User", foreign_keys=[created_by])
    target_user = relationship("User", foreign_keys=[remind_to])
