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
