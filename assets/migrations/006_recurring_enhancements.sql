-- 006_recurring_enhancements.sql
-- Adds snapshot item name and HSN/SAC code to recurring_invoice_items

ALTER TABLE recurring_invoice_items ADD COLUMN product_name TEXT;
ALTER TABLE recurring_invoice_items ADD COLUMN hsn_sac TEXT;
