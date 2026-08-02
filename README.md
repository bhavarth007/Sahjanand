# Sahjanand — सहजानन्द : विश्वासानन्द :

A full-stack business management platform with web app, Android, and iOS apps.

## Project Structure

```
Sahjanand/
├── backend/          # Python FastAPI REST API
│   ├── app/
│   │   ├── main.py
│   │   ├── auth.py
│   │   ├── config.py
│   │   ├── database.py
│   │   ├── models/
│   │   └── routes/   # auth, sales, reminders, samples
│   ├── requirements.txt
│   └── render.yaml   # Render.com deployment config
├── frontend/         # Responsive web app (HTML/CSS/JS)
│   ├── login.html
│   ├── forgot-password.html
│   ├── dashboard.html
│   ├── css/
│   └── js/
└── flutter_app/      # Flutter mobile app (Android + iOS)
```

## Tech Stack

| Layer    | Technology                        |
|----------|-----------------------------------|
| Backend  | Python, FastAPI, Motor (async)    |
| Database | MongoDB (free tier)               |
| Images   | Cloudinary (free tier)            |
| Hosting  | Render.com (free tier)            |
| Web      | HTML5, CSS3, Vanilla JS           |
| Mobile   | Flutter (Android first, then iOS) |

## Getting Started

### Backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt
cp .env.example .env         # Fill in your secrets
uvicorn app.main:app --reload
```

API docs available at: http://localhost:8000/docs

### Frontend

Open `frontend/login.html` in a browser, or use Live Server in VS Code.

### Flutter

```bash
cd flutter_app
flutter pub get
flutter run
```

## Features

- **Login** — Email + password with forgot password flow
- **Sales** — Sales dashboard with stats and transaction history
- **Reminders** — Smart reminders and follow-up management
- **Samples** — Product sample management with Cloudinary image upload
- **Responsive** — Works on desktop, tablet, and mobile

## Deployment

- Backend: Deploy to [Render.com](https://render.com) using `render.yaml`
- Frontend: Deploy to Render Static Sites or Vercel
- Mobile: Build APK for Android, then IPA for iOS

---

&copy; 2026 Sahjanand. All rights reserved.
