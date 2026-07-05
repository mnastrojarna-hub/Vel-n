-- =============================================================================
-- MIGRACE 2026-07-15: „Jeden e-mail = max 1 rezervace na den" — anon check pro web
-- =============================================================================
-- Zadání: web frontend musí HLÍDAT, že zákazník (jeden e-mail) nemá dvě rezervace na
-- stejný den. DB pojistka (trigger `check_user_booking_overlap`) existuje, ale web má
-- na to upozornit PŘED odesláním (lepší UX než kryptická chyba). Tato read-only RPC
-- vrací, jestli e-mail už má nezrušenou rezervaci překrývající vybraný termín.
-- Anon-callable (web formulář, nepřihlášený zákazník). Vylučuje vlastní rozpracovaný draft.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_web_booking_user_overlap(
  p_email               text,
  p_start               date,
  p_end                 date,
  p_exclude_booking_id  uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid;
  v_row record;
BEGIN
  IF p_email IS NULL OR trim(p_email) = '' OR p_start IS NULL OR p_end IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  SELECT id INTO v_uid FROM auth.users
   WHERE lower(email) = lower(trim(p_email))
   LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('overlap', false);  -- neznámý e-mail → žádná kolize
  END IF;

  SELECT b.id, b.start_date, b.end_date
    INTO v_row
    FROM bookings b
   WHERE b.user_id = v_uid
     AND b.status IN ('pending','reserved','active','completed')
     AND (p_exclude_booking_id IS NULL OR b.id <> p_exclude_booking_id)
     AND daterange(b.start_date::date, b.end_date::date, '[]')
         && daterange(p_start, p_end, '[]')
   ORDER BY b.start_date
   LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  RETURN jsonb_build_object(
    'overlap',    true,
    'booking_id', v_row.id,
    'start_date', v_row.start_date,
    'end_date',   v_row.end_date
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_web_booking_user_overlap(text, date, date, uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
