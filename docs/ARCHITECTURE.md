# Architecture

Approved proposal (full detail): the "Mukafaah — Architecture Proposal v2" document.

## Shape
- **Two Flutter apps** sharing `mk_core` (API client, secure session, strings) and `mk_ui` (design system).
  - Customer app: onboarding (phone + OTP), wallet, rotating QR, Pre-Points collect, explore, account.
  - Business app: one install, two role-locked shells chosen at first launch:
    - **Owner Mode** (`/owner/*`): dashboard, transactions + reversal, team (cashiers, limits, counter devices), settings (earn rate, redemption value, branches).
    - **Cashier Mode** (`/counter*`): paired device + cashier PIN, one counter screen (scan/type → bill → confirm), redeem with live QR, own shift + void.
- **Backend**: NestJS 12 on Fastify, ESM, modular monolith. Modules: auth (OTP, sessions), customer, owner (onboarding + manage), cashier, ledger.
- **PostgreSQL 18**: one schema file per migration in `backend/sql`, applied on boot.

## Rules enforced in code
1. Balances are never edited: every movement is a double-entry ledger transaction (DB trigger rejects unbalanced or edited rows).
2. The server computes points, discounts and permissions. Apps send facts (phone/QR, bill amount).
3. Points-moving requests need an `Idempotency-Key`; retries never double-credit.
4. A cashier token can only reach `/v1/business/cashier/*`. Owner routes need a user session that owns the business.
5. A cashier sees only balances in programs their business belongs to; names only after a QR scan or a prior visit.

## Program types
`programs.type` is `IN_STORE`, `SHARED` or `NETWORK`; membership in `program_members` decides where points can be earned and redeemed. v0.1 creates the In-Store program automatically; Shared/Network governance screens are Phase 3.
