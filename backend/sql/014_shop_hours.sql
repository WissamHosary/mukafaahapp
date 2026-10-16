-- v0.11: weekly opening hours (so the app can say Open now / Closed), a
-- "temporarily closed" switch, and pictures for Online store categories.
-- opening_hours: 7 entries, Monday first. Each is null (closed all day) or
-- {"open":"10:00","close":"18:00"}; close before open runs past midnight,
-- open equal to close means open 24 hours.
ALTER TABLE businesses
  ADD COLUMN opening_hours jsonb CHECK (opening_hours IS NULL OR (jsonb_typeof(opening_hours) = 'array' AND jsonb_array_length(opening_hours) = 7)),
  ADD COLUMN temporarily_closed boolean NOT NULL DEFAULT false;

ALTER TABLE store_categories ADD COLUMN media_id uuid REFERENCES media(id);
