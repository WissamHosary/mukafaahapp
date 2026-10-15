-- v0.9: Shared and Network points groups, made in Mukafaah Manager.
--   Shared:  every shop in the group earns into the same points, and they can
--            be spent in full at any shop in the group.
--   Network: the same, but each shop can cap how much it takes per visit
--            (a % of the customer's balance and/or a number of points).

ALTER TABLE program_members
  ADD COLUMN redeem_max_percent int NOT NULL DEFAULT 100 CHECK (redeem_max_percent BETWEEN 1 AND 100),
  ADD COLUMN redeem_max_points  int CHECK (redeem_max_points IS NULL OR redeem_max_points > 0),
  ADD COLUMN updated_at         timestamptz NOT NULL DEFAULT now();

ALTER TABLE programs ADD COLUMN description text CHECK (length(description) <= 300);
