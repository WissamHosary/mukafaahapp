# Mukafaah - one-click setup, test and build (Windows PowerShell 5.1+).
# Run it by double-clicking tools\SETUP-AND-BUILD.bat
# Everything is logged to tools\logs so problems can be diagnosed.

param(
  [switch]$SkipBackend,
  [switch]$WithWindows,
  # Build only one app: -Only customer  or  -Only business
  [ValidateSet('all', 'customer', 'business')][string]$Only = 'all'
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Logs = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $Logs "run-$Stamp.log"
Start-Transcript -Path $LogFile -Force | Out-Null

$Summary = New-Object System.Collections.ArrayList
function Step($name) { Write-Host ""; Write-Host "==== $name ====" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "  OK   $msg" -ForegroundColor Green; [void]$Summary.Add("OK    $msg") }
function Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red; [void]$Summary.Add("FAIL  $msg") }
function Info($msg) { Write-Host "  ..   $msg" }

# Run an external command, stream output to the log, return exit code.
function Run($file, $argList, $workDir) {
  Info "$file $argList"
  $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $file $argList" -WorkingDirectory $workDir -NoNewWindow -PassThru -Wait `
    -RedirectStandardOutput "$Logs\_out.txt" -RedirectStandardError "$Logs\_err.txt"
  Get-Content "$Logs\_out.txt" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "     $_" }
  Get-Content "$Logs\_err.txt" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "     $_" }
  return $p.ExitCode
}

# ---------------------------------------------------------------- tools
Step 'Checking tools'
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue)
if (-not $flutter) {
  foreach ($c in @("$env:USERPROFILE\flutter\bin\flutter.bat", "C:\src\flutter\bin\flutter.bat", "C:\flutter\bin\flutter.bat", "$env:USERPROFILE\dev\flutter\bin\flutter.bat")) {
    if (Test-Path $c) { $env:Path = (Split-Path $c) + ';' + $env:Path; $flutter = Get-Command flutter -ErrorAction SilentlyContinue; break }
  }
}
if ($flutter) { Ok "Flutter found: $($flutter.Source)" } else { Fail 'Flutter not found. Install Flutter (stable) and add it to PATH.' }

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($docker) { Ok 'Docker CLI found' } else { Fail 'Docker not found. Install Docker Desktop.' }

if ($flutter) {
  $v = & flutter --version --machine 2>$null | Out-String
  Write-Host $v
  try {
    $fv = ($v | ConvertFrom-Json).frameworkVersion
    $parts = $fv.Split('.')
    if ([int]$parts[0] -lt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -lt 44)) {
      Info "Flutter $fv is older than 3.44 - upgrading to the latest stable"
      Run 'flutter' 'upgrade' $Root | Out-Null
    } else { Ok "Flutter version $fv" }
  } catch { Info 'Could not read Flutter version' }
  Run 'flutter' 'doctor -v' $Root | Out-Null
}

# ---------------------------------------------------------------- backend
$apiOk = $false
if (-not $SkipBackend -and $docker) {
  Step 'Starting backend (PostgreSQL + API) with Docker'
  $code = Run 'docker' 'compose up -d --build' $Root
  if ($code -ne 0) { Fail 'docker compose up failed (is Docker Desktop running?)' }
  else {
    Info 'Waiting for API health...'
    for ($i = 0; $i -lt 60; $i++) {
      try { $h = Invoke-RestMethod -Uri 'http://localhost:3000/health' -TimeoutSec 3; if ($h.status -eq 'ok') { $apiOk = $true; break } } catch {}
      Start-Sleep -Seconds 3
    }
    if ($apiOk) { Ok 'API is healthy on http://localhost:3000' }
    else {
      Fail 'API did not become healthy'
      Run 'docker' 'compose logs --tail 200 api' $Root | Out-Null
    }
  }
}

# ---------------------------------------------------------------- end-to-end smoke test
if ($apiOk) {
  Step 'End-to-end test: owner -> cashier -> Pre-Points -> customer collect -> redeem'
  & (Join-Path $PSScriptRoot 'smoke-test.ps1') -Base 'http://localhost:3000'
  if ($LASTEXITCODE -eq 0) { Ok 'End-to-end API test passed' } else { Fail 'End-to-end API test failed (see log)' }
}

# ---------------------------------------------------------------- LAN address for phones
$ip = $null
try {
  $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL|Docker|VirtualBox|VMware' -and $_.IPAddress -notmatch '^(169\.254|127\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
      Select-Object -First 1).IPAddress
} catch {}
if (-not $ip) { $ip = '10.0.2.2' }
$apiUrl = "http://${ip}:3000"
Ok "Apps will call the API at $apiUrl (phones must be on the same Wi-Fi)"

