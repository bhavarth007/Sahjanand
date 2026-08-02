@echo off
title Sahjanand - Local Setup
color 0A

echo.
echo ==========================================
echo   Sahjanand - Local Environment Setup
echo ==========================================
echo.

cd /d "%~dp0backend"

echo [1/4] Creating Python virtual environment...
python -m venv .venv
if errorlevel 1 (
    echo ERROR: Python not found or venv failed.
    echo Install Python 3.12 from https://python.org
    pause
    exit /b 1
)
echo   Done.

echo.
echo [2/4] Installing Python packages...
.venv\Scripts\pip.exe install --upgrade pip --quiet
.venv\Scripts\pip.exe install -r requirements.txt
if errorlevel 1 (
    echo ERROR: Package installation failed.
    pause
    exit /b 1
)
echo   Done.

echo.
echo [3/4] Checking PostgreSQL...
pg_isready -h localhost -p 5432 >nul 2>&1
if errorlevel 1 (
    echo   PostgreSQL not running locally.
    echo.
    echo   OPTIONS:
    echo   A) Install PostgreSQL locally:
    echo      https://www.postgresql.org/download/windows/
    echo      Then create DB: createdb -U postgres sahjanand
    echo.
    echo   B) Use Render.com free PostgreSQL (recommended for deployment):
    echo      https://render.com  ^> New ^> PostgreSQL ^> Free plan
    echo      Then paste the External Database URL into backend\.env
    echo.
) else (
    echo   PostgreSQL is running.
    echo   Creating database 'sahjanand' if it doesn't exist...
    psql -U postgres -c "CREATE USER sahjanand WITH PASSWORD 'sahjanand';" >nul 2>&1
    psql -U postgres -c "CREATE DATABASE sahjanand OWNER sahjanand;" >nul 2>&1
    echo   Done.
)

echo.
echo [4/4] Setup complete!
echo.
echo ==========================================
echo   Next Steps:
echo ==========================================
echo.
echo  1. Open backend\.env and set:
echo     - DATABASE_URL  (PostgreSQL connection)
echo     - CLOUDINARY_CLOUD_NAME / API_KEY / API_SECRET
echo       (free at cloudinary.com)
echo.
echo  2. Run the server:
echo     start_server.bat
echo.
echo  3. Open frontend\login.html with VS Code Live Server
echo.
pause
