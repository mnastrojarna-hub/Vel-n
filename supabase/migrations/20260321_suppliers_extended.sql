-- ═══════════════════════════════════════════════════════
-- Suppliers table – extended for OCR auto-matching
-- Adds: normalized_name, ico, dic, bank_account, default_category,
--        default_account, contact_email, notes columns
-- + normalize_supplier_name() function for diacritics-free matching
-- ═══════════════════════════════════════════════════════

-- Add missing columns (IF NOT EXISTS handles idempotency)
DO $$ BEGIN
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS normalized_name TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS ico TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS dic TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS address TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS bank_account TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS default_category TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS default_account TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS contact_email TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS notes TEXT;
  ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
END $$;

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_suppliers_normalized_name ON suppliers(normalized_name);
CREATE INDEX IF NOT EXISTS idx_suppliers_ico ON suppliers(ico);

-- Normalize supplier name: lowercase, strip Czech diacritics
CREATE OR REPLACE FUNCTION normalize_supplier_name(input TEXT)
RETURNS TEXT AS $$
  SELECT lower(
    translate(input,
      'áäčďéěíľňóöřšťúůüýžÁÄČĎÉĚÍĽŇÓÖŘŠŤÚŮÜÝŽ',
      'aacdeeillnoorstuuuyzAACDEEILNOORSTUUUYZ'
    )
  )
$$ LANGUAGE SQL IMMUTABLE;

-- Auto-update updated_at on suppliers (reuse existing trigger function)
DROP TRIGGER IF EXISTS trg_suppliers_updated ON suppliers;
CREATE TRIGGER trg_suppliers_updated BEFORE UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Backfill normalized_name for existing rows
UPDATE suppliers
SET normalized_name = normalize_supplier_name(name)
WHERE normalized_name IS NULL AND name IS NOT NULL;
