-- 2026-10-05: přesun motorky rezervace na JINOU pobočku (Flotila → Přesunout) a uvolnění kódů po změně kategorie ŘP:
-- zákazník dostával zprávu v appce + push + SMS/WA, ale e-mail s novou pobočkou, kódem brány a postupem NE —
-- čísla kódů se při přesunu nemění (20261005e), created_at zůstal z prvního vydání a dedup send_door_codes_email
-- (message_log.created_at >= max(created_at kódů)) mail zahodil. Oprava: před oznámením created_at vydaných kódů
-- = now() (jako p_bump v _door_codes_notify). Dvojímu mailu v jedné transakci brání GUC v send_door_codes_email.
-- Zbytek funkce beze změny (20261005e). Idempotentní (CREATE OR REPLACE).

CREATE OR REPLACE FUNCTION public._door_codes_follow_moto(p_booking_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_b record; v_branch uuid; v_box integer; v_branch_name text;
  r record; v_new text; v_moved boolean := false; v_changed boolean := false;
  v_code_moto text; v_code_gear text; v_all_sent boolean; v_gate text; v_door integer; v_phone text;
  v_old_moto uuid; v_old_lic text; v_new_lic text; v_withheld text; v_released integer := 0; v_intro text;
BEGIN
  SELECT id, user_id, moto_id, status, is_test, start_date, end_date INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.is_test IS TRUE OR v_b.status NOT IN ('active','reserved') THEN RETURN; END IF;
  SELECT m.branch_id, m.box_number, br.name INTO v_branch, v_box, v_branch_name
    FROM motorcycles m LEFT JOIN branches br ON br.id = m.branch_id WHERE m.id = v_b.moto_id;

  IF NOT EXISTS (SELECT 1 FROM branch_door_codes WHERE booking_id = p_booking_id AND is_active) THEN
    PERFORM regen_door_codes_for_booking(p_booking_id, p_reason);   -- první vydání (doklady, zprávy)
    RETURN;
  END IF;

  IF v_branch IS NULL THEN   -- motorka mimo pobočku → kódy nic neotevřou (jako dřív)
    UPDATE branch_door_codes SET is_active = false WHERE booking_id = p_booking_id AND is_active;
    RETURN;
  END IF;

  FOR r IN SELECT * FROM branch_door_codes WHERE booking_id = p_booking_id AND is_active ORDER BY code_type LOOP
    IF r.moto_id IS DISTINCT FROM v_b.moto_id AND r.moto_id IS NOT NULL THEN v_old_moto := r.moto_id; END IF;
    IF r.branch_id IS DISTINCT FROM v_branch THEN
      v_moved := true;
      IF EXISTS (SELECT 1 FROM branch_door_codes c
                  WHERE c.branch_id = v_branch AND c.door_code = r.door_code AND c.is_active AND c.id <> r.id)
         OR EXISTS (SELECT 1 FROM branch_service_codes s WHERE s.branch_id = v_branch AND s.code = r.door_code) THEN
        LOOP   -- číslo na cílové pobočce už někdo má → nové (nikdy dvě rezervace se stejným kódem)
          v_new := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
          EXIT WHEN NOT EXISTS (SELECT 1 FROM branch_door_codes c
                                 WHERE c.branch_id = v_branch AND c.door_code = v_new AND c.is_active)
                AND NOT EXISTS (SELECT 1 FROM branch_service_codes s WHERE s.branch_id = v_branch AND s.code = v_new);
        END LOOP;
        UPDATE branch_door_codes SET is_active = false, superseded_by_regen = true WHERE id = r.id;
        INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code, is_active,
                                       valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
        VALUES (v_branch, p_booking_id, v_b.moto_id, r.code_type, v_new, true,
                r.valid_from, r.valid_until, r.sent_to_customer, r.sent_at, r.withheld_reason);
        v_changed := true;
      ELSE
        UPDATE branch_door_codes SET branch_id = v_branch, moto_id = v_b.moto_id WHERE id = r.id;
      END IF;
    ELSIF r.moto_id IS DISTINCT FROM v_b.moto_id THEN
      UPDATE branch_door_codes SET moto_id = v_b.moto_id WHERE id = r.id;
    END IF;
  END LOOP;

  -- jiná motorka jiné kategorie ŘP → doklady znovu (dřív to dělala regenerace): bez ověřeného ŘP kód zadržet,
  -- motorka bez ŘP → kód zadržený kvůli dokladům uvolnit. Stejná kategorie = beze změny (ruční „Odeslat“ platí).
  IF v_old_moto IS NOT NULL THEN
    SELECT license_required::text INTO v_old_lic FROM motorcycles WHERE id = v_old_moto;
    SELECT license_required::text INTO v_new_lic FROM motorcycles WHERE id = v_b.moto_id;
    IF v_old_lic IS DISTINCT FROM v_new_lic THEN
      v_withheld := CASE WHEN v_new_lic = 'N' THEN NULL
                         ELSE check_booking_docs_status(v_b.user_id, v_b.end_date::date, v_b.moto_id) END;
      IF v_withheld IS NOT NULL THEN
        UPDATE branch_door_codes SET sent_to_customer = false, withheld_reason = v_withheld
         WHERE booking_id = p_booking_id AND is_active
           AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
      ELSE
        UPDATE branch_door_codes SET sent_to_customer = true, sent_at = now(), withheld_reason = NULL
         WHERE booking_id = p_booking_id AND is_active AND NOT coalesce(sent_to_customer, false)
           AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
           AND withheld_reason IS DISTINCT FROM 'Vlastní výbava';
        GET DIAGNOSTICS v_released = ROW_COUNT;
      END IF;
    END IF;
  END IF;
  -- výměna motorky na samoobslužné pobočce: kód motorky až po vrácení původní (jako withhold_swap_next_codes u INSERT)
  IF (v_moved OR v_old_moto IS NOT NULL) AND public._swap_predecessor_pending(p_booking_id, v_branch) THEN
    UPDATE branch_door_codes SET sent_to_customer = false, withheld_reason = 'Vraťte nejdřív původní motorku'
     WHERE booking_id = p_booking_id AND is_active AND code_type = 'motorcycle';
  END IF;

  -- offline cache jednotky (kóje motorky / řádky kódů) — trg_door_codes_kiosk_sync na moto_id nereaguje
  PERFORM public.kiosk_request_sync(v_branch);
  -- jiná kóje / motorka na téže pobočce: kódy platí dál, kóji ukáže kiosk → bez zprávy
  IF NOT v_moved AND v_released = 0 THEN RETURN; END IF;
  v_intro := CASE WHEN v_moved THEN 'Vaše motorka byla přesunuta na pobočku ' || coalesce(v_branch_name, '') ||
                                    CASE WHEN v_changed THEN ' – nové kódy:' ELSE ' – kódy platí dál:' END
                  ELSE 'Vaše přístupové kódy jsou uvolněné:' END;

  -- zákazník musí vědět kam / že kódy platí (appka + SMS/WA + mail), jen u vydaných kódů
  SELECT bool_and(sent_to_customer) INTO v_all_sent FROM branch_door_codes WHERE booking_id = p_booking_id AND is_active;
  IF NOT coalesce(v_all_sent, false) THEN RETURN; END IF;
  -- 2026-10-05: mail musí odejít, i když čísla zůstala (send_door_codes_email deduplikuje podle created_at kódů —
  -- přenesený kód má created_at z prvního vydání → mail o nové pobočce / uvolnění kódů se dřív neposlal)
  UPDATE branch_door_codes SET created_at = now()
   WHERE booking_id = p_booking_id AND is_active AND sent_to_customer;
  SELECT door_code INTO v_code_moto FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active ORDER BY created_at DESC LIMIT 1;
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active ORDER BY created_at DESC LIMIT 1;
  v_gate := public._booking_gate_code(p_booking_id);
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

  BEGIN
    INSERT INTO admin_messages (user_id, booking_id, title, message, type)
    VALUES (v_b.user_id, p_booking_id, CASE WHEN v_moved THEN 'Přístupové kódy — jiná pobočka' ELSE 'Přístupové kódy' END,
      v_intro || E'\n' ||
      public._door_codes_msg_lines(v_gate, v_door, v_code_gear, coalesce(v_code_moto, '—')) || E'\n' ||
      public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, false) ||
      TO_CHAR(v_b.start_date::date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(v_b.end_date::date, 'DD.MM.YYYY') || ').' ||
      CASE WHEN v_branch_name IS NOT NULL THEN E'\nPobočka: ' || v_branch_name ELSE '' END ||
      CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END ||
      public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
      'door_codes');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT phone INTO v_phone FROM profiles WHERE id = v_b.user_id;
    IF v_phone IS NOT NULL AND v_phone <> '' AND v_code_moto IS NOT NULL THEN
      PERFORM send_sms_and_wa(v_phone,
        public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
        jsonb_build_object('booking_number', upper(left(p_booking_id::text, 8)),
                           'door_code_moto', v_code_moto, 'door_code_gear', coalesce(v_code_gear, ''))
          || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
        v_b.user_id, p_booking_id, public._door_codes_sms_lang(v_b.user_id, p_booking_id));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN PERFORM send_door_codes_email(p_booking_id, v_b.user_id); EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;
ALTER FUNCTION public._door_codes_follow_moto(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._door_codes_follow_moto(uuid, text) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public._door_codes_follow_moto(uuid, text) IS
  'Kódy rezervace následují její motorku (2026-10-05): jiná kóje / motorka na téže pobočce = čísla beze změny; jiná pobočka = táž čísla přenesená (nové jen při kolizi) + zpráva zákazníkovi; jiná kategorie ŘP = doklady znovu (zadržet / uvolnit + zpráva); výměna motorky na samoobsluze = zadržet do vrácení původní; bez aktivního kódu = regen_door_codes_for_booking (první vydání); motorka bez pobočky = zneplatnit.';
