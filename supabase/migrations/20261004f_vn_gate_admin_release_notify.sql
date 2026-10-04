-- =============================================================================
-- Velké Němčice / kódy: RPC pro Velín — ruční uvolnění kódů a dopo­slání kódu brány
-- Migrace: 20261004f_vn_gate_admin_release_notify.sql (6/6; potřebuje 20261004_…d)
--
-- 1) _door_codes_notify(p_booking_id, p_title, p_intro, p_bump) — INTERNÍ: jedno
--    místo, které zákazníkovi oznámí AKTUÁLNÍ vydané kódy rezervace stejně jako
--    automatické uvolnění: zpráva v appce (+ push) v pořadí brána → šatna
--    (dveře č. N) → motorka + postup u pobočky s bránou, SMS/WA (slug podle
--    brány, jazyk zákazníka) a e-mail (send_door_codes_email). `p_bump` posune
--    created_at vydaných kódů → dedup mailu je bere jako „nově vydané“ (jinak by
--    send_door_codes_email mail přeskočil — kódy se nezměnily).
-- 2) admin_release_door_codes(p_booking_id) — Velín „Odeslat“ u zadrženého kódu
--    (obsluha ověřila doklady osobně): uvolní VŠECHNY zadržené aktivní kódy
--    rezervace kromě držených výměnou motorky a pošle zprávu + SMS/WA + e-mail.
--    Dřív Velín jen přepnul sent_to_customer a vložil info zprávu — bez SMS a
--    e-mailu (SMS šla dřív předčasně už při vložení kódu, 20261004d to zrušilo).
-- 3) admin_notify_branch_gate_code(p_branch_id, p_dry_run) — po zadání / změně /
--    zapnutí kódu brány ve Velínu: každé reserved/active rezervaci motorky
--    z pobočky s vydaným kódem motorky dopošle aktuální kódy včetně kódu brány
--    (zákazníci, kteří kódy dostali před zavedením brány, by jinak kód schránky
--    neměli). p_dry_run = jen počet.
--
-- Idempotentní (CREATE OR REPLACE). Oprávnění: admin RPC jen authenticated
-- (uvnitř is_admin()) + service_role; interní helper jen service_role.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._door_codes_notify(p_booking_id uuid, p_title text, p_intro text DEFAULT NULL, p_bump boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b record;
  v_code_moto text;
  v_code_gear text;
  v_gate text;
  v_door integer;
  v_phone text;
BEGIN
  SELECT b.id, b.user_id, b.start_date, b.end_date, m.branch_id, m.box_number, br.name AS branch_name
    INTO v_b
    FROM bookings b
    LEFT JOIN motorcycles m ON m.id = b.moto_id
    LEFT JOIN branches br ON br.id = m.branch_id
   WHERE b.id = p_booking_id;
  IF NOT FOUND OR v_b.user_id IS NULL THEN RETURN false; END IF;

  SELECT door_code INTO v_code_moto FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer
   ORDER BY created_at DESC LIMIT 1;
  IF v_code_moto IS NULL THEN RETURN false; END IF;   -- bez vydaného kódu motorky není co oznámit
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer
   ORDER BY created_at DESC LIMIT 1;

  v_gate := public._branch_gate_code(v_b.branch_id);
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_b.branch_id) END;

  IF p_bump THEN
    UPDATE branch_door_codes SET created_at = now()
     WHERE booking_id = p_booking_id AND is_active AND sent_to_customer;
  END IF;

  BEGIN
    INSERT INTO admin_messages (user_id, booking_id, title, message, type)
    VALUES (v_b.user_id, p_booking_id, p_title,
      COALESCE(p_intro || E'\n', '') ||
      public._door_codes_msg_lines(v_gate, v_door, v_code_gear, v_code_moto) || E'\n' ||
      public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, true) ||
      TO_CHAR(v_b.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_b.end_date::date, 'DD.MM.YYYY') || ').' ||
      CASE WHEN v_b.branch_name IS NOT NULL THEN E'\nPobočka: ' || v_b.branch_name ELSE '' END ||
      CASE WHEN v_b.box_number IS NOT NULL AND v_b.box_number > 0 THEN E'\nKóje: ' || v_b.box_number ELSE '' END ||
      public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
      'door_codes');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_door_codes_notify: admin_message insert failed: %', SQLERRM;
  END;

  BEGIN
    SELECT phone INTO v_phone FROM profiles WHERE id = v_b.user_id;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
      PERFORM send_sms_and_wa(v_phone,
        public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', v_code_moto,
          'door_code_gear', COALESCE(v_code_gear, '')
        ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
        v_b.user_id, p_booking_id, public._door_codes_sms_lang(v_b.user_id, p_booking_id));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_door_codes_notify: SMS/WA failed: %', SQLERRM;
  END;

  PERFORM send_door_codes_email(p_booking_id, v_b.user_id);
  RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.admin_release_door_codes(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_released integer := 0;
  v_swap integer := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM bookings WHERE id = p_booking_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  UPDATE branch_door_codes
     SET sent_to_customer = true, sent_at = now(), withheld_reason = NULL
   WHERE booking_id = p_booking_id AND is_active AND sent_to_customer = false
     AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
  GET DIAGNOSTICS v_released = ROW_COUNT;
  SELECT count(*) INTO v_swap FROM branch_door_codes
   WHERE booking_id = p_booking_id AND is_active AND sent_to_customer = false;

  IF v_released = 0 THEN
    RETURN jsonb_build_object('success', false, 'released', 0,
      'error', CASE WHEN v_swap > 0 THEN 'Vraťte nejdřív původní motorku' ELSE 'Žádné zadržené kódy' END);
  END IF;

  PERFORM public._door_codes_notify(p_booking_id, 'Přístupové kódy k pobočce', NULL, false);
  RETURN jsonb_build_object('success', true, 'released', v_released, 'swap_withheld', v_swap);
END $$;

CREATE OR REPLACE FUNCTION public.admin_notify_branch_gate_code(p_branch_id uuid, p_dry_run boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  v_n integer := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF public._branch_gate_code(p_branch_id) IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_active_gate');
  END IF;

  FOR r IN
    SELECT b.id
      FROM bookings b
      JOIN motorcycles m ON m.id = b.moto_id
     WHERE m.branch_id = p_branch_id
       AND b.is_test IS NOT TRUE
       AND b.status IN ('reserved', 'active')
       AND b.end_date::date >= (now() AT TIME ZONE 'Europe/Prague')::date
       AND EXISTS (SELECT 1 FROM branch_door_codes c
                    WHERE c.booking_id = b.id AND c.code_type = 'motorcycle'
                      AND c.is_active AND c.sent_to_customer)
     ORDER BY b.start_date
  LOOP
    IF p_dry_run THEN
      v_n := v_n + 1;
      CONTINUE;
    END IF;
    BEGIN
      IF public._door_codes_notify(r.id, 'Kód schránky s klíčem od brány',
           'K vaší rezervaci přibyl kód schránky s klíčem od vjezdové brány — aktuální kódy:', true) THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'admin_notify_branch_gate_code %: %', r.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_n, 'notified', CASE WHEN p_dry_run THEN 0 ELSE v_n END);
END $$;

REVOKE ALL ON FUNCTION public._door_codes_notify(uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._door_codes_notify(uuid, text, text, boolean) TO service_role;
REVOKE ALL ON FUNCTION public.admin_release_door_codes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_release_door_codes(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_notify_branch_gate_code(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_notify_branch_gate_code(uuid, boolean) TO authenticated, service_role;
