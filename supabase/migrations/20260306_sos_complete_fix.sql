-- =====================================================
-- MotoGo24 — SOS Kompletní oprava (v2 — bezpečné pořadí)
-- SPOUŠTĚJ CELÉ NAJEDNOU v SQL Editoru
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ╔═══════════════════════════════════════════════════════╗
-- ║  FÁZE 1: PŘIDEJ VŠECHNY CHYBĚJÍCÍ SLOUPCE           ║
-- ╚═══════════════════════════════════════════════════════╝

-- 1a. severity (NULLABLE s defaultem — vyhne se NOT NULL chybě na existujících řádcích)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='severity') THEN
    ALTER TABLE sos_incidents ADD COLUMN severity text DEFAULT 'medium';
  END IF;
END $$;

-- 1b. contact_phone
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='contact_phone') THEN
    ALTER TABLE sos_incidents ADD COLUMN contact_phone text;
  END IF;
END $$;

-- 1c. customer_fault
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='customer_fault') THEN
    ALTER TABLE sos_incidents ADD COLUMN customer_fault boolean;
  END IF;
END $$;

-- 1d. customer_decision
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='customer_decision') THEN
    ALTER TABLE sos_incidents ADD COLUMN customer_decision text;
  END IF;
END $$;

-- 1e. moto_rideable
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='moto_rideable') THEN
    ALTER TABLE sos_incidents ADD COLUMN moto_rideable boolean;
  END IF;
END $$;

-- 1f. damage_severity
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='damage_severity') THEN
    ALTER TABLE sos_incidents ADD COLUMN damage_severity text;
  END IF;
END $$;

-- 1g. damage_description
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='damage_description') THEN
    ALTER TABLE sos_incidents ADD COLUMN damage_description text;
  END IF;
END $$;

-- 1h. admin_notes
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='admin_notes') THEN
    ALTER TABLE sos_incidents ADD COLUMN admin_notes text;
  END IF;
END $$;

-- 1i. resolution
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='resolution') THEN
    ALTER TABLE sos_incidents ADD COLUMN resolution text;
  END IF;
END $$;

-- 1j. resolved_at
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='resolved_at') THEN
    ALTER TABLE sos_incidents ADD COLUMN resolved_at timestamptz;
  END IF;
END $$;

-- 1k. resolved_by
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='resolved_by') THEN
    ALTER TABLE sos_incidents ADD COLUMN resolved_by uuid;
  END IF;
END $$;

-- 1l. assigned_to
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='assigned_to') THEN
    ALTER TABLE sos_incidents ADD COLUMN assigned_to uuid;
  END IF;
END $$;

-- 1m. photos
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='photos') THEN
    ALTER TABLE sos_incidents ADD COLUMN photos text[] DEFAULT '{}';
  END IF;
END $$;

-- 1n. address
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='address') THEN
    ALTER TABLE sos_incidents ADD COLUMN address text;
  END IF;
END $$;

-- 1o. title
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='title') THEN
    ALTER TABLE sos_incidents ADD COLUMN title text;
  END IF;
END $$;

-- 1p. nearest_service_*
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='nearest_service_name') THEN
    ALTER TABLE sos_incidents ADD COLUMN nearest_service_name text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='nearest_service_address') THEN
    ALTER TABLE sos_incidents ADD COLUMN nearest_service_address text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_incidents' AND column_name='nearest_service_phone') THEN
    ALTER TABLE sos_incidents ADD COLUMN nearest_service_phone text;
  END IF;
END $$;

-- 1q. sos_timeline.description
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_timeline' AND column_name='description') THEN
    ALTER TABLE sos_timeline ADD COLUMN description text;
  END IF;
END $$;

-- 1r. sos_timeline.admin_id
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_timeline' AND column_name='admin_id') THEN
    ALTER TABLE sos_timeline ADD COLUMN admin_id uuid;
  END IF;
END $$;

-- 1s. sos_timeline.performed_by (text, ne uuid)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sos_timeline' AND column_name='performed_by') THEN
    ALTER TABLE sos_timeline ADD COLUMN performed_by text;
  END IF;
END $$;

-- ╔═══════════════════════════════════════════════════════╗
-- ║  FÁZE 2: CHECK CONSTRAINTY (po přidání sloupců)      ║
-- ╚═══════════════════════════════════════════════════════╝

