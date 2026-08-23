-- =============================================================================
-- 20260823_check_booking_overlap_rls_fix.sql
-- FIX: check_booking_overlap neviděl cizí rezervace přes RLS → dvojrezervace
--       motorky z appky prošla (incident 23. 8. 2026, Honda VTX 1800 8J1414:
--       web pending #C2CB115 10:01 + app #EAA475E 13:37, stejný termín 4.–6. 9.).
--
-- PŘÍČINA: check_booking_overlap() jako JEDINÁ overlap trigger funkce na
-- `bookings` NEMĚLA SECURITY DEFINER (check_user_booking_overlap i
-- check_trailer_overlap ji mají). Trigger tedy běžel s právy volajícího:
--   - web create_web_booking = SECURITY DEFINER (postgres) → RLS se neuplatní,
--     kontrola fungovala;
--   - appka dělá PŘÍMÝ INSERT do `bookings` jako přihlášený zákazník → EXISTS
--     dotaz v triggeru podléhá RLS politice `bookings_user_select`
--     (user_id = auth.uid() OR is_admin()) → PENDING rezervaci JINÉHO účtu
--     (zákazník má oddělený web a app účet) trigger NEVIDĚL → kolize prošla.
-- UI kalendář (get_moto_booked_dates, SECURITY DEFINER) obsazenost ukazuje
-- správně — selhala pouze DB pojistka při zastaralém/otevřeném formuláři.
--
-- OPRAVA: tělo 1:1 z 20260726b_check_booking_overlap_trailer_gear.sql,
-- + SECURITY DEFINER + SET search_path = public (žádné pgcrypto → extensions
-- netřeba). Trigger trg_check_booking_overlap se nemění. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_booking_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- SOS replacement bookings are exempt from moto overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Překrývající se rezervace pro moto_id %', NEW.moto_id;
  END IF;

  -- Kus je v termínu přiřazený jako vozík-příslušenství jiné rezervace
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE trailer_moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Kus % je v tomto termínu přiřazen jako vozík k jiné rezervaci', NEW.moto_id;
  END IF;

  RETURN NEW;
END;
$$;
