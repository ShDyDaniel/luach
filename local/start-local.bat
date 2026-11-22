@echo off
chcp 65001 >nul
rem ===== לוח הקומה — שרת מקומי (עובד גם בלי אינטרנט) =====
rem מופעל אוטומטית בכניסה ל-Windows. אם השרת נופל — עולה מחדש תוך 3 שניות.
cd /d "%~dp0"
:loop
if exist "C:\luach\STOP.flag" goto end
node luach-local.js >> "%~dp0server.log" 2>&1
timeout /t 3 /nobreak >nul
goto loop
:end
