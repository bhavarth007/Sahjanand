"""
Multi-Group Chat — REST + WebSocket
=====================================
Endpoints:
  GET    /api/chat/groups                 → list groups current user is in
  POST   /api/chat/groups                 → admin creates a new group
  PATCH  /api/chat/groups/{gid}           → admin rename group
  GET    /api/chat/groups/{gid}/messages  → message history (members only)
  DELETE /api/chat/messages/{mid}         → delete own message
  POST   /api/chat/upload                 → upload media file
  GET    /api/chat/groups/{gid}/members   → list group members
  GET    /api/chat/all-users              → list ALL registered users (for left panel)
  GET    /api/chat/groups/{gid}/available → users not in this group (for add dropdown)
  POST   /api/chat/groups/{gid}/members   → admin add member
  DELETE /api/chat/groups/{gid}/members/{uid} → admin remove member
  PATCH  /api/chat/users/{uid}/permission → admin toggle chat_can_send

WebSocket:
  WS /api/chat/ws?token=<jwt>&group_id=<id>
"""

import uuid
from typing import List, Optional
from pathlib import Path

from fastapi import (
    APIRouter, Depends, HTTPException, status,
    WebSocket, WebSocketDisconnect, UploadFile, File, Query,
)
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from pydantic import BaseModel
from datetime import datetime

from app.auth import get_current_user
from app.database import get_db, AsyncSessionLocal
from app.models.db_models import ChatMessage, User, GroupMember, ChatGroup, MessageRead
from app.config import get_settings
from app.notifications import notify_new_chat_message
from jose import JWTError, jwt

settings = get_settings()
router = APIRouter(prefix="/api/chat", tags=["Chat"])

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

ALLOWED_EXTENSIONS = {
    "image": {".jpg", ".jpeg", ".png", ".gif", ".webp"},
    "voice": {".mp3", ".ogg", ".wav", ".m4a", ".webm"},
    "video": {".mp4", ".mov", ".webm", ".avi"},
}
MAX_FILE_SIZE = 50 * 1024 * 1024


# ═══════════════════════════════════════════════════════════════
# WebSocket Connection Manager (per-group)
# ═══════════════════════════════════════════════════════════════
class ConnectionManager:
    def __init__(self):
        # group_id → {user_id: WebSocket}
        self._groups: dict[int, dict[int, WebSocket]] = {}

    async def connect(self, ws: WebSocket, group_id: int, user_id: int):
        await ws.accept()
        if group_id not in self._groups:
            self._groups[group_id] = {}
        self._groups[group_id][user_id] = ws

    def disconnect(self, group_id: int, user_id: int):
        if group_id in self._groups:
            self._groups[group_id].pop(user_id, None)

    async def broadcast(self, group_id: int, payload: dict):
        if group_id not in self._groups:
            return
        dead = []
        for uid, ws in list(self._groups[group_id].items()):
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(uid)
        for uid in dead:
            self.disconnect(group_id, uid)

    def online_in_group(self, group_id: int) -> list[int]:
        return list(self._groups.get(group_id, {}).keys())


manager = ConnectionManager()


# ═══════════════════════════════════════════════════════════════
# Schemas
# ═══════════════════════════════════════════════════════════════
class GroupOut(BaseModel):
    id: int
    name: str
    created_by: int
    created_at: datetime
    model_config = {"from_attributes": True}

class GroupCreate(BaseModel):
    name: str

class GroupRename(BaseModel):
    name: str

class MessageOut(BaseModel):
    id: int
    group_id: int
    sender_id: int
    sender_name: str
    msg_type: str
    content: Optional[str]
    media_url: Optional[str]
    media_name: Optional[str]
    created_at: datetime
    # Read receipt counts for WhatsApp-style ticks
    # delivered_count: how many non-sender members have received the message
    # seen_count: how many non-sender members have explicitly seen it
    # member_count: total non-sender members in the group
    delivered_count: int = 0
    seen_count: int = 0
    member_count: int = 0

class MemberOut(BaseModel):
    id: int
    email: str
    full_name: Optional[str]
    is_admin: bool
    chat_can_send: bool
    designation: Optional[str] = None
    mobile_no: Optional[str] = None
    model_config = {"from_attributes": True}

