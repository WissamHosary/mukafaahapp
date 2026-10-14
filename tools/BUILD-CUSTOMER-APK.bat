@echo off
title Mukafaah - build Customer APK
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-and-build.ps1" -SkipBackend -Only customer
echo.
echo Done. The APK is in the "dist" folder.
pause
