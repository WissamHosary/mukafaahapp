# Security (v0.1 status)

| Area | Implemented now | Next |
| --- | --- | --- |
| OTP | 6 digits, 5-min expiry, max 5 attempts, growing resend cooldown, per-phone hour/day caps, per-IP and per-device caps, country allowlist (LB) | Real SMS provider behind `OtpProvider`, SMS-pumping detection |
| Sessions | ES256 JWT (15 min) + opaque refresh token stored hashed, rotated on every use, reuse revokes the family; logout / logout everywhere | Device list in app |
| Staff | Argon2id PINs, 5 wrong PINs → 15-min lock, device pairing with one-time 8-char code (10 min), device revocation, per-cashier limits (bill, points per bill, per day, Pre-Points per phone per day, redeem on/off, void window) | Manager role, step-up approval |
| Ledger | Double entry, append-only (triggers), balance ≥ 0 check, row locks in fixed order, idempotency keys | Nightly reconciliation job, expiry lots |
| QR | Server-signed token valid 90 s; redemption consumes it once | — |
| Privacy | Phones stored AES-256-GCM encrypted + HMAC blind index; cashier lookup scoped to the business's programs | Row-Level Security policies |
| Audit | `audit_log` for logins, onboarding, staff/program changes, devices, earn/redeem/void/reverse | Admin viewer |
| Transport | Helmet headers; dev builds allow http on the LAN only | HTTPS everywhere, WAF, App Attest / Play Integrity |
| Secrets | Dev keys generated into a Docker volume; nothing secret in the apps | AWS Secrets Manager + KMS |

`OTP_DEV_ECHO=true` (returns the code in the API response) is for local testing only and the API refuses to start with it in production.
