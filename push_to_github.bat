@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo.
echo ==========================================
echo   Sahjanand - Push to GitHub
echo ==========================================
echo.

REM Stage everything
%GIT% add .
%GIT% status --short

echo.
echo Committing changes...
%GIT% commit -m "fix: login redirect to dashboard, auth guard, push_to_github script"

echo.
REM Add remote if not already set
%GIT% remote get-url origin >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo Adding remote origin...
    %GIT% remote add origin https://github.com/Bhavarth-dev/Sahjanand.git
)

echo.
echo Setting branch to main...
%GIT% branch -M main

echo.
echo Pushing to GitHub...
echo (Browser login window may appear - sign in with your GitHub account)
echo.
%GIT% push -u origin main

echo.
IF %ERRORLEVEL% EQU 0 (
    echo ==========================================
    echo   SUCCESS!
    echo   https://github.com/Bhavarth-dev/Sahjanand
    echo ==========================================
) ELSE (
    echo ==========================================
    echo   FAILED - Try these steps:
    echo   1. Make sure repo exists at:
    echo      https://github.com/Bhavarth-dev/Sahjanand
    echo   2. If login fails, create a Personal Access Token:
    echo      https://github.com/settings/tokens/new
    echo      Scopes: check 'repo'
    echo      Use token as password when prompted
    echo ==========================================
)
echo.
pause
