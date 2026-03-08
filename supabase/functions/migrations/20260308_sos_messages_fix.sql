-- Fix SOS auto-notification: light incidents get friendly short message
-- Heavy incidents get standard "asistent vás kontaktuje" message
-- This prevents Velín from needing to send duplicate messages

CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
  v_message text;
  v_title text;
  v_is_light boolean;
BEGIN
  -- Map type to readable label
  CASE NEW.type
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  -- Light incidents = just a thank you, no follow-up needed
  v_is_light := NEW.type IN ('accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_is_light THEN
    v_title := 'Děkujeme za nahlášení';
    v_message := 'Děkujeme za nahlášení incidentu (' || v_type_label || '). Šťastnou cestu! 🏍️';
  ELSE
    v_title := 'SOS přijato: ' || v_type_label;
    v_message := 'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
      COALESCE(NEW.description, '') ||
      ' Asistent vás bude kontaktovat.';
  END IF;

  -- Create confirmation message for the user
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

-- Trigger already exists, function is replaced in-place

-- ═══════════════════════════════════════════════════════
-- Fix bridge trigger: use SOS title for SOS threads,
-- and use 'sos_response' type for SOS-related messages
-- This is the ONLY path for admin_messages from Velín messages
-- (direct inserts in SOSDetailPanel, ChatPanel, Messages.jsx removed)
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION bridge_admin_message_to_app()
RETURNS trigger AS $$
DECLARE
  v_thread message_threads%ROWTYPE;
  v_customer_id uuid;
  v_title text;
  v_type text;
BEGIN
  IF NEW.direction != 'admin' THEN RETURN NEW; END IF;

  SELECT * INTO v_thread FROM message_threads WHERE id = NEW.thread_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_customer_id := v_thread.customer_id;
  IF v_customer_id IS NULL THEN RETURN NEW; END IF;

  -- Detect SOS threads by subject prefix
  IF v_thread.subject IS NOT NULL AND v_thread.subject LIKE 'SOS:%' THEN
    v_title := v_thread.subject;
    v_type := 'sos_response';
  ELSE
    v_title := COALESCE(v_thread.subject, 'Zpráva z MotoGo24');
    v_type := 'info';
  END IF;

  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (v_customer_id, v_title, NEW.content, v_type);

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
