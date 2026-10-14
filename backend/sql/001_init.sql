-- Mukafaah schema v0.1 (PostgreSQL 18). Points only: no money tables.
-- Ledger rows are append-only (enforced by triggers below).

CREATE TABLE IF NOT EXISTS schema_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

-- ---------- Identity ----------
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  phone_hash    bytea NOT NULL UNIQUE,          -- HMAC-SHA256 blind index of E.164 phone
  phone_enc     bytea NOT NULL,                 -- AES-256-GCM encrypted E.164 phone
  phone_last4   text  NOT NULL,
  name          text,
  locale        text  NOT NULL DEFAULT 'ar',
  status        text  NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','FROZEN','DELETED')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id       uuid NOT NULL REFERENCES users(id),
  family_id     uuid NOT NULL,
  refresh_hash  bytea NOT NULL UNIQUE,
  device_label  text,
  app           text NOT NULL CHECK (app IN ('CUSTOMER','BUSINESS')),
  expires_at    timestamptz NOT NULL,
  rotated_at    timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_family_idx ON sessions(family_id);

CREATE TABLE otp_challenges (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  phone_hash    bytea NOT NULL,
  phone_enc     bytea NOT NULL,
  phone_last4   text  NOT NULL,
  code_hash     bytea NOT NULL,
  ip            text,
  device_id     text,
  attempts      int  NOT NULL DEFAULT 0,
  expires_at    timestamptz NOT NULL,
  consumed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX otp_phone_time_idx ON otp_challenges(phone_hash, created_at DESC);
CREATE INDEX otp_ip_time_idx ON otp_challenges(ip, created_at DESC);

-- ---------- Businesses ----------
CREATE TABLE businesses (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  owner_user_id      uuid NOT NULL REFERENCES users(id),
  name               text NOT NULL,
  category           text NOT NULL DEFAULT 'OTHER',
  currency           text NOT NULL DEFAULT 'USD',
  time_zone          text NOT NULL DEFAULT 'Asia/Beirut',
  whatsapp           text,
  earning_program_id uuid,
  status             text NOT NULL DEFAULT 'ACTIVE',
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX businesses_owner_idx ON businesses(owner_user_id);

CREATE TABLE branches (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  name         text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------- Programs (three separate types) ----------
CREATE TABLE programs (
  id                       uuid PRIMARY KEY DEFAULT uuidv7(),
  type                     text NOT NULL CHECK (type IN ('IN_STORE','SHARED','NETWORK')),
  name                     text NOT NULL,
  owner_business_id        uuid REFERENCES businesses(id),   -- set for IN_STORE
  earn_points_per_unit     int  NOT NULL DEFAULT 10 CHECK (earn_points_per_unit BETWEEN 0 AND 10000),
  redeem_points_per_unit   int  NOT NULL DEFAULT 100 CHECK (redeem_points_per_unit BETWEEN 1 AND 100000),
  min_bill_minor           bigint NOT NULL DEFAULT 0,
  status                   text NOT NULL DEFAULT 'ACTIVE',
  created_at               timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE businesses ADD CONSTRAINT businesses_earning_program_fk
  FOREIGN KEY (earning_program_id) REFERENCES programs(id);

CREATE TABLE program_members (
  program_id   uuid NOT NULL REFERENCES programs(id),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  can_earn     boolean NOT NULL DEFAULT true,
  can_redeem   boolean NOT NULL DEFAULT true,
  active       boolean NOT NULL DEFAULT true,
  joined_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (program_id, business_id)
);

-- ---------- Staff and devices ----------
CREATE TABLE staff (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id        uuid NOT NULL REFERENCES businesses(id),
  branch_id          uuid NOT NULL REFERENCES branches(id),
  name               text NOT NULL,
  role               text NOT NULL DEFAULT 'CASHIER' CHECK (role IN ('CASHIER')),
  pin_hash           text NOT NULL,
  pin_failures       int  NOT NULL DEFAULT 0,
  locked_until       timestamptz,
  active             boolean NOT NULL DEFAULT true,
  max_bill_minor     bigint NOT NULL DEFAULT 100000,
  max_points_tx      bigint NOT NULL DEFAULT 20000,
  max_points_day     bigint NOT NULL DEFAULT 200000,
  max_prepoints_day_per_phone bigint NOT NULL DEFAULT 5000,
  can_redeem         boolean NOT NULL DEFAULT true,
  void_window_min    int  NOT NULL DEFAULT 10,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  branch_id    uuid NOT NULL REFERENCES branches(id),
  label        text NOT NULL,
  secret_hash  bytea NOT NULL,
  status       text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED')),
  last_seen_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE pairing_codes (
  code_hash    bytea PRIMARY KEY,
  business_id  uuid NOT NULL REFERENCES businesses(id),
  branch_id    uuid NOT NULL REFERENCES branches(id),
  expires_at   timestamptz NOT NULL,
  used_at      timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------- Pre-Points holders ----------
CREATE TABLE pending_holders (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  phone_hash  bytea NOT NULL UNIQUE,
  phone_enc   bytea NOT NULL,
  phone_last4 text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Ledger (double entry, points only) ----------
CREATE TABLE ledger_accounts (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  program_id  uuid NOT NULL REFERENCES programs(id),
  owner_type  text NOT NULL CHECK (owner_type IN ('CUSTOMER','PENDING','BUSINESS_ISSUED','BUSINESS_REDEEMED')),
  owner_id    uuid NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (program_id, owner_type, owner_id)
);

CREATE TABLE account_balances (
  account_id      uuid PRIMARY KEY REFERENCES ledger_accounts(id),
  balance         bigint NOT NULL DEFAULT 0,
  allow_negative  boolean NOT NULL DEFAULT false,
  version         bigint NOT NULL DEFAULT 0,
  CONSTRAINT balance_non_negative CHECK (allow_negative OR balance >= 0)
);

CREATE TABLE ledger_transactions (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  type               text NOT NULL CHECK (type IN ('EARN','PREPOINT_EARN','PREPOINT_CLAIM','REDEEM','VOID','REVERSAL','ADJUSTMENT')),
  program_id         uuid NOT NULL REFERENCES programs(id),
  idempotency_key    text NOT NULL UNIQUE,
  business_id        uuid REFERENCES businesses(id),
  branch_id          uuid REFERENCES branches(id),
  staff_id           uuid REFERENCES staff(id),
  device_id          uuid REFERENCES devices(id),
  user_id            uuid REFERENCES users(id),
  pending_holder_id  uuid REFERENCES pending_holders(id),
  reverses_tx_id     uuid REFERENCES ledger_transactions(id),
  reason             text,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ltx_user_idx ON ledger_transactions(user_id, created_at DESC);
CREATE UNIQUE INDEX ltx_one_reversal_idx ON ledger_transactions(reverses_tx_id) WHERE reverses_tx_id IS NOT NULL;

CREATE TABLE ledger_entries (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  transaction_id  uuid NOT NULL REFERENCES ledger_transactions(id),
  account_id      uuid NOT NULL REFERENCES ledger_accounts(id),
  amount          bigint NOT NULL CHECK (amount <> 0),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lentries_account_idx ON ledger_entries(account_id, id DESC);
CREATE INDEX lentries_tx_idx ON ledger_entries(transaction_id);

-- Every transaction must balance to zero (checked at commit).
CREATE FUNCTION ledger_check_balanced() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s bigint;
BEGIN
  SELECT COALESCE(SUM(amount),0) INTO s FROM ledger_entries WHERE transaction_id = NEW.transaction_id;
  IF s <> 0 THEN
    RAISE EXCEPTION 'ledger transaction % does not balance (sum=%)', NEW.transaction_id, s;
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER ledger_entries_balanced
  AFTER INSERT ON ledger_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION ledger_check_balanced();

-- Ledger history can never be changed or deleted.
CREATE FUNCTION ledger_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'ledger rows are append-only';
END $$;
CREATE TRIGGER ledger_entries_no_update BEFORE UPDATE OR DELETE ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION ledger_immutable();
CREATE TRIGGER ledger_tx_no_update BEFORE UPDATE OR DELETE ON ledger_transactions
  FOR EACH ROW EXECUTE FUNCTION ledger_immutable();

-- ---------- Visits (every bill entered; source of owner analytics) ----------
CREATE TABLE visits (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id        uuid NOT NULL REFERENCES businesses(id),
  branch_id          uuid NOT NULL REFERENCES branches(id),
  staff_id           uuid REFERENCES staff(id),
  device_id          uuid REFERENCES devices(id),
  user_id            uuid REFERENCES users(id),
  pending_holder_id  uuid REFERENCES pending_holders(id),
  program_id         uuid NOT NULL REFERENCES programs(id),
  type               text NOT NULL CHECK (type IN ('EARN','PREPOINT_EARN','REDEEM')),
  bill_minor         bigint NOT NULL DEFAULT 0,
  currency           text NOT NULL,
  points             bigint NOT NULL,
  ledger_tx_id       uuid NOT NULL UNIQUE REFERENCES ledger_transactions(id),
  voided_by_tx_id    uuid REFERENCES ledger_transactions(id),
  local_date         date NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX visits_biz_date_idx ON visits(business_id, local_date);
CREATE INDEX visits_staff_date_idx ON visits(staff_id, local_date);

-- Customer QR tokens may be used once for a redemption.
CREATE TABLE qr_token_uses (
  jti        text PRIMARY KEY,
  used_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------- Audit ----------
CREATE TABLE audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_type  text NOT NULL,
  actor_id    uuid,
  business_id uuid,
  action      text NOT NULL,
  entity      text,
  entity_id   text,
  data        jsonb,
  ip          text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_biz_idx ON audit_log(business_id, created_at DESC);
