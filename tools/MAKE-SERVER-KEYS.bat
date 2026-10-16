@echo off
title Mukafaah - server keys
rem Copies this PC server's secret keys into one line for the hosted server (KEYS_JSON).
rem The PC server must be running (START-SERVER.bat).
cd /d "%~dp0.."
docker compose exec -T api node -e "process.stdout.write(Buffer.from(require('fs').readFileSync('/app/keys/keys.json')).toString('base64'))" > "%~dp0server-keys.txt"
if errorlevel 1 (
  echo Could not read the keys. Start the server first with START-SERVER.bat.
  pause
  exit /b 1
)
echo.
echo Saved to tools\server-keys.txt
echo Copy everything in that file into KEYS_JSON on the hosted server (Render).
echo Keep it secret: anyone with it can read the phone numbers. Do not put it on GitHub.
notepad "%~dp0server-keys.txt"
