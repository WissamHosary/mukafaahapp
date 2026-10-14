-- v0.9: customers sign back in with their phone and a password (WhatsApp code
-- the first time and to reset it); shop pages get social links, banners and
-- written reviews.

-- ---------- Customer passwords ----------
ALTER TABLE users
  ADD COLUMN password_hash         text,
  ADD COLUMN password_set_at       timestamptz,
  ADD COLUMN password_failures     int NOT NULL DEFAULT 0,
  ADD COLUMN password_locked_until timestamptz;

-- Phone checks and password sign-ins, for rate limits.
CREATE TABLE login_attempts (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  kind        text NOT NULL CHECK (kind IN ('CHECK', 'PASSWORD')),
  ip          text,
  phone_hash  bytea,
  ok          boolean NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_ip_idx ON login_attempts(ip, created_at DESC);
CREATE INDEX login_attempts_phone_idx ON login_attempts(phone_hash, created_at DESC);

-- ---------- Shop page ----------
ALTER TABLE businesses
  ADD COLUMN facebook  text CHECK (length(facebook) <= 120),
  ADD COLUMN tiktok    text CHECK (length(tiktok) <= 60),
  ADD COLUMN website   text CHECK (length(website) <= 200),
  ADD COLUMN phone     text CHECK (length(phone) <= 20),
  ADD COLUMN hours     text CHECK (length(hours) <= 120);

-- Pictures that slide at the top of the shop page.
CREATE TABLE business_banners (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  media_id     uuid NOT NULL REFERENCES media(id),
  caption      text CHECK (length(caption) <= 80),
  sort         int  NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX business_banners_idx ON business_banners(business_id, sort, created_at);

-- Mukafaah can hide a review that breaks the rules.
ALTER TABLE business_ratings ADD COLUMN hidden boolean NOT NULL DEFAULT false;
CREATE INDEX business_ratings_recent_idx ON business_ratings(business_id, updated_at DESC);
