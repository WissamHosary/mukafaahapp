@echo off
title Mukafaah - build Business APK
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-and-build.ps1" -SkipBackend -Only business
echo.
echo Done. The APK is in the "dist" folder.
pause
