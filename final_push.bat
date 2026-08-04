@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo.
echo ==========================================
echo   Sahjanand - Final Push to GitHub
echo ==========================================
echo.

REM Stage everything
%GIT% add .

echo === Files being committed ===
%GIT% status --short
echo.

REM Commit
%GIT% commit -m "feat: logo.png, backup_db.py, data safety README, gitignore cleanup"

echo.
echo === Pushing to GitHub ===
echo (Sign in if browser window appears)
echo.
%GIT% push origin main

echo.
IF %ERRORLEVEL% EQU 0 (
    echo ==========================================
    echo   SUCCESS!
    echo   https://github.com/Bhavarth-dev/Sahjanand
    echo ==========================================
) ELSE (
    echo ==========================================
    echo   Push failed. Trying force-set upstream...
    echo ==========================================
    %GIT% push --set-upstream origin main
)
echo.
pause
