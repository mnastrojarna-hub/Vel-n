-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — kód brány, oznámení kódů, vydání při rezervaci, SMS trigger (2/14)
-- _booking_gate_code (pobočka výbavy z rezervace), _door_codes_notify (výbava → gear notifikátor),
-- auto_generate_door_codes (výbava = JEN kód šatny), trg_notify_door_codes (+ WHEN motorcycle|accessories).
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._booking_gate_code(p_booking_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN b.pickup_method = 'delivery' OR NULLIF(btrim(b.pickup_address), '') IS NOT NULL THEN NULL
              -- 2026-10-23: výpůjčka výbavy = pobočka z rezervace (bookings.branch_id)
              ELSE public._branch_gate_code(CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END) END
    FROM bookings b LEFT JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id;
$function$
;

CREATE OR REPLACE FUNCTION public._door_codes_notify(p_booking_id uuid, p_title text, p_intro text DEFAULT NULL::text, p_bump boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b record;
  v_code_moto text;
  v_code_gear text;
  v_gate text;
  v_door integer;
  v_phone text;
BEGIN
  -- 2026-10-23: výpůjčka výbavy — kotva je kód šatny; zpráva (č. rezervace, „Výpůjčka výbavy — kódy“),
  -- SMS/WA (door_codes*_gear_only) i e-mail přes gear notifikátor. Motorka níže beze změny.
  IF public._booking_is_gear(p_booking_id) THEN
    RETURN public._gear_door_codes_notify(p_booking_id, p_intro, p_bump, true);
  END IF;

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

  v_gate := public._booking_gate_code(p_booking_id);   -- NULL u přistavení na adresu
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
END $function$
;

CREATE OR REPLACE FUNCTION public.auto_generate_door_codes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_branch_id uuid;
  v_has_docs boolean;
  v_withheld text;
  v_code1 text;
  v_code2 text;
  v_needs boolean;
  v_gate text;
  v_door integer;
  v_released boolean;
BEGIN
  -- Testovací rezervace (seed obsazenosti kalendáře) NIKDY negenerují kódy
  -- ani neposílají zákazníkovi e-mail/in-app zprávu s kódy (NEW 2026-08-21):
  IF NEW.is_test IS TRUE THEN RETURN NEW; END IF;
  -- Spouští se jen pro reserved/active přechody
  IF NEW.status NOT IN ('active', 'reserved') THEN RETURN NEW; END IF;
  -- UPDATE: skip pokud OLD už byl ve stejném targetu (no-op change)
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  -- Idempotence: pokud už kódy pro booking existují, nic negeneruj
  IF EXISTS (SELECT 1 FROM branch_door_codes WHERE booking_id = NEW.id LIMIT 1) THEN RETURN NEW; END IF;

  -- 2026-10-23: VÝPŮJČKA VÝBAVY (booking_kind='gear', bez motorky) — pobočka z rezervace, JEN kód šatny
  -- (kód brány jen ve zprávě), NIKDY kód motorky; doklady booking_docs_gate (u výbavy jen totožnost + 18+),
  -- zpráva/e-mail přes gear pomocníky, SMS/WA pošle trg_notify_door_codes na řádku šatny. Motorka níže beze změny.
  IF NEW.booking_kind = 'gear' THEN
    PERFORM public._gear_issue_door_codes(NEW.id, NULL, false);
    RETURN NEW;
  END IF;

  SELECT branch_id INTO v_branch_id FROM motorcycles WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN RETURN NEW; END IF;

  -- Doklady (2026-10-10): kanonická přísná brána — OP líc+rub nebo pas, ŘP
  -- líc+rub, 18+, platný ŘP, skupina pro motorku; dětská motorka bez dokladů.
  v_withheld := public.booking_docs_gate(NEW.id);
  v_has_docs := v_withheld IS NULL;

  -- Kód šatny jen když je v šatně co vyzvednout (2026-09-25)
  v_needs := public._booking_needs_locker(NEW.id);

  -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04): kód brány první,
  -- šatna (dveře č. N) druhá, motorka třetí + stručný postup. Bez brány beze změny.
  v_gate := public._booking_gate_code(NEW.id);   -- NULL u přistavení na adresu
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch_id) END;

  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  -- Šatna PŘED motorkou: AFTER INSERT trigger trg_notify_door_codes (SMS/WA)
  -- na řádku motorky si kód šatny načítá z tabulky.
  IF v_needs THEN
    INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
      is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
    VALUES
      (v_branch_id, NEW.id, NEW.moto_id, 'accessories', v_code2,
       true, NEW.start_date, NEW.end_date, v_has_docs,
       CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld);
  END IF;
  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, NEW.id, NEW.moto_id, 'motorcycle', v_code1,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld);

  -- BEFORE trigger withhold_swap_next_codes mohl kód motorky zadržet (výměna
  -- motorky na samoobsluze) → kódy oznámí až release_swap_next_codes (jako regen).
  SELECT bool_and(sent_to_customer) INTO v_released
    FROM branch_door_codes WHERE booking_id = NEW.id AND is_active = true;

  IF v_has_docs AND COALESCE(v_released, false) THEN
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        NEW.user_id,
        'Přístupové kódy k pobočce',
        public._door_codes_msg_lines(v_gate, v_door, CASE WHEN v_needs THEN v_code2 END, v_code1) ||
        E'\n' || public._door_codes_msg_valid(v_gate, v_needs, true) ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').' ||
        public._gate_procedure_msg(v_gate, v_door, v_needs),
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_generate_door_codes: admin_message insert failed: %', SQLERRM;
    END;

    -- Email s kódy (deduplikováno přes message_log v send_door_codes_email)
    PERFORM send_door_codes_email(NEW.id, NEW.user_id);
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_generate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_notify_door_codes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_phone text;
  v_user_id uuid;
  v_booking_id uuid;
  v_lang text;
  v_code_moto text;
  v_code_gear text;
  v_already_sent boolean;
  v_gate text;
