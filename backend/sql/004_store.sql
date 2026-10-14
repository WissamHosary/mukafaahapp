-- Mukafaah v0.4: optional online store per shop (catalog only, no online payment).
-- A shop turns its store on; customers browse categories and products with
-- options (Size, Colour...) and variants, fill a cart and send the order on WhatsApp.

ALTER TABLE businesses ADD COLUMN store_enabled boolean NOT NULL DEFAULT false;
-- Shops that already listed products keep showing them.
UPDATE businesses b SET store_enabled = true WHERE EXISTS (SELECT 1 FROM products p WHERE p.business_id = b.id AND NOT p.archived);

-- ---------- Store categories (per shop) ----------
CREATE TABLE store_categories (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id  uuid NOT NULL REFERENCES businesses(id),
  name         text NOT NULL CHECK (length(name) BETWEEN 1 AND 40),
  sort         int  NOT NULL DEFAULT 0,
  active       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX store_categories_biz_idx ON store_categories(business_id, active, sort);

-- ---------- Products: gallery, sale price, stock, options ----------
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_description_check;
ALTER TABLE products ADD CONSTRAINT products_description_check CHECK (length(description) <= 2000);
ALTER TABLE products
  ADD COLUMN category_id       uuid REFERENCES store_categories(id),
  ADD COLUMN image_ids         uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN compare_at_minor  bigint CHECK (compare_at_minor IS NULL OR compare_at_minor >= 0),
  ADD COLUMN track_stock       boolean NOT NULL DEFAULT false,
  ADD COLUMN stock             int CHECK (stock IS NULL OR stock >= 0),
  -- [{"name":"Size","values":["S","M","L"]}, ...] at most 3 options.
  ADD COLUMN options           jsonb NOT NULL DEFAULT '[]',
  ADD COLUMN featured          boolean NOT NULL DEFAULT false,
  ADD COLUMN updated_at        timestamptz NOT NULL DEFAULT now();
UPDATE products SET image_ids = ARRAY[media_id] WHERE media_id IS NOT NULL;

-- One row per combination of option values, with its own price and stock.
CREATE TABLE product_variants (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  product_id        uuid NOT NULL REFERENCES products(id),
  option_values     text[] NOT NULL,
  price_minor       bigint NOT NULL CHECK (price_minor >= 0),
  compare_at_minor  bigint CHECK (compare_at_minor IS NULL OR compare_at_minor >= 0),
  stock             int CHECK (stock IS NULL OR stock >= 0),
  sku               text CHECK (length(sku) <= 60),
  media_id          uuid REFERENCES media(id),
  active            boolean NOT NULL DEFAULT true,
  sort              int NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_variants_product_idx ON product_variants(product_id, active, sort);

-- ---------- Orders: status and how the customer gets them ----------
ALTER TABLE whatsapp_orders
  ADD COLUMN code         text,
  ADD COLUMN status       text NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW','CONFIRMED','READY','COMPLETED','CANCELLED')),
  ADD COLUMN fulfilment   text NOT NULL DEFAULT 'PICKUP' CHECK (fulfilment IN ('PICKUP','DELIVERY')),
  ADD COLUMN address      text CHECK (length(address) <= 300),
  ADD COLUMN stock_taken  boolean NOT NULL DEFAULT false,
  ADD COLUMN updated_at   timestamptz NOT NULL DEFAULT now();
