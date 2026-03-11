-- ═══════════════════════════════════════════════════════
-- SOS: 1 závažný aktivní incident na 1 aktivní rezervaci
-- 2026-03-11
--
-- Požadavek: Na jednu aktivní rezervaci může být pouze
-- 1 závažný (high/critical) aktivní incident.
-- Lehké incidenty (low/medium) nejsou omezeny.
-- Kontrola per-booking místo per-user.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION check_one_active_sos()
RETURNS trigger AS $$
DECLARE
  v_active_count int;
  v_booking_status text;
BEGIN
  -- Light types don't block (zachováno z v2)
  IF NEW.type::text IN ('breakdown_minor', 'defect_question', 'location_share', 'other') THEN
    RETURN NEW;
  END IF;

  -- Pokud incident nemá booking_id, fallback na per-user kontrolu
  IF NEW.booking_id IS NULL THEN
    SELECT count(*) INTO v_active_count
    FROM sos_incidents
    WHERE user_id = NEW.user_id
      AND status::text NOT IN ('resolved', 'closed')
      AND type::text NOT IN ('breakdown_minor', 'defect_question', 'location_share', 'other');

    IF v_active_count > 0 THEN
      RAISE EXCEPTION 'Máte již aktivní SOS incident. Počkejte na vyřešení stávajícího incidentu velínem.';
    END IF;

    RETURN NEW;
  END IF;

  -- Ověř, že booking je aktivní (reserved nebo active)
  SELECT status::text INTO v_booking_status
  FROM bookings
  WHERE id = NEW.booking_id;

  IF v_booking_status IS NULL OR v_booking_status NOT IN ('reserved', 'active') THEN
    -- Booking není aktivní — povolíme incident (edge case)
    RETURN NEW;
  END IF;

  -- Kontrola: max 1 závažný (high/critical) aktivní incident per booking
  SELECT count(*) INTO v_active_count
  FROM sos_incidents si
  WHERE si.booking_id = NEW.booking_id
    AND si.status::text NOT IN ('resolved', 'closed')
    AND si.type::text NOT IN ('breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'Na tuto rezervaci již existuje aktivní závažný SOS incident. Počkejte na vyřešení stávajícího incidentu.';
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN raise_exception THEN
    RAISE;  -- Re-raise intentional block
  WHEN OTHERS THEN
    RAISE NOTICE '[check_one_active_sos] unexpected error (allowing INSERT): %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
