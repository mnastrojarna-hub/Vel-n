-- ============================================================================
-- PŘÍSTUPOVÉ KÓDY JEN S KOMPLETNÍMI DOKLADY — opravy ze závěrečného review 1/2 (2026-10-10)
-- `20261010*` a–f už jsou aplikované (auto-deploy) → opravy jdou sem; body 3–5 v `20261010h`.
-- 1) OBCHVAT (ověřeno na kopii živé DB): zákazník si přímým REST zápisem
--    přepnul zaplacenou rezervaci z `reserved` na `pending` a pak `moto_id`
--    (dětská motorka bez dokladů → vydané kódy → zpět dospělá motorka). U
--    `pending` se kódy při změně motorky nepřepočítávají → kiosk otevřel box
--    dospělé motorky bez dokladů. `_guard_customer_booking_status`: zákazník
--    smí do `pending` jen ze zrušené (obnovení v appce), nikdy z reserved/active.
-- 2) `_door_codes_follow_moto`: doklady znovu i při jiné SADĚ skupin ŘP
--    (license_groups, ne jen license_required), přes `booking_docs_gate`;
--    u PŘEVZATÉ rezervace se už vydaný kód nikdy nezamkne; do zprávy jen
--    vydané kódy. Jinak tělo 1:1.
-- 3) `release_my_door_codes`: jen rezervace reserved/active.
-- 4) Pobočka rezervace: navazující rezervace (`extends_booking_id`) jde s
--    motorkou, dokud původní není vyzvednutá (dřív zůstala na staré pobočce).
-- 5) `ai_booking_readiness` (anon, jen číslo rezervace): důvody bez věku a
--    data platnosti ŘP; brána `booking_docs_gate`.
-- ============================================================================

-- 1) ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._guard_customer_booking_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user NOT IN ('anon', 'authenticated') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.payment_status := 'unpaid';
    RETURN NEW;
  END IF;
  -- Zrušení ano; zpět do `pending` jen obnovení zrušené (appka) — NIKDY reserved/active → pending
  -- (zmrazení kódů: pending rezervaci se při změně motorky kódy nepřepočítávají, 20261010g).
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT (NEW.status = 'cancelled' OR (NEW.status = 'pending' AND OLD.status IN ('pending', 'cancelled'))) THEN
    NEW.status := OLD.status;
  END IF;
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NEW.payment_status IS DISTINCT FROM 'unpaid' THEN
    NEW.payment_status := OLD.payment_status;
  END IF;
  RETURN NEW;
END;
$function$;

-- 2) ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._door_codes_follow_moto(p_booking_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b record; v_branch uuid; v_box integer; v_branch_name text;
  r record; v_new text; v_moved boolean := false; v_changed boolean := false;
  v_code_moto text; v_code_gear text; v_all_sent boolean; v_gate text; v_door integer; v_phone text;
  v_old_moto uuid; v_old_lic text; v_new_lic text; v_withheld text; v_released integer := 0; v_intro text;
  v_old_grp text[]; v_new_grp text[]; v_picked boolean;
BEGIN
  SELECT id, user_id, moto_id, status, is_test, start_date, end_date, picked_up_at INTO v_b FROM bookings WHERE id = p_booking_id;
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
    -- 2026-10-10 (20261010g): i jiná SADA skupin ŘP (license_groups) při stejné license_required
    SELECT license_required::text,
           (SELECT array_agg(g ORDER BY g) FROM unnest(COALESCE(NULLIF(license_groups, '{}'::text[]), ARRAY[license_required::text])) g)
      INTO v_old_lic, v_old_grp FROM motorcycles WHERE id = v_old_moto;
    SELECT license_required::text,
           (SELECT array_agg(g ORDER BY g) FROM unnest(COALESCE(NULLIF(license_groups, '{}'::text[]), ARRAY[license_required::text])) g)
      INTO v_new_lic, v_new_grp FROM motorcycles WHERE id = v_b.moto_id;
    v_picked := v_b.picked_up_at IS NOT NULL;
    IF v_old_lic IS DISTINCT FROM v_new_lic OR v_old_grp IS DISTINCT FROM v_new_grp THEN
      v_withheld := public.booking_docs_gate(p_booking_id);   -- přísná brána (dětská motorka uvnitř)
      IF v_withheld IS NOT NULL THEN
        -- probíhající pronájem: už VYDANÝ kód nikdy nezamknout (zákazník musí motorku vrátit)
        UPDATE branch_door_codes SET sent_to_customer = false, withheld_reason = v_withheld
         WHERE booking_id = p_booking_id AND is_active
           AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
           AND NOT (v_picked AND sent_to_customer IS TRUE);
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
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer ORDER BY created_at DESC LIMIT 1;
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer ORDER BY created_at DESC LIMIT 1;
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
END $function$;
