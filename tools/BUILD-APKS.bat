@echo off
title Mukafaah - build both APKs
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-and-build.ps1" -SkipBackend
echo.
echo Done. The APKs are in the "dist" folder.
pause
