from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from contextlib import asynccontextmanager
from pathlib import Path
from app.database import init_db, close_db
from app.routes import auth, sales, reminders, samples, chat as chat_router, admin as admin_router, group_reminders
from app.config import get_settings

import app.models.db_models  # noqa: F401

settings = get_settings()

# Path to the frontend folder (one level up from backend/)
FRONTEND_DIR = Path(__file__).resolve().parent.parent.parent / "frontend"


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    # Seed default admin user on startup
    from app.seed import seed
    try:
        await seed()
    except Exception as e:
        print(f"⚠️ Seed skipped: {e}")
    yield
    await close_db()


app = FastAPI(
    title="Sahjanand API",
    description="Backend API for Sahjanand — सहजानन्द : विश्वासानन्द :",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS
allowed_origins = [
    "http://localhost:8000",
    "http://127.0.0.1:8000",
    "http://localhost:5500",
    "http://127.0.0.1:5500",
    settings.FRONTEND_URL,
]
if settings.PRODUCTION_URL:
    allowed_origins.append(settings.PRODUCTION_URL)

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API routes first ────────────────────────────────────
app.include_router(auth.router)
app.include_router(sales.router)
app.include_router(reminders.router)
app.include_router(samples.router)
app.include_router(chat_router.router)
app.include_router(admin_router.router)
app.include_router(group_reminders.router)
app.include_router(group_reminders.global_reminder_router)


@app.get("/health", tags=["Health"])
async def health():
    return {"status": "ok"}


@app.get("/api/config", tags=["Config"])
async def app_config():
    """Returns public app config including logo URL for frontend use."""
    return {
        "app_name": settings.APP_NAME,
        "logo_url": settings.LOGO_URL,
    }


# ── Serve frontend static files ─────────────────────────
# CSS, JS, images etc.
if FRONTEND_DIR.exists():
    app.mount("/css",    StaticFiles(directory=str(FRONTEND_DIR / "css")),    name="css")
    app.mount("/js",     StaticFiles(directory=str(FRONTEND_DIR / "js")),     name="js")
    app.mount("/assets", StaticFiles(directory=str(FRONTEND_DIR / "assets")), name="assets")

# ── Serve uploaded chat media ────────────────────────────
from pathlib import Path as _Path
_uploads_dir = _Path("uploads")
_uploads_dir.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(_uploads_dir)), name="uploads")


# ── HTML page routes ────────────────────────────────────
@app.get("/", include_in_schema=False)
async def index():
    """Root → redirect to login page."""
    return FileResponse(str(FRONTEND_DIR / "login.html"))


@app.get("/login", include_in_schema=False)
@app.get("/login.html", include_in_schema=False)
async def login_page():
    return FileResponse(str(FRONTEND_DIR / "login.html"))


@app.get("/dashboard", include_in_schema=False)
@app.get("/dashboard.html", include_in_schema=False)
async def dashboard_page():
    return FileResponse(str(FRONTEND_DIR / "dashboard.html"))


@app.get("/forgot-password", include_in_schema=False)
@app.get("/forgot-password.html", include_in_schema=False)
async def forgot_password_page():
    return FileResponse(str(FRONTEND_DIR / "forgot-password.html"))
