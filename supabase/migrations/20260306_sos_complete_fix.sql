-- =====================================================
-- MotoGo24 — SOS Kompletní oprava
-- Opravuje: CHECK constraint pro typy, RLS pro timeline,
--           chybějící sloupce, severity auto-trigger
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. Přidej 'location_share' do CHECK constraintu type
--    (appka posílá location_share, DB ho odmítne)
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  -- Odstraň starý CHECK constraint a vytvoř nový s location_share
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_type_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_type_check
    CHECK (type IN (
      'theft', 'accident_minor', 'accident_major',
      'breakdown_minor', 'breakdown_major',
      'defect_question', 'location_share', 'other'
    ));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'sos_incidents type constraint: %', SQLERRM;
END $$;

-- ═══════════════════════════════════════════════════════
-- 2. RLS: Zákazník může INSERT do sos_timeline
--    (appka zapisuje timeline záznamy, ale RLS blokoval)
-- ═══════════════════════════════════════════════════════
DROP POLICY IF EXISTS sos_timeline_customer_insert ON sos_timeline;
CREATE POLICY sos_timeline_customer_insert ON sos_timeline
  FOR INSERT WITH CHECK (
    incident_id IN (SELECT id FROM sos_incidents WHERE user_id = auth.uid())
  );

-- ═══════════════════════════════════════════════════════
-- 3. Zajistit sloupec contact_phone na sos_incidents
--    (appka ho nyní posílá s profilem zákazníka)
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'contact_phone'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN contact_phone text;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 4. Zajistit sloupec severity na sos_incidents
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'severity'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN severity text NOT NULL DEFAULT 'medium'
      CHECK (severity IN ('low', 'medium', 'high', 'critical'));
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 5. Zajistit sloupec customer_fault (appka ho posílá)
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'customer_fault'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN customer_fault boolean;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 6. Zajistit sloupec customer_decision
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'customer_decision'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN customer_decision text
      CHECK (customer_decision IN ('replacement_moto', 'end_ride', 'continue', 'waiting'));
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 7. Zajistit sloupec moto_rideable
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'moto_rideable'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN moto_rideable boolean;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 8. Zajistit sloupec description na sos_timeline
--    (appka ho nyní posílá místo neexistujícího data)
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_timeline' AND column_name = 'description'
  ) THEN
    ALTER TABLE sos_timeline ADD COLUMN description text;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 9. Auto-severity trigger — automaticky nastaví severity
--    při vytvoření incidentu dle typu
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sos_auto_severity()
RETURNS trigger AS $$
BEGIN
  -- Nastav severity automaticky dle typu, pokud přichází jako default 'medium'
  IF NEW.severity = 'medium' OR NEW.severity IS NULL THEN
    CASE NEW.type
      WHEN 'theft' THEN NEW.severity := 'critical';
      WHEN 'accident_major' THEN NEW.severity := 'high';
      WHEN 'breakdown_major' THEN NEW.severity := 'high';
      WHEN 'accident_minor' THEN NEW.severity := 'medium';
      WHEN 'breakdown_minor' THEN NEW.severity := 'low';
      WHEN 'defect_question' THEN NEW.severity := 'low';
      ELSE NEW.severity := 'medium';
    END CASE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sos_auto_severity ON sos_incidents;
CREATE TRIGGER trg_sos_auto_severity
  BEFORE INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_severity();

-- ═══════════════════════════════════════════════════════
-- 10. Zajistit auto-timeline trigger existuje
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sos_auto_timeline()
RETURNS trigger AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlášen zákazníkem (' || COALESCE(NEW.type, 'other') || ')', 'Systém');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW; -- nevyhazuj chybu při selhání timeline
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sos_auto_timeline ON sos_incidents;
CREATE TRIGGER trg_sos_auto_timeline
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_timeline();

-- ═══════════════════════════════════════════════════════
-- 11. Zajistit RLS policies pro sos_incidents
-- ═══════════════════════════════════════════════════════
ALTER TABLE sos_incidents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sos_incidents_admin ON sos_incidents;
CREATE POLICY sos_incidents_admin ON sos_incidents
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS sos_incidents_customer_read ON sos_incidents;
CREATE POLICY sos_incidents_customer_read ON sos_incidents
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS sos_incidents_customer_insert ON sos_incidents;
CREATE POLICY sos_incidents_customer_insert ON sos_incidents
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS sos_incidents_customer_update ON sos_incidents;
CREATE POLICY sos_incidents_customer_update ON sos_incidents
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 12. Zajistit RLS policies pro sos_timeline
-- ═══════════════════════════════════════════════════════
ALTER TABLE sos_timeline ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sos_timeline_admin ON sos_timeline;
CREATE POLICY sos_timeline_admin ON sos_timeline
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS sos_timeline_customer_read ON sos_timeline;
CREATE POLICY sos_timeline_customer_read ON sos_timeline
  FOR SELECT USING (
    incident_id IN (SELECT id FROM sos_incidents WHERE user_id = auth.uid())
  );

-- customer_insert already created above (section 2)

-- ═══════════════════════════════════════════════════════
-- 13. Zajistit realtime pro sos tabulky
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_incidents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_timeline;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ═══════════════════════════════════════════════════════
-- 14. Zajistit sloupce pro detail panel Velínu
--     (damage_severity, damage_description, admin_notes, etc.)
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'damage_severity') THEN
    ALTER TABLE sos_incidents ADD COLUMN damage_severity text CHECK (damage_severity IN ('none', 'cosmetic', 'functional', 'totaled'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'damage_description') THEN
    ALTER TABLE sos_incidents ADD COLUMN damage_description text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'admin_notes') THEN
    ALTER TABLE sos_incidents ADD COLUMN admin_notes text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'resolution') THEN
    ALTER TABLE sos_incidents ADD COLUMN resolution text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'resolved_at') THEN
    ALTER TABLE sos_incidents ADD COLUMN resolved_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'resolved_by') THEN
    ALTER TABLE sos_incidents ADD COLUMN resolved_by uuid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'assigned_to') THEN
    ALTER TABLE sos_incidents ADD COLUMN assigned_to uuid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'photos') THEN
    ALTER TABLE sos_incidents ADD COLUMN photos text[] DEFAULT '{}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'address') THEN
    ALTER TABLE sos_incidents ADD COLUMN address text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'title') THEN
    ALTER TABLE sos_incidents ADD COLUMN title text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'nearest_service_name') THEN
    ALTER TABLE sos_incidents ADD COLUMN nearest_service_name text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'nearest_service_address') THEN
    ALTER TABLE sos_incidents ADD COLUMN nearest_service_address text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sos_incidents' AND column_name = 'nearest_service_phone') THEN
    ALTER TABLE sos_incidents ADD COLUMN nearest_service_phone text;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 15. Indexy pro rychlé dotazy
-- ═══════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_sos_incidents_user ON sos_incidents(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_booking ON sos_incidents(booking_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_status ON sos_incidents(status);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_created ON sos_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_severity ON sos_incidents(severity);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_incident ON sos_timeline(incident_id);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_created ON sos_timeline(created_at);
