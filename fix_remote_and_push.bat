@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo.
echo ==========================================
echo   Fix GitHub Remote and Push
echo ==========================================
echo.
echo Your current remote:
%GIT% remote -v
echo.
echo --- ACTION REQUIRED ---
echo.
echo 1. Go to https://github.com and sign in
echo 2. Click your profile picture top-right
echo 3. Your USERNAME is shown (e.g. bhavarthhapani or BhavarthHapani)
echo 4. Go to https://github.com/new
echo 5. Create repo named: Sahjanand
echo 6. Keep it PRIVATE, NO readme, NO gitignore
echo 7. Click Create repository
echo.
echo Then come back here and type your exact GitHub username:
echo.
set /p GITHUB_USER="Enter your GitHub username: "

echo.
echo Setting remote to: https://github.com/%GITHUB_USER%/Sahjanand.git
%GIT% remote set-url origin https://github.com/%GITHUB_USER%/Sahjanand.git

echo.
echo Pushing...
%GIT% push -u origin main

echo.
IF %ERRORLEVEL% EQU 0 (
    echo ==========================================
    echo   SUCCESS!
    echo   https://github.com/%GITHUB_USER%/Sahjanand
    echo ==========================================
) ELSE (
    echo Push failed. Make sure:
    echo  1. Repo exists at github.com/%GITHUB_USER%/Sahjanand
    echo  2. You are signed in to GitHub
)
echo.
pause
