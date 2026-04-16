-- ═══════════════════════════════════════════════════════
-- FIX SOS TRIGGERS — 2026-03-10
-- 1. Drop mystery trigger sos_auto_reply_on_create (no known function body, can crash INSERT)
-- 2. Recreate trigger_sos_auto_reply as safe no-op (in case something references it)
-- 3. Make check_one_active_sos SECURITY DEFINER (needs to read all user's incidents)
-- ═══════════════════════════════════════════════════════

-- 1. Drop the mystery trigger that may not have a valid function
DROP TRIGGER IF EXISTS sos_auto_reply_on_create ON sos_incidents;

-- 2. Create a safe no-op function in case anything references trigger_sos_auto_reply
CREATE OR REPLACE FUNCTION trigger_sos_auto_reply()
RETURNS trigger AS $$
BEGIN
  -- Handled by sos_notify_user_on_create() instead
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Recreate check_one_active_sos with SECURITY DEFINER
-- so it can properly read sos_incidents regardless of RLS
CREATE OR REPLACE FUNCTION check_one_active_sos()
RETURNS trigger AS $$
DECLARE
  v_active_count int;
BEGIN
  -- Light types are auto-acknowledged and don't block new incidents
  IF NEW.type IN ('breakdown_minor', 'defect_question', 'location_share', 'other') THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_active_count
  FROM sos_incidents
  WHERE user_id = NEW.user_id
    AND status NOT IN ('resolved', 'closed')
    AND type NOT IN ('breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'Máte již aktivní SOS incident. Počkejte na vyřešení stávajícího incidentu velínem.';
  END IF;

  RETURN NEW;
EXCEPTION WHEN raise_exception THEN
  RAISE;  -- Re-raise our intentional exception
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_one_active_sos ON sos_incidents;
CREATE TRIGGER trg_one_active_sos
  BEFORE INSERT ON sos_incidents
  FOR EACH ROW
  EXECUTE FUNCTION check_one_active_sos();

-- 4. Ensure sos_notify_user_on_create is safe and SECURITY DEFINER
CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
  v_message text;
  v_title text;
  v_is_light boolean;
  v_exists boolean;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM admin_messages
    WHERE user_id = NEW.user_id
      AND type IN ('sos_response', 'sos_auto')
      AND created_at > now() - interval '2 minutes'
  ) INTO v_exists;

  IF v_exists THEN
    RETURN NEW;
  END IF;

  CASE NEW.type
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  v_is_light := NEW.type IN ('accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_is_light THEN
    v_title := 'Děkujeme za nahlášení';
    v_message := 'Děkujeme za nahlášení incidentu (' || v_type_label || '). Šťastnou cestu!';
  ELSE
    v_title := 'SOS přijato: ' || v_type_label;
    v_message := 'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
      COALESCE(NEW.description, '') ||
      ' Asistent vás bude kontaktovat.';
  END IF;

  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    v_title,
    v_message,
    CASE WHEN v_is_light THEN 'sos_auto' ELSE 'sos_response' END
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
