@echo off
chcp 65001 >nul
title לוח הקומה — התקנת מצב מקומי (בלי אינטרנט)
net session >nul 2>&1 || (echo. & echo   ** צריך להריץ כמנהל ** & echo   קליק ימני על הקובץ ובחר "הפעל כמנהל" & echo. & pause & exit /b)
set "APP=C:\luach\app"
set "SRC=%~dp0.."

echo.
echo   ====== מצב מקומי ללוח הקומה ======
echo.
where node >nul 2>&1 || (
  echo   ** Node.js לא מותקן **
  echo   התקן פעם אחת ^(צריך אינטרנט^) עם הפקודה:
  echo       winget install OpenJS.NodeJS.LTS
  echo   או מהאתר nodejs.org ^(גרסת LTS^), ואז הרץ את הקובץ הזה שוב.
  echo.
  pause & exit /b
)
echo   [1/5] Node.js נמצא

if not exist "C:\luach" md "C:\luach"
robocopy "%SRC%" "%APP%" /MIR /XD .git /XF state.json state.json.tmp server.log /NFL /NDL /NJH /NJS /NP >nul
copy /y "%SRC%\board-kiosk.bat" "C:\luach\board-kiosk.bat" >nul
powershell -NoProfile -Command "Get-ChildItem -Path 'C:\luach' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File" >nul 2>&1
echo   [2/5] הקבצים הועתקו ל-%APP%

netsh advfirewall firewall delete rule name="Luach local board" >nul 2>&1
netsh advfirewall firewall add rule name="Luach local board" dir=in action=allow protocol=TCP localport=8770 profile=any >nul
echo   [3/5] חומת האש מאפשרת לאייפון להתחבר ^(פורט 8770^)

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v LuachLocal /t REG_SZ /f /d "powershell -NoProfile -WindowStyle Hidden -Command \"Start-Process -WindowStyle Hidden -FilePath '%APP%\local\start-local.bat'\"" >nul
echo   [4/5] השרת המקומי יופעל בכל כניסה ל-Windows

copy /y "%APP%\local\show-address.bat" "C:\Users\Public\Desktop\כתובת-ניהול.bat" >nul
echo   [5/5] בשולחן העבודה: "כתובת-ניהול" — מציג את הכתובת לאייפון

echo.
echo   ====== הסתיים ======
echo.
echo   הלוח ייפתח מעכשיו מהמחשב עצמו ^(http://localhost:8770^) ויעבוד גם בלי אינטרנט.
echo   כשיש אינטרנט — כל שינוי מסתנכרן לענן ולהפך.
echo.
echo   לשליטה מהאייפון בלי אינטרנט: הגדרות ^> רשת ואינטרנט ^> נקודה חמה לניידים
echo   ^(או נתב קטן^), חבר את האייפון לרשת הזו, ופתח את הכתובת שמוצגת ב"כתובת-ניהול".
echo.
echo   כבה והדלק את המחשב כדי שהכול יעלה מחדש.
echo.
pause
