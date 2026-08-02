@echo off
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand\backend"
.venv\Scripts\pip.exe install aiosqlite==0.20.0 --quiet
.venv\Scripts\uvicorn.exe app.main:app --reload --host 0.0.0.0 --port 8000
