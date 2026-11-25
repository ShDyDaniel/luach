#!/bin/sh
# בונה את LuachScreen.exe (גם ממק/לינוקס) ומעתיק את התוצאה לתיקייה screen/ שבמאגר,
# שממנה ההתקנה (luach-setup.bat) מעתיקה אותה למחשב המסך.
set -e
cd "$(dirname "$0")"
rm -rf bin obj
dotnet build -c Release -nologo
OUT=../screen
rm -rf "$OUT" && mkdir -p "$OUT"
cp bin/Release/LuachScreen.exe bin/Release/LuachScreen.exe.config \
   bin/Release/Microsoft.Web.WebView2.Core.dll bin/Release/Microsoft.Web.WebView2.WinForms.dll \
   bin/Release/WebView2Loader.dll "$OUT/"
mkdir -p "$OUT/runtimes/win-x64/native" && cp bin/Release/WebView2Loader.dll "$OUT/runtimes/win-x64/native/"
ls -l "$OUT"
# הורדה עצמאית מדף הניהול (מידע ← תוכנת מסך מלא): zip עם התיקייה כולה
rm -f "$OUT/LuachScreen.zip"
( cd "$OUT" && mkdir -p ../.zipstage/LuachScreen && cp -R LuachScreen.exe LuachScreen.exe.config *.dll runtimes ../.zipstage/LuachScreen/ \
  && cd ../.zipstage && zip -qr -X ../screen/LuachScreen.zip LuachScreen ) && rm -rf ../.zipstage
ls -l "$OUT/LuachScreen.zip"
