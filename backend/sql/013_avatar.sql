-- v0.9: members can add a profile photo. Without one the app shows the
-- Mukafaah avatar that matches their gender.
ALTER TABLE users ADD COLUMN avatar_media_id uuid REFERENCES media(id);