-- 2a. type CHECK — přidej location_share
DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_type_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_type_check
    CHECK (type::text IN (
      'theft', 'accident_minor', 'accident_major',
      'breakdown_minor', 'breakdown_major',
      'defect_question', 'location_share', 'other'
    ));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'type constraint: %', SQLERRM;
END $$;

-- 2b. severity CHECK
DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_severity_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_severity_check
    CHECK (severity::text IN ('low', 'medium', 'high', 'critical'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'severity constraint: %', SQLERRM;
END $$;

-- 2c. customer_decision CHECK
DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_customer_decision_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_customer_decision_check
    CHECK (customer_decision IS NULL OR customer_decision::text IN ('replacement_moto', 'end_ride', 'continue', 'waiting'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'customer_decision constraint: %', SQLERRM;
END $$;

-- 2d. damage_severity CHECK
DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_damage_severity_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_damage_severity_check
    CHECK (damage_severity IS NULL OR damage_severity::text IN ('none', 'cosmetic', 'functional', 'totaled'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'damage_severity constraint: %', SQLERRM;
END $$;

-- ╔═══════════════════════════════════════════════════════╗
-- ║  FÁZE 3: TRIGGERY (sloupce už existují)              ║
-- ╚═══════════════════════════════════════════════════════╝

-- 3a. Auto-severity trigger
CREATE OR REPLACE FUNCTION sos_auto_severity()
RETURNS trigger AS $$
BEGIN
  IF NEW.severity IS NULL OR NEW.severity = 'medium' THEN
    CASE NEW.type::text
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
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sos_auto_severity ON sos_incidents;
CREATE TRIGGER trg_sos_auto_severity
  BEFORE INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_severity();

-- 3b. Auto-timeline trigger
CREATE OR REPLACE FUNCTION sos_auto_timeline()
RETURNS trigger AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlášen zákazníkem (' || COALESCE(NEW.type::text, 'other') || ')', 'Systém');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sos_auto_timeline ON sos_incidents;
CREATE TRIGGER trg_sos_auto_timeline
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_timeline();

-- ╔═══════════════════════════════════════════════════════╗
-- ║  FÁZE 4: RLS POLICIES                               ║
-- ╚═══════════════════════════════════════════════════════╝

ALTER TABLE sos_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_timeline ENABLE ROW LEVEL SECURITY;

-- sos_incidents
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

-- sos_timeline
DROP POLICY IF EXISTS sos_timeline_admin ON sos_timeline;
CREATE POLICY sos_timeline_admin ON sos_timeline
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS sos_timeline_customer_read ON sos_timeline;
CREATE POLICY sos_timeline_customer_read ON sos_timeline
  FOR SELECT USING (
    incident_id IN (SELECT id FROM sos_incidents WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS sos_timeline_customer_insert ON sos_timeline;
CREATE POLICY sos_timeline_customer_insert ON sos_timeline
  FOR INSERT WITH CHECK (
    incident_id IN (SELECT id FROM sos_incidents WHERE user_id = auth.uid())
  );

-- ╔═══════════════════════════════════════════════════════╗
-- ║  FÁZE 5: INDEXY + REALTIME                          ║
-- ╚═══════════════════════════════════════════════════════╝

CREATE INDEX IF NOT EXISTS idx_sos_incidents_user ON sos_incidents(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_booking ON sos_incidents(booking_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_status ON sos_incidents(status);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_created ON sos_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_incident ON sos_timeline(incident_id);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_created ON sos_timeline(created_at);

-- Index na severity — BEZPEČNĚ (sloupec teď existuje)
DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS idx_sos_incidents_severity ON sos_incidents(severity);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'severity index: %', SQLERRM;
END $$;

-- Realtime
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_incidents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_timeline;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ╔═══════════════════════════════════════════════════════╗
-- ║  HOTOVO — Ověření                                    ║
-- ╚═══════════════════════════════════════════════════════╝
DO $$
DECLARE
  col_count integer;
BEGIN
  SELECT count(*) INTO col_count
  FROM information_schema.columns
  WHERE table_name = 'sos_incidents';
  RAISE NOTICE '✅ sos_incidents má % sloupců', col_count;

  SELECT count(*) INTO col_count
  FROM information_schema.columns
  WHERE table_name = 'sos_timeline';
  RAISE NOTICE '✅ sos_timeline má % sloupců', col_count;
END $$;
