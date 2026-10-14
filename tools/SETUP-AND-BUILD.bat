@echo off
title Mukafaah - setup, test and build
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-and-build.ps1" %*
echo.
echo Done. Results are in the "dist" folder and logs in "tools\logs".
pause
