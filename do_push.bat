@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo === Staging all changes ===
%GIT% add .

echo.
echo === Committing ===
%GIT% commit -m "feat: add real logo.png committed to repo, cloud logo system via /api/config"

echo.
echo === Pushing to GitHub ===
%GIT% push origin main

echo.
IF %ERRORLEVEL% EQU 0 (
    echo SUCCESS - https://github.com/Bhavarth-dev/Sahjanand
) ELSE (
    echo Push failed - check GitHub remote URL
)
pause
