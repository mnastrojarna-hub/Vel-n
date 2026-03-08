-- ═══════════════════════════════════════════════════════
-- Fix: SOS notification sends ONLY ONE message per incident
-- Problem: old trigger version may still be active, causing
-- duplicate admin_messages. This migration ensures the correct
-- single-message version is installed.
--
-- Also ensures ALL SOS types produce a visible admin_message
-- so every incident shows up in customer's message list.
-- ═══════════════════════════════════════════════════════

-- Drop and recreate trigger to ensure clean state
DROP TRIGGER IF EXISTS trg_sos_notify_user ON sos_incidents;

CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
  v_title text;
  v_message text;
BEGIN
  -- Map type to readable Czech label
  CASE NEW.type
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  -- Single unified message for ALL incident types
  v_title := 'SOS přijato: ' || v_type_label;
  v_message := 'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
    COALESCE(NEW.description, '') ||
    ' Asistent vás bude kontaktovat.';

  -- Insert exactly ONE admin_message
  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    v_title,
    v_message,
    'sos_response'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block incident creation
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger (single AFTER INSERT trigger)
CREATE TRIGGER trg_sos_notify_user
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_notify_user_on_create();
