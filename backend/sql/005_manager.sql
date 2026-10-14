-- Mukafaah v0.6: Mukafaah Manager runs the shops (adds them, edits everything).
-- The shop owner uses the Business app at the counter (Collect / Redeem) and sets
-- the shop's loyalty %. Every bill can carry the shop's invoice number.

-- The owner's own counter login (no PIN; issued to the signed-in owner only).
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_role_check;
ALTER TABLE staff ADD CONSTRAINT staff_role_check CHECK (role IN ('CASHIER','OWNER'));

ALTER TABLE visits ADD COLUMN invoice_no text CHECK (length(invoice_no) <= 40);
CREATE INDEX visits_invoice_idx ON visits(business_id, invoice_no) WHERE invoice_no IS NOT NULL;

-- Who added the shop (admin user) and when.
ALTER TABLE businesses ADD COLUMN added_by uuid REFERENCES users(id);

-- For monthly reports.
CREATE INDEX IF NOT EXISTS visits_created_idx ON visits(created_at);
CREATE INDEX IF NOT EXISTS users_created_idx ON users(created_at);
CREATE INDEX IF NOT EXISTS wa_orders_created_idx ON whatsapp_orders(created_at);
