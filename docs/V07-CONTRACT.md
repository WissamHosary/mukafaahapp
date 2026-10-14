# Mukafaah v0.7 — shared contract (backend ⇄ Manager ⇄ apps)

Repo root: /mnt/user-data/outputs/mukafaah. Version strings: backend `'0.7.0'`, apps `0.7.0+7`.
Ownership (do not edit files owned by another workstream):
- A Backend: `backend/src/**`, `backend/sql/006_v07.sql`, `tools/smoke-test.ps1`, `tools/seed-demo.ps1`
- B Manager web: `backend/admin/**`
- C Customer app: `apps/customer_app/**`, `packages/mk_ui/**`
- D Business app: `apps/business_app/**`
- Nobody edits `packages/mk_core/**` except A may not either (frozen).

Money: minor units (cents). Points: integers, 100 points = $1. Timezone Asia/Beirut. All new JSON camelCase.
Errors keep the existing `{error:{code,message}}` shape.

## 1. Fixed member QR (replaces rotating token)
- `users.member_code` text UNIQUE, 12 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, created lazily.
- `GET /v1/customer/qr` → `{ payload: "MKF2:<memberCode>", memberCode }`. Never changes.
- Old `POST /v1/customer/qr/token` stays and returns `{ token: payload, payload, ttlSeconds: 0, expiresAt: null }` (same static payload).
- Cashier `lookup` / `earn` / every place that accepted `qr` accepts `MKF2:` payloads (and still old MKF1 tokens if present).
- Earning needs no approval. Spending points always needs customer approval (section 2).

## 2. Redeem approvals (customer approves in the app)
Table `redeem_requests(id uuid pk, user_id, business_id, branch_id, staff_id, device_id, kind text CHECK IN ('POINTS','OFFER','REWARD','BOOKING','MUKAFAAH'), title text, points int, value_minor int, payload jsonb, status text CHECK IN ('PENDING','APPROVED','DECLINED','EXPIRED','FAILED') default 'PENDING', result jsonb, error text, created_at, decided_at, expires_at = created_at + 120s)`.
- Cashier spend endpoints (`POST redeem`, `offers/:id/apply` when it costs points, `rewards/:id/redeem`, `bookings/:id/redeem` when it costs points, new `mukafaah/redeem`) for a MEMBER no longer post to the ledger. They validate exactly as today (balance, limits, offer rules) and return **202** `{ requestId, status:'PENDING', expiresAt, title, points }`. Free actions (0 points) execute immediately as today.
- `GET /v1/business/cashier/redeem-requests/:id` → `{ id, status, title, points, result?, error? }` (expired PENDING rows report `EXPIRED`).
- `POST /v1/business/cashier/redeem-requests/:id/cancel` → cashier cancels a pending one (status DECLINED, error 'CANCELLED').
- Customer: `GET /v1/customer/redeem-requests/pending` → `{ requests:[{ id, kind, title, points, valueMinor, shop:{id,name,logoUrl}, expiresAt }] }`.
- `POST /v1/customer/redeem-requests/:id/approve` → runs the original ledger posting inside the same transaction (re-checking balance); sets APPROVED + result, or FAILED + error. Returns `{ status, result?, error? }`.
- `POST /v1/customer/redeem-requests/:id/decline` → DECLINED.
- Creating a request also inserts a customer notification (kind `'REDEEM_REQUEST'`). Approve/decline creates a business alert (section 5).

## 3. Mukafaah Points (company points)
- A platform program row: `programs.type` gains `'PLATFORM'`; one row created by migration, name 'Mukafaah Points'. Stored in setting `mukafaah.programId`.
- Issuance account: owner_type `BUSINESS_ISSUED`, owner_id = that program id (allow_negative true). Customer account: `CUSTOMER`/user id. Redeemed at a shop: credit `BUSINESS_REDEEMED` owned by that shop (so Mukafaah knows what it owes each shop).
- Ledger tx types gain `'GRANT'` (Mukafaah gives points).
- `mukafaah_rules(code pk, title_en, title_ar, points int, active bool, sort)` seeded: `SIGNUP` 'Download the app and join' 100, `REFERRAL` 'Invite a friend who joins' 200, `FIRST_BILL` 'Your first bill at any shop' 50. Granted automatically: SIGNUP on registration (first OTP verify that creates the user), REFERRAL to the referrer when a referral is applied, FIRST_BILL on the user's first EARN. Each grant idempotent per (rule,user).
- Mukafaah Friends: `businesses.friends_enabled bool default false`, `businesses.friends_max_points int default 0` (max Mukafaah Points accepted per bill).
- Customer: `GET /v1/customer/wallet` adds `mukafaahPoints`. `GET /v1/customer/mukafaah` → `{ balance, rules:[{code,title,points}], friends:[{id,name,logoUrl,category,maxPoints}], history:[{id,type,points,title,createdAt}] }`.
- Cashier: `lookup` response adds `mukafaahPoints` and `friends:{ enabled, maxPoints }`. `POST /v1/business/cashier/mukafaah/redeem { userId, points, billMinor? }` → approval request kind MUKAFAAH; 403 `NOT_A_FRIEND` if shop not in Friends, 400 `OVER_LIMIT` if points > maxPoints.
- Admin: `GET /v1/admin/mukafaah` → `{ rules, totals:{ issued, redeemed, outstanding }, friends:[{id,name,friendsEnabled,maxPoints,redeemedPoints}] }`; `PATCH /v1/admin/mukafaah/rules/:code { title?, points?, active? }`; `POST /v1/admin/mukafaah/grant { phone, points (1..100000), reason }` (user must exist; 404 `USER_NOT_FOUND`); `PATCH /v1/admin/shops/:id/friends { enabled, maxPoints (0..100000) }`.

