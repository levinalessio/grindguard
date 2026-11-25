@echo off
rem GrindGuard entfernen (Doppelklick genuegt). Waehrend einer Fokus-Sitzung geht das nicht.
set "GG=%USERPROFILE%\GrindGuard\grindguard.ps1"
if not exist "%GG%" (
    echo GrindGuard ist auf diesem PC nicht installiert.
    echo.
    pause
    exit /b 1
)
cd /d "%TEMP%"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%GG%" deinstallieren
exit /b 0
