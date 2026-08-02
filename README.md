# Sahjanand — सहजानन्द : विश्वासानन्द :

A full-stack business management platform built with **Python (FastAPI)**, **PostgreSQL**, and **Flutter**.

---

## Project Structure

```
Sahjanand/
├── backend/                  # Python FastAPI REST API
│   ├── app/
│   │   ├── main.py           # App entry point, CORS, lifespan
│   │   ├── config.py         # Settings (reads .env)
│   │   ├── database.py       # SQLAlchemy async engine
│   │   ├── auth.py           # JWT helpers, password hashing
│   │   ├── seed.py           # Creates default admin user
│   │   ├── models/
│   │   │   ├── db_models.py  # SQLAlchemy ORM tables
│   │   │   └── user.py       # Pydantic request/response schemas
│   │   └── routes/
│   │       ├── auth.py       # /api/auth — login, register, forgot-password
│   │       ├── sales.py      # /api/sales
│   │       ├── reminders.py  # /api/reminders
│   │       └── samples.py    # /api/samples + Cloudinary upload
│   ├── migrations/           # Alembic migrations
│   │   └── versions/
│   │       └── 0001_initial_schema.py
│   ├── requirements.txt
│   ├── render.yaml           # Render.com deployment config
│   ├── .env.example          # Copy to .env and fill in values
│   └── run_dev.bat           # One-click local server start
│
├── frontend/                 # Responsive web app
│   ├── login.html            # Login page
│   ├── forgot-password.html  # Forgot password page
│   ├── dashboard.html        # Main dashboard (Sales / Reminders / Samples)
│   ├── css/
│   │   ├── variables.css     # Brand colours and tokens
│   │   ├── login.css
│   │   └── dashboard.css
│   └── js/
│       ├── login.js
│       └── dashboard.js
│
└── flutter_app/              # Flutter mobile app (Android first, iOS later)
    ├── lib/
    │   ├── main.dart
    │   ├── core/
    │   │   ├── api/          # Dio client, auth service, GoRouter
    │   │   ├── constants/    # App constants, API URLs
    │   │   ├── theme/        # Brand colours, MaterialTheme
    │   │   └── utils/        # Validators
    │   ├── features/
    │   │   ├── auth/         # Login + Forgot Password screens
    │   │   ├── dashboard/    # Dashboard with Nav Rail / Bottom Nav
    │   │   ├── sales/        # Sales screen
    │   │   ├── reminders/    # Reminders screen
    │   │   └── samples/      # Samples screen
    │   └── shared/
    │       ├── models/       # UserModel
    │       └── widgets/      # SahjanandLogo, PrimaryButton
    └── pubspec.yaml
```

---

## Tech Stack

| Layer      | Technology                                   |
|------------|----------------------------------------------|
| Backend    | Python 3.12, FastAPI, SQLAlchemy (async)     |
| Database   | PostgreSQL (production), SQLite (local dev)  |
| Images     | Cloudinary (free tier)                       |
| Hosting    | Render.com (free tier)                       |
| Web        | HTML5, CSS3, Vanilla JS                      |
| Mobile     | Flutter 3.x — Android + iOS                  |

---

## Default Admin Credentials

```
Email:    admin@gmail.com
Password: admin
```

> Change this password immediately after first login in production.

---

## Local Setup

### Backend

```bash
cd backend

# 1. Create virtual environment
python -m venv .venv
.venv\Scripts\activate       # Windows
# source .venv/bin/activate  # Mac/Linux

# 2. Install dependencies
pip install -r requirements.txt

# 3. Create .env file
copy .env.example .env       # Windows
# cp .env.example .env       # Mac/Linux
# Fill in Cloudinary credentials

# 4. Seed the admin user
python -m app.seed

# 5. Start the server
uvicorn app.main:app --reload --port 8000
```

API runs at: `http://localhost:8000`
Swagger docs: `http://localhost:8000/docs`

Or simply double-click **`run_dev.bat`** (Windows).

### Frontend

Open `frontend/login.html` with **VS Code Live Server** (port 5500).

Login with `admin@gmail.com` / `admin`.

### Flutter

```bash
# Install Flutter SDK first: https://docs.flutter.dev/get-started/install/windows

cd flutter_app
flutter pub get
flutter run        # Android emulator or physical device
```

---

## Deployment on Render.com

1. Push this repo to GitHub
2. Go to [render.com](https://render.com) → **New** → **Web Service**
3. Connect your GitHub repo
4. Render reads `backend/render.yaml` automatically:
   - Creates the FastAPI web service
   - Creates a free PostgreSQL database
   - Runs `alembic upgrade head` before starting
5. Add these environment variables in Render dashboard:
   - `CLOUDINARY_CLOUD_NAME`
   - `CLOUDINARY_API_KEY`
   - `CLOUDINARY_API_SECRET`

Get free Cloudinary credentials at [cloudinary.com](https://cloudinary.com).

---

## Features

| Feature | Web | Flutter |
|---------|-----|---------|
| Login (email + password) | ✅ | ✅ |
| Forgot password | ✅ | ✅ |
| Sales dashboard | ✅ | ✅ |
| Reminders | ✅ | ✅ |
| Samples + image upload | ✅ | ✅ |
| User profile dropdown | ✅ | ✅ |
| Responsive design | ✅ | ✅ |
| JWT authentication | ✅ | ✅ |
| PostgreSQL (production) | ✅ | ✅ |
| Cloudinary image storage | ✅ | ✅ |

---

&copy; 2026 Sahjanand. All rights reserved.