## 4. Tiers by total spend
- `tiers(code pk, name_en, name_ar, min_spend_minor int, bonus_points int, color text, perks_en text, sort, active)` seeded SILVER 0/0 '#9AA0A6', GOLD 2000 ($20)/100 '#E9B800', PLATINUM 10000 ($100)/300 '#5B2BD6'.
- `users.lifetime_spend_minor bigint default 0`, `users.tier text default 'SILVER'`. Every EARN (member) adds billMinor (VOID subtracts). When the user crosses into a higher tier: set tier, grant `bonus_points` Mukafaah Points (type GRANT, idempotent per user+tier), notify 'You reached Gold'.
- `GET /v1/customer/tier` → `{ tier, lifetimeSpendMinor, tiers:[{code,name,minSpendMinor,bonusPoints,color,perks}], next: {code,name,minSpendMinor,remainingMinor} | null }`. Home `tierProgress` keeps working, now spend-based.
- Admin `GET /v1/admin/tiers`, `PUT /v1/admin/tiers { tiers:[{code,name,minSpendMinor,bonusPoints,color,perks,active}] }` (codes `^[A-Z_]{2,20}$`, first tier min 0, strictly increasing).

## 5. Business alerts (live popup + sound in Business app)
- `business_alerts(id bigserial pk, business_id, kind text CHECK IN ('BOOKING','ORDER','REDEEM_APPROVED','REDEEM_DECLINED','RATING','OFFER_USED'), title, body, ref_id text, created_at)`.
- Inserted when: customer requests a booking (BOOKING), customer places a store order (ORDER), customer approves/declines a redeem request (REDEEM_*), customer rates (RATING).
- `GET /v1/business/manage/alerts?after=<id>` (owner) and `GET /v1/business/cashier/alerts?after=<id>` (staff, its business) → `{ alerts:[{ id, kind, title, body, refId, createdAt }], cursor }` newest last, max 50. `after` omitted → returns only `{alerts:[], cursor:<latest id>}` so the app starts from "now".

## 6. Home: banners layout + categories with logos
- Setting `home.bannerLayout` ∈ `UNO|DUO|TRIO` (default `UNO`). `GET /v1/customer/home` adds `bannerLayout`. UNO = one wide banner per slide; DUO = two side by side; TRIO = one tall + two stacked.
- Migration deletes the 3 seeded demo banners (titles 'In-Store','Shared','Earn more. Redeem more.') so banners start empty; the app hides the banner area when empty.
- Banners JSON add `imageUrl` (from media_id). Admin banner create/patch accept `mediaId`.
- `categories.color text` (hex, nullable). Category JSON (home, `/customer/categories`, public) adds `iconUrl` (from icon_media_id) and `color`. Admin category create/patch accept `iconMediaId` (nullable to clear) and `color`.

## 7. Mukafaah Manager accounts and scope
- `admins.role` CHECK gains `'SHOP'`. Table `admin_shops(user_id → admins, business_id, PRIMARY KEY(user_id,business_id))`.
- Sign-in unchanged (phone + OTP, app `ADMIN`). An account exists only if Mukafaah created it.
- `GET /v1/admin/me` → `{ userId, name, role, shops:[{id,name}] }`.
- Roles: OWNER/ADMIN = everything; EDITOR = content (banners, categories, sections, offers moderation, shops) but not accounts/tiers/mukafaah grant; SHOP = only their shops.
- SHOP may call: `me`, `GET shops` (filtered to theirs), `/v1/admin/shops/:id/**` for their shops only (profile, media, offers, rewards, bookings, store, orders, staff, branches, pairing codes, devices, bills), `GET reports/monthly` (shopId forced to one of theirs; `totals` only for their shop), `POST media`. Everything else → 403 `FORBIDDEN_SCOPE`. Shop PATCH of `earnPercent` allowed, `featured`/`category` not.
- `GET /v1/admin/accounts` (OWNER/ADMIN) → `{ accounts:[{ userId, name, phoneLast4, role, active, shops:[{id,name}], createdAt }] }`; `POST /v1/admin/accounts { phone, name, role:'ADMIN'|'EDITOR'|'SHOP', shopIds?:[] }` (creates the user by phone if needed); `PATCH /v1/admin/accounts/:userId { name?, role?, active?, shopIds? }`. An OWNER can't be demoted by an ADMIN.
- Creating a shop in Manager (`POST /v1/admin/shops`) gains optional `managerAccess: boolean` → also creates a SHOP account for the owner phone with that shop.

## 8. Intro animation (both apps) — mk_ui
`MkIntroGate({required Widget child})` in `packages/mk_ui` (exported from mk_ui.dart): on first build shows a full-screen brand intro over `child` (~2.2 s): "Mukafaah" typed letter by letter with a yellow caret on the dark purple background, the logo mark pops in, Arabic "مكافأة" fades in, then the intro fades/scales away revealing `child`. Tap skips. Honours reduced motion (shows logo 400 ms, no typing). Apps wrap their `MaterialApp.router(builder: (c, child) => MkIntroGate(child: child!))`.