# Allow phones on the LAN to reach port 3000 (needs admin; ignored otherwise)
try { New-NetFirewallRule -DisplayName 'Mukafaah API dev 3000' -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -Profile Private -ErrorAction Stop 2>$null | Out-Null; Ok 'Firewall rule added for port 3000' } catch { Info 'Firewall rule not added (run as administrator if phones cannot connect)' }

# ---------------------------------------------------------------- Flutter apps
function Patch-Android($appDir, $label, [bool]$camera, [bool]$location = $false) {
  $manifest = Join-Path $appDir 'android\app\src\main\AndroidManifest.xml'
  if (Test-Path $manifest) {
    $m = (Get-Content $manifest -Raw).TrimStart([char]0xFEFF)
    if ($m -notmatch 'android.permission.INTERNET') {
      $perms = '    <uses-permission android:name="android.permission.INTERNET"/>' + "`r`n"
      if ($camera) { $perms += '    <uses-permission android:name="android.permission.CAMERA"/>' + "`r`n" }
      $m = $m -replace '(<manifest[^>]*>)', ('$1' + "`r`n" + $perms)
    }
    if ($location -and $m -notmatch 'ACCESS_FINE_LOCATION') {
      # v0.7: the customer map asks for location to show nearby shops.
      $loc = '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>' + "`r`n" + '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>' + "`r`n"
      $m = $m -replace '(<manifest[^>]*>)', ('$1' + "`r`n" + $loc)
    }
    if ($location -and $m -notmatch 'USE_BIOMETRIC') {
      # v0.8: fingerprint unlock in the customer app.
      $m = $m -replace '(<manifest[^>]*>)', ('$1' + "`r`n" + '    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>' + "`r`n")
    }
    $m = $m -replace 'android:label="[^"]*"', ('android:label="' + $label + '"')
    if ($m -notmatch 'usesCleartextTraffic') {
      # Development builds talk to the local API over http. Production uses HTTPS only.
      $m = $m -replace '<application', '<application android:usesCleartextTraffic="true"'
    }
    [System.IO.File]::WriteAllText($manifest, $m, (New-Object System.Text.UTF8Encoding($false)))
  }
  if ($location) {
    # Fingerprint unlock (local_auth) needs a FlutterFragmentActivity.
    Get-ChildItem -Recurse -ErrorAction SilentlyContinue (Join-Path $appDir 'android\app\src\main') -Include 'MainActivity.kt', 'MainActivity.java' | ForEach-Object {
      $a = (Get-Content $_.FullName -Raw)
      $a = $a -replace 'io\.flutter\.embedding\.android\.FlutterActivity\b', 'io.flutter.embedding.android.FlutterFragmentActivity'
      $a = $a -replace '\bFlutterActivity\(\)', 'FlutterFragmentActivity()'
      $a = $a -replace 'extends FlutterActivity\b', 'extends FlutterFragmentActivity'
      [System.IO.File]::WriteAllText($_.FullName, $a, (New-Object System.Text.UTF8Encoding($false)))
    }
    # iPhone: Face ID needs a reason shown to the user.
    $plist = Join-Path $appDir 'ios\Runner\Info.plist'
    if ((Test-Path $plist) -and -not ((Get-Content $plist -Raw) -match 'NSFaceIDUsageDescription')) {
      # Only the first (top-level) <dict>.
      $p = ([regex]'<dict>').Replace((Get-Content $plist -Raw), "<dict>`n`t<key>NSFaceIDUsageDescription</key>`n`t<string>Unlock your Mukafaah wallet with Face ID.</string>", 1)
      [System.IO.File]::WriteAllText($plist, $p, (New-Object System.Text.UTF8Encoding($false)))
    }
  }
  foreach ($g in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
    $gp = Join-Path $appDir $g
    if (Test-Path $gp) {
      $c = (Get-Content $gp -Raw).TrimStart([char]0xFEFF)
      $c = $c -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
      $c = $c -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'
      if ($c -notmatch 'org\.jetbrains\.kotlin\.android|kotlin-android') {
        $c = $c -replace 'id\("com\.android\.application"\)', ('id("com.android.application")' + "`r`n" + '    id("org.jetbrains.kotlin.android")')
      }
      [System.IO.File]::WriteAllText($gp, $c, (New-Object System.Text.UTF8Encoding($false)))
    }
  }
}

