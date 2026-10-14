# Database

PostgreSQL 18, migrations in `backend/sql/*.sql` applied in order on API boot (tracked in `schema_migrations`).

- Identity: `users` (encrypted phone + HMAC index), `sessions` (hashed refresh tokens, families), `otp_challenges`.
- Businesses: `businesses`, `branches`, `programs` (type IN_STORE | SHARED | NETWORK), `program_members`.
- Staff & devices: `staff` (Argon2 PIN, limits), `devices` (hashed secret), `pairing_codes`.
- Pre-Points: `pending_holders` (one per phone).
- Ledger: `ledger_accounts` (CUSTOMER, PENDING, BUSINESS_ISSUED, BUSINESS_REDEEMED per program), `account_balances` (non-negative check), `ledger_transactions` (unique idempotency key), `ledger_entries`. Triggers: entries must sum to zero per transaction; ledger rows can't be updated or deleted.
- Analytics source: `visits` (every bill: business, branch, cashier, device, customer or pending phone, bill amount, points, program, type, local date).
- `qr_token_uses`, `audit_log`.

Money is stored as integer minor units (`bill_minor`); points are integers. There are no money balances anywhere.
