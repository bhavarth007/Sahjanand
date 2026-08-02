@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"
%GIT% add .
%GIT% commit -m "fix: serve frontend from FastAPI so localhost:8000 shows login page"
%GIT% push origin main
echo.
echo Done! Check https://github.com/Bhavarth-dev/Sahjanand
pause
