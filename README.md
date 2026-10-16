# Mukafaah

Loyalty, Pre-Points, offers and commerce for Lebanon. Points only: no cash wallet, no online payments.

| Part | Folder | Platforms |
| --- | --- | --- |
| Customer app | `apps/customer_app` | Android, iOS |
| Business app (Owner Mode + Cashier Mode) | `apps/business_app` | Android, iOS |
| Backend API (NestJS + PostgreSQL) | `backend` | Docker / AWS |
| Design system | `packages/mk_ui` | shared |
| Core (API client, session, strings) | `packages/mk_core` | shared |

## Quick start (Windows)

1. Install **Docker Desktop**, **Flutter (stable, 3.44 or newer)** and **Android Studio** (Android SDK).
2. Double-click `tools\SETUP-AND-BUILD.bat`.
   It starts PostgreSQL + the API, runs an end-to-end test of the whole points flow,
   then builds `dist\Mukafaah-Customer.apk`, and `dist\Mukafaah-Business.apk`.
3. Install the APKs on phones connected to the **same Wi-Fi** as this PC.

The development API returns the OTP code on screen ("Test code") so you can test without SMS.
This is disabled in production.

## Test the full flow (two phones)

1. **Business app → "I'm the owner"** → phone + code → create your business.
2. **Team → Add cashier** (name + PIN) → **Pair a counter device** → note the 8-letter code.
3. On the counter device: **Business app → "Counter device"** → enter the code → choose the cashier → PIN.
4. Type a phone number that is **not** on the app yet, enter a bill → points are saved as **Pre-Points**.
5. **Customer app** → sign in with that same phone → **Collect** → points move to the wallet.
6. Show **My QR** at the counter → scan (or type) → give or redeem points.
7. Owner → **Dashboard** shows bills, points and cashier performance.

See `docs/` for architecture, security, API, database, design system and deployment.

## Working together on this repo

Everyone works from a clone of `https://github.com/WissamHosary/mukafaahapp` and pushes back to it.

1. **First time:** `git clone https://github.com/WissamHosary/mukafaahapp.git` (or in Android Studio: *File → New → Project from Version Control*).
2. **Before you start each time:** `git pull` so you have the other person's latest work.
3. **For each change:** make a branch, commit, push it and open a Pull Request into `main`:
   ```
   git checkout -b my-change
   git add -A
   git commit -m "What changed"
   git push -u origin my-change
   ```
4. GitHub runs **App check** (flutter analyze) and **Backend check** on every push and Pull Request. Merge only when both are green.
5. After a merge, everyone runs `git pull` on `main` again.
6. New database changes go in a new numbered file in `backend/sql/` (the next one is `015_...sql`). Never edit a file that is already merged, and restart the server so it runs.
7. Never commit secrets: `.env`, keys and Google service files are ignored on purpose.

APKs: *Actions → Build APKs → Run workflow*. The files appear under *Releases → latest*.
