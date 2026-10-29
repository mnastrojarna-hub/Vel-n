-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — uvolnění zadržených kódů (3/14)
-- release_my_door_codes (appka), release_withheld_door_codes_for_user (doklady / cron): výbava = kotva kód šatny.
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.release_my_door_codes(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_booking record;
  v_reason text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int := 0;
  v_branch uuid;
  v_gate text;
  v_door integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT id, user_id, start_date, end_date, status, moto_id, booking_kind
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;
  -- 2026-10-10 (20261010g): jen živá rezervace (ne pending / zrušená / dokončená)
  IF v_booking.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not active');
  END IF;

  -- Kód držený VÝMĚNOU motorky uvolní až vrácení původní motorky — nikdy doklady.
  IF NOT EXISTS (
    SELECT 1 FROM branch_door_codes
    WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false
      AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
    LIMIT 1
  ) THEN
    IF EXISTS (SELECT 1 FROM branch_door_codes
                WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false) THEN
      RETURN jsonb_build_object('success', false, 'released', 0, 'error', 'Vraťte nejdřív původní motorku',
                                'withheld_reason', 'Vraťte nejdřív původní motorku');
    END IF;
    RETURN jsonb_build_object('success', true, 'released', 0, 'message', 'No withheld codes');
  END IF;

  -- 2026-10-10: přísná brána rezervace (OP líc+rub / pas, ŘP líc+rub, 18+, platnost, skupina)
  v_reason := public.booking_docs_gate(p_booking_id);
  IF v_reason IS NOT NULL THEN
    UPDATE branch_door_codes SET withheld_reason = v_reason
     WHERE booking_id = p_booking_id AND is_active AND sent_to_customer = false
       AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
       AND withheld_reason IS DISTINCT FROM v_reason;
    RETURN jsonb_build_object('success', false, 'error', 'Documents missing', 'withheld_reason', v_reason);
  END IF;

  UPDATE branch_door_codes
  SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
  WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false
    AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
  GET DIAGNOSTICS v_released = ROW_COUNT;

  -- 2026-10-23: výpůjčka výbavy — jen kód šatny (bez kódu motorky); zpráva/SMS/e-mail přes gear notifikátor
  IF v_booking.booking_kind = 'gear' THEN
    IF NOT public._gear_door_codes_notify(p_booking_id, NULL, false, true) THEN
      RETURN jsonb_build_object('success', false, 'released', 0, 'error', 'Documents missing',
                                'withheld_reason', public.booking_docs_gate(p_booking_id));
    END IF;
    RETURN jsonb_build_object('success', true, 'released', v_released);
  END IF;

  SELECT door_code INTO v_code_moto FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer LIMIT 1;
  IF v_code_moto IS NULL THEN
    RETURN jsonb_build_object('success', false, 'released', 0, 'error', 'Documents missing',
                              'withheld_reason', public.booking_docs_gate(p_booking_id));
  END IF;
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer LIMIT 1;

  -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
  SELECT branch_id INTO v_branch FROM motorcycles WHERE id = v_booking.moto_id;
  v_gate := public._booking_gate_code(p_booking_id);   -- NULL u přistavení na adresu
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (
      v_uid,
      'Přístupové kódy k pobočce',
      public._door_codes_msg_lines(v_gate, v_door, v_code_gear, v_code_moto) || E'\n' ||
      public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, true) ||
      TO_CHAR(v_booking.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_booking.end_date::date, 'DD.MM.YYYY') || ').' ||
      public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
      'door_codes'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'release_my_door_codes: admin_message insert failed: %', SQLERRM;
  END;

  BEGIN
    SELECT phone INTO v_phone FROM profiles WHERE id = v_uid;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
      PERFORM send_sms_and_wa(
        v_phone,
        public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', v_code_moto,
          'door_code_gear', COALESCE(v_code_gear, '')
        ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
        v_uid, p_booking_id, public._door_codes_sms_lang(v_uid, p_booking_id)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'release_my_door_codes: SMS/WA failed: %', SQLERRM;
  END;

  PERFORM send_door_codes_email(p_booking_id, v_uid);

  RETURN jsonb_build_object('success', true, 'released', v_released);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.release_withheld_door_codes_for_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_booking record;
  v_withheld text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int;
  v_branch uuid;
  v_gate text;
  v_door integer;
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
      -- kódy držené kvůli nevrácené původní motorce uvolní až vrácení stroje
      AND bdc.withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
  LOOP
    -- 2026-10-10: přísná brána PER REZERVACE (motorka → skupina / dětská, začátek → věk)
    v_withheld := public.booking_docs_gate(v_booking.booking_id);
    IF v_withheld IS NOT NULL THEN
      UPDATE branch_door_codes
      SET withheld_reason = v_withheld
      WHERE booking_id = v_booking.booking_id
        AND is_active = true
        AND sent_to_customer = false
        AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
        AND withheld_reason IS DISTINCT FROM v_withheld;
      CONTINUE; -- neuvolňujeme
    END IF;

    UPDATE branch_door_codes
    SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false
      AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released = 0 THEN CONTINUE; END IF;

    -- 2026-10-23: výpůjčka výbavy — kotva = kód šatny; zpráva (č. rezervace) + SMS/WA + e-mail přes gear notifikátor
    IF public._booking_is_gear(v_booking.booking_id) THEN
      BEGIN
        PERFORM public._gear_door_codes_notify(v_booking.booking_id, NULL, false, true);
      EXCEPTION WHEN OTHERS THEN NULL; END;
      CONTINUE;
    END IF;

    -- Do zprávy JEN opravdu vydané kódy (pojistka trg_zz_door_codes_docs_gate)
    v_code_moto := NULL; v_code_gear := NULL;
    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer LIMIT 1;
    IF v_code_moto IS NULL THEN CONTINUE; END IF;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer LIMIT 1;

    -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
    SELECT m.branch_id INTO v_branch FROM bookings b JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.id = v_booking.booking_id;
    v_gate := public._booking_gate_code(v_booking.booking_id);   -- NULL u přistavení na adresu
    v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        public._door_codes_msg_lines(v_gate, v_door, v_code_gear, v_code_moto) || E'\n' ||
        public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, true) ||
        TO_CHAR(v_booking.start_date::date,'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date,'DD.MM.YYYY') || ').' ||
        public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone,
          public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text,8)),
            'door_code_moto', v_code_moto,
            'door_code_gear', COALESCE(v_code_gear,'')
          ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
          v_booking.user_id, v_booking.booking_id,
          public._door_codes_sms_lang(v_booking.user_id, v_booking.booking_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM send_door_codes_email(v_booking.booking_id, v_booking.user_id);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes_for_user failed: %', SQLERRM;
END;
$function$
;
