<# : batch portion
@echo off
chcp 65001 >nul
title לוח הקומה — התקנה במחשב המסך
set "LUACH_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText($env:LUACH_SELF, [Text.Encoding]::UTF8))"
exit /b
#>
# ===== לוח הקומה — התקנה אוטומטית של מצב מקומי במחשב המסך =====
# קובץ אחד: מבקש הרשאות מנהל, מתקין Node.js אם חסר, מוריד את הלוח מ-GitHub ומריץ את local\install-local.bat.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$RepoZip = 'https://github.com/ShDyDaniel/luach/archive/refs/heads/main.zip'

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host '  מבקש הרשאות מנהל... (לחץ "כן" בחלון שייפתח)'
  Start-Process -FilePath $env:LUACH_SELF -Verb RunAs
  exit
}
function Step($t) { Write-Host "`n  $t" -ForegroundColor Cyan }

try {
  Step '[1/4] בודק Node.js...'
  $nodeExe = Join-Path $env:ProgramFiles 'nodejs\node.exe'
  if (-not (Get-Command node -ErrorAction SilentlyContinue) -and -not (Test-Path $nodeExe)) {
    Step '      מתקין Node.js (פעם אחת, כמה דקות)...'
    $ver = (Invoke-RestMethod 'https://nodejs.org/dist/index.json' | Where-Object { $_.lts } | Select-Object -First 1).version
    $base = "https://nodejs.org/dist/$ver/"
    $line = (Invoke-WebRequest -UseBasicParsing ($base + 'SHASUMS256.txt')).Content -split "`n" |
      Where-Object { $_ -match 'node-v[\d.]+-x64\.msi\s*$' } | Select-Object -First 1
    $hash, $name = $line.Trim() -split '\s+'
    $msi = Join-Path $env:TEMP $name
    Invoke-WebRequest -UseBasicParsing ($base + $name) -OutFile $msi
    if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne $hash.ToUpper()) { throw 'הקובץ של Node.js הורד פגום. נסה שוב.' }
    $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "התקנת Node.js נכשלה (קוד $($p.ExitCode))" }
  }
  $env:Path += ";$(Join-Path $env:ProgramFiles 'nodejs')"
  Write-Host "      Node.js $(& node --version)"

  Step '[2/4] בודק את רכיב התצוגה של Windows (WebView2)...'
  $wvKey = 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
  $wvVer = @((Get-ItemProperty "HKLM:\$wvKey" -ErrorAction SilentlyContinue).pv, (Get-ItemProperty "HKCU:\$($wvKey -replace 'WOW6432Node\\','')" -ErrorAction SilentlyContinue).pv) |
    Where-Object { $_ -and $_ -ne '0.0.0.0' } | Select-Object -First 1
  if ($wvVer) { Write-Host "      WebView2 $wvVer" }
  else {
    Step '      מתקין את WebView2 של מיקרוסופט (פעם אחת)...'
    $wvSetup = Join-Path $env:TEMP 'MicrosoftEdgeWebview2Setup.exe'
    Invoke-WebRequest -UseBasicParsing 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $wvSetup
    $sig = Get-AuthenticodeSignature $wvSetup
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'קובץ ההתקנה של WebView2 לא חתום על ידי מיקרוסופט — עצרתי.' }
    $p = Start-Process $wvSetup -ArgumentList '/silent', '/install' -Wait -PassThru
    if ($p.ExitCode -ne 0) { Write-Host "      אזהרה: התקנת WebView2 החזירה קוד $($p.ExitCode). אם המסך לא נפתח — התקן ידנית מאתר מיקרוסופט." -ForegroundColor Yellow }
  }

  Step '[3/4] מוריד את הלוח מ-GitHub...'
  $work = Join-Path $env:TEMP 'luach-setup'
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $work | Out-Null
  $zip = Join-Path $work 'luach.zip'
  Invoke-WebRequest -UseBasicParsing $RepoZip -OutFile $zip
  Expand-Archive $zip $work -Force
  $src = Get-ChildItem $work -Directory | Select-Object -First 1

  Step '[4/4] מתקין...'
  $p = Start-Process cmd.exe -ArgumentList '/c', "`"$($src.FullName)\local\install-local.bat`"" -Wait -PassThru -NoNewWindow
  if ($p.ExitCode -ne 0) { throw "ההתקנה נכשלה (קוד $($p.ExitCode))" }

  # מפעיל את השרת כבר עכשיו, בלי לחכות להדלקה הבאה
  Start-Process -WindowStyle Hidden -FilePath 'C:\luach\app\local\start-local.bat'
  Start-Sleep -Seconds 3
  # סוגר את Chrome של הקיוסק הישן (רק אותו — לפי תיקיית הפרופיל שלו) ומפעיל את תוכנת המסך המלא
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like '*C:\luach\chrome-profile*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Process -WindowStyle Hidden -FilePath 'C:\luach\board-kiosk.bat'
  Step 'הכול מוכן ✓  הלוח נפתח עכשיו במסך מלא. לסגירה: Ctrl+Shift+Q'
} catch {
  Write-Host "`n  שגיאה: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host '  צלם את המסך הזה ושלח אותו.'
}
Read-Host "`n  לחץ Enter לסגירה"
