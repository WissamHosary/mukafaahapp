@echo off
title Mukafaah - server
cd /d "%~dp0.."
if not exist "%~dp0logs" mkdir "%~dp0logs"
echo Starting Mukafaah server (PostgreSQL + API) in Docker...
docker compose up -d --build > "%~dp0logs\server-start.log" 2>&1
if errorlevel 1 (
  type "%~dp0logs\server-start.log"
  echo.
  echo Could not start. Is Docker Desktop open and running?
  pause
  exit /b 1
)
echo.
echo Waiting for the API...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0;$i -lt 60;$i++){try{$h=Invoke-RestMethod http://localhost:3000/health -TimeoutSec 3; if($h.status -eq 'ok'){$ok=$true; break}}catch{}; Start-Sleep 3}; if($ok){Write-Host 'API is running on port 3000' -ForegroundColor Green}else{Write-Host 'The API did not answer. Look at tools\logs\api.log' -ForegroundColor Red}"
docker compose logs --tail 120 api > "%~dp0logs\api.log" 2>&1
echo.
echo ==================================================================
echo  Phones must be on the SAME Wi-Fi as this PC.
echo  In the app, tap "Server" on the first screen and type the address below.
echo ==================================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback|VirtualBox|VMware' } | ForEach-Object { Write-Host ('   ' + $_.IPAddress + ':3000     (' + $_.InterfaceAlias + ')') -ForegroundColor Yellow }"
echo.
echo  Manager (web dashboard) on this PC:  http://localhost:3000/admin
echo  If phones still can't connect, run ALLOW-PHONES.bat once (Windows Firewall).
echo.
echo Running the end-to-end test...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0smoke-test.ps1" > "%~dp0logs\smoke-test.log" 2>&1
type "%~dp0logs\smoke-test.log"
echo.
echo Done. You can close this window; the server keeps running in Docker
echo and starts again by itself whenever Docker Desktop starts.
pause
