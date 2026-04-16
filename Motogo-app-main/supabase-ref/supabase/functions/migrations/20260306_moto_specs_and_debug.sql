-- =====================================================
-- MotoGo24 — Motorcycle specs + debug log
-- Idempotentni — bezpecne spustit opakovane
-- =====================================================

-- 1. MOTORCYCLES — technicke parametry

ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS power_kw numeric(6,1);
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS torque_nm numeric(6,1);
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS weight_kg integer;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS fuel_tank_l numeric(4,1);
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS seat_height_mm text;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS license_required text DEFAULT 'A';
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS has_abs boolean DEFAULT true;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS has_asc boolean DEFAULT false;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS ideal_usage text[];
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS features text[];
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS manual_url text;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS engine_type text;
ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS power_hp integer;

-- 2. DEBUG_LOG — admin debug tracking

CREATE TABLE IF NOT EXISTS debug_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid,
  source text NOT NULL,
  action text NOT NULL,
  component text,
  status text NOT NULL DEFAULT 'info',
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
