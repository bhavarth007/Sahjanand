# ============================================================
#  Sahjanand — Local Environment Setup Script
#  Run this once from a fresh PowerShell window:
#  .\setup_local.ps1
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Sahjanand Local Environment Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Check Python ──────────────────────────────────
Write-Host "[1/5] Checking Python..." -ForegroundColor Yellow
$pythonVersion = python --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Python not found. Installing Python 3.12..." -ForegroundColor Red
    winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "Python installed. Please CLOSE and REOPEN PowerShell, then run this script again." -ForegroundColor Green
    exit
} else {
    Write-Host "  Python found: $pythonVersion" -ForegroundColor Green
}

# ── Step 2: Create virtual environment ───────────────────
Write-Host ""
Write-Host "[2/5] Creating Python virtual environment..." -ForegroundColor Yellow
Set-Location "$PSScriptRoot\backend"

if (Test-Path ".venv") {
    Write-Host "  .venv already exists, skipping creation." -ForegroundColor Gray
} else {
    python -m venv .venv
    Write-Host "  Virtual environment created at backend\.venv" -ForegroundColor Green
}

# ── Step 3: Install dependencies ─────────────────────────
Write-Host ""
Write-Host "[3/5] Installing Python dependencies..." -ForegroundColor Yellow
& ".\.venv\Scripts\python.exe" -m pip install --upgrade pip --quiet
& ".\.venv\Scripts\pip.exe" install -r requirements.txt
Write-Host "  All packages installed." -ForegroundColor Green

# ── Step 4: Create .env file ─────────────────────────────
Write-Host ""
Write-Host "[4/5] Setting up .env file..." -ForegroundColor Yellow

if (Test-Path ".env") {
    Write-Host "  .env already exists, skipping." -ForegroundColor Gray
} else {
    # Generate a random 32-char secret key
    $secretKey = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 48 | ForEach-Object { [char]$_ })

    $envContent = @"
# Sahjanand Local Environment
# Generated automatically by setup_local.ps1

# JWT
SECRET_KEY=$secretKey
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# MongoDB — using LOCAL MongoDB for development
# To use Atlas free tier instead, replace with your connection string:
# MONGODB_URL=mongodb+srv://<user>:<pass>@cluster.mongodb.net/sahjanand
MONGODB_URL=mongodb://localhost:27017
DB_NAME=sahjanand

# Cloudinary — fill these in from cloudinary.com dashboard
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret

# App
APP_NAME=Sahjanand
FRONTEND_URL=http://127.0.0.1:5500
"@

    $envContent | Out-File -FilePath ".env" -Encoding UTF8
    Write-Host "  .env created with auto-generated SECRET_KEY" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ACTION NEEDED: Open backend\.env and fill in:" -ForegroundColor Magenta
    Write-Host "    - CLOUDINARY_CLOUD_NAME" -ForegroundColor Magenta
    Write-Host "    - CLOUDINARY_API_KEY" -ForegroundColor Magenta
    Write-Host "    - CLOUDINARY_API_SECRET" -ForegroundColor Magenta
    Write-Host "  Get these free at: https://cloudinary.com" -ForegroundColor Magenta
}

# ── Step 5: Check MongoDB ─────────────────────────────────
Write-Host ""
Write-Host "[5/5] Checking MongoDB..." -ForegroundColor Yellow
$mongoRunning = Get-Service -Name "MongoDB" -ErrorAction SilentlyContinue
if ($mongoRunning -and $mongoRunning.Status -eq "Running") {
    Write-Host "  MongoDB service is running." -ForegroundColor Green
} else {
    Write-Host "  MongoDB not detected as a Windows service." -ForegroundColor Yellow
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    A) Install MongoDB Community: https://www.mongodb.com/try/download/community" -ForegroundColor Cyan
    Write-Host "    B) Use MongoDB Atlas free tier (cloud): https://www.mongodb.com/atlas" -ForegroundColor Cyan
    Write-Host "       Then update MONGODB_URL in backend\.env with your Atlas connection string." -ForegroundColor Cyan
}

# ── Done ─────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To START the backend server, run:" -ForegroundColor White
Write-Host ""
Write-Host "  cd backend" -ForegroundColor Yellow
Write-Host "  .\.venv\Scripts\activate" -ForegroundColor Yellow
Write-Host "  uvicorn app.main:app --reload --port 8000" -ForegroundColor Yellow
Write-Host ""
Write-Host "Then open frontend\login.html in your browser." -ForegroundColor White
Write-Host "(Use VS Code Live Server on port 5500 for best results)" -ForegroundColor Gray
Write-Host ""
