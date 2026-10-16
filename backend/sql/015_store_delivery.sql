-- v0.12: how a shop's online store hands orders over. Set from Mukafaah
-- Manager; until then every store offers delivery and pickup with no fee.
ALTER TABLE businesses
  ADD COLUMN store_pickup boolean NOT NULL DEFAULT true,
  ADD COLUMN store_delivery boolean NOT NULL DEFAULT true,
  ADD COLUMN delivery_fee_minor int NOT NULL DEFAULT 0 CHECK (delivery_fee_minor BETWEEN 0 AND 100000),
  ADD COLUMN free_delivery_over_minor int CHECK (free_delivery_over_minor IS NULL OR free_delivery_over_minor BETWEEN 0 AND 10000000),
  ADD COLUMN min_order_minor int NOT NULL DEFAULT 0 CHECK (min_order_minor BETWEEN 0 AND 10000000),
  -- e.g. "Beirut only, 30 to 45 minutes"
  ADD COLUMN delivery_note text CHECK (length(delivery_note) <= 120);

ALTER TABLE whatsapp_orders ADD COLUMN delivery_fee_minor int NOT NULL DEFAULT 0;
