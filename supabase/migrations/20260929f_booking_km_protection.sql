-- =============================================================================
-- STAV TACHOMETRU (2026-09-29) — 4/6 (merge A): km v protokolu appky + ochrana mileage_*
-- Migrace: 20260929f_booking_km_protection.sql — idempotentní
--  • get_handover_protocol_state (živé tělo) + mileage, mileage_unit; vlastník přes IS DISTINCT FROM
--  • trg_protect_booking_mileage: zákaznický JWT nezapíše mileage_start/mileage_end (INSERT ani UPDATE) —
--    přes trg_booking_mileage_to_moto by otrávil motorcycles.mileage = km dalšího zákazníka + spodní mez kiosku
--  • update_test_booking_fields: SECURITY DEFINER bez kontroly role s GRANT anon (měnil LIBOVOLNOU rezervaci
--    vč. mileage_*) → EXECUTE jen service_role (v repu žádný volající)
-- Závisí na 20260929c (_handover_pickup_km).
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."get_handover_protocol_state"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
  v_self boolean;
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_unit text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  -- IS DISTINCT FROM (2026-09-29): rezervaci s user_id NULL nesmí číst cizí přihlášený zákazník
  IF v_b.user_id IS DISTINCT FROM v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  v_self := _is_self_service_booking(p_booking_id);
  SELECT CASE WHEN m.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END INTO v_unit FROM motorcycles m WHERE m.id = v_b.moto_id;

  RETURN jsonb_build_object(
    'is_self_service', v_self,
    'started_at',  v_b.handover_protocol_started_at,
    'deadline',    NULL::timestamptz,   -- 2026-09-25: 1h okno + autofill zrušeny
    'filled_at',   v_b.handover_protocol_filled_at,
    'autofilled',  v_b.handover_protocol_autofilled,
    'locked',      (v_b.handover_protocol_filled_at IS NOT NULL),
    -- podepsat lze po výzvě z kiosku NEBO ode dne začátku termínu (Praha) —
    -- ne týdny předem (protokol = stav km/výbavy v den předání)
    'can_fill',    (v_self
                    AND v_b.status IN ('reserved','active')
                    AND v_b.handover_protocol_filled_at IS NULL
                    AND (v_b.handover_protocol_started_at IS NOT NULL
                         OR (v_b.start_date AT TIME ZONE 'Europe/Prague')::date <= v_today)),
    'needs_locker',      public._booking_needs_locker(p_booking_id),
    'gear_collected_at', v_b.gear_collected_at,
    'prompted_at',       v_b.handover_protocol_prompted_at,
    'start_date',        v_b.start_date,
    -- 2026-09-29: km do protokolu vyplní systém — appka jen zobrazí, edge zapíše (form.mileage appky ignoruje)
    'mileage',           public._handover_pickup_km(p_booking_id),
    'mileage_unit',      COALESCE(v_unit, 'km')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._protect_booking_mileage()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Běžný JWT zákazníka (auth.uid() NOT NULL, ne admin): stav tachometru zapisuje jen backend —
  -- edge (service_role), kiosk RPC (anon + zařízení), Velín (admin).
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    IF TG_OP = 'INSERT' THEN
      NEW.mileage_start := NULL;
      NEW.mileage_end   := NULL;
    ELSE
      NEW.mileage_start := OLD.mileage_start;
      NEW.mileage_end   := OLD.mileage_end;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._protect_booking_mileage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._protect_booking_mileage() TO service_role;
DROP TRIGGER IF EXISTS trg_protect_booking_mileage ON public.bookings;
CREATE TRIGGER trg_protect_booking_mileage
  BEFORE INSERT OR UPDATE OF mileage_start, mileage_end ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._protect_booking_mileage();

REVOKE ALL ON FUNCTION public.update_test_booking_fields(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_test_booking_fields(uuid, jsonb) TO service_role;
