"""
Supabase Storage — upload media files (images, audio, video)
Uses httpx to call Supabase Storage REST API directly (no supabase-py dependency).
Files are stored in a public bucket and served via Supabase CDN.
"""
import uuid
from pathlib import Path
import httpx
from app.config import get_settings

settings = get_settings()

BUCKET_NAME = "media"


def _headers():
    return {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
    }


def _storage_url(path: str = "") -> str:
    return f"{settings.SUPABASE_URL}/storage/v1{path}"


def ensure_bucket():
    """Create the media bucket if it doesn't exist (called once on startup)."""
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_KEY:
        print("⚠️ Supabase not configured — skipping bucket setup")
        return

    # Check if bucket exists
    r = httpx.get(_storage_url("/bucket"), headers=_headers(), timeout=10)
    if r.status_code == 200:
        buckets = r.json()
        if any(b.get("name") == BUCKET_NAME for b in buckets):
            return  # Already exists

    # Create public bucket
    httpx.post(
        _storage_url("/bucket"),
        headers={**_headers(), "Content-Type": "application/json"},
        json={"id": BUCKET_NAME, "name": BUCKET_NAME, "public": True},
        timeout=10,
    )


def upload_file(file_bytes: bytes, original_filename: str) -> dict:
    """
    Upload a file to Supabase Storage.
    Returns: {"media_url": "https://...public URL", "media_name": "original.ext", "msg_type": "image|voice|video"}
    """
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_KEY:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set")

    # Generate unique filename
    ext = Path(original_filename).suffix.lower() if original_filename else ""
    unique_name = f"{uuid.uuid4().hex}{ext}"
    content_type = _get_content_type(ext)

    # Upload via REST API
    r = httpx.post(
        _storage_url(f"/object/{BUCKET_NAME}/{unique_name}"),
        headers={
            **_headers(),
            "Content-Type": content_type,
            "x-upsert": "true",
        },
        content=file_bytes,
        timeout=60,
    )

    if r.status_code not in (200, 201):
        raise RuntimeError(f"Supabase upload failed: {r.status_code} {r.text}")

    # Public URL
    public_url = f"{settings.SUPABASE_URL}/storage/v1/object/public/{BUCKET_NAME}/{unique_name}"

    return {
        "media_url": public_url,
        "media_name": original_filename or unique_name,
        "msg_type": _get_msg_type(ext),
        "storage_path": unique_name,
    }


def delete_file(storage_path: str):
    """Delete a file from Supabase Storage."""
    try:
        httpx.delete(
            _storage_url(f"/object/{BUCKET_NAME}"),
            headers={**_headers(), "Content-Type": "application/json"},
            json={"prefixes": [storage_path]},
            timeout=10,
        )
    except Exception:
        pass


def _get_content_type(ext: str) -> str:
    types = {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
        ".gif": "image/gif", ".webp": "image/webp",
        ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav",
        ".m4a": "audio/mp4", ".webm": "audio/webm",
        ".mp4": "video/mp4", ".mov": "video/quicktime", ".avi": "video/x-msvideo",
    }
    return types.get(ext, "application/octet-stream")


def _get_msg_type(ext: str) -> str:
    if ext in {".jpg", ".jpeg", ".png", ".gif", ".webp"}:
        return "image"
    elif ext in {".mp3", ".ogg", ".wav", ".m4a", ".webm"}:
        return "voice"
    elif ext in {".mp4", ".mov", ".avi"}:
        return "video"
    return "file"
