-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — oznámení vydaného kódu (1a/14)
-- Odděleno z 20261023c_gear_booking_codes.sql kvůli limitu velikosti souboru
-- (CLAUDE.md; FIX-R1). Aplikuje se hned po něm (bytové pořadí: '.' < '_'),
-- před _b_notify; volající (plpgsql) se vážou až za běhu.
--  • _gear_door_codes_sms_slug: slug SMS/WA šablony — brána / bez brány / obslužná
--    pobočka (door_codes_gear_staffed, FIX-R1; šablony v _l_sms)
--  • _gear_door_codes_sms: SMS + WhatsApp s VYDANÝM kódem (+ kód brány)
--  • _gear_door_codes_notify: in-app zpráva (+ push), SMS/WA, e-mail s kódy
-- Idempotentní (DROP IF EXISTS staré signatury / CREATE OR REPLACE).
-- =============================================================================

-- Slug SMS/WA šablony (Velín → Zprávy → Šablony): brána (Velké Němčice) / bez brány / obslužná (FIX-R1).
DROP FUNCTION IF EXISTS public._gear_door_codes_sms_slug(boolean);
CREATE OR REPLACE FUNCTION public._gear_door_codes_sms_slug(p_has_gate boolean, p_self_service boolean DEFAULT true)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_has_gate THEN 'door_codes_gate_gear_only'
              WHEN p_self_service IS NOT TRUE THEN 'door_codes_gear_staffed'
              ELSE 'door_codes_gear_only' END;
$$;