function Prepare-App($name, $project, $platforms, $label, [bool]$camera) {
  $dir = Join-Path $Root "apps\$name"
  $platformSrc = Join-Path $PSScriptRoot "platform\$(if ($name -eq 'customer_app') { 'customer' } else { 'business' })"
  Step "Preparing $name"
  if (-not (Test-Path (Join-Path $dir 'android'))) {
    Run 'flutter' "create --org app.mukafaah --project-name $project --platforms=$platforms --no-pub ." $dir | Out-Null
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $dir 'test\widget_test.dart')
  }
  Patch-Android $dir $label $camera ($name -eq 'customer_app')
  # Brand icons
  Copy-Item -Recurse -Force (Join-Path $platformSrc 'android') $dir -ErrorAction SilentlyContinue
  if (Test-Path (Join-Path $platformSrc 'windows')) { Copy-Item -Recurse -Force (Join-Path $platformSrc 'windows') $dir -ErrorAction SilentlyContinue }

  if ((Run 'flutter' 'pub get' $dir) -ne 0) { Fail "${name}: pub get failed"; return $false }
  Ok "${name}: dependencies resolved"
  Run 'flutter' 'analyze --no-fatal-infos --no-fatal-warnings' $dir | Out-Null
  if (Test-Path (Join-Path $dir 'test')) {
    if ((Run 'flutter' 'test' $dir) -eq 0) { Ok "${name}: tests passed" } else { Fail "${name}: tests failed" }
  }
  return $true
}

$dist = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$defines = "--dart-define=ENV=dev --dart-define=API_URL=$apiUrl"
# Real phones only (ARM). Skipping the x86_64 emulator build roughly halves
# the disk space and time a release build needs.
$apkArgs = "build apk --release --target-platform android-arm,android-arm64 $defines"

# Build output is several GB and fully regenerated, so clear it before and
# after each build to keep the disk from filling up.
function Clear-Build($dir) {
  $b = Join-Path $dir 'build'
  if (Test-Path $b) { Remove-Item -Recurse -Force $b -ErrorAction SilentlyContinue; Info "Cleared $b" }
}
foreach ($a in @('customer_app', 'business_app')) { Clear-Build (Join-Path $Root "apps\$a") }

if ($flutter) {
  foreach ($pkg in @('packages\mk_core', 'packages\mk_ui')) {
    Step "Resolving $pkg"
    if ((Run 'flutter' 'pub get' (Join-Path $Root $pkg)) -eq 0) { Ok "$pkg resolved" } else { Fail "$pkg pub get failed" }
  }

  if ($Only -ne 'business' -and (Prepare-App 'customer_app' 'mukafaah_customer' 'android,ios' 'Mukafaah' $false)) {
    Step 'Building Customer APK'
    $dir = Join-Path $Root 'apps\customer_app'
    if ((Run 'flutter' $apkArgs $dir) -eq 0) {
      Copy-Item -Force (Join-Path $dir 'build\app\outputs\flutter-apk\app-release.apk') (Join-Path $dist 'Mukafaah-Customer.apk')
      Ok 'Customer APK -> dist\Mukafaah-Customer.apk'
    } else { Fail 'Customer APK build failed' }
    Clear-Build $dir
  }

  if ($Only -ne 'customer' -and (Prepare-App 'business_app' 'mukafaah_business' 'android,ios' 'Mukafaah Business' $true)) {
    Step 'Building Business APK'
    $dir = Join-Path $Root 'apps\business_app'
    if ((Run 'flutter' $apkArgs $dir) -eq 0) {
      Copy-Item -Force (Join-Path $dir 'build\app\outputs\flutter-apk\app-release.apk') (Join-Path $dist 'Mukafaah-Business.apk')
      Ok 'Business APK -> dist\Mukafaah-Business.apk'
    } else { Fail 'Business APK build failed (if it says "not enough space", free a few GB and run BUILD-BUSINESS-APK.bat)' }
    if (-not $WithWindows) { Clear-Build $dir }

    if ($WithWindows) {
      Step 'Building Business app for Windows'
      $winDefines = "--dart-define=ENV=dev --dart-define=API_URL=http://localhost:3000"
      if ((Run 'flutter' "build windows --release $winDefines" $dir) -eq 0) {
        $out = Join-Path $dir 'build\windows\x64\runner\Release'
        $target = Join-Path $dist 'Mukafaah-Business-Windows'
        Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
        Copy-Item -Recurse -Force $out $target
        Ok 'Windows build -> dist\Mukafaah-Business-Windows\mukafaah_business.exe'
      } else { Fail 'Windows build failed (needs Visual Studio 2022 with "Desktop development with C++")' }
    }
  }
}

Step 'Summary'
$Summary | ForEach-Object { Write-Host "  $_" }
$Summary | Out-File -FilePath (Join-Path $Logs 'last-summary.txt') -Encoding UTF8
Stop-Transcript | Out-Null
Copy-Item -Force $LogFile (Join-Path $Logs 'last-run.log')
Write-Host ""
Write-Host "Full log: $LogFile"
