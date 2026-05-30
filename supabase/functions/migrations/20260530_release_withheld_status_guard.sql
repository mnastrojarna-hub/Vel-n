-- =============================================================================
-- MIGRACE: Door codes — pojistka na status rezervace v release_withheld_door_codes_for_user
-- Datum: 2026-05-30
--
-- Problém / zadání:
--   Při dodatečném nahrání dokladů za zákazníka (Velín „+ Nahrát doklady" / web / app)
--   se NESMÍ uvolnit přístupové kódy ani poslat door_codes mail/SMS, pokud má zákazník
--   jen ZRUŠENÉ / DOKONČENÉ rezervace (nebo žádnou nadcházející).
--
-- Stav před změnou:
--   Smyčka brala rezervace jen podle `bdc.is_active = true AND sent_to_customer = false`.
--   Completed/cancelled mají kódy zneaktivněné triggerem `auto_deactivate_door_codes`,
--   takže to bylo ošetřené nepřímo. Tato migrace přidává EXPLICITNÍ pojistku na status
--   pro případ nekonzistence dat.
--
-- Změna: do `WHERE` smyčky přidán `AND b.status IN ('reserved','active')`.
-- Beze změny: `release_withheld_door_codes()` (wrapper delegující sem),
--   `check_booking_docs_status` (hardening fotka/OCR + expirace ŘP z 20260520).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.release_withheld_door_codes_for_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_booking record;
  v_withheld text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  FOR v_booking IN
    SELECT DISTINCT b.id AS booking_id, b.user_id, b.start_date, b.end_date
    FROM bookings b
    JOIN branch_door_codes bdc ON bdc.booking_id = b.id
    WHERE b.user_id = p_user_id
      AND b.status IN ('reserved','active')   -- POJISTKA: jen aktivní/nadcházející rezervace
      AND bdc.is_active = true
      AND bdc.sent_to_customer = false
  LOOP
    v_withheld := check_booking_docs_status(v_booking.user_id, v_booking.end_date::date);
    IF v_withheld IS NOT NULL THEN
      -- Aktualizuj jen důvod (třeba z "Chybí doklady" na "ŘP propadlý")
      UPDATE branch_door_codes
      SET withheld_reason = v_withheld
      WHERE booking_id = v_booking.booking_id
        AND is_active = true
        AND sent_to_customer = false
        AND withheld_reason IS DISTINCT FROM v_withheld;
      CONTINUE; -- neuvolňujeme
    END IF;

    -- Uvolni
    UPDATE branch_door_codes
    SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false;

    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || COALESCE(v_code_moto,'–') || E'\n' ||
        'Kód k příslušenství: ' || COALESCE(v_code_gear,'–') || E'\n' ||
        'Kódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(v_booking.start_date::date,'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date,'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone, 'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text,8)),
            'door_code_moto', COALESCE(v_code_moto,'–'),
            'door_code_gear', COALESCE(v_code_gear,'–')
          ), v_booking.user_id, v_booking.booking_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM send_door_codes_email(v_booking.booking_id, v_booking.user_id);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes_for_user failed: %', SQLERRM;
END;
$function$;