class AddMemberReq(BaseModel):
    user_id: int

class PermissionUpdate(BaseModel):
    chat_can_send: bool

class AvailableUser(BaseModel):
    id: int
    email: str
    full_name: Optional[str]
    model_config = {"from_attributes": True}


# ═══════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════
async def ws_get_user(token: str, db: AsyncSession) -> Optional[User]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        email = payload.get("sub")
        if not email:
            return None
    except JWTError:
        return None
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()

async def check_membership(user_id: int, group_id: int, db: AsyncSession) -> bool:
    r = await db.execute(
        select(GroupMember).where(GroupMember.user_id == user_id, GroupMember.group_id == group_id)
    )
    return r.scalar_one_or_none() is not None

async def require_member(user: User, group_id: int, db: AsyncSession):
    if not await check_membership(user.id, group_id, db):
        raise HTTPException(403, "Not a member of this group.")

def require_admin(user: User):
    if not user.is_admin:
        raise HTTPException(403, "Admin access required.")


def require_group_manager(user: User):
    """Allow admin OR users with 'Sales Manager' designation to manage groups."""
    if user.is_admin:
        return
    if user.designation and user.designation.strip().lower() == "sales manager":
        return
    raise HTTPException(403, "Admin or Sales Manager access required.")


# ═══════════════════════════════════════════════════════════════
# Groups CRUD
# ═══════════════════════════════════════════════════════════════
@router.get("/groups", response_model=List[GroupOut])
async def list_my_groups(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List groups the current user is a member of."""
    result = await db.execute(
        select(ChatGroup)
        .join(GroupMember, GroupMember.group_id == ChatGroup.id)
        .where(GroupMember.user_id == current_user.id)
        .order_by(ChatGroup.name)
    )
    return result.scalars().all()


@router.post("/groups", response_model=GroupOut, status_code=201)
async def create_group(
    body: GroupCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Admin creates a new group and is auto-added as first member."""
    require_group_manager(current_user)
    name = body.name.strip()
    if not name:
        raise HTTPException(400, "Group name cannot be empty.")
    # Prevent duplicate group names
    existing = await db.execute(select(ChatGroup).where(ChatGroup.name == name))
    if existing.scalar_one_or_none():
        raise HTTPException(400, "A group with this name already exists.")
    group = ChatGroup(name=name, created_by=current_user.id)
    db.add(group)
    await db.flush()
    await db.refresh(group)
    # Auto-add creator as member
    db.add(GroupMember(group_id=group.id, user_id=current_user.id, added_by=current_user.id))
    await db.flush()
    return group


@router.patch("/groups/{gid}", response_model=GroupOut)
async def rename_group(
    gid: int,
    body: GroupRename,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Admin renames a group."""
    require_group_manager(current_user)
    result = await db.execute(select(ChatGroup).where(ChatGroup.id == gid))
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(404, "Group not found.")
    group.name = body.name.strip()
    await db.flush()
    await db.refresh(group)
    return group


@router.delete("/groups/{gid}")
async def delete_group(
    gid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Admin: permanently deletes the group for ALL users (messages + members gone).
    Non-admin: leaves the group (removes self from members only).
    """
    result = await db.execute(select(ChatGroup).where(ChatGroup.id == gid))
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(404, "Group not found.")

    is_manager = current_user.is_admin or (
        current_user.designation and current_user.designation.strip().lower() == "sales manager"
    )

    if is_manager:
        # Admin/Sales Manager: Delete entire group: messages, members, then group itself
        await db.execute(delete(ChatMessage).where(ChatMessage.group_id == gid))
        await db.execute(delete(GroupMember).where(GroupMember.group_id == gid))
        await db.delete(group)
        await db.flush()
        # Disconnect all online in this group
        await manager.broadcast(gid, {"event": "group_deleted", "group_id": gid})
        return {"ok": True, "message": "Group permanently deleted for all users."}
    else:
        # Non-admin: just leave the group
        mem = await db.execute(
            select(GroupMember).where(GroupMember.group_id == gid, GroupMember.user_id == current_user.id)
        )
        member = mem.scalar_one_or_none()
        if not member:
            raise HTTPException(400, "You are not a member of this group.")
        await db.delete(member)
        await db.flush()
        manager.disconnect(gid, current_user.id)
        return {"ok": True, "message": "You left the group."}


# ═══════════════════════════════════════════════════════════════
# All users (for left panel — shows everyone)
# ═══════════════════════════════════════════════════════════════
@router.get("/all-users", response_model=List[MemberOut])
async def list_all_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.is_active == True).order_by(User.full_name))
    return result.scalars().all()


