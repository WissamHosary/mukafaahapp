@echo off
title Mukafaah - add demo shops
cd /d "%~dp0"
echo Adds 6 sample shops marked "Demo".
set /p ADMINPHONE=Your Mukafaah Manager phone number (press Enter to skip): 
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0seed-demo.ps1" -AdminPhone "%ADMINPHONE%"
pause
