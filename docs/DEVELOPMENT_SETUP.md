# Development setup (Windows)

1. Docker Desktop (running), Flutter stable ≥ 3.44, Android Studio + SDK (accept licences: `flutter doctor --android-licenses`), Visual Studio 2022 "Desktop development with C++" for Windows builds.
2. `tools\SETUP-AND-BUILD.bat` — starts the stack, runs `tools\smoke-test.ps1`, resolves packages, analyzes, tests and builds. Logs: `tools\logs\last-run.log`.
3. Run an app against the local API: `flutter run --dart-define=ENV=dev --dart-define=API_URL=http://<your-PC-IP>:3000` (Android emulator: `http://10.0.2.2:3000`).
4. Backend only: `docker compose up -d --build`, logs `docker compose logs -f api`, reset data `docker compose down -v`.
