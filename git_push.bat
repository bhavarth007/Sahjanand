@echo off
SET GIT="C:\Program Files\Git\cmd\git.exe"
cd /d "C:\Users\ghans\OneDrive\Desktop\Work\Sahjanand"

echo === Staging all files ===
%GIT% add .

echo.
echo === Status ===
%GIT% status --short

echo.
echo === Creating initial commit ===
%GIT% commit -m "Initial commit: Sahjanand web app, backend API, Flutter scaffold"

echo.
echo === Done! ===
echo.
echo NEXT STEP: Connect to GitHub by running:
echo   git remote add origin https://github.com/YOUR_USERNAME/Sahjanand.git
echo   git branch -M main
echo   git push -u origin main
echo.
pause
