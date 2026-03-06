-- =====================================================
-- MotoGo24 — Motorcycle specs + debug log
-- Přidává: parametry motorek (výkon, moment, hmotnost,
--          nádrž, sedlo, ABS/ASC, popis, využití, návod)
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. MOTORCYCLES — technické parametry
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='power_kw') THEN
    ALTER TABLE motorcycles ADD COLUMN power_kw numeric(6,1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='torque_nm') THEN
    ALTER TABLE motorcycles ADD COLUMN torque_nm numeric(6,1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='weight_kg') THEN
    ALTER TABLE motorcycles ADD COLUMN weight_kg integer;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='fuel_tank_l') THEN
    ALTER TABLE motorcycles ADD COLUMN fuel_tank_l numeric(4,1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='seat_height_mm') THEN
    ALTER TABLE motorcycles ADD COLUMN seat_height_mm text; -- text kvůli rozsahu "850-870"
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='license_required') THEN
    ALTER TABLE motorcycles ADD COLUMN license_required text DEFAULT 'A';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='has_abs') THEN
    ALTER TABLE motorcycles ADD COLUMN has_abs boolean DEFAULT true;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='has_asc') THEN
    ALTER TABLE motorcycles ADD COLUMN has_asc boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='description') THEN
    ALTER TABLE motorcycles ADD COLUMN description text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='ideal_usage') THEN
    ALTER TABLE motorcycles ADD COLUMN ideal_usage text[]; -- ['silnice','teren','dvou','dlouhe-cesty']
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='features') THEN
    ALTER TABLE motorcycles ADD COLUMN features text[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='manual_url') THEN
    ALTER TABLE motorcycles ADD COLUMN manual_url text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='engine_type') THEN
    ALTER TABLE motorcycles ADD COLUMN engine_type text; -- "1254 cc boxer"
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='motorcycles' AND column_name='power_hp') THEN
    ALTER TABLE motorcycles ADD COLUMN power_hp integer;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 2. DEBUG_LOG — admin debug tracking
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS debug_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid,
  source text NOT NULL, -- 'velin' | 'app' | 'backend'
  action text NOT NULL,
  component text, -- 'FleetDetail', 'Bookings', etc.
  status text NOT NULL DEFAULT 'info', -- 'info' | 'success' | 'error' | 'warning'
  request_data jsonb,
  response_data jsonb,
  error_message text,
  error_stack text,
  duration_ms integer,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_debug_log_created ON debug_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_debug_log_status ON debug_log(status);
CREATE INDEX IF NOT EXISTS idx_debug_log_action ON debug_log(action);

ALTER TABLE debug_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS debug_log_admin ON debug_log;
CREATE POLICY debug_log_admin ON debug_log
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());
