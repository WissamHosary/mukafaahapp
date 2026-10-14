-- v0.8: every home section is controlled from Mukafaah Manager.
--   layout:    how a shop section looks (CAROUSEL, GRID or ROW).
--   pick_mode: AUTO fills the section by itself, PICKED shows only what the admin chose.

ALTER TABLE home_sections DROP CONSTRAINT IF EXISTS home_sections_type_check;
ALTER TABLE home_sections ADD CONSTRAINT home_sections_type_check CHECK (type IN
  ('CATEGORIES','FEATURED_SHOPS','DISCOVER_SHOPS','NEW_OFFERS','CATEGORY_SHOPS','PICKED_SHOPS','REWARDS','RECENT_ACTIVITY'));

ALTER TABLE home_sections
  ADD COLUMN layout     text CHECK (layout IN ('CAROUSEL', 'GRID', 'ROW')),
  ADD COLUMN pick_mode  text NOT NULL DEFAULT 'AUTO' CHECK (pick_mode IN ('AUTO', 'PICKED')),
  ADD COLUMN offer_ids  uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN reward_ids uuid[] NOT NULL DEFAULT '{}';

-- Hand-picked shop sections become "picked" shop rows.
UPDATE home_sections SET pick_mode = 'PICKED', layout = 'ROW' WHERE type = 'PICKED_SHOPS';
UPDATE home_sections SET layout = 'CAROUSEL' WHERE type = 'FEATURED_SHOPS' AND layout IS NULL;

-- The new home: Categories, Featured shops, New offers, More shops to discover,
-- Rewards for you, Recent transactions. Category rows stay available but start off.
UPDATE home_sections SET active = false WHERE type = 'CATEGORY_SHOPS';
INSERT INTO home_sections(type, title_en, title_ar, layout, max_items, sort)
  SELECT 'DISCOVER_SHOPS', 'More shops to discover', 'محلات تانية تكتشفها', 'GRID', 8, 40
   WHERE NOT EXISTS (SELECT 1 FROM home_sections WHERE type = 'DISCOVER_SHOPS');
INSERT INTO home_sections(type, title_en, title_ar, max_items, sort)
  SELECT 'REWARDS', 'Rewards for you', 'مكافآت إلك', 6, 50
   WHERE NOT EXISTS (SELECT 1 FROM home_sections WHERE type = 'REWARDS');
UPDATE home_sections SET sort = 10 WHERE type = 'CATEGORIES';
UPDATE home_sections SET sort = 20 WHERE type = 'FEATURED_SHOPS';
UPDATE home_sections SET sort = 30 WHERE type = 'NEW_OFFERS';
UPDATE home_sections SET sort = 1000 WHERE type = 'RECENT_ACTIVITY';
