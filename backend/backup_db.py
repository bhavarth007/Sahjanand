"""
Database Backup Script — run anytime to back up all records.

Usage:
  python backup_db.py

Creates a timestamped backup of sahjanand.db in backend/backups/
Safe to run while the server is live — SQLite supports hot backups.
"""
import shutil
import sys
from pathlib import Path
from datetime import datetime

DB_PATH     = Path(__file__).parent / "sahjanand.db"
BACKUP_DIR  = Path(__file__).parent / "backups"


def backup():
    if not DB_PATH.exists():
        print(f"❌ Database not found at: {DB_PATH}")
        print("   Run the server at least once to create it.")
        sys.exit(1)

    BACKUP_DIR.mkdir(exist_ok=True)

    timestamp   = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = BACKUP_DIR / f"sahjanand_{timestamp}.db"

    # sqlite3 backup — safe while server is running
    import sqlite3
    src  = sqlite3.connect(str(DB_PATH))
    dest = sqlite3.connect(str(backup_path))
    src.backup(dest)
    dest.close()
    src.close()

    size_kb = backup_path.stat().st_size // 1024
    print(f"✅ Backup created: {backup_path.name}  ({size_kb} KB)")
    print(f"   Location: {backup_path}")

    # Keep only last 10 backups
    backups = sorted(BACKUP_DIR.glob("sahjanand_*.db"))
    if len(backups) > 10:
        for old in backups[:-10]:
            old.unlink()
            print(f"   Removed old backup: {old.name}")


if __name__ == "__main__":
    backup()
