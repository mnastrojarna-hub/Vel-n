-- =============================================================================
-- MIGRACE: Persistentní ověření dokladů v profiles
-- Datum: 2026-03-25
--
-- Problém: Ověření dokladů je v localStorage → ztrácí se při odhlášení.
-- Řešení: Nové sloupce v profiles pro datum ověření každého typu dokladu.
-- Zákazník nemusí znovu nahrávat doklady do data expirace.
-- =============================================================================

-- Datum ověření dokladů (nastavuje se po úspěšném Mindee scan + verify)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS id_verified_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS id_verified_until DATE DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS license_verified_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS license_verified_until DATE DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS passport_verified_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS passport_verified_until DATE DEFAULT NULL;

COMMENT ON COLUMN profiles.id_verified_at IS 'Datum ověření OP přes Mindee OCR';
COMMENT ON COLUMN profiles.id_verified_until IS 'Platnost OP — do tohoto data je ověření platné';
COMMENT ON COLUMN profiles.license_verified_at IS 'Datum ověření ŘP přes Mindee OCR';
COMMENT ON COLUMN profiles.license_verified_until IS 'Platnost ŘP — do tohoto data je ověření platné';
COMMENT ON COLUMN profiles.passport_verified_at IS 'Datum ověření pasu přes Mindee OCR';
COMMENT ON COLUMN profiles.passport_verified_until IS 'Platnost pasu — do tohoto data je ověření platné';
