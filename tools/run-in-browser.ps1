# Mukafaah - open both apps in Chrome on this PC (for quick testing).
#   Customer app -> http://localhost:8080
#   Business app -> http://localhost:8081
# Each app is built in its own window. After a code change, close that window and run this again.

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
  foreach ($c in @("$env:USERPROFILE\flutter\bin\flutter.bat", "C:\src\flutter\bin\flutter.bat", "C:\flutter\bin\flutter.bat")) {
    if (Test-Path $c) { $env:Path = (Split-Path $c) + ';' + $env:Path; break }
  }
}

Write-Host 'Starting the server (Docker)...' -ForegroundColor Cyan
Push-Location $Root
cmd.exe /c "docker compose up -d --build"
Pop-Location
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { $h = Invoke-RestMethod -Uri 'http://localhost:3000/health' -TimeoutSec 3; if ($h.status -eq 'ok') { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 3
}
if ($ok) { Write-Host 'Server is running on http://localhost:3000' -ForegroundColor Green }
else { Write-Host 'Server did not start - is Docker Desktop open?' -ForegroundColor Red }

$defines = '--dart-define=ENV=dev --dart-define=API_URL=http://localhost:3000'
$apps = @(
  @{ Dir = 'customer_app'; Name = 'mukafaah_customer'; Port = 8080; Title = 'Mukafaah Customer (browser)' },
  @{ Dir = 'business_app'; Name = 'mukafaah_business'; Port = 8081; Title = 'Mukafaah Business (browser)' }
)
foreach ($a in $apps) {
  $dir = Join-Path $Root "apps\$($a.Dir)"
  if (-not (Test-Path (Join-Path $dir 'web'))) {
    Write-Host "Adding web support to $($a.Dir)..." -ForegroundColor Cyan
    Push-Location $dir
    cmd.exe /c "flutter create --org app.mukafaah --project-name $($a.Name) --platforms=web --no-pub ."
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $dir 'test\widget_test.dart')
    Pop-Location
  }
  Write-Host "Opening $($a.Title) on http://localhost:$($a.Port)" -ForegroundColor Green
  Start-Process -FilePath 'cmd.exe' -WorkingDirectory $dir `
    -ArgumentList "/k title $($a.Title) && flutter run -d web-server --release --web-hostname localhost --web-port $($a.Port) $defines"
  Start-Sleep -Seconds 20
}

# Open each app in the normal browser as soon as it is being served.
# (No debugger is attached, which avoids the "web debug service" timeout.)
foreach ($a in $apps) {
  $url = "http://localhost:$($a.Port)"
  Write-Host "Waiting for $url ..."
  for ($i = 0; $i -lt 100; $i++) {
    try { $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3; if ($r.StatusCode -eq 200) { Start-Process $url; Write-Host "Opened $url" -ForegroundColor Green; break } } catch {}
    Start-Sleep -Seconds 5
  }
}

Write-Host ''
Write-Host 'Two windows are building the apps. Your browser opens each one when it is ready (2-4 minutes the first time).'
Write-Host 'Customer: http://localhost:8080    Business: http://localhost:8081'
Write-Host 'The sign-in code is shown on screen ("Test code").'
