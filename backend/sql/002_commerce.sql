-- Mukafaah v0.2: shop directory, offers with bookings, rewards, products and
-- WhatsApp orders, ratings, tiers inputs, points transfer, referrals and
-- in-app notifications. Points only: still no money tables.

-- ---------- Media (images; stored in the database in development) ----------
CREATE TABLE media (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  owner_business_id  uuid REFERENCES businesses(id),
  content_type       text NOT NULL CHECK (content_type IN ('image/jpeg','image/png','image/webp')),
  bytes              bytea NOT NULL,
  size               int  NOT NULL CHECK (size > 0 AND size <= 3145728),
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- ---------- Shop profile ----------
ALTER TABLE businesses
  ADD COLUMN description     text,
  ADD COLUMN logo_media_id   uuid REFERENCES media(id),
  ADD COLUMN cover_media_id  uuid REFERENCES media(id),
  ADD COLUMN address         text,
  ADD COLUMN city            text,
  ADD COLUMN lat             double precision CHECK (lat BETWEEN -90 AND 90),
  ADD COLUMN lng             double precision CHECK (lng BETWEEN -180 AND 180),
  ADD COLUMN instagram       text,
  ADD COLUMN featured        boolean NOT NULL DEFAULT false,
  ADD COLUMN listed          boolean NOT NULL DEFAULT true;

-- New category set (matches the customer app sections).
UPDATE businesses SET category = CASE category
  WHEN 'RESTAURANT' THEN 'RESTAURANTS_CAFES'
  WHEN 'CAFE'       THEN 'RESTAURANTS_CAFES'
  WHEN 'GROCERY'    THEN 'FOOD_DRINKS'
  WHEN 'BEAUTY'     THEN 'BEAUTY_WELLNESS'
  WHEN 'PHARMACY'   THEN 'BEAUTY_WELLNESS'
  WHEN 'FASHION'    THEN 'FASHION'
  WHEN 'RETAIL'     THEN 'RETAIL'
  WHEN 'SERVICES'   THEN 'SERVICES'
  ELSE 'OTHER' END;

-- Owners can switch transfers off for their own points.
ALTER TABLE programs ADD COLUMN allow_transfer boolean NOT NULL DEFAULT true;

-- ---------- Customers: referral codes ----------
ALTER TABLE users
  ADD COLUMN referral_code text,
  ADD COLUMN referred_by   uuid REFERENCES users(id),
  ADD COLUMN referred_at   timestamptz;
UPDATE users SET referral_code = upper(substr(md5(id::text || random()::text), 1, 7)) WHERE referral_code IS NULL;
ALTER TABLE users
  ALTER COLUMN referral_code SET DEFAULT upper(substr(md5(random()::text || clock_timestamp()::text), 1, 7)),
  ALTER COLUMN referral_code SET NOT NULL;
CREATE UNIQUE INDEX users_referral_code_idx ON users(referral_code);
CREATE INDEX users_referred_by_idx ON users(referred_by);

-- ---------- Ratings ----------
CREATE TABLE business_ratings (
  business_id  uuid NOT NULL REFERENCES businesses(id),
  user_id      uuid NOT NULL REFERENCES users(id),
  stars        smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment      text CHECK (length(comment) <= 500),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, user_id)
);