# ═══════════════════════════════════════════════════════════════
# Group Members
# ═══════════════════════════════════════════════════════════════
@router.get("/groups/{gid}/members", response_model=List[MemberOut])
async def list_group_members(
    gid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await require_member(current_user, gid, db)
    result = await db.execute(
        select(User).join(GroupMember, GroupMember.user_id == User.id)
        .where(GroupMember.group_id == gid, User.is_active == True)
        .order_by(User.full_name)
    )
    return result.scalars().all()


@router.get("/groups/{gid}/available", response_model=List[AvailableUser])
async def list_available_for_group(
    gid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_group_manager(current_user)
    member_q = await db.execute(select(GroupMember.user_id).where(GroupMember.group_id == gid))
    member_ids = {r[0] for r in member_q.all()}
    result = await db.execute(select(User).where(User.is_active == True).order_by(User.full_name))
    return [u for u in result.scalars().all() if u.id not in member_ids]


@router.post("/groups/{gid}/members", status_code=201)
async def add_member(
    gid: int, body: AddMemberReq,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_group_manager(current_user)
    # Verify group exists
    gq = await db.execute(select(ChatGroup).where(ChatGroup.id == gid))
    if not gq.scalar_one_or_none():
        raise HTTPException(404, "Group not found.")
    # Verify user
    uq = await db.execute(select(User).where(User.id == body.user_id, User.is_active == True))
    target = uq.scalar_one_or_none()
    if not target:
        raise HTTPException(404, "User not found.")
    # Check duplicate
    if await check_membership(body.user_id, gid, db):
        raise HTTPException(400, "Already a member.")
    db.add(GroupMember(group_id=gid, user_id=body.user_id, added_by=current_user.id))
    await db.flush()
    await manager.broadcast(gid, {"event": "member_added", "user_id": target.id, "name": target.full_name or target.email})
    return {"ok": True}


@router.delete("/groups/{gid}/members/{uid}")
async def remove_member(
    gid: int, uid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_group_manager(current_user)
    if uid == current_user.id:
        raise HTTPException(400, "Cannot remove yourself.")
    r = await db.execute(select(GroupMember).where(GroupMember.group_id == gid, GroupMember.user_id == uid))
    m = r.scalar_one_or_none()
    if not m:
        raise HTTPException(404, "Not a member.")
    await db.delete(m)
    await db.flush()
    manager.disconnect(gid, uid)
    await manager.broadcast(gid, {"event": "member_removed", "user_id": uid, "online": manager.online_in_group(gid)})
    return {"ok": True}


# ═══════════════════════════════════════════════════════════════
# Messages
# ═══════════════════════════════════════════════════════════════
@router.get("/groups/{gid}/messages", response_model=List[MessageOut])
async def get_messages(
    gid: int,
    limit: int = Query(100, le=500),
    before_id: Optional[int] = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await require_member(current_user, gid, db)
    q = select(ChatMessage).where(ChatMessage.group_id == gid).order_by(ChatMessage.id.desc()).limit(limit)
    if before_id:
        q = q.where(ChatMessage.id < before_id)
    result = await db.execute(q)
    msgs = result.scalars().all()

    sender_ids = {m.sender_id for m in msgs}
    if sender_ids:
        uq = await db.execute(select(User).where(User.id.in_(sender_ids)))
        user_map = {u.id: u for u in uq.scalars().all()}
    else:
        user_map = {}

    # Get member count for this group (for tick logic)
    mq = await db.execute(select(GroupMember.user_id).where(GroupMember.group_id == gid))
    all_member_ids = [r[0] for r in mq.all()]
    member_count = len(all_member_ids)

    # Bulk fetch read receipts for all messages
    msg_ids = [m.id for m in msgs]
    reads_map: dict[int, int] = {}  # message_id → seen count
    if msg_ids:
        rq = await db.execute(
            select(MessageRead.message_id).where(MessageRead.message_id.in_(msg_ids))
        )
        for row in rq.all():
            reads_map[row[0]] = reads_map.get(row[0], 0) + 1

    # Mark messages as seen by current user (they're loading the chat)
    for m in msgs:
        if m.sender_id != current_user.id:
            existing = await db.execute(
                select(MessageRead).where(
                    MessageRead.message_id == m.id,
                    MessageRead.user_id == current_user.id
                )
            )
            if not existing.scalar_one_or_none():
                db.add(MessageRead(message_id=m.id, user_id=current_user.id))
    await db.flush()

    out = []
    for m in reversed(msgs):
        s = user_map.get(m.sender_id)
        seen = reads_map.get(m.id, 0)
        non_sender_count = max(0, member_count - 1)
        out.append(MessageOut(
            id=m.id, group_id=m.group_id, sender_id=m.sender_id,
            sender_name=(s.full_name or s.email) if s else "Unknown",
            msg_type=m.msg_type, content=m.content,
            media_url=m.media_url, media_name=m.media_name,
            created_at=m.created_at,
            delivered_count=seen,
            seen_count=seen,
            member_count=non_sender_count,
        ))
    return out


class MessageCreate(BaseModel):
    msg_type: str = "text"
    content: Optional[str] = None
    media_url: Optional[str] = None
    media_name: Optional[str] = None


@router.post("/groups/{gid}/messages", response_model=MessageOut, status_code=201)
async def post_message(
    gid: int,
    body: MessageCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a message via REST API (used by mobile app when WebSocket is unavailable)."""
    await require_member(current_user, gid, db)
    if not current_user.chat_can_send:
        raise HTTPException(403, "You are muted.")
    content = (body.content or "").strip() or None
    if not content and not body.media_url:
        raise HTTPException(400, "Empty message.")

    msg = ChatMessage(
        group_id=gid, sender_id=current_user.id,
        msg_type=body.msg_type, content=content,
        media_url=body.media_url, media_name=body.media_name,
    )
    db.add(msg)
    await db.flush()
    await db.refresh(msg)

    # Broadcast via WebSocket to all connected users
    await manager.broadcast(gid, {
        "event": "message", "id": msg.id, "group_id": gid,
        "sender_id": current_user.id,
        "sender_name": current_user.full_name or current_user.email,
        "msg_type": body.msg_type, "content": content,
        "media_url": body.media_url, "media_name": body.media_name,
        "created_at": msg.created_at.isoformat(),
    })

    # Send push notification to offline group members
    try:
        members_result = await db.execute(
            select(GroupMember.user_id).where(GroupMember.group_id == gid)
        )
        member_ids = [row[0] for row in members_result.all()]
        # Exclude users currently connected via WebSocket (they already see the message)
        online_ids = manager.online_in_group(gid)
        offline_member_ids = [uid for uid in member_ids if uid not in online_ids]
        group = await db.get(ChatGroup, gid)
        group_name = group.name if group else "Group Chat"
        await notify_new_chat_message(
            sender_name=current_user.full_name or current_user.email,
            msg_type=body.msg_type,
            content=content or "",
            group_name=group_name,
            recipient_user_ids=offline_member_ids,
            sender_id=current_user.id,
            db=db,
            group_id=gid,
        )
    except Exception:
        pass  # Don't fail the message send if push fails

    return MessageOut(
        id=msg.id, group_id=gid, sender_id=current_user.id,
        sender_name=current_user.full_name or current_user.email,
        msg_type=msg.msg_type, content=msg.content,
        media_url=msg.media_url, media_name=msg.media_name,
        created_at=msg.created_at,
    )


@router.delete("/messages/{mid}")
async def delete_message(
    mid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete message — own messages for anyone, admin can delete any message."""
    result = await db.execute(select(ChatMessage).where(ChatMessage.id == mid))
    msg = result.scalar_one_or_none()
    if not msg:
        raise HTTPException(404, "Message not found.")
    if msg.sender_id != current_user.id and not current_user.is_admin:
        raise HTTPException(403, "Can only delete your own messages.")
    group_id = msg.group_id
    await db.delete(msg)
    await db.flush()
    await manager.broadcast(group_id, {"event": "message_deleted", "id": mid})
    return {"ok": True}


# ═══════════════════════════════════════════════════════════════
# Mark message(s) as seen — WhatsApp-style blue ticks
# ═══════════════════════════════════════════════════════════════
@router.post("/messages/{mid}/seen")
async def mark_message_seen(
    mid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark a message as seen by the current user. Broadcasts tick update to the group."""
    result = await db.execute(select(ChatMessage).where(ChatMessage.id == mid))
    msg = result.scalar_one_or_none()
    if not msg:
        raise HTTPException(404, "Message not found.")
    # Don't record sender reading their own message
    if msg.sender_id == current_user.id:
        return {"ok": True}
    # Upsert read record
    existing = await db.execute(
        select(MessageRead).where(
            MessageRead.message_id == mid,
            MessageRead.user_id == current_user.id
        )
    )
    if not existing.scalar_one_or_none():
        db.add(MessageRead(message_id=mid, user_id=current_user.id))
        await db.flush()
    # Count current reads
    count_q = await db.execute(
        select(MessageRead).where(MessageRead.message_id == mid)
    )
    seen_count = len(count_q.scalars().all())
    # Get non-sender member count for this group
    mq = await db.execute(
        select(GroupMember.user_id).where(GroupMember.group_id == msg.group_id)
    )
    member_count = max(0, len(mq.all()) - 1)
    # Broadcast tick update so sender sees live tick change
    await manager.broadcast(msg.group_id, {
        "event": "message_status",
        "id": mid,
        "seen_count": seen_count,
        "member_count": member_count,
    })
    return {"ok": True, "seen_count": seen_count, "member_count": member_count}


@router.post("/groups/{gid}/seen")
async def mark_group_messages_seen(
    gid: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark all recent unread messages in a group as seen (called when user opens a group)."""
    await require_member(current_user, gid, db)
    # Get last 100 messages in this group
    result = await db.execute(
        select(ChatMessage)
        .where(ChatMessage.group_id == gid, ChatMessage.sender_id != current_user.id)
        .order_by(ChatMessage.id.desc())
        .limit(100)
    )
    msgs = result.scalars().all()
    if not msgs:
        return {"ok": True}
    msg_ids = [m.id for m in msgs]
    # Find which ones are already read
    rq = await db.execute(
        select(MessageRead.message_id).where(
            MessageRead.message_id.in_(msg_ids),
            MessageRead.user_id == current_user.id
        )
    )
    already_read = {r[0] for r in rq.all()}
    new_reads = [mid for mid in msg_ids if mid not in already_read]
    for mid in new_reads:
        db.add(MessageRead(message_id=mid, user_id=current_user.id))
    if new_reads:
        await db.flush()
        # Get member count once
        mq = await db.execute(
            select(GroupMember.user_id).where(GroupMember.group_id == gid)
        )
        member_count = max(0, len(mq.all()) - 1)
        # Broadcast status for all newly read messages
        rq2 = await db.execute(
            select(MessageRead.message_id).where(MessageRead.message_id.in_(msg_ids))
        )
        seen_counts: dict[int, int] = {}
        for row in rq2.all():
            seen_counts[row[0]] = seen_counts.get(row[0], 0) + 1
        for mid in new_reads:
            await manager.broadcast(gid, {
                "event": "message_status",
                "id": mid,
                "seen_count": seen_counts.get(mid, 1),
                "member_count": member_count,
            })
    return {"ok": True, "marked": len(new_reads)}
# ═══════════════════════════════════════════════════════════════
@router.post("/upload")
async def upload_media(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    from app.storage import upload_file

    ext = Path(file.filename or "").suffix.lower()
    msg_type = None
    for t, exts in ALLOWED_EXTENSIONS.items():
        if ext in exts:
            msg_type = t
            break
    if not msg_type:
        raise HTTPException(400, f"File type '{ext}' not allowed.")
    data = await file.read()
    if len(data) > MAX_FILE_SIZE:
        raise HTTPException(413, "File too large (max 50 MB).")

    # Upload to Supabase Storage (returns public CDN URL)
    result = upload_file(data, file.filename or f"file{ext}")
    return {"media_url": result["media_url"], "media_name": result["media_name"], "msg_type": result["msg_type"]}


# ═══════════════════════════════════════════════════════════════
# Permission toggle
# ═══════════════════════════════════════════════════════════════
@router.patch("/users/{uid}/permission", response_model=MemberOut)
async def update_permission(
    uid: int, body: PermissionUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    require_admin(current_user)
    r = await db.execute(select(User).where(User.id == uid))
    target = r.scalar_one_or_none()
    if not target:
        raise HTTPException(404, "User not found.")
    target.chat_can_send = body.chat_can_send
    await db.flush()
    await db.refresh(target)
    return target


# ═══════════════════════════════════════════════════════════════
# WebSocket — per group
# ═══════════════════════════════════════════════════════════════
@router.websocket("/ws")
async def chat_ws(websocket: WebSocket, token: str = Query(...), group_id: int = Query(...)):
    async with AsyncSessionLocal() as db:
        user = await ws_get_user(token, db)
        if not user or not user.is_active:
            await websocket.close(code=4001)
            return
        if not await check_membership(user.id, group_id, db):
            await websocket.close(code=4003)
            return

    await manager.connect(websocket, group_id, user.id)
    await manager.broadcast(group_id, {
        "event": "user_joined", "user_id": user.id,
        "name": user.full_name or user.email,
        "online": manager.online_in_group(group_id),
    })

    try:
        while True:
            data = await websocket.receive_json()
            event = data.get("event", "message")

            if event == "message":
                if not user.chat_can_send:
                    await websocket.send_json({"event": "error", "detail": "You are muted."})
                    continue
                content = (data.get("content") or "").strip()
                media_url = data.get("media_url")
                media_name = data.get("media_name")
                msg_type = data.get("msg_type", "text")
                if not content and not media_url:
                    continue

                async with AsyncSessionLocal() as db:
                    msg = ChatMessage(
                        group_id=group_id, sender_id=user.id,
                        msg_type=msg_type, content=content or None,
                        media_url=media_url, media_name=media_name,
                    )
                    db.add(msg)
                    await db.flush()
                    await db.refresh(msg)
                    await db.commit()

                    # Send push notification to offline members
                    try:
                        members_result = await db.execute(
                            select(GroupMember.user_id).where(GroupMember.group_id == group_id)
                        )
                        member_ids = [row[0] for row in members_result.all()]
                        # Exclude users currently connected via WebSocket (they already see the message)
                        online_ids = manager.online_in_group(group_id)
                        offline_member_ids = [uid for uid in member_ids if uid not in online_ids]
                        group = await db.get(ChatGroup, group_id)
                        group_name = group.name if group else "Group Chat"
                        await notify_new_chat_message(
                            sender_name=user.full_name or user.email,
                            msg_type=msg_type,
                            content=content or "",
                            group_name=group_name,
                            recipient_user_ids=offline_member_ids,
                            sender_id=user.id,
                            db=db,
                            group_id=group_id,
                        )
                    except Exception:
                        pass

                await manager.broadcast(group_id, {
                    "event": "message", "id": msg.id, "group_id": group_id,
                    "sender_id": user.id, "sender_name": user.full_name or user.email,
                    "msg_type": msg_type, "content": content or None,
                    "media_url": media_url, "media_name": media_name,
                    "created_at": msg.created_at.isoformat(),
                })

            elif event == "typing":
                await manager.broadcast(group_id, {
                    "event": "typing", "user_id": user.id,
                    "name": user.full_name or user.email,
                    "typing": data.get("typing", False),
                })

    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(group_id, user.id)
        await manager.broadcast(group_id, {
            "event": "user_left", "user_id": user.id,
            "name": user.full_name or user.email,
            "online": manager.online_in_group(group_id),
        })
