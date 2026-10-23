-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — kódy, zprávy, aktivace, kiosek, vrácení (1/14)
-- Zadání majitele: rezervace booking_kind='gear' (bez motorky, pobočka v
-- bookings.branch_id) dostane JEN kód šatny (accessories) + kód brány ve zprávě,
-- NIKDY kód motorky; vydání po zaplacení a dokladech (booking_docs_gate — u výbavy
-- jen doklad totožnosti + 18+, 20261023b). Po zavření šatny kiosk ukáže předávací
-- protokol (velikosti + podpis, identita = kód šatny téže rezervace); při vrácení se
-- po zavření šatny zeptá „Vracíš všechnu výbavu?“ — Ano = událost
-- GEAR_RETURN_CONFIRMED → rezervace se dokončí (returned_at = čas potvrzení), kód
-- šatny dobíhá 15 min po zavření šatny (kiosk 1.3.0).
--
-- Kvůli limitu velikosti souboru (CLAUDE.md) je balík rozdělen do 14 (+1) souborů se
-- SPOLEČNOU předponou (autodeploy je aplikuje v bytovém pořadí, vše po 20261023b
-- a před 20261023d):
--   20261023c_gear_booking_codes.sql              — gear pomocníci: texty zpráv, vydání / regenerace kódu
--   20261023c_gear_booking_codes_a_notify         — (1a, FIX-R1) slug SMS/WA, SMS + WA s kódem, notifikátor
--   20261023c_gear_booking_codes_b_notify         — kód brány, _door_codes_notify, auto_generate, SMS trigger
--   20261023c_gear_booking_codes_c_release        — uvolnění zadržených kódů (zákazník / doklady)
--   20261023c_gear_booking_codes_d_regen          — regenerace, kód šatny, brána (Velín, appka), změna pobočky
--   20261023c_gear_booking_codes_e_follow_moto    — kódy za motorkou (výbavu přeskočí)
--   20261023c_gear_booking_codes_f_activation     — aktivace / protokol (pobočka výbavy z rezervace)
--   20261023c_gear_booking_codes_g0_kiosk_protocol — _kiosk_protocol gear_only + sizes_catalog
--   20261023c_gear_booking_codes_g_kiosk_sync     — kiosk_sync_config codes[].gear_only
--   20261023c_gear_booking_codes_h_kiosk_resolve  — kiosk_resolve_code gear_only
--   20261023c_gear_booking_codes_i0_return_event  — GEAR_RETURN_CONFIRMED → booking_kiosk_returns
--   20261023c_gear_booking_codes_i_return         — _kiosk_return_from_door_event (gear větev)
--   20261023c_gear_booking_codes_j_process_returns — dokončení vrácení výbavy (cron kiosk-return-completion)
--   20261023c_gear_booking_codes_k_crons          — připomínky / přehled nevyzvednutých
--   20261023c_gear_booking_codes_l_sms            — SMS/WA šablony door_codes*_gear_only + _gear_staffed (8 jazyků)
-- Motorka beze změny: převzatá těla jsou 1:1 z živé DB, změněné řádky označené
-- „2026-10-23“. _gate_procedure_msg (čeká na text majitele) se NEMĚNÍ. Nový vzdálený
-- příkaz není (protocol_signed už v CHECK je); branch_door_events.detail.event žádný
-- CHECK nemá. Idempotentní (CREATE OR REPLACE / DROP TRIGGER IF EXISTS / ON CONFLICT).
-- =============================================================================


-- Řádky kódů do in-app zprávy: brána (je-li) → šatna (dveře č. N). Kód motorky výbava nemá.
-- FIX-R1: obslužná pobočka bez brány → „Kód výpůjčky“ (identita při předání ve Velínu), ne „Kód šatny“.
DROP FUNCTION IF EXISTS public._gear_door_codes_msg_lines(text, integer, text);
CREATE OR REPLACE FUNCTION public._gear_door_codes_msg_lines(p_gate text, p_locker_door integer, p_code_gear text,
  p_self_service boolean DEFAULT true)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_gate IS NOT NULL THEN 'Kód schránky s klíčem od brány: ' || p_gate || E'\n' ELSE '' END ||
         CASE WHEN p_gate IS NULL AND p_self_service IS NOT TRUE THEN 'Kód výpůjčky'
              ELSE 'Kód šatny' || CASE WHEN p_locker_door IS NOT NULL THEN ' (dveře č. ' || p_locker_door || ')' ELSE '' END END ||
         ': ' || COALESCE(p_code_gear, '–');
