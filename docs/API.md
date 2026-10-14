# API (v1)

Errors: `application/problem+json` with a stable `code` (e.g. `OTP_INVALID`, `INSUFFICIENT_BALANCE`, `STAFF_LIMIT_DAY`). Points-moving POSTs require `Idempotency-Key`.

**Auth** — `POST /v1/auth/otp/request {phone, app, deviceId?, locale}` · `POST /v1/auth/otp/verify {challengeId, code, app}` · `POST /v1/auth/refresh {refreshToken}` · `POST /v1/auth/logout` · `POST /v1/auth/logout-all`

**Customer** (user token) — `GET/PATCH /v1/customer/me` · `GET /v1/customer/wallet` · `GET /v1/customer/wallet/transactions` · `GET /v1/customer/prepoints` · `POST /v1/customer/prepoints/collect`* · `POST /v1/customer/qr/token` · `GET /v1/customer/businesses`

**Owner** (user token that owns a business) — `POST /v1/business/onboarding` · `GET /v1/business/manage/me` · `PUT /v1/business/manage/program` · `POST /v1/business/manage/branches` · `GET/POST /v1/business/manage/staff` · `PATCH /v1/business/manage/staff/:id` · `POST /v1/business/manage/pairing-codes` · `GET /v1/business/manage/devices` · `POST /v1/business/manage/devices/:id/revoke` · `GET /v1/business/manage/dashboard?from&to&branchId&staffId&programId` · `GET /v1/business/manage/transactions` · `POST /v1/business/manage/transactions/:id/reverse {reason}`

**Cashier** — `POST /v1/business/cashier/pair {code,label}` · `POST /v1/business/cashier/device/staff` · `POST /v1/business/cashier/login {deviceId,deviceSecret,staffId,pin}` · then staff token: `POST lookup {phone|qr}` · `POST earn/preview {billMinor}` · `POST earn {phone|qr,billMinor}`* · `POST redeem {qr,programId,points}`* · `GET shift` · `POST transactions/:id/void`

\* requires `Idempotency-Key`. `GET /health` for liveness.
