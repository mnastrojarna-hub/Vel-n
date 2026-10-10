-- ============================================================================
-- PŘÍSTUPOVÉ KÓDY JEN S KOMPLETNÍMI DOKLADY — další cesty (2026-10-10, 4/4)
-- Pravidlo a jádro viz `20261010_docs_gate_core.sql` (`booking_docs_gate`).
-- * `release_my_door_codes` (appka / web „Nahrát doklady a uvolnit kódy“):
--   přísná brána rezervace; při nesplnění zapíše přesný důvod do kódu;
--   zpráva / SMS jen z opravdu vydaných kódů.
-- * `release_swap_next_codes`: přísná brána + zpráva jen z vydaných kódů.
-- * `trg_notify_door_codes` (SMS/WA po vložení kódu motorky): kód šatny jen
--   vydaný (dřív četl i zadržený).
-- * Pojistný cron `door-codes-docs-recheck` á 15 min: znovu vyhodnotí
--   zadržené kódy živých rezervací (18. narozeniny před začátkem, soubor
--   dokladu dorazil až po řádku, spolknutá chyba triggeru) — uvolní je
--   standardní cestou `release_withheld_door_codes_for_user`.
-- Těla release_swap_next_codes / trg_notify_door_codes jinak 1:1 z živé DB.
-- ============================================================================

-- 1) release_my_door_codes: přísná brána rezervace, zpráva jen z vydaných -----
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

  SELECT id, user_id, start_date, end_date, status, moto_id
  INTO v_booking
  FROM bookings
  WHERE id = p_booking_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
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
$function$;

-- 2) release_swap_next_codes ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.release_swap_next_codes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           public.booking_docs_gate(b.id) AS docs_reason   -- 2026-10-10: přísná brána (dětská uvnitř)
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

    -- Do zprávy JEN vydané kódy (zadržený kód šatny neunikne, 2026-10-10)
    v_code_moto := NULL; v_code_gear := NULL;
    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = r.booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer LIMIT 1;
    IF v_code_moto IS NULL THEN CONTINUE; END IF;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = r.booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer LIMIT 1;
    SELECT br.name, m.box_number, b.start_date::date, b.end_date::date, m.branch_id
      INTO v_branch, v_box, v_start, v_end, v_branch_id
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
      LEFT JOIN branches br   ON br.id = m.branch_id
     WHERE b.id = r.booking_id;

    -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
    v_gate := public._booking_gate_code(r.booking_id);   -- NULL u přistavení na adresu
    v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch_id) END;

    -- a) in-app zpráva (+ push přes trg_push_on_admin_message) — zákazník stojí
    --    u kóje, e-mail sám o sobě nestačí
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (r.user_id, 'Nové přístupové kódy',
        CASE WHEN NEW.status = 'cancelled' THEN 'Původní rezervace byla zrušena — tady jsou kódy k nové motorce:'
             ELSE 'Původní motorka je vrácená — tady jsou kódy k nové:' END || E'\n' ||
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
          -- jazyk z PROFILU (jako dosud): navazující rezervace výměny vzniká bez
          -- jazyka (default cs), takže jazyk rezervace by tu byl vždy cs
          r.user_id, r.booking_id,
          CASE WHEN v_lang IN ('cs','en','de','nl','es','fr','pl','uk') THEN v_lang ELSE 'cs' END);
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
$function$;

-- 3) trg_notify_door_codes -----------------------------------------------------
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
$function$;


-- 4) Pojistný přepočet zadržených kódů ----------------------------------------
CREATE OR REPLACE FUNCTION public.door_codes_docs_recheck()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT b.user_id
      FROM bookings b
      JOIN branch_door_codes c ON c.booking_id = b.id
     WHERE b.status IN ('reserved', 'active') AND b.is_test IS NOT TRUE
       AND b.end_date >= now() - interval '1 day'
       AND c.is_active AND c.sent_to_customer = false
       AND c.withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
       AND b.user_id IS NOT NULL
  LOOP
    PERFORM public.release_withheld_door_codes_for_user(r.user_id);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.door_codes_docs_recheck() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.door_codes_docs_recheck() TO service_role;

DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('door-codes-docs-recheck');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM cron.schedule('door-codes-docs-recheck', '*/15 * * * *', $cron$ SELECT public.door_codes_docs_recheck(); $cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule door-codes-docs-recheck selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;
