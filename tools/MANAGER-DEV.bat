@echo off
setlocal
cd /d "%~dp0.."
where node >nul 2>nul || (echo Node.js is not installed. Get the LTS from https://nodejs.org then run this again. & pause & exit /b 1)
set "API=%~1"
if "%API%"=="" set /p API=API address [Enter for http://localhost:3000, or Wissam's e.g. http://192.168.1.5:3000]: 
if "%API%"=="" set "API=http://localhost:3000"
start "" "http://localhost:5173/admin"
node tools\manager-dev\server.mjs %API%
pause
