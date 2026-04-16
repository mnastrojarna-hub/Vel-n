-- =====================================================
-- MotoGo24 Velin — SOS Incidenty & Timeline
-- Kompletni tabulky pro SOS system
-- ZAVISI NA: 20260305_000_base_tables.sql
-- =====================================================

-- 1. SOS_INCIDENTS

CREATE TABLE IF NOT EXISTS sos_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  type text NOT NULL DEFAULT 'other'
    CHECK (type IN (
      'theft', 'accident_minor', 'accident_major',
      'breakdown_minor', 'breakdown_major', 'defect_question', 'other'
    )),
  title text,
  description text,
  severity text NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status text NOT NULL DEFAULT 'reported'
    CHECK (status IN ('reported', 'acknowledged', 'in_progress', 'resolved', 'closed')),
  moto_rideable boolean,
  customer_decision text
    CHECK (customer_decision IN ('replacement_moto', 'end_ride', 'continue', 'waiting')),
  customer_fault boolean,
  damage_description text,
  damage_severity text
    CHECK (damage_severity IN ('none', 'cosmetic', 'functional', 'totaled')),
  nearest_service_name text,
  nearest_service_address text,
  nearest_service_phone text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  address text,
  photos text[] DEFAULT '{}',
  assigned_to uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  contact_phone text,
  admin_notes text,
  resolution text,
  resolved_at timestamptz,
  resolved_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Zajistit, ze sloupce existuji
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS severity text DEFAULT 'medium';
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS status text DEFAULT 'reported';
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS moto_rideable boolean;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS customer_decision text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS customer_fault boolean;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS damage_description text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS damage_severity text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS nearest_service_name text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS nearest_service_address text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS nearest_service_phone text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS latitude numeric(10,7);
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS longitude numeric(10,7);
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS photos text[] DEFAULT '{}';
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS assigned_to uuid;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS contact_phone text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS admin_notes text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS resolution text;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS resolved_by uuid;

CREATE INDEX IF NOT EXISTS idx_sos_incidents_user ON sos_incidents(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_booking ON sos_incidents(booking_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_status ON sos_incidents(status);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_created ON sos_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_severity ON sos_incidents(severity);

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

DROP TRIGGER IF EXISTS trg_sos_incidents_updated ON sos_incidents;
CREATE TRIGGER trg_sos_incidents_updated
  BEFORE UPDATE ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 2. SOS_TIMELINE

CREATE TABLE IF NOT EXISTS sos_timeline (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid NOT NULL REFERENCES sos_incidents(id) ON DELETE CASCADE,
  action text NOT NULL,
  description text,
  performed_by text,
  admin_id uuid REFERENCES admin_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sos_timeline_incident ON sos_timeline(incident_id);
CREATE INDEX IF NOT EXISTS idx_sos_timeline_created ON sos_timeline(created_at);

ALTER TABLE sos_timeline ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sos_timeline_admin ON sos_timeline;
CREATE POLICY sos_timeline_admin ON sos_timeline
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS sos_timeline_customer_read ON sos_timeline;
CREATE POLICY sos_timeline_customer_read ON sos_timeline
  FOR SELECT USING (
    incident_id IN (SELECT id FROM sos_incidents WHERE user_id = auth.uid())
  );

-- 3. Automaticky timeline zaznam pri vytvoreni incidentu

CREATE OR REPLACE FUNCTION sos_auto_timeline()
RETURNS trigger AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlasen zakaznikem', 'System');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sos_auto_timeline ON sos_incidents;
CREATE TRIGGER trg_sos_auto_timeline
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_timeline();

-- 4. Realtime

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_incidents;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE sos_timeline;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE messages;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE message_threads;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
