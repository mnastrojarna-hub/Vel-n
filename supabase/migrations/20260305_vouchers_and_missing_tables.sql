-- =====================================================
-- Velín v2.1 — Vouchers + doplnění tabulek
-- ZÁVISÍ NA: 20260305_000_base_tables.sql (admin_users, update_updated_at)
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. VOUCHERS (dárkové poukazy)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS vouchers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  amount numeric(10,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'CZK',
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'redeemed', 'expired', 'cancelled')),

  -- Kdo koupil
  buyer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  buyer_name text,
  buyer_email text,

  -- Platnost
  valid_from date NOT NULL DEFAULT CURRENT_DATE,
  valid_until date NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '1 year'),

  -- Uplatnění
  redeemed_at timestamptz,
  redeemed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  redeemed_for text,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,

  -- Metadata
  description text,
  category text CHECK (category IS NULL OR category IN ('rental', 'gear', 'experience', 'gift')),
  created_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vouchers_status ON vouchers(status);
CREATE INDEX IF NOT EXISTS idx_vouchers_code ON vouchers(code);
CREATE INDEX IF NOT EXISTS idx_vouchers_buyer_id ON vouchers(buyer_id);
CREATE INDEX IF NOT EXISTS idx_vouchers_created_at ON vouchers(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_vouchers_valid_until ON vouchers(valid_until);

-- RLS
ALTER TABLE vouchers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vouchers_admin_all ON vouchers;
CREATE POLICY vouchers_admin_all ON vouchers
  FOR ALL USING (
    is_admin()
  );

DROP POLICY IF EXISTS vouchers_user_select ON vouchers;
CREATE POLICY vouchers_user_select ON vouchers
  FOR SELECT USING (
    buyer_id = auth.uid() OR redeemed_by = auth.uid()
  );

-- Trigger updated_at (funkce definována v base migraci)
DROP TRIGGER IF EXISTS trg_vouchers_updated ON vouchers;
CREATE TRIGGER trg_vouchers_updated
  BEFORE UPDATE ON vouchers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Automatická expirace
CREATE OR REPLACE FUNCTION expire_vouchers()
RETURNS void AS $$
BEGIN
  UPDATE vouchers
  SET status = 'expired'
  WHERE status = 'active'
    AND valid_until < CURRENT_DATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- pg_cron schedule (spouštět denně v 01:00)
-- Vyžaduje pg_cron extension — v Supabase zapnout v Dashboard > Database > Extensions
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('expire-vouchers');
    PERFORM cron.schedule('expire-vouchers', '0 1 * * *', 'SELECT expire_vouchers()');
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not available — schedule expire_vouchers() manually or enable pg_cron extension';
END $$;

-- ═══════════════════════════════════════════════════════
-- 2. MOTO_LOCATIONS (polohy motorek)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS moto_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moto_id uuid NOT NULL REFERENCES motorcycles(id) ON DELETE CASCADE,
  lat double precision,
  lng double precision,
  address text,
  speed numeric(5,1),
  heading numeric(5,1),
  accuracy numeric(6,1),
  source text DEFAULT 'gps'
    CHECK (source IN ('gps', 'manual', 'tracker')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(moto_id)
);

CREATE INDEX IF NOT EXISTS idx_moto_locations_moto ON moto_locations(moto_id);

ALTER TABLE moto_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS moto_locations_admin ON moto_locations;
CREATE POLICY moto_locations_admin ON moto_locations
  FOR ALL USING (
    is_admin()
  );

DROP POLICY IF EXISTS moto_locations_read ON moto_locations;
CREATE POLICY moto_locations_read ON moto_locations
  FOR SELECT USING (true);

-- ═══════════════════════════════════════════════════════
-- 3. SERVICE_ORDERS (servisní objednávky)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS service_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moto_id uuid NOT NULL REFERENCES motorcycles(id) ON DELETE CASCADE,
  maintenance_log_id uuid REFERENCES maintenance_log(id) ON DELETE SET NULL,
  type text NOT NULL,
  items jsonb NOT NULL DEFAULT '[]',
  km integer,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
  assigned_to text,
  notes text,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_orders_moto ON service_orders(moto_id);
CREATE INDEX IF NOT EXISTS idx_service_orders_status ON service_orders(status);

ALTER TABLE service_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS service_orders_admin ON service_orders;
CREATE POLICY service_orders_admin ON service_orders
  FOR ALL USING (
    is_admin()
  );

-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_service_orders_updated ON service_orders;
CREATE TRIGGER trg_service_orders_updated
  BEFORE UPDATE ON service_orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 4. ALTER existujících tabulek — doplnění chybějících sloupců
-- ═══════════════════════════════════════════════════════

-- MAINTENANCE_SCHEDULES
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'schedule_type')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN schedule_type text DEFAULT 'mileage'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'interval_km')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN interval_km integer DEFAULT 10000; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'interval_days')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN interval_days integer; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'last_service_km')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN last_service_km integer DEFAULT 0; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'last_service_date')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN last_service_date date; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'description')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN description text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_schedules' AND column_name = 'active')
  THEN ALTER TABLE maintenance_schedules ADD COLUMN active boolean DEFAULT true; END IF;
END $$;

-- MAINTENANCE_LOG
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'km_at_service')
  THEN ALTER TABLE maintenance_log ADD COLUMN km_at_service integer; END IF;
END $$;

-- MOTORCYCLES
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'motorcycles' AND column_name = 'stk_valid_until')
  THEN ALTER TABLE motorcycles ADD COLUMN stk_valid_until date; END IF;
END $$;

-- BOOKINGS
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'bookings' AND column_name = 'notes')
  THEN ALTER TABLE bookings ADD COLUMN notes text; END IF;
END $$;

-- PROFILES — doplnění sloupců pro Velín frontend
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'license_group')
  THEN ALTER TABLE profiles ADD COLUMN license_group text[] DEFAULT '{}'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'riding_experience')
  THEN ALTER TABLE profiles ADD COLUMN riding_experience text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'emergency_contact')
  THEN ALTER TABLE profiles ADD COLUMN emergency_contact text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'emergency_phone')
  THEN ALTER TABLE profiles ADD COLUMN emergency_phone text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'gear_sizes')
  THEN ALTER TABLE profiles ADD COLUMN gear_sizes jsonb; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'reliability_score')
  THEN ALTER TABLE profiles ADD COLUMN reliability_score jsonb; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'marketing_consent')
  THEN ALTER TABLE profiles ADD COLUMN marketing_consent boolean DEFAULT false; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'street')
  THEN ALTER TABLE profiles ADD COLUMN street text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'city')
  THEN ALTER TABLE profiles ADD COLUMN city text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'zip')
  THEN ALTER TABLE profiles ADD COLUMN zip text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'country')
  THEN ALTER TABLE profiles ADD COLUMN country text DEFAULT 'CZ'; END IF;
END $$;
