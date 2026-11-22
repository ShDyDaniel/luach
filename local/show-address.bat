@echo off
chcp 65001 >nul
title לוח הקומה — כתובת לדף הניהול
echo.
echo   חבר את האייפון לאותה רשת Wi-Fi של המחשב הזה, ופתח בספארי:
echo.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do for /f "tokens=*" %%b in ("%%a") do echo       http://%%b:8770/#manage
echo.
echo   (בנקודה חמה של Windows הכתובת היא בדרך כלל http://192.168.137.1:8770/#manage)
echo.
pause
