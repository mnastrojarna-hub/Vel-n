-- =============================================================================
-- Velké Němčice: kód brány ve zprávách s kódy — UVOLNĚNÍ ZADRŽENÝCH KÓDŮ
-- Migrace: 20261004c_vn_gate_codes_release.sql (3/5; potřebuje 20261004_vn_gate_access.sql)
--
-- release_my_door_codes (zákazník doplnil doklady v appce/na webu),
-- release_withheld_door_codes_for_user (doklady nahrány / ověřeny) a
-- release_swap_next_codes (vrácena původní motorka při výměně): u pobočky
-- s bránou zpráva v appce (+ push) v pořadí BRÁNA → ŠATNA (dveře č. N) →
-- MOTORKA + stručný postup; SMS/WA šablony door_codes_gate*.
-- Pobočky bez brány: text i šablony beze změny.
--
-- Navíc všechny tři posílají SMS/WA v jazyce zákazníka přes _door_codes_sms_lang
-- (rezervace → profil, jen jazyky se šablonami, jinak cs; release_my a
-- release_withheld dřív vždy cs). Šablony existují ve všech 8 jazycích
-- (uk doplňuje 20261004d).
--
-- Těla 1:1 z živé DB (supabase-live-snapshot 2026-10-03, shodná s migrací
-- 20260925a_locker_codes_own_gear.sql) kromě označených změn.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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

  SELECT id, user_id, start_date, end_date, status, moto_id
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
  END IF;

  -- Existují zadržené kódy?
  IF NOT EXISTS (
    SELECT 1 FROM branch_door_codes
    WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false
    LIMIT 1
  ) THEN
    RETURN jsonb_build_object('success', true, 'released', 0, 'message', 'No withheld codes');
  END IF;

  -- KANONICKÁ kontrola dokladů: fotka NEBO OCR verified_at + expirace ŘP + child-bike skip
  v_reason := check_booking_docs_status(v_uid, v_booking.end_date::date, v_booking.moto_id);
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Documents missing', 'withheld_reason', v_reason);
  END IF;

  -- Uvolni kódy
  UPDATE branch_door_codes
  SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
  WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false;
  GET DIAGNOSTICS v_released = ROW_COUNT;

  SELECT door_code INTO v_code_moto FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

  -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
  SELECT branch_id INTO v_branch FROM motorcycles WHERE id = v_booking.moto_id;
  v_gate := public._branch_gate_code(v_branch);
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (
      v_uid,
      'Přístupové kódy k pobočce',
      public._door_codes_msg_lines(v_gate, v_door, v_code_gear, COALESCE(v_code_moto, '–')) || E'\n' ||
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
          'door_code_moto', COALESCE(v_code_moto, '–'),
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
$$;

CREATE OR REPLACE FUNCTION "public"."release_withheld_door_codes_for_user"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
      -- NOVÉ: kódy držené kvůli nevrácené původní motorce sem nepatří —
      -- ty uvolní až vrácení stroje (trg_release_swap_next_codes).
      AND bdc.withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
  LOOP
    v_withheld := check_booking_docs_status(v_booking.user_id, v_booking.end_date::date);
    IF v_withheld IS NOT NULL THEN
      -- Aktualizuj jen důvod (třeba z "Chybí doklady" na "ŘP propadlý")
      UPDATE branch_door_codes
      SET withheld_reason = v_withheld
      WHERE booking_id = v_booking.booking_id
        AND is_active = true
        AND sent_to_customer = false
        AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
        AND withheld_reason IS DISTINCT FROM v_withheld;
      CONTINUE; -- neuvolňujeme
    END IF;

    -- Uvolni (kromě kódů čekajících na vrácení původní motorky)
    UPDATE branch_door_codes
    SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false
      AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released = 0 THEN CONTINUE; END IF;

    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

    -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
    SELECT m.branch_id INTO v_branch FROM bookings b JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.id = v_booking.booking_id;
    v_gate := public._branch_gate_code(v_branch);
    v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        public._door_codes_msg_lines(v_gate, v_door, v_code_gear, COALESCE(v_code_moto,'–')) || E'\n' ||
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
            'door_code_moto', COALESCE(v_code_moto,'–'),
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
$$;

CREATE OR REPLACE FUNCTION "public"."release_swap_next_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  r            record;
  v_released   int;
  v_code_moto  text;
  v_code_gear  text;
  v_branch     text;
  v_box        integer;
  v_phone      text;
  v_lang       text;
  v_start      date;
  v_end        date;
  v_branch_id  uuid;
  v_gate       text;
  v_door       integer;
BEGIN
  FOR r IN
    SELECT b.id AS booking_id, b.user_id,
           -- Doklady se musí ověřit ZNOVU: `withhold_swap_next_codes` (BEFORE INSERT)
           -- přepsal případný důvod „Chybí doklady" svým „Vraťte nejdřív původní
           -- motorku", takže bez téhle kontroly by se kód uvolnil i zákazníkovi
           -- s chybějícím / propadlým dokladem.
           CASE WHEN m.license_required::text = 'N' THEN NULL
                ELSE check_booking_docs_status(b.user_id, b.end_date::date, b.moto_id) END AS docs_reason
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.continues_booking_id = NEW.id
       AND b.status IN ('reserved','active','pending')
  LOOP
    IF r.docs_reason IS NOT NULL THEN
      -- Motorka je vrácená, ale kód drží doklady → přepiš důvod, ať zákazník
      -- i Velín vidí, na čem to stojí (uvolní ho pak standardní doklad-flow).
      UPDATE branch_door_codes
         SET withheld_reason = r.docs_reason
       WHERE booking_id = r.booking_id AND is_active = true
         AND withheld_reason = 'Vraťte nejdřív původní motorku';
      CONTINUE;
    END IF;

    UPDATE branch_door_codes
       SET sent_to_customer = true, sent_at = now(), withheld_reason = NULL
     WHERE booking_id = r.booking_id AND is_active = true
       AND withheld_reason = 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released = 0 THEN CONTINUE; END IF;

    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = r.booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = r.booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;
    SELECT br.name, m.box_number, b.start_date::date, b.end_date::date, m.branch_id
      INTO v_branch, v_box, v_start, v_end, v_branch_id
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
      LEFT JOIN branches br   ON br.id = m.branch_id
     WHERE b.id = r.booking_id;

    -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
    v_gate := public._branch_gate_code(v_branch_id);
    v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch_id) END;

    -- a) in-app zpráva (+ push přes trg_push_on_admin_message) — zákazník stojí
    --    u kóje, e-mail sám o sobě nestačí
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (r.user_id, 'Nové přístupové kódy',
        'Původní motorka je vrácená — tady jsou kódy k nové:' || E'\n' ||
        public._door_codes_msg_lines(v_gate, v_door, v_code_gear, COALESCE(v_code_moto, '—')) || E'\n' ||
        public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, false) ||
        TO_CHAR(v_start, 'DD.MM.YYYY') || ' – ' || TO_CHAR(v_end, 'DD.MM.YYYY') || ').' ||
        CASE WHEN v_branch IS NOT NULL THEN E'\nPobočka: ' || v_branch ELSE '' END ||
        CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END ||
        public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
        'door_codes');
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- b) SMS + WhatsApp (stejně jako při vydání kódů)
    BEGIN
      SELECT phone, COALESCE(language, 'cs') INTO v_phone, v_lang FROM profiles WHERE id = r.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' AND v_code_moto IS NOT NULL THEN
        PERFORM send_sms_and_wa(v_phone,
          public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
          jsonb_build_object(
            'booking_number', upper(left(r.booking_id::text, 8)),
            'door_code_moto', v_code_moto,
            'door_code_gear', COALESCE(v_code_gear, '')
          ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
          r.user_id, r.booking_id, public._door_codes_sms_lang(r.user_id, r.booking_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- c) e-mail (beze změny; dedup GUC brání dvojímu odeslání)
    BEGIN PERFORM send_door_codes_email(r.booking_id, r.user_id); EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_swap_next_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$;
