-- =====================================================
-- MotoGo24 Velín — Frontend enhancements migration
-- Adds: moto_day_prices, branch fields, booking timestamps,
--        motorcycle acquired_at
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. MOTO_DAY_PRICES — ceník dle dne v týdnu
-- ═══════════════════════════════════════════════════════
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

-- RLS
ALTER TABLE moto_day_prices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moto_day_prices_admin ON moto_day_prices;
CREATE POLICY moto_day_prices_admin ON moto_day_prices
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS moto_day_prices_public_read ON moto_day_prices;
CREATE POLICY moto_day_prices_public_read ON moto_day_prices
  FOR SELECT USING (true);

-- Auto-update updated_at
DROP TRIGGER IF EXISTS moto_day_prices_updated ON moto_day_prices;
CREATE TRIGGER moto_day_prices_updated
  BEFORE UPDATE ON moto_day_prices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 2. MOTORCYCLES — datum pořízení
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'motorcycles' AND column_name = 'acquired_at'
  ) THEN
    ALTER TABLE motorcycles ADD COLUMN acquired_at date;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 3. BOOKINGS — timestampy pro timeline
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'confirmed_at'
  ) THEN
    ALTER TABLE bookings ADD COLUMN confirmed_at timestamptz;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'picked_up_at'
  ) THEN
    ALTER TABLE bookings ADD COLUMN picked_up_at timestamptz;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'returned_at'
  ) THEN
    ALTER TABLE bookings ADD COLUMN returned_at timestamptz;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 4. BRANCHES — rozšíření o kontaktní údaje
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'city'
  ) THEN
    ALTER TABLE branches ADD COLUMN city text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'address'
  ) THEN
    ALTER TABLE branches ADD COLUMN address text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'phone'
  ) THEN
    ALTER TABLE branches ADD COLUMN phone text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'email'
  ) THEN
    ALTER TABLE branches ADD COLUMN email text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'opening_hours'
  ) THEN
    ALTER TABLE branches ADD COLUMN opening_hours text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'gps_lat'
  ) THEN
    ALTER TABLE branches ADD COLUMN gps_lat numeric(10,7);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'gps_lng'
  ) THEN
    ALTER TABLE branches ADD COLUMN gps_lng numeric(10,7);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'notes'
  ) THEN
    ALTER TABLE branches ADD COLUMN notes text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'branches' AND column_name = 'active'
  ) THEN
    ALTER TABLE branches ADD COLUMN active boolean NOT NULL DEFAULT true;
  END IF;
END $$;
