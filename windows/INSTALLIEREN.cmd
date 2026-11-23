@echo off
rem GrindGuard fuer Windows installieren oder aktualisieren (Doppelklick genuegt)
if not exist "%~dp0app\install.ps1" (
    echo Bitte zuerst das ZIP entpacken: Rechtsklick auf die ZIP-Datei, "Alle extrahieren".
    echo Danach INSTALLIEREN.cmd im entpackten Ordner starten.
    echo.
    pause
    exit /b 1
)
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\install.ps1"
echo.
pause
