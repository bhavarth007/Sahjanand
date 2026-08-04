"""
Run this ONCE after placing logo.png in frontend/assets/images/
to upload it to Cloudinary for permanent cloud storage.

Usage:
  python upload_logo.py
"""
import os
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent))
from dotenv import load_dotenv
load_dotenv()

import cloudinary
import cloudinary.uploader

LOGO_PATH = Path(__file__).parent.parent / "frontend" / "assets" / "images" / "logo.png"

def upload_logo():
    cloud_name   = os.getenv("CLOUDINARY_CLOUD_NAME", "")
    api_key      = os.getenv("CLOUDINARY_API_KEY", "")
    api_secret   = os.getenv("CLOUDINARY_API_SECRET", "")

    if not all([cloud_name, api_key, api_secret]):
        print("❌ Cloudinary credentials not set in backend/.env")
        print("   Set CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET")
        return

    if not LOGO_PATH.exists():
        print(f"❌ Logo not found at: {LOGO_PATH}")
        print("   Save your logo.png to frontend/assets/images/ first.")
        return

    cloudinary.config(
        cloud_name=cloud_name,
        api_key=api_key,
        api_secret=api_secret,
    )

    print(f"Uploading logo from: {LOGO_PATH}")
    result = cloudinary.uploader.upload(
        str(LOGO_PATH),
        public_id="sahjanand/logo",
        overwrite=True,
        invalidate=True,
        resource_type="image",
    )

    cloud_url = result["secure_url"]
    print(f"\n✅ Logo uploaded to Cloudinary!")
    print(f"   URL: {cloud_url}")
    print(f"\nAdd this to your .env:")
    print(f"   LOGO_URL={cloud_url}")

    # Auto-write LOGO_URL to .env
    env_path = Path(__file__).parent / ".env"
    env_text = env_path.read_text(encoding="utf-8")
    if "LOGO_URL=" in env_text:
        lines = [f"LOGO_URL={cloud_url}" if l.startswith("LOGO_URL=") else l
                 for l in env_text.splitlines()]
        env_path.write_text("\n".join(lines), encoding="utf-8")
    else:
        with open(env_path, "a") as f:
            f.write(f"\n# Logo (Cloudinary)\nLOGO_URL={cloud_url}\n")

    print(f"\n✅ LOGO_URL saved to backend/.env automatically.")
    print(f"\nThe logo is now permanently hosted at:")
    print(f"   {cloud_url}")


if __name__ == "__main__":
    upload_logo()
