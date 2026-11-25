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
echo   [1/6] Node.js נמצא

rem עוצרים את שומר-המסך הישן לפני שמחליפים את הקובץ שלו (cmd קורא קובץ bat תוך כדי ריצה)
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='cmd.exe'\" | Where-Object { $_.CommandLine -like '*board-kiosk.bat*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
taskkill /f /im LuachScreen.exe >nul 2>&1
timeout /t 2 /nobreak >nul

if not exist "C:\luach" md "C:\luach"
robocopy "%SRC%" "%APP%" /MIR /R:3 /W:2 /XD .git /XF state.json state.json.tmp server.log /NFL /NDL /NJH /NJS /NP >nul
copy /y "%SRC%\board-kiosk.bat" "C:\luach\board-kiosk.bat" >nul
powershell -NoProfile -Command "Get-ChildItem -Path 'C:\luach' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File" >nul 2>&1
echo   [2/6] הקבצים הועתקו ל-%APP%

netsh advfirewall firewall delete rule name="Luach local board" >nul 2>&1
netsh advfirewall firewall add rule name="Luach local board" dir=in action=allow protocol=TCP localport=8770 profile=any >nul
echo   [3/6] חומת האש מאפשרת לאייפון להתחבר ^(פורט 8770^)

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v LuachLocal /t REG_SZ /f /d "powershell -NoProfile -WindowStyle Hidden -Command \"Start-Process -WindowStyle Hidden -FilePath '%APP%\local\start-local.bat'\"" >nul
echo   [4/6] השרת המקומי יופעל בכל כניסה ל-Windows

rem הפעלת המסך בכל כניסה ל-Windows — דרך הרישום ולא דרך קובץ VBS (שאנטי-וירוס לפעמים מוחק)
del "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\luach-board.vbs" >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v LuachBoard /t REG_SZ /f /d "powershell -NoProfile -WindowStyle Hidden -Command \"Start-Process -WindowStyle Hidden -FilePath 'C:\luach\board-kiosk.bat'\"" >nul
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('C:\Users\Public\Desktop\לוח הקומה.lnk'); $s.TargetPath='%APP%\screen\LuachScreen.exe'; $s.WorkingDirectory='%APP%\screen'; $s.Save()" >nul 2>&1
echo   [5/6] המסך ייפתח במסך מלא בכל הדלקה ^(תוכנת "לוח הקומה"^)

copy /y "%APP%\local\show-address.bat" "C:\Users\Public\Desktop\כתובת-ניהול.bat" >nul
echo   [6/6] בשולחן העבודה: "כתובת-ניהול" — מציג את הכתובת לאייפון

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
if not defined LUACH_SELF pause
