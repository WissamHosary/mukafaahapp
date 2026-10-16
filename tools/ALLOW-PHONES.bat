@echo off
title Mukafaah - allow phones
rem Lets phones on your Wi-Fi reach the Mukafaah server (port 3000) through Windows Firewall.
rem Needs administrator rights once; Windows will ask.
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
netsh advfirewall firewall delete rule name="Mukafaah server 3000" >nul 2>&1
netsh advfirewall firewall add rule name="Mukafaah server 3000" dir=in action=allow protocol=TCP localport=3000 profile=private,domain
echo.
echo Done. Phones on the same Wi-Fi can now reach this PC on port 3000.
echo If your Wi-Fi is set as "Public" in Windows, change it to "Private":
echo   Settings ^> Network ^& internet ^> Wi-Fi ^> your network ^> Private network
pause
