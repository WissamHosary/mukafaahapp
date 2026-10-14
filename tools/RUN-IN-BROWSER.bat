@echo off
title Mukafaah - run in browser
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-in-browser.ps1"
pause
