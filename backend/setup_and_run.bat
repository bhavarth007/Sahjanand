@echo off
title Sahjanand Backend Setup + Run
color 0A

cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand\backend"

echo.
echo === Step 1: Installing packages ===
.venv\Scripts\pip.exe install -r requirements.txt
if errorlevel 1 (
    echo.
    echo ERROR: pip install failed. 
    echo Trying to create venv first...
    python -m venv .venv
    .venv\Scripts\pip.exe install -r requirements.txt
)

echo.
echo === Step 2: Checking PostgreSQL ===
.venv\Scripts\python.exe -c "import asyncpg; print('asyncpg OK')"

echo.
echo === Step 3: Starting Sahjanand API ===
echo.
echo  URL:      http://localhost:8000
echo  API Docs: http://localhost:8000/docs
echo.
echo Press Ctrl+C to stop.
echo.

.venv\Scripts\uvicorn.exe app.main:app --reload --host 0.0.0.0 --port 8000

pause
