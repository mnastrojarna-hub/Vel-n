-- ═══════════════════════════════════════════════════════
-- 1. FIX message_threads_channel_check
--    Add 'app' as valid channel (was missing, causing insert errors from mobile app)
-- ═══════════════════════════════════════════════════════

DO $$
BEGIN
  ALTER TABLE message_threads DROP CONSTRAINT IF EXISTS message_threads_channel_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

ALTER TABLE message_threads ADD CONSTRAINT message_threads_channel_check
  CHECK (channel IN ('app', 'web', 'email', 'sms'));

-- ═══════════════════════════════════════════════════════
-- 2. ENFORCE ONE ACTIVE SOS PER USER
--    User cannot create a new SOS incident while they have
--    an unresolved one (status NOT IN resolved, closed)
-- ═══════════════════════════════════════════════════════

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
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_one_active_sos ON sos_incidents;
CREATE TRIGGER trg_one_active_sos
  BEFORE INSERT ON sos_incidents
  FOR EACH ROW
  EXECUTE FUNCTION check_one_active_sos();
