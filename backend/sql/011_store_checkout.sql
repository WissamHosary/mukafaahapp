-- v0.9: delivery details for WhatsApp orders, and limits against fake orders.
ALTER TABLE whatsapp_orders
  ADD COLUMN contact_name   text CHECK (length(contact_name) <= 60),
  ADD COLUMN contact_phone  text CHECK (length(contact_phone) <= 20),
  ADD COLUMN area           text CHECK (length(area) <= 80),
  ADD COLUMN street         text CHECK (length(street) <= 120),
  ADD COLUMN building       text CHECK (length(building) <= 80),
  ADD COLUMN landmark       text CHECK (length(landmark) <= 120),
  ADD COLUMN lat            double precision CHECK (lat BETWEEN -90 AND 90),
  ADD COLUMN lng            double precision CHECK (lng BETWEEN -180 AND 180);
CREATE INDEX wa_orders_user_idx ON whatsapp_orders(user_id, created_at DESC);
