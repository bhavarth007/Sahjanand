@echo off
title Sahjanand API Server
color 0B

echo.
echo ==========================================
echo   Sahjanand API - Starting Server
echo ==========================================
echo.

cd /d "%~dp0backend"

if not exist ".venv\Scripts\activate.bat" (
    echo Virtual environment not found.
    echo Please run install.bat first.
    pause
    exit /b 1
)

echo Activating virtual environment...
call .venv\Scripts\activate.bat

echo.
echo Server starting at:
echo   http://localhost:8000
echo   http://localhost:8000/docs  (API docs)
echo.
echo Press Ctrl+C to stop the server.
echo.

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

pause
