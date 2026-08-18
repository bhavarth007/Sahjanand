"""
Supabase Storage — upload media files (images, audio, video)
Files are stored in a public bucket and served via Supabase CDN.
"""
import uuid
from pathlib import Path
from supabase import create_client, Client
from app.config import get_settings

settings = get_settings()

# Bucket name for all media uploads
BUCKET_NAME = "media"

# Initialize Supabase client (using service key for storage operations)
_supabase: Client | None = None


def get_supabase() -> Client:
    global _supabase
    if _supabase is None:
        if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_KEY:
            raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in .env")
        _supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
    return _supabase


def ensure_bucket():
    """Create the media bucket if it doesn't exist (called once on startup)."""
    sb = get_supabase()
    try:
        sb.storage.get_bucket(BUCKET_NAME)
    except Exception:
        # Bucket doesn't exist — create it as public
        sb.storage.create_bucket(BUCKET_NAME, options={"public": True})


def upload_file(file_bytes: bytes, original_filename: str) -> dict:
    """
    Upload a file to Supabase Storage.
    Returns: {"url": "https://...public URL", "path": "media/xxx.ext", "name": "original.ext"}
    """
    sb = get_supabase()

    # Generate unique filename preserving extension
    ext = Path(original_filename).suffix.lower() if original_filename else ""
    unique_name = f"{uuid.uuid4().hex}{ext}"

    # Determine content type
    content_type = _get_content_type(ext)

    # Upload to bucket
    sb.storage.from_(BUCKET_NAME).upload(
        path=unique_name,
        file=file_bytes,
        file_options={"content-type": content_type, "upsert": "true"},
    )

    # Get public URL
    public_url = sb.storage.from_(BUCKET_NAME).get_public_url(unique_name)

    # Determine media type
    msg_type = _get_msg_type(ext)

    return {
        "media_url": public_url,
        "media_name": original_filename or unique_name,
        "msg_type": msg_type,
        "storage_path": unique_name,
    }


def delete_file(storage_path: str):
    """Delete a file from Supabase Storage by its path."""
    try:
        sb = get_supabase()
        sb.storage.from_(BUCKET_NAME).remove([storage_path])
    except Exception:
        pass  # Non-critical — file may already be deleted


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
