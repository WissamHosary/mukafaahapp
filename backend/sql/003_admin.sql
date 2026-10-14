-- Mukafaah v0.3: Mukafaah Manager (admin). Content the customer app shows is
-- managed here: categories, home banners, home sections, featured shops,
-- each shop's points-back %, offer visibility and app-wide settings.

-- ---------- Admin accounts (sign in with the same phone OTP) ----------
ALTER TABLE sessions DROP CONSTRAINT sessions_app_check;
ALTER TABLE sessions ADD CONSTRAINT sessions_app_check CHECK (app IN ('CUSTOMER','BUSINESS','ADMIN'));

CREATE TABLE admins (
  user_id     uuid PRIMARY KEY REFERENCES users(id),
  role        text NOT NULL DEFAULT 'ADMIN' CHECK (role IN ('OWNER','ADMIN','EDITOR')),
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Categories ----------
CREATE TABLE categories (
  key            text PRIMARY KEY CHECK (key ~ '^[A-Z0-9_]{2,40}$'),
  name_en        text NOT NULL CHECK (length(name_en) BETWEEN 1 AND 60),
  name_ar        text NOT NULL CHECK (length(name_ar) BETWEEN 1 AND 60),
  icon_media_id  uuid REFERENCES media(id),
  emoji          text CHECK (length(emoji) <= 16),
  sort           int  NOT NULL DEFAULT 0,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);
INSERT INTO categories(key, name_en, name_ar, emoji, sort) VALUES
  ('RESTAURANTS_CAFES', 'Restaurants & Coffee Shops', 'مطاعم ومقاهي', '☕', 10),
  ('FOOD_DRINKS', 'Food & Drinks', 'أكل ومشروبات', '🍔', 20),
  ('FASHION', 'Fashion & Accessories', 'أزياء وإكسسوارات', '👜', 30),
  ('ELECTRONICS', 'Electronics & Technology', 'إلكترونيات وتكنولوجيا', '🎧', 40),
  ('FITNESS', 'Fitness & Sports', 'رياضة ولياقة', '🏋️', 50),
  ('BEAUTY_WELLNESS', 'Beauty & Wellness', 'جمال وعناية', '💅', 60),
  ('ENTERTAINMENT', 'Entertainment & Leisure', 'ترفيه وتسلية', '🎮', 70),
  ('GIFTS', 'Gifts & Accessories', 'هدايا وإكسسوارات', '🎁', 80),
  ('RETAIL', 'Retail', 'تسوّق', '🛍️', 90),
  ('SERVICES', 'Services', 'خدمات', '🛠️', 100),
  ('OTHER', 'Other', 'غير ذلك', '🏪', 110);

-- ---------- Home banners (carousel) ----------
CREATE TABLE banners (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  title_en      text CHECK (length(title_en) <= 80),
  title_ar      text CHECK (length(title_ar) <= 80),
  subtitle_en   text CHECK (length(subtitle_en) <= 160),
  subtitle_ar   text CHECK (length(subtitle_ar) <= 160),
  media_id      uuid REFERENCES media(id),
  style         text NOT NULL DEFAULT 'PURPLE' CHECK (style IN ('PURPLE','YELLOW','IMAGE')),
  action_type   text NOT NULL DEFAULT 'NONE' CHECK (action_type IN ('NONE','SHOP','CATEGORY','OFFERS','URL')),
  action_value  text CHECK (length(action_value) <= 300),
  starts_at     timestamptz,
  ends_at       timestamptz,
  sort          int NOT NULL DEFAULT 0,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
INSERT INTO banners(title_en, title_ar, subtitle_en, subtitle_ar, style, action_type, sort) VALUES
  ('In-Store', 'داخل المتجر', 'Earn and redeem at the same store', 'اربح واصرف بنفس المحل', 'PURPLE', 'NONE', 10),
  ('Shared', 'مشترك', 'More choice. More value. More happy customers.', 'خيارات أكثر، قيمة أكثر، زباين أسعد', 'YELLOW', 'NONE', 20),
  ('Earn more. Redeem more.', 'اربح أكثر، اصرف أكثر', 'Gifts and discounts from your favourite places', 'هدايا وخصومات من محلاتك المفضلة', 'PURPLE', 'OFFERS', 30);

-- ---------- Home sections (order and content of the home screen) ----------
CREATE TABLE home_sections (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  type          text NOT NULL CHECK (type IN ('CATEGORIES','FEATURED_SHOPS','NEW_OFFERS','CATEGORY_SHOPS','PICKED_SHOPS','REWARDS','RECENT_ACTIVITY')),
  title_en      text CHECK (length(title_en) <= 60),
  title_ar      text CHECK (length(title_ar) <= 60),
  category_key  text REFERENCES categories(key),
  shop_ids      uuid[] NOT NULL DEFAULT '{}',
  max_items     int NOT NULL DEFAULT 12 CHECK (max_items BETWEEN 1 AND 50),
  sort          int NOT NULL DEFAULT 0,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);
INSERT INTO home_sections(type, title_en, title_ar, sort) VALUES
  ('CATEGORIES', 'Categories', 'الفئات', 10),
  ('FEATURED_SHOPS', 'Featured shops', 'محلات مميزة', 20),
  ('NEW_OFFERS', 'New offers', 'عروض جديدة', 30);
INSERT INTO home_sections(type, title_en, title_ar, category_key, sort)
  SELECT 'CATEGORY_SHOPS', name_en, name_ar, key, 100 + sort FROM categories WHERE key <> 'OTHER';
INSERT INTO home_sections(type, title_en, title_ar, sort) VALUES
  ('RECENT_ACTIVITY', 'Recent transactions', 'آخر العمليات', 1000);

-- ---------- App-wide settings ----------
CREATE TABLE app_settings (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES users(id)
);
INSERT INTO app_settings(key, value) VALUES
  ('tiers', '{"GOLD": 2500, "PLATINUM": 10000}'),
  ('transfer', '{"minPoints": 10, "dailyMaxPoints": 20000, "dailyMaxCount": 10, "minTier": "GOLD"}'),
  ('referral', '{"windowDays": 14}'),
  ('support', '{"whatsapp": null, "instagram": "mukafaah.app"}'),
  ('defaults', '{"earnPercent": 10}');

-- ---------- Admin controls on shops and offers ----------
ALTER TABLE offers ADD COLUMN hidden_by_admin boolean NOT NULL DEFAULT false;
ALTER TABLE businesses ADD COLUMN featured_sort int NOT NULL DEFAULT 0;
ALTER TABLE businesses ADD COLUMN admin_note text;

-- Categories on shops now point at the categories table.
INSERT INTO categories(key, name_en, name_ar, sort)
  SELECT DISTINCT b.category, initcap(replace(lower(b.category), '_', ' ')), b.category, 999
    FROM businesses b WHERE NOT EXISTS (SELECT 1 FROM categories c WHERE c.key = b.category);
ALTER TABLE businesses ADD CONSTRAINT businesses_category_fk FOREIGN KEY (category) REFERENCES categories(key) ON UPDATE CASCADE;
