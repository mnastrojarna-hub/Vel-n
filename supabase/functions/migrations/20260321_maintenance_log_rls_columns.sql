-- ═══════════════════════════════════════════════════════
-- maintenance_log: Chybějící sloupce + RLS politiky
-- ═══════════════════════════════════════════════════════

-- 1. Doplnit chybějící sloupce
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'service_type')
  THEN ALTER TABLE maintenance_log ADD COLUMN service_type text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'status')
  THEN ALTER TABLE maintenance_log ADD COLUMN status text DEFAULT 'pending'; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'type')
  THEN ALTER TABLE maintenance_log ADD COLUMN type text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'description')
  THEN ALTER TABLE maintenance_log ADD COLUMN description text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'performed_by')
  THEN ALTER TABLE maintenance_log ADD COLUMN performed_by text; END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'maintenance_log' AND column_name = 'cost')
  THEN ALTER TABLE maintenance_log ADD COLUMN cost numeric; END IF;
END $$;

-- 2. RLS politiky (admin full access + public read)
ALTER TABLE maintenance_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS maintenance_log_admin ON maintenance_log;
CREATE POLICY maintenance_log_admin ON maintenance_log
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS maintenance_log_public_read ON maintenance_log;
CREATE POLICY maintenance_log_public_read ON maintenance_log
  FOR SELECT USING (true);

-- 3. Stejné pro maintenance_schedules (pokud chybí)
ALTER TABLE maintenance_schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS maintenance_schedules_admin ON maintenance_schedules;
CREATE POLICY maintenance_schedules_admin ON maintenance_schedules
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS maintenance_schedules_public_read ON maintenance_schedules;
CREATE POLICY maintenance_schedules_public_read ON maintenance_schedules
  FOR SELECT USING (true);

-- 4. Stejné pro service_orders
ALTER TABLE service_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS service_orders_admin ON service_orders;
CREATE POLICY service_orders_admin ON service_orders
  FOR ALL USING (is_admin());