$$;

-- Postup na pobočce u výpůjčky výbavy (tykání): brána → šatna → protokol na displeji (velikosti + podpis,
-- potvrzení kódem šatny) → vrácení (šatna, „Vracíš všechnu výbavu?“ → Ano) → zavřít bránu.
-- Bez brány jen na samoobsluze; obslužná pobočka = výdej obsluhou → jen věta o nahlášení kódu (FIX-R1).
CREATE OR REPLACE FUNCTION public._gear_procedure_msg(p_gate text, p_locker_door integer, p_self_service boolean)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN p_gate IS NULL AND p_self_service IS NOT TRUE
    THEN E'\n\nKód výpůjčky při převzetí nahlásíš obsluze na pobočce.' ELSE
    E'\n\nPostup na pobočce:' ||
    CASE WHEN p_gate IS NOT NULL THEN
      E'\n1) Je-li vjezdová brána zavřená, otevři HORNÍ schránku na pravém sloupku vrat kódem ' || p_gate ||
      ' — je v ní klíč od visacího zámku brány. Bránu odemkni, vjeď dovnitř a zaparkuj na kterémkoli parkovacím místě 1–7 vpravo u plotu.'
    ELSE '' END ||
    E'\n' || CASE WHEN p_gate IS NOT NULL THEN '2' ELSE '1' END || ') Na displeji zadej kód šatny' ||
    CASE WHEN p_locker_door IS NOT NULL THEN ' (šatna = dveře č. ' || p_locker_door || ')' ELSE '' END ||
    ', vezmi si výbavu a zavři dveře šatny.' ||
    E'\n' || CASE WHEN p_gate IS NOT NULL THEN '3' ELSE '2' END ||
    ') Na displeji se ukáže předávací protokol: zkontroluj velikosti (případně je uprav) a protokol podepiš — potvrdíš ho znovu kódem šatny.' ||
    E'\n' || CASE WHEN p_gate IS NOT NULL THEN '4' ELSE '3' END ||
    ') Vrácení: výbavu vrať do šatny (stejným kódem šatny), zavři dveře a na displeji na otázku „Vracíš všechnu výbavu?“ odpověz „Ano“ — tím výpůjčku ukončíš.' ||
    CASE WHEN p_gate IS NOT NULL THEN
      E'\n5) DŮLEŽITÉ: Byla-li brána zavřená, po odjezdu ji zase zavři, zamkni visacím zámkem, klíč vrať do horní schránky a přetoč číselník, aby kód nezůstal nastavený. Otevřenou bránu nech otevřenou. Stejně postupuj i při vrácení výbavy.'
    ELSE '' END
  END;
$$;

-- Vydání kódu šatny výpůjčky výbavy (auto_generate_door_codes / regenerace): JEN řádek accessories na pobočce
-- rezervace, zadržený dle booking_docs_gate (pojistka _door_codes_docs_guard). Číslo bez kolize s jiným aktivním
-- kódem / servisním heslem pobočky. p_mute_sms: SMS pošle notifikátor sám (regenerace), ne trigger při vložení.
-- p_keep_sent (regenerace): byl-li starý kód šatny už VYDANÝ (i ručním „Odeslat“ z Velínu), nový kód se vydá
-- HNED, bez znovuzadržení dle dokladů (zákazník může mít výbavu u sebe). Číslo je vždy NOVÉ (jako
-- regen_door_codes_for_booking u motorky) — starý kód přestane platit, nový jde zprávou / SMS / e-mailem.
CREATE OR REPLACE FUNCTION public._gear_issue_door_codes(p_booking_id uuid, p_intro text DEFAULT NULL,
  p_mute_sms boolean DEFAULT false, p_keep_sent boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_withheld text;
  v_code text;
  v_released boolean;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.booking_kind IS DISTINCT FROM 'gear' OR v_b.is_test IS TRUE
     OR v_b.status NOT IN ('reserved', 'active') OR v_b.branch_id IS NULL THEN
    RETURN false;
  END IF;

  v_withheld := CASE WHEN p_keep_sent THEN NULL
                     ELSE public.booking_docs_gate(p_booking_id) END;   -- výbava: doklad totožnosti + 18+ (20261023b)
  LOOP
    v_code := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM branch_door_codes c
                           WHERE c.branch_id = v_b.branch_id AND c.door_code = v_code AND c.is_active)
          AND NOT EXISTS (SELECT 1 FROM branch_service_codes s WHERE s.branch_id = v_b.branch_id AND s.code = v_code);
  END LOOP;

  IF p_mute_sms THEN PERFORM set_config('motogo.gear_sms_mute', p_booking_id::text, true); END IF;
  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES (v_b.branch_id, p_booking_id, NULL, 'accessories', v_code,
    true, v_b.start_date, v_b.end_date, v_withheld IS NULL,
    CASE WHEN v_withheld IS NULL THEN now() END, v_withheld);
  IF p_mute_sms THEN PERFORM set_config('motogo.gear_sms_mute', '', true); END IF;

  -- pojistka dokladů (BEFORE trigger) mohla kód zadržet → ověř skutečný stav
  SELECT bool_and(sent_to_customer) INTO v_released
    FROM branch_door_codes WHERE booking_id = p_booking_id AND is_active;
  IF COALESCE(v_released, false) THEN
    PERFORM public._gear_door_codes_notify(p_booking_id, p_intro, false, p_mute_sms);
  END IF;
  RETURN true;
