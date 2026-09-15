@echo off
rem ============================================================
rem  Double-click wrapper. All real work lives in install-open-with.ps1.
rem  Comments here are kept ASCII-only ON PURPOSE: cmd.exe parses this
rem  file with the console's current code page, so Chinese text would be
rem  garbled bytes before "chcp 65001" below takes effect.
rem  (Chinese console output comes from the PowerShell script.)
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-open-with.ps1"
echo.
pause
