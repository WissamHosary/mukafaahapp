-- v0.8: Mukafaah creates usernames and passwords for each shop's owner and
-- workers. They sign in to Mukafaah Business with them.

-- Workers created with a password don't need a counter PIN.
ALTER TABLE staff ALTER COLUMN pin_hash DROP NOT NULL;

CREATE TABLE business_logins (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  business_id    uuid NOT NULL REFERENCES businesses(id),
  kind           text NOT NULL CHECK (kind IN ('OWNER', 'STAFF')),
  user_id        uuid REFERENCES users(id),      -- OWNER: the shop owner
  staff_id       uuid REFERENCES staff(id),      -- STAFF: the worker
  username       text NOT NULL CHECK (username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
  password_hash  text NOT NULL,
  failures       int  NOT NULL DEFAULT 0,
  locked_until   timestamptz,
  active         boolean NOT NULL DEFAULT true,
  last_login_at  timestamptz,
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'OWNER' AND user_id IS NOT NULL AND staff_id IS NULL) OR (kind = 'STAFF' AND staff_id IS NOT NULL))
);
CREATE UNIQUE INDEX business_logins_username_idx ON business_logins(lower(username));
CREATE UNIQUE INDEX business_logins_owner_idx ON business_logins(business_id) WHERE kind = 'OWNER';
CREATE UNIQUE INDEX business_logins_staff_idx ON business_logins(staff_id) WHERE staff_id IS NOT NULL;

-- A worker's own phone (signed in with their password) is a counter device tied to them.
ALTER TABLE devices ADD COLUMN staff_id uuid REFERENCES staff(id);
