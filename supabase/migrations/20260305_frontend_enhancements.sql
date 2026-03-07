-- =====================================================
-- MotoGo24 Velin — Frontend enhancements migration
-- Idempotentni — bezpecne spustit opakovane
-- =====================================================

-- 1. MOTO_DAY_PRICES — cenik dle dne v tydnu

CREATE TABLE IF NOT EXISTS moto_day_prices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moto_id uuid NOT NULL REFERENCES motorcycles(id) ON DELETE CASCADE,
  price_monday numeric(10,2) NOT NULL DEFAULT 0,
  price_tuesday numeric(10,2) NOT NULL DEFAULT 0,
  price_wednesday numeric(10,2) NOT NULL DEFAULT 0,
  price_thursday numeric(10,2) NOT NULL DEFAULT 0,
  price_friday numeric(10,2) NOT NULL DEFAULT 0,
  price_saturday numeric(10,2) NOT NULL DEFAULT 0,
  price_sunday numeric(10,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(moto_id)
);

CREATE INDEX IF NOT EXISTS idx_moto_day_prices_moto ON moto_day_prices(moto_id);

ALTER TABLE moto_day_prices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moto_day_prices_admin ON moto_day_prices;
CREATE POLICY moto_day_prices_admin ON moto_day_prices
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS moto_day_prices_public_read ON moto_day_prices;
CREATE POLICY moto_day_prices_public_read ON moto_day_prices
  FOR SELECT USING (true);

DROP TRIGGER IF EXISTS moto_day_prices_updated ON moto_day_prices;
CREATE TRIGGER moto_day_prices_updated
  BEFORE UPDATE ON moto_day_prices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 2. MOTORCYCLES — datum porizeni

ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS acquired_at date;

-- 3. BOOKINGS — timestampy pro timeline

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS confirmed_at timestamptz;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS picked_up_at timestamptz;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS returned_at timestamptz;

-- 4. BRANCHES — rozsireni o kontaktni udaje

ALTER TABLE branches ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS opening_hours text;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS gps_lat numeric(10,7);
ALTER TABLE branches ADD COLUMN IF NOT EXISTS gps_lng numeric(10,7);
ALTER TABLE branches ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE branches ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true;
