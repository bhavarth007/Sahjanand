@echo off
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand\backend"

echo.
echo ==========================================
echo   Sahjanand - Starting local server
echo ==========================================
echo.
echo   Login page:  http://localhost:8000
echo   API docs:    http://localhost:8000/docs
echo.
echo   Press Ctrl+C to stop
echo ==========================================
echo.

.venv\Scripts\uvicorn.exe app.main:app --reload --host 0.0.0.0 --port 8000

pause
