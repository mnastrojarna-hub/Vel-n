-- =============================================================================
-- MIGRACE: Přidání sloupců velikostí výbavy do bookings
-- Datum: 2026-04-11
-- Popis: helmet_size, jacket_size, pants_size, boots_size, gloves_size
-- =============================================================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS helmet_size text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS jacket_size text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS pants_size text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS boots_size text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS gloves_size text;
