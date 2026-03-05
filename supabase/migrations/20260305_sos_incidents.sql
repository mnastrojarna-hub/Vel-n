-- =====================================================
-- MotoGo24 Velín — SOS Incidenty & Timeline
-- Kompletní tabulky pro SOS systém
-- ZÁVISÍ NA: 20260305_000_base_tables.sql
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. SOS_INCIDENTS
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS sos_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,

  -- Typ incidentu (hlavní kategorie)
  type text NOT NULL DEFAULT 'other'
    CHECK (type IN (
      'theft',              -- Krádež motorky
      'accident_minor',     -- Lehká nehoda (motorka pojízdná)
      'accident_major',     -- Závažná nehoda (motorka nepojízdná)
      'breakdown_minor',    -- Lehká porucha (pojízdná, dojede na servis)
      'breakdown_major',    -- Těžká porucha (nepojízdná, nutný odtah)
      'defect_question',    -- Dotaz na závadu (poradenství)
      'other'               -- Jiný problém
    )),

  -- Nadpis — konkrétní popis situace od zákazníka
  title text,

  -- Detailní popis
  description text,

  -- Závažnost (automaticky dle typu, admin může změnit)
  severity text NOT NULL DEFAULT 'medium'
    CHECK (severity IN ('low', 'medium', 'high', 'critical')),

  -- Stav
  status text NOT NULL DEFAULT 'reported'
    CHECK (status IN ('reported', 'acknowledged', 'in_progress', 'resolved', 'closed')),

  -- Pojízdnost motorky
  moto_rideable boolean,       -- true = pojízdná, false = nepojízdná, null = nezjištěno

  -- Rozhodnutí zákazníka (u závažné nehody / těžké poruchy)
  customer_decision text
    CHECK (customer_decision IN (
      'replacement_moto',   -- Chce náhradní motorku
      'end_ride',           -- Ukončuje jízdu
      'continue',           -- Pokračuje (po opravě)
      'waiting'             -- Čeká na rozhodnutí
    )),

  -- Zavinění (u nehod)
  customer_fault boolean,      -- true = zavinil zákazník → platí, false = cizí zavinění

  -- Poškození
  damage_description text,     -- Popis poškození motorky
  damage_severity text         -- 'none', 'cosmetic', 'functional', 'totaled'
    CHECK (damage_severity IN ('none', 'cosmetic', 'functional', 'totaled')),

  -- Nejbližší servis (pro lehké poruchy / dotazy)
  nearest_service_name text,
  nearest_service_address text,
  nearest_service_phone text,

  -- GPS poloha
  latitude numeric(10,7),
  longitude numeric(10,7),
  address text,                -- Rozpoznaná adresa (geocoding)

  -- Fotografie
  photos text[] DEFAULT '{}',

  -- Přiřazený admin/technik
  assigned_to uuid REFERENCES admin_users(id) ON DELETE SET NULL,

  -- Kontaktní telefon (může se lišit od profilu)
  contact_phone text,

  -- Poznámky admina
  admin_notes text,

  -- Vyřešení
  resolution text,             -- Jak byl incident vyřešen
  resolved_at timestamptz,
  resolved_by uuid REFERENCES admin_users(id) ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sos_incidents_user ON sos_incidents(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_booking ON sos_incidents(booking_id);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_status ON sos_incidents(status);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_created ON sos_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_incidents_severity ON sos_incidents(severity);

ALTER TABLE sos_incidents ENABLE ROW LEVEL SECURITY;

-- Admini vidí vše
DROP POLICY IF EXISTS sos_incidents_admin ON sos_incidents;
CREATE POLICY sos_incidents_admin ON sos_incidents
  FOR ALL USING (is_admin());

-- Zákazník vidí své incidenty
DROP POLICY IF EXISTS sos_incidents_customer_read ON sos_incidents;
CREATE POLICY sos_incidents_customer_read ON sos_incidents
  FOR SELECT USING (user_id = auth.uid());

-- Zákazník může vytvořit incident
DROP POLICY IF EXISTS sos_incidents_customer_insert ON sos_incidents;
CREATE POLICY sos_incidents_customer_insert ON sos_incidents
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Zákazník může aktualizovat svůj incident (přidat popis, fotky)
DROP POLICY IF EXISTS sos_incidents_customer_update ON sos_incidents;
CREATE POLICY sos_incidents_customer_update ON sos_incidents
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP TRIGGER IF EXISTS trg_sos_incidents_updated ON sos_incidents;
CREATE TRIGGER trg_sos_incidents_updated
  BEFORE UPDATE ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 2. SOS_TIMELINE
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS sos_timeline (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid NOT NULL REFERENCES sos_incidents(id) ON DELETE CASCADE,
  action text NOT NULL,
  description text,
  performed_by text,           -- jméno / email admina
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

-- ═══════════════════════════════════════════════════════
-- 3. Automatický timeline záznam při vytvoření incidentu
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sos_auto_timeline()
RETURNS trigger AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlášen zákazníkem', 'Systém');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sos_auto_timeline ON sos_incidents;
CREATE TRIGGER trg_sos_auto_timeline
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_auto_timeline();

-- ═══════════════════════════════════════════════════════
-- 4. Realtime — povolení pro sos tabulky
-- ═══════════════════════════════════════════════════════
ALTER PUBLICATION supabase_realtime ADD TABLE sos_incidents;
ALTER PUBLICATION supabase_realtime ADD TABLE sos_timeline;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE message_threads;
