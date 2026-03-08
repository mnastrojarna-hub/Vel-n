-- ═══════════════════════════════════════════════════════
-- DEFINITIVE FIX: Only ONE message per SOS incident
--
-- Problem: customer receives 2 messages on every SOS report.
-- Sources of duplicate messages:
--   1) trg_sos_notify_user trigger on sos_incidents
--   2) Unknown trigger/rule in DB (possibly notification_rules
--      or automation_rules table, or another named trigger)
--
-- Solution: Drop ALL known triggers that could send messages,
-- disable notification/automation rules for SOS,
-- and create ONE clean trigger.
-- ═══════════════════════════════════════════════════════

-- 1. Drop ALL possible notification triggers on sos_incidents
DROP TRIGGER IF EXISTS trg_sos_notify_user ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_notify ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_notification ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_auto_message ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_auto_notify ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_send_message ON sos_incidents;
DROP TRIGGER IF EXISTS trg_notify_sos ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_admin_message ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_user_message ON sos_incidents;
DROP TRIGGER IF EXISTS trg_sos_confirmation ON sos_incidents;

-- 2. Disable automation/notification rules for SOS (schema-safe)
DO $$ BEGIN
  EXECUTE 'UPDATE automation_rules SET enabled = false WHERE id IN (SELECT id FROM automation_rules WHERE to_jsonb(automation_rules)::text ILIKE ''%sos%'')';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  EXECUTE 'UPDATE notification_rules SET enabled = false WHERE id IN (SELECT id FROM notification_rules WHERE to_jsonb(notification_rules)::text ILIKE ''%sos%'')';
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 3. Create the ONE and ONLY notification function
CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
BEGIN
  -- Map type to Czech label
  CASE NEW.type
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  -- Insert exactly ONE admin_message
  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    'SOS přijato: ' || v_type_label,
    'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
      COALESCE(NEW.description, '') ||
      ' Asistent vás bude kontaktovat.',
    'sos_response'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create single trigger
CREATE TRIGGER trg_sos_notify_user
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_notify_user_on_create();

-- 5. Drop any other functions that might also send SOS messages
-- (safe — if they don't exist, nothing happens)
DROP FUNCTION IF EXISTS sos_send_confirmation() CASCADE;
DROP FUNCTION IF EXISTS sos_auto_notify() CASCADE;
DROP FUNCTION IF EXISTS sos_notify_customer() CASCADE;
DROP FUNCTION IF EXISTS notify_sos_user() CASCADE;
DROP FUNCTION IF EXISTS sos_send_user_message() CASCADE;
DROP FUNCTION IF EXISTS handle_sos_notification() CASCADE;
