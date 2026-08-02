# ============================================================
#  Start Sahjanand Backend Server (local dev)
#  Run: .\run.ps1
# ============================================================

$backendDir = $PSScriptRoot
$venvPython = "$backendDir\.venv\Scripts\python.exe"
$venvActivate = "$backendDir\.venv\Scripts\Activate.ps1"

# Check venv exists
if (-not (Test-Path $venvPython)) {
    Write-Host "Virtual environment not found." -ForegroundColor Red
    Write-Host "Run setup_local.ps1 first from the project root." -ForegroundColor Yellow
    exit 1
}

# Activate venv
Write-Host "Activating virtual environment..." -ForegroundColor Cyan
& $venvActivate

# Start server
Write-Host ""
Write-Host "Starting Sahjanand API on http://localhost:8000" -ForegroundColor Green
Write-Host "API Docs: http://localhost:8000/docs" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
