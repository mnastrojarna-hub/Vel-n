-- =====================================================
-- MotoGo24 SOS – KOMPLETNÍ MIGRACE (vše v jednom)
-- Bezpečné spustit opakovaně (idempotentní)
-- Spusťte v Supabase SQL editoru
-- =====================================================

-- =====================================================
-- 1. TABULKY
-- =====================================================

CREATE TABLE IF NOT EXISTS sos_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  type text NOT NULL DEFAULT 'other',
  title text,
  description text,
  severity text NOT NULL DEFAULT 'medium',
  status text NOT NULL DEFAULT 'reported',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sos_timeline (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid NOT NULL REFERENCES sos_incidents(id) ON DELETE CASCADE,
  action text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =====================================================
-- 2. VŠECHNY SLOUPCE na sos_incidents
-- =====================================================

-- Core fields
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS severity text DEFAULT 'medium';
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS status text DEFAULT 'reported';

-- Stav motorky a zákazníka
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS moto_rideable boolean;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS customer_decision text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS customer_fault boolean;

-- Poškození
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS damage_description text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS damage_severity text;

-- Servis
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS nearest_service_name text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS nearest_service_address text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS nearest_service_phone text;

-- GPS a kontakt
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS latitude numeric(10,7);
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS longitude numeric(10,7);
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS contact_phone text;

-- Fotky
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS photos text[] DEFAULT '{}';

-- Admin
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS assigned_to uuid;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS admin_notes text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS resolution text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS resolved_by uuid;

-- Moto ID – přímý odkaz na motorku (ne přes booking)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'moto_id'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN moto_id uuid REFERENCES motorcycles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Replacement order
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'replacement_data'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN replacement_data jsonb DEFAULT NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sos_incidents' AND column_name = 'replacement_status'
  ) THEN
    ALTER TABLE sos_incidents ADD COLUMN replacement_status text DEFAULT NULL;
  END IF;
END $$;

-- =====================================================
-- 3. VŠECHNY SLOUPCE na sos_timeline
-- =====================================================

ALTER TABLE sos_timeline ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE sos_timeline ADD COLUMN IF NOT EXISTS performed_by text;
ALTER TABLE sos_timeline ADD COLUMN IF NOT EXISTS admin_id uuid;
ALTER TABLE sos_timeline ADD COLUMN IF NOT EXISTS data jsonb;

-- =====================================================
-- 4. CHECK CONSTRAINTY (drop + recreate)
-- =====================================================

DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_type_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_type_check
    CHECK (type::text IN (
      'theft', 'accident_minor', 'accident_major',
      'breakdown_minor', 'breakdown_major',
      'defect_question', 'location_share', 'other'
    ));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'type constraint skipped: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_status_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_status_check
    CHECK (status::text IN ('reported', 'acknowledged', 'in_progress', 'resolved', 'closed'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'status constraint skipped: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_severity_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_severity_check
    CHECK (severity::text IN ('low', 'medium', 'high', 'critical'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'severity constraint skipped: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_customer_decision_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_customer_decision_check
    CHECK (customer_decision IS NULL OR customer_decision::text IN ('replacement_moto', 'end_ride', 'continue', 'waiting'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'customer_decision constraint skipped: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_damage_severity_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_damage_severity_check
    CHECK (damage_severity IS NULL OR damage_severity::text IN ('none', 'cosmetic', 'functional', 'totaled'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'damage_severity constraint skipped: %', SQLERRM;
END $$;

DO $$ BEGIN
  ALTER TABLE sos_incidents DROP CONSTRAINT IF EXISTS sos_incidents_replacement_status_check;
  ALTER TABLE sos_incidents ADD CONSTRAINT sos_incidents_replacement_status_check
    CHECK (replacement_status IS NULL OR replacement_status::text IN (
      'selecting', 'pending_payment', 'paid', 'admin_review',
      'approved', 'dispatched', 'delivered', 'rejected'
    ));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'replacement_status constraint skipped: %', SQLERRM;
END $$;

-- =====================================================
-- 5. TRIGGERY
-- =====================================================

-- Auto severity based on type
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

-- Auto timeline entry on new incident
CREATE OR REPLACE FUNCTION sos_auto_timeline()
RETURNS trigger AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlasen zakaznikem (' || COALESCE(NEW.type::text, 'other') || ')', 'System');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sos_auto_timeline ON sos_incidents;
CREATE TRIGGER trg_sos_auto_timeline
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_timeline();

-- Auto updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sos_incidents_updated ON sos_incidents;
CREATE TRIGGER trg_sos_incidents_updated
  BEFORE UPDATE ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- 6. INDEXY
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_sos_incidents_user ON sos_incidents(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_booking ON sos_incidents(booking_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_status ON sos_incidents(status);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_created ON sos_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_moto ON sos_incidents(moto_id);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_incident ON sos_timeline(incident_id);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_created ON sos_timeline(created_at);

DO $$ BEGIN
  CREATE INDEX IF NOT EXISTS idx_sos_incidents_severity ON sos_incidents(severity);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- =====================================================
-- 7. RLS POLICIES
-- =====================================================

ALTER TABLE sos_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_timeline ENABLE ROW LEVEL SECURITY;

-- sos_incidents policies
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

-- sos_timeline policies
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

-- =====================================================
-- 8. REALTIME
-- =====================================================

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_incidents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_timeline;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =====================================================
-- HOTOVO! Spusťte tento SQL v Supabase SQL editoru.
-- =====================================================
