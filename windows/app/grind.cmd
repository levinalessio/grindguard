@echo off
rem GrindGuard - Befehle. Beispiel:  grind status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0grindguard.ps1" %*
exit /b %ERRORLEVEL%