BEGIN
  -- 2026-10-23: trigger běží i na řádku šatny (WHEN motorcycle|accessories) — SMS/WA pošle JEN u výpůjčky
  -- výbavy (kotva = kód šatny, šablona door_codes*_gear_only); kód šatny motorkové rezervace SMS nespouští
  -- (beze změny). Regenerace výbavy SMS posílá sama (GUC motogo.gear_sms_mute = id rezervace).
  IF NEW.code_type = 'accessories' THEN
    IF COALESCE(NEW.sent_to_customer, false) AND public._booking_is_gear(NEW.booking_id)
       AND COALESCE(current_setting('motogo.gear_sms_mute', true), '') <> NEW.booking_id::text THEN
      PERFORM public._gear_door_codes_sms(NEW.booking_id, true);
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.code_type != 'motorcycle' THEN RETURN NEW; END IF;
  -- Zadržený kód (chybí doklady / výměna motorky) se NEPOSÍLÁ — po uvolnění
  -- pošlou SMS/WA funkce release_* (2026-10-04: dřív odešel hned při vložení,
  -- s kódem brány by unikl i kód schránky).
  IF NOT COALESCE(NEW.sent_to_customer, false) THEN RETURN NEW; END IF;

  -- Najdi user_id přes booking_id
  SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;
  v_booking_id := NEW.booking_id;

  -- Dedup (obě šablony kódů)
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id AND status = 'sent'
      AND template_slug IN ('door_codes', 'door_codes_moto_only', 'door_codes_gate', 'door_codes_gate_moto_only')
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = v_user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Načti oba kódy (kód šatny existuje jen při nároku na šatnu)
  -- Jen VYDANÉ kódy (zadržený kód šatny do SMS nepatří, 2026-10-10)
  SELECT door_code INTO v_code_moto
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer
   ORDER BY created_at DESC LIMIT 1;
  IF v_code_moto IS NULL THEN RETURN NEW; END IF;
  SELECT door_code INTO v_code_gear
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer
   ORDER BY created_at DESC LIMIT 1;

  v_lang := public._door_codes_sms_lang(v_user_id, v_booking_id);
  -- Brána se schránkou na klíč (Velké Němčice): šablona door_codes_gate* (brána → šatna → motorka)
  v_gate := public._booking_gate_code(NEW.booking_id);   -- NULL u přistavení na adresu

  PERFORM send_sms_and_wa(
    v_phone,
    public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
    jsonb_build_object(
      'booking_number',  upper(left(v_booking_id::text, 8)),
      'door_code_moto',  coalesce(v_code_moto, ''),
      'door_code_gear',  coalesce(v_code_gear, '')
    ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
    v_user_id,
    v_booking_id,
    v_lang
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_door_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$function$
;

-- SMS/WA při vložení kódu: nově i řádek šatny (funkce pokračuje jen u výpůjčky výbavy, motorka beze změny)
DROP TRIGGER IF EXISTS trg_notify_door_codes ON public.branch_door_codes;
CREATE TRIGGER trg_notify_door_codes AFTER INSERT ON public.branch_door_codes
  FOR EACH ROW WHEN (new.code_type = ANY (ARRAY['motorcycle'::text, 'accessories'::text]))
  EXECUTE FUNCTION public.trg_notify_door_codes();
