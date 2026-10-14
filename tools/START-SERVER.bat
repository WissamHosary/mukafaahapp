@echo off
title Mukafaah - server
cd /d "%~dp0.."
echo Starting Mukafaah server (PostgreSQL + API) in Docker...
docker compose up -d --build > "%~dp0logs\server-start.log" 2>&1
type "%~dp0logs\server-start.log"
echo.
echo Waiting for the API...
powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 60;$i++){try{$h=Invoke-RestMethod http://localhost:3000/health -TimeoutSec 3; if($h.status -eq 'ok'){Write-Host 'API is running on port 3000' -ForegroundColor Green; break}}catch{}; Start-Sleep 3}"
echo.
echo Running the end-to-end test...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0smoke-test.ps1" > "%~dp0logs\smoke-test.log" 2>&1
type "%~dp0logs\smoke-test.log"
docker compose logs --tail 80 api > "%~dp0logs\api.log" 2>&1
echo.
echo Done. You can close this window; the server keeps running in Docker.
pause