-- ---------- Offers and bookings ----------
CREATE TABLE offers (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id       uuid NOT NULL REFERENCES businesses(id),
  title             text NOT NULL CHECK (length(title) BETWEEN 2 AND 90),
  description       text CHECK (length(description) <= 600),
  terms             text CHECK (length(terms) <= 600),
  media_id          uuid REFERENCES media(id),
  kind              text NOT NULL DEFAULT 'DEAL' CHECK (kind IN ('DEAL','DISCOUNT','FREE_ITEM','SERVICE')),
  discount_percent  int CHECK (discount_percent BETWEEN 1 AND 100),
  points_cost       bigint NOT NULL DEFAULT 0 CHECK (points_cost >= 0),
  saving_minor      bigint NOT NULL DEFAULT 0 CHECK (saving_minor >= 0),
  requires_booking  boolean NOT NULL DEFAULT true,
  max_per_customer  int NOT NULL DEFAULT 1 CHECK (max_per_customer BETWEEN 1 AND 100),
  total_limit       int CHECK (total_limit > 0),
  valid_from        date NOT NULL DEFAULT current_date,
  valid_to          date,
  status            text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','PAUSED','ARCHIVED')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
CREATE INDEX offers_biz_idx ON offers(business_id, status);
CREATE INDEX offers_live_idx ON offers(status, valid_to);

CREATE TABLE offer_bookings (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  offer_id           uuid NOT NULL REFERENCES offers(id),
  business_id        uuid NOT NULL REFERENCES businesses(id),
  user_id            uuid NOT NULL REFERENCES users(id),
  status             text NOT NULL DEFAULT 'REQUESTED'
                       CHECK (status IN ('REQUESTED','ACCEPTED','DECLINED','CANCELLED','REDEEMED','EXPIRED')),
  requested_for      timestamptz,
  party_size         int CHECK (party_size BETWEEN 1 AND 100),
  note               text CHECK (length(note) <= 300),
  code               text NOT NULL,
  decided_at         timestamptz,
  decline_reason     text CHECK (length(decline_reason) <= 200),
  redeemed_at        timestamptz,
  redeemed_staff_id  uuid REFERENCES staff(id),
  redeem_tx_id       uuid REFERENCES ledger_transactions(id),
  saving_minor       bigint NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX bookings_biz_status_idx ON offer_bookings(business_id, status, created_at DESC);
CREATE INDEX bookings_user_idx ON offer_bookings(user_id, created_at DESC);
CREATE INDEX bookings_offer_user_idx ON offer_bookings(offer_id, user_id);
CREATE UNIQUE INDEX bookings_code_idx ON offer_bookings(business_id, code);

-- ---------- Rewards catalog (spend points on a gift or discount) ----------
CREATE TABLE rewards (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  title        text NOT NULL CHECK (length(title) BETWEEN 2 AND 90),
  description  text CHECK (length(description) <= 600),
  media_id     uuid REFERENCES media(id),
  points_cost  bigint NOT NULL CHECK (points_cost > 0),
  value_minor  bigint NOT NULL DEFAULT 0 CHECK (value_minor >= 0),
  stock        int CHECK (stock >= 0),
  status       text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','PAUSED','ARCHIVED')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rewards_biz_idx ON rewards(business_id, status);

CREATE TABLE reward_redemptions (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  reward_id     uuid NOT NULL REFERENCES rewards(id),
  business_id   uuid NOT NULL REFERENCES businesses(id),
  user_id       uuid NOT NULL REFERENCES users(id),
  staff_id      uuid REFERENCES staff(id),
  ledger_tx_id  uuid NOT NULL UNIQUE REFERENCES ledger_transactions(id),
  points        bigint NOT NULL,
  value_minor   bigint NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reward_red_user_idx ON reward_redemptions(user_id, created_at DESC);

-- ---------- Products and WhatsApp orders (no online payment) ----------
CREATE TABLE products (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  name         text NOT NULL CHECK (length(name) BETWEEN 1 AND 90),
  description  text CHECK (length(description) <= 400),
  price_minor  bigint NOT NULL CHECK (price_minor >= 0),
  media_id     uuid REFERENCES media(id),
  available    boolean NOT NULL DEFAULT true,
  sort         int NOT NULL DEFAULT 0,
  archived     boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX products_biz_idx ON products(business_id, archived, sort);

CREATE TABLE whatsapp_orders (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  user_id      uuid NOT NULL REFERENCES users(id),
  items        jsonb NOT NULL,
  total_minor  bigint NOT NULL,
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wa_orders_biz_idx ON whatsapp_orders(business_id, created_at DESC);

-- ---------- Points transfer between customers ----------
ALTER TABLE ledger_transactions DROP CONSTRAINT ledger_transactions_type_check;
ALTER TABLE ledger_transactions ADD CONSTRAINT ledger_transactions_type_check
  CHECK (type IN ('EARN','PREPOINT_EARN','PREPOINT_CLAIM','REDEEM','VOID','REVERSAL','ADJUSTMENT','TRANSFER'));

CREATE TABLE point_transfers (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  program_id    uuid NOT NULL REFERENCES programs(id),
  from_user_id  uuid NOT NULL REFERENCES users(id),
  to_user_id    uuid NOT NULL REFERENCES users(id),
  points        bigint NOT NULL CHECK (points > 0),
  note          text CHECK (length(note) <= 120),
  ledger_tx_id  uuid NOT NULL UNIQUE REFERENCES ledger_transactions(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (from_user_id <> to_user_id)
);
CREATE INDEX transfers_from_idx ON point_transfers(from_user_id, created_at DESC);
CREATE INDEX transfers_to_idx ON point_transfers(to_user_id, created_at DESC);

-- Redemptions made for a reward or an offer point to what they paid for.
ALTER TABLE visits
  ADD COLUMN ref_type text CHECK (ref_type IN ('REWARD','OFFER')),
  ADD COLUMN ref_id   uuid;

-- ---------- In-app notifications ----------
CREATE TABLE notifications (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  user_id     uuid NOT NULL REFERENCES users(id),
  kind        text NOT NULL,
  title       text NOT NULL,
  body        text,
  data        jsonb,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications(user_id, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications(user_id) WHERE read_at IS NULL;
