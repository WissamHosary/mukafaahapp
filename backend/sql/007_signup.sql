-- v0.8: sign up with Google or a phone number, profile details.

-- Google members may have no phone number.
ALTER TABLE users
  ALTER COLUMN phone_hash DROP NOT NULL,
  ALTER COLUMN phone_enc DROP NOT NULL,
  ALTER COLUMN phone_last4 DROP NOT NULL;

ALTER TABLE users
  ADD COLUMN email text,
  ADD COLUMN google_sub text UNIQUE,
  ADD COLUMN gender text CHECK (gender IN ('MALE', 'FEMALE')),
  -- Age is asked at sign-up and stored as a birth year so it stays correct.
  ADD COLUMN birth_year int CHECK (birth_year BETWEEN 1900 AND 2100),
  ADD COLUMN profile_completed_at timestamptz;

ALTER TABLE users ADD CONSTRAINT users_has_identity CHECK (phone_hash IS NOT NULL OR google_sub IS NOT NULL);

-- Members who already chose a name have finished signing up.
UPDATE users SET profile_completed_at = created_at WHERE name IS NOT NULL AND profile_completed_at IS NULL;
