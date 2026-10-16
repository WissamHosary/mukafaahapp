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

## Working on the Manager (admin panel) locally

The Manager lives in `backend/admin` (`app.js`, `styles.css`, `index.html`) - plain files, no build step.
`tools\MANAGER-DEV.bat` serves them straight from disk on http://localhost:5173/admin and forwards
every `/v1` call to a Mukafaah API, so an edit shows on a browser refresh (no Docker rebuild).
It needs Node.js only, no packages.

Pick the API it talks to:
- **Wissam's PC (same Wi-Fi):** Wissam runs `tools\START-SERVER.bat` (it prints his IP) and `tools\ALLOW-PHONES.bat` once;
  you run `tools\MANAGER-DEV.bat http://<his IP>:3000`. You see and change the same data as his phones.
- **Your own server:** install Docker Desktop, run `tools\START-SERVER.bat`, then `tools\MANAGER-DEV.bat` and press Enter.
  Run `tools\SEED-DEMO.bat` for demo shops.

Signing in: in development the code shows on screen. On a fresh server the first person to sign in
becomes the Manager owner; on Wissam's server, he adds you under Accounts.

## Mukafaah Manager on Netlify

The web dashboard can be live on Netlify, updated automatically on every push to `main` (by either programmer).

1. Netlify → **Add new site → Import an existing project → GitHub** → pick `WissamHosary/mukafaahapp`. The settings come from `netlify.toml`; leave them as they are.
2. **Site configuration → Environment variables** → add `API_URL` = the public HTTPS address of the Mukafaah server (for example `https://api.mukafaah.app`). Then **Deploys → Trigger deploy**.
3. Open the Netlify address: it goes straight to the Manager. Sign-in and all data go through Netlify to that server, so it must be online on the internet (a PC at home on Wi-Fi is not reachable from Netlify).
4. To let the other programmer manage the Netlify site too: **Team settings → Members → Invite**. For code, adding them to the GitHub repo is enough: their pushes deploy as well.

Pull Requests get their own preview link from Netlify, so a change can be checked before it is merged.

## Putting the server online (Supabase + Render)

The data lives in **Supabase** (PostgreSQL) and the Mukafaah API runs on **Render**. Netlify shows the Manager and passes its calls to Render.

1. **Supabase:** create a project (region: Frankfurt/eu-central). Then **Connect → Session pooler** and copy the connection string (with your database password filled in).
2. **Keys:** on the PC, with the server running, double-click `tools\MAKE-SERVER-KEYS.bat`. It saves `tools\server-keys.txt` (secret, never on GitHub).
3. **Render:** New → **Blueprint** → pick this repo (it reads `render.yaml`). Fill in:
   `DATABASE_URL` = the Supabase string, `KEYS_JSON` = the text from step 2, `ADMIN_PHONES` = your phone (e.g. `70123456`).
   On first start the server creates all the tables in Supabase by itself. It also locks Supabase's public Data API, since everything goes through the Mukafaah server.
4. **Netlify:** set `API_URL` to the Render address (e.g. `https://mukafaah-api.onrender.com`) and redeploy.
5. **Apps:** build the APKs with that same address (Actions → Build APKs → `api_url`), or type it under **Server** on the app's first screen.

Every push to `main` redeploys Render (server) and Netlify (Manager) automatically.