END $$;

-- Regenerace kódu šatny výpůjčky výbavy (jiná pobočka / ruční regenerace): staré kódy zneplatnit, NOVÝ kód šatny
-- (nové číslo) na pobočce rezervace + zpráva/SMS/e-mail; byl-li starý kód vydaný, nový se vydá rovnou, bez
-- zadržení dle dokladů. Volá regen_door_codes_for_booking (gear větev).
CREATE OR REPLACE FUNCTION public._gear_regen_door_codes(p_booking_id uuid, p_reason text DEFAULT 'branch_move')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_name text; v_sent boolean; v_word text;
BEGIN
  SELECT COALESCE(bool_or(sent_to_customer), false) INTO v_sent
    FROM branch_door_codes WHERE booking_id = p_booking_id AND is_active = true;
  UPDATE branch_door_codes SET is_active = false WHERE booking_id = p_booking_id AND is_active = true;
  -- FIX-R1: obslužná pobočka bez brány = „kód výpůjčky“ (jako _gear_door_codes_msg_lines)
  SELECT br.name, CASE WHEN br.type IS DISTINCT FROM 'samoobslužná' AND public._booking_gate_code(b.id) IS NULL
                       THEN 'výpůjčky' ELSE 'šatny' END
    INTO v_name, v_word FROM bookings b LEFT JOIN branches br ON br.id = b.branch_id WHERE b.id = p_booking_id;
  RETURN public._gear_issue_door_codes(p_booking_id,
    CASE p_reason WHEN 'branch_move' THEN 'Výpůjčka výbavy byla přesunuta na pobočku ' || COALESCE(v_name, '') || ' – nový kód ' || COALESCE(v_word, 'šatny') || ':'
                  ELSE CASE WHEN v_word = 'výpůjčky' THEN 'Kód k výpůjčce výbavy' ELSE 'Kód šatny k výpůjčce výbavy' END || ' byl změněn – nový kód:' END,
    true, v_sent);
END $$;

-- Výpůjčka výbavy přesunutá na jinou pobočku (Velín / admin_update_gear_booking) → kód šatny na nové pobočce.
-- Jen živá rezervace, která už živá byla (přechod pending → reserved řeší auto_generate_door_codes).
CREATE OR REPLACE FUNCTION public._gear_codes_follow_branch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.booking_kind IS DISTINCT FROM 'gear' OR NEW.is_test IS TRUE
     OR OLD.branch_id IS NOT DISTINCT FROM NEW.branch_id
     OR OLD.status NOT IN ('reserved', 'active') OR NEW.status NOT IN ('reserved', 'active') THEN
    RETURN NULL;
  END IF;
  PERFORM public.regen_door_codes_for_booking(NEW.id, 'branch_move');
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_gear_codes_follow_branch failed for booking %: %', NEW.id, SQLERRM;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public._gear_door_codes_msg_lines(text, integer, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_procedure_msg(text, integer, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_issue_door_codes(uuid, text, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_regen_door_codes(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_codes_follow_branch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_door_codes_msg_lines(text, integer, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_procedure_msg(text, integer, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_issue_door_codes(uuid, text, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_regen_door_codes(uuid, text) TO service_role;
