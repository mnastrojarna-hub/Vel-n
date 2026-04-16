-- =============================================================================
-- MIGRACE: set_web_booking_password RPC
-- Datum: 2026-03-29
-- Popis: Nastaví heslo zákazníka přes booking ID (pouze pro web bookings).
--        Heslo se použije pro editaci rezervace i budoucí přihlášení do app.
-- =============================================================================

CREATE OR REPLACE FUNCTION set_web_booking_password(
  p_booking_id uuid,
  p_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_source text;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RETURN jsonb_build_object('error', 'Heslo musí mít alespoň 8 znaků');
  END IF;

  SELECT user_id, booking_source INTO v_user_id, v_source
    FROM bookings WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source != 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  UPDATE auth.users SET
    encrypted_password = crypt(p_password, gen_salt('bf')),
    updated_at = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