-- SMS + WhatsApp s kódem šatny (+ brány). p_dedup = trigger při vložení kódu: už odeslaná SMS výbavy → nic.
-- Číslo rezervace = posledních 8 znaků (shodně s e-maily, webem a appkou).
CREATE OR REPLACE FUNCTION public._gear_door_codes_sms(p_booking_id uuid, p_dedup boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b record; v_code text; v_gate text; v_door integer; v_phone text;
BEGIN
  SELECT b.user_id, b.branch_id, b.start_date, b.end_date INTO v_b
    FROM bookings b WHERE b.id = p_booking_id AND b.booking_kind = 'gear';
  IF NOT FOUND OR v_b.user_id IS NULL THEN RETURN; END IF;
  IF p_dedup AND EXISTS (SELECT 1 FROM message_log
                          WHERE booking_id = p_booking_id AND status = 'sent'
                            AND template_slug IN ('door_codes_gear_only', 'door_codes_gate_gear_only', 'door_codes_gear_staffed')) THEN
    RETURN;
  END IF;
  SELECT phone INTO v_phone FROM profiles WHERE id = v_b.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN; END IF;
  -- jen VYDANÝ kód šatny (zadržený do SMS nepatří)
  SELECT door_code INTO v_code FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer
   ORDER BY created_at DESC LIMIT 1;
  IF v_code IS NULL THEN RETURN; END IF;
  v_gate := public._booking_gate_code(p_booking_id);
  v_door := public._branch_locker_door_no(v_b.branch_id);
  PERFORM send_sms_and_wa(v_phone, public._gear_door_codes_sms_slug(v_gate IS NOT NULL, public.branch_is_self_service(v_b.branch_id)),
    jsonb_build_object(
      'booking_number', upper(right(p_booking_id::text, 8)),
      'door_code_gear', v_code,
      'locker_door',    COALESCE(v_door::text, '–'),
      'valid_from',     to_char((v_b.start_date AT TIME ZONE 'Europe/Prague')::date, 'DD.MM.YYYY'),
      'valid_to',       to_char((v_b.end_date AT TIME ZONE 'Europe/Prague')::date, 'DD.MM.YYYY')
    ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
    v_b.user_id, p_booking_id, public._door_codes_sms_lang(v_b.user_id, p_booking_id));
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_gear_door_codes_sms failed for booking %: %', p_booking_id, SQLERRM;
END $$;

-- Oznámení vydaného kódu šatny výpůjčky výbavy: in-app zpráva (VŽDY booking_id + č. rezervace, titulek
-- „Výpůjčka výbavy — kódy“, push posílá trg_push_on_admin_message), SMS/WA (p_sms) a e-mail s kódy
-- (send_door_codes_email → edge send-booking-email vybere gear šablonu). false = není co oznámit.
CREATE OR REPLACE FUNCTION public._gear_door_codes_notify(p_booking_id uuid, p_intro text DEFAULT NULL,
  p_bump boolean DEFAULT false, p_sms boolean DEFAULT true)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b record; v_code text; v_gate text; v_door integer;
BEGIN
  SELECT b.id, b.user_id, b.start_date, b.end_date, b.branch_id, b.booking_kind,
         br.name AS branch_name, br.type AS branch_type
    INTO v_b
    FROM bookings b LEFT JOIN branches br ON br.id = b.branch_id
   WHERE b.id = p_booking_id;
  IF NOT FOUND OR v_b.booking_kind IS DISTINCT FROM 'gear' OR v_b.user_id IS NULL THEN RETURN false; END IF;

  SELECT door_code INTO v_code FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer
   ORDER BY created_at DESC LIMIT 1;
  IF v_code IS NULL THEN RETURN false; END IF;   -- bez vydaného kódu šatny není co oznámit

  v_gate := public._booking_gate_code(p_booking_id);
  v_door := public._branch_locker_door_no(v_b.branch_id);

  IF p_bump THEN   -- nový e-mail i se stejným kódem (send_door_codes_email deduplikuje dle created_at kódů)
    UPDATE branch_door_codes SET created_at = now()
     WHERE booking_id = p_booking_id AND is_active AND sent_to_customer;
  END IF;

  BEGIN
    INSERT INTO admin_messages (user_id, booking_id, title, message, type)
    VALUES (v_b.user_id, p_booking_id, 'Výpůjčka výbavy — kódy',
      COALESCE(p_intro || E'\n', '') ||
      'Výpůjčka výbavy č. ' || upper(right(p_booking_id::text, 8)) || E'\n' ||
      public._gear_door_codes_msg_lines(v_gate, v_door, v_code, v_b.branch_type = 'samoobslužná') || E'\n' ||
      -- FIX-R1: obslužná pobočka bez brány = kód výpůjčky (ne šatny)
      CASE WHEN v_gate IS NULL AND v_b.branch_type IS DISTINCT FROM 'samoobslužná' THEN 'Kód platí'
           ELSE 'Kód šatny platí' END || ' po dobu výpůjčky (' ||
      to_char((v_b.start_date AT TIME ZONE 'Europe/Prague')::date, 'DD.MM.YYYY') || ' – ' ||
      to_char((v_b.end_date AT TIME ZONE 'Europe/Prague')::date, 'DD.MM.YYYY') || ').' ||
      CASE WHEN v_b.branch_name IS NOT NULL THEN E'\nPobočka: ' || v_b.branch_name ELSE '' END ||
      public._gear_procedure_msg(v_gate, v_door, v_b.branch_type = 'samoobslužná'),
      'door_codes');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_gear_door_codes_notify: admin_message insert failed: %', SQLERRM;
  END;

  IF p_sms THEN PERFORM public._gear_door_codes_sms(p_booking_id, false); END IF;
  -- e-mail s kódy (dedup v send_door_codes_email; GUC brání dvojímu odeslání s triggerem na admin_messages)
  PERFORM public.send_door_codes_email(p_booking_id, v_b.user_id);
  RETURN true;
END $$;

-- Práva hned u funkcí (výchozí práva schématu public dávají EXECUTE všem)
REVOKE ALL ON FUNCTION public._gear_door_codes_sms_slug(boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_door_codes_sms(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_door_codes_notify(uuid, text, boolean, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_door_codes_sms_slug(boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_door_codes_sms(uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_door_codes_notify(uuid, text, boolean, boolean) TO service_role;
