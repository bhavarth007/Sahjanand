@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo === Fixing remote URL ===
%GIT% remote set-url origin https://github.com/bhavarth007/Sahjanand.git
echo Remote set to: https://github.com/bhavarth007/Sahjanand.git

echo.
echo === Staging all files ===
%GIT% add .

echo.
echo === Committing ===
%GIT% commit -m "feat: full Sahjanand app - login, dashboard, sales, reminders, samples, logo, backup"

echo.
echo === Pushing to GitHub ===
%GIT% push -u origin main

echo.
IF %ERRORLEVEL% EQU 0 (
    echo ==========================================
    echo   SUCCESS!
    echo   https://github.com/bhavarth007/Sahjanand
    echo ==========================================
) ELSE (
    echo Push failed - check GitHub login
)
pause
