-- Mukafaah v0.7: fixed member QR, redeem approvals in the customer app,
-- Mukafaah Points (platform program), tiers by total spend, live business
-- alerts, home banner layouts and category colours, Manager accounts with
-- per-shop scope.

-- ---------- 1. Fixed member QR ----------
ALTER TABLE users ADD COLUMN member_code text
  CHECK (member_code IS NULL OR member_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$');
CREATE UNIQUE INDEX users_member_code_idx ON users(member_code);

-- ---------- 3. Mukafaah Points (platform program) ----------
ALTER TABLE programs DROP CONSTRAINT IF EXISTS programs_type_check;
ALTER TABLE programs ADD CONSTRAINT programs_type_check CHECK (type IN ('IN_STORE','SHARED','NETWORK','PLATFORM'));

ALTER TABLE ledger_transactions DROP CONSTRAINT IF EXISTS ledger_transactions_type_check;
ALTER TABLE ledger_transactions ADD CONSTRAINT ledger_transactions_type_check
  CHECK (type IN ('EARN','PREPOINT_EARN','PREPOINT_CLAIM','REDEEM','VOID','REVERSAL','ADJUSTMENT','TRANSFER','GRANT'));

WITH p AS (
  INSERT INTO programs(type, name, earn_points_per_unit, redeem_points_per_unit, allow_transfer)
  VALUES ('PLATFORM', 'Mukafaah Points', 0, 100, false)
  RETURNING id
)
INSERT INTO app_settings(key, value) SELECT 'mukafaah.programId', to_jsonb(id::text) FROM p
ON CONFLICT (key) DO NOTHING;

CREATE TABLE mukafaah_rules (
  code      text PRIMARY KEY CHECK (code ~ '^[A-Z_]{2,30}$'),
  title_en  text NOT NULL CHECK (length(title_en) BETWEEN 1 AND 120),
  title_ar  text NOT NULL CHECK (length(title_ar) BETWEEN 1 AND 120),
  points    int  NOT NULL CHECK (points BETWEEN 0 AND 100000),
  active    boolean NOT NULL DEFAULT true,
  sort      int  NOT NULL DEFAULT 0
);
INSERT INTO mukafaah_rules(code, title_en, title_ar, points, sort) VALUES
  ('SIGNUP', 'Download the app and join', 'نزّل التطبيق وانضم', 100, 10),
  ('REFERRAL', 'Invite a friend who joins', 'ادعُ صاحب ينضم', 200, 20),
  ('FIRST_BILL', 'Your first bill at any shop', 'أول فاتورة بأي محل', 50, 30);

-- Mukafaah Friends: shops that accept Mukafaah Points.
ALTER TABLE businesses
  ADD COLUMN friends_enabled    boolean NOT NULL DEFAULT false,
  ADD COLUMN friends_max_points int NOT NULL DEFAULT 0 CHECK (friends_max_points BETWEEN 0 AND 100000);

-- Mukafaah Points spent at a shop are recorded as a visit too.
ALTER TABLE visits DROP CONSTRAINT IF EXISTS visits_ref_type_check;
ALTER TABLE visits ADD CONSTRAINT visits_ref_type_check CHECK (ref_type IN ('REWARD','OFFER','MUKAFAAH'));

-- ---------- 2. Redeem approvals ----------
CREATE TABLE redeem_requests (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id      uuid NOT NULL REFERENCES users(id),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  branch_id    uuid REFERENCES branches(id),
  staff_id     uuid REFERENCES staff(id),
  device_id    uuid REFERENCES devices(id),
  kind         text NOT NULL CHECK (kind IN ('POINTS','OFFER','REWARD','BOOKING','MUKAFAAH')),
  title        text NOT NULL,
  points       int  NOT NULL CHECK (points > 0),
  value_minor  int  NOT NULL DEFAULT 0 CHECK (value_minor >= 0),
  payload      jsonb NOT NULL DEFAULT '{}',
  status       text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','DECLINED','EXPIRED','FAILED')),
  result       jsonb,
  error        text,
  -- Cashier retries with the same Idempotency-Key get the same request back.
  idem_key     text UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  decided_at   timestamptz,
  expires_at   timestamptz NOT NULL DEFAULT now() + interval '120 seconds'
);
CREATE INDEX redeem_requests_user_idx ON redeem_requests(user_id, status, expires_at);
CREATE INDEX redeem_requests_biz_idx ON redeem_requests(business_id, created_at DESC);

-- ---------- 4. Tiers by total spend ----------
CREATE TABLE tiers (
  code             text PRIMARY KEY CHECK (code ~ '^[A-Z_]{2,20}$'),
  name_en          text NOT NULL CHECK (length(name_en) BETWEEN 1 AND 40),
  name_ar          text NOT NULL CHECK (length(name_ar) BETWEEN 1 AND 40),
  min_spend_minor  int  NOT NULL CHECK (min_spend_minor >= 0),
  bonus_points     int  NOT NULL DEFAULT 0 CHECK (bonus_points BETWEEN 0 AND 100000),
  color            text CHECK (color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$'),
  perks_en         text CHECK (length(perks_en) <= 1000),
  sort             int  NOT NULL DEFAULT 0,
  active           boolean NOT NULL DEFAULT true
);
INSERT INTO tiers(code, name_en, name_ar, min_spend_minor, bonus_points, color, perks_en, sort) VALUES
  ('SILVER', 'Silver', 'فضي', 0, 0, '#9AA0A6', 'Earn points at every shop', 10),
  ('GOLD', 'Gold', 'ذهبي', 2000, 100, '#E9B800', 'Send points to friends. Gold member offers.', 20),
  ('PLATINUM', 'Platinum', 'بلاتيني', 20000, 300, '#5B2BD6', 'Exclusive partner offers. Mukafaah gifts.', 30);

ALTER TABLE users
  ADD COLUMN lifetime_spend_minor bigint NOT NULL DEFAULT 0 CHECK (lifetime_spend_minor >= 0),
  ADD COLUMN tier text NOT NULL DEFAULT 'SILVER';

-- Existing members start from the bills they already have (no bonus for the past).
UPDATE users u SET lifetime_spend_minor = s.total
  FROM (SELECT user_id, SUM(bill_minor) AS total FROM visits
         WHERE type = 'EARN' AND user_id IS NOT NULL AND voided_by_tx_id IS NULL GROUP BY user_id) s
 WHERE s.user_id = u.id;
UPDATE users u SET tier = COALESCE(
  (SELECT t.code FROM tiers t WHERE t.active AND t.min_spend_minor <= u.lifetime_spend_minor ORDER BY t.min_spend_minor DESC LIMIT 1),
  'SILVER');

-- ---------- 5. Business alerts (live popup in the Business app) ----------
CREATE TABLE business_alerts (
  id           bigserial PRIMARY KEY,
  business_id  uuid NOT NULL REFERENCES businesses(id),
  kind         text NOT NULL CHECK (kind IN ('BOOKING','ORDER','REDEEM_APPROVED','REDEEM_DECLINED','RATING','OFFER_USED')),
  title        text NOT NULL,
  body         text,
  ref_id       text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX business_alerts_biz_idx ON business_alerts(business_id, id);

-- ---------- 6. Home: banner layout, categories with colours ----------
INSERT INTO app_settings(key, value) VALUES ('home.bannerLayout', '"UNO"') ON CONFLICT (key) DO NOTHING;
DELETE FROM banners
 WHERE media_id IS NULL AND title_en IN ('In-Store', 'Shared', 'Earn more. Redeem more.');
ALTER TABLE categories ADD COLUMN color text CHECK (color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$');

-- ---------- 7. Manager accounts scoped to shops ----------
ALTER TABLE admins DROP CONSTRAINT IF EXISTS admins_role_check;
ALTER TABLE admins ADD CONSTRAINT admins_role_check CHECK (role IN ('OWNER','ADMIN','EDITOR','SHOP'));
CREATE TABLE admin_shops (
  user_id      uuid NOT NULL REFERENCES admins(user_id),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, business_id)
);
CREATE INDEX admin_shops_biz_idx ON admin_shops(business_id);
