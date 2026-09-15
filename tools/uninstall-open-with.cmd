@echo off
rem ============================================================
rem  Double-click wrapper for REMOVING the "Open with" entry.
rem  Same PowerShell file as install-open-with.cmd, plus -Uninstall.
rem  ASCII-only comments on purpose -- see install-open-with.cmd.
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-open-with.ps1" -Uninstall
echo.
pause
