@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo === Staging all changes ===
%GIT% add .

echo.
echo === Files staged ===
%GIT% status --short

echo.
echo === Committing ===
%GIT% commit -m "feat: login->dashboard flow, profile dropdown, admin seed, README, .gitignore"

echo.
echo === Checking remote ===
%GIT% remote -v

echo.
echo ========================================
echo If remote is set, run:
echo   git push -u origin main
echo.
echo If NOT set yet, run:
echo   git remote add origin https://github.com/YOUR_USERNAME/Sahjanand.git
echo   git branch -M main
echo   git push -u origin main
echo ========================================
pause
