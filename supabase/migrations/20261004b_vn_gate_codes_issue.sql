-- =============================================================================
-- Velké Němčice: kód brány ve zprávách s kódy — VYDÁNÍ a PŘEGENEROVÁNÍ
-- Migrace: 20261004b_vn_gate_codes_issue.sql (2/5; potřebuje 20261004_vn_gate_access.sql)
--
-- auto_generate_door_codes (nová rezervace / výměna motorky – nová navazující
-- rezervace) a regen_door_codes_for_booking (změna motorky, přesun motorky na
-- jinou pobočku / do jiné kóje): u pobočky s bránou (branch_gate_access) zpráva
-- v appce (+ push) nese kódy v pořadí BRÁNA → ŠATNA (dveře č. N) → MOTORKA
-- a stručný postup (brána, parkování 1–7, šatna, protokol, motorka, zavřít
-- bránu + vrátit klíč + přetočit číselník); SMS/WA šablony door_codes_gate*.
-- Pobočky BEZ brány (Mezná): text, SMS i e-mail přesně jako dosud.
--
-- Navíc auto_generate_door_codes ověří po vložení skutečný stav vydání
-- (bool_and(sent_to_customer), stejně jako regen): kód motorky zadržený
-- triggerem withhold_swap_next_codes (výměna na samoobsluze) se už neposílá
-- předčasně — oznámí ho release_swap_next_codes po vrácení původní motorky.
--
-- Těla 1:1 z živé DB (supabase-live-snapshot 2026-10-03, shodná s migrací
-- 20260925a_locker_codes_own_gear.sql) kromě označených změn.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."auto_generate_door_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_branch_id uuid;
  v_license_required text;
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

  SELECT branch_id, license_required
    INTO v_branch_id, v_license_required
    FROM motorcycles
   WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN RETURN NEW; END IF;

  -- DĚTSKÁ MOTORKA: license_required='N' → doklady nepotřeba, hned vydáme kódy
  IF v_license_required = 'N' THEN
    v_has_docs := true;
  ELSE
    -- Dospělá motorka: kódy jen když je KAŽDÝ doklad ověřený FOTKOU nebo reálným OCR.
    -- Pouhé ručně vypsané číslo (license_number/id_number) NESTAČÍ — slouží jen do smlouvy.
    v_has_docs := (
      -- ŘP: fotka (i při neúspěšném OCR) NEBO reálný Mindee OCR sken (license_verified_at)
      (
        EXISTS (SELECT 1 FROM documents
                 WHERE user_id = NEW.user_id AND type IN ('drivers_license','license_photo') LIMIT 1)
        OR EXISTS (SELECT 1 FROM profiles
                    WHERE id = NEW.user_id AND license_verified_at IS NOT NULL)
      )
      AND
      -- Doklad totožnosti: fotka NEBO reálný Mindee OCR sken (id/passport_verified_at)
      (
        EXISTS (SELECT 1 FROM documents
                 WHERE user_id = NEW.user_id AND type IN ('id_card','id_photo','passport') LIMIT 1)
        OR EXISTS (SELECT 1 FROM profiles
                    WHERE id = NEW.user_id
                      AND (id_verified_at IS NOT NULL OR passport_verified_at IS NOT NULL))
      )
    );
  END IF;

  v_withheld := CASE WHEN v_has_docs THEN NULL ELSE 'Chybí doklady (OP/pas/ŘP)' END;

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
$$;

CREATE OR REPLACE FUNCTION "public"."regen_door_codes_for_booking"("p_booking_id" "uuid", "p_reason" "text" DEFAULT 'moto_change'::"text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_branch_id uuid;
  v_branch_name text;
  v_box integer;
  v_lic text;
  v_withheld text;
  v_code1 text;
  v_code2 text;
  v_released boolean;
  v_phone text;
  v_lang text;
  v_intro text;
  v_needs boolean;
  v_gate text;
  v_door integer;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.is_test IS TRUE OR v_b.status NOT IN ('active','reserved') THEN
    RETURN false;
  END IF;

  SELECT m.branch_id, m.box_number, m.license_required::text, br.name
    INTO v_branch_id, v_box, v_lic, v_branch_name
    FROM motorcycles m LEFT JOIN branches br ON br.id = m.branch_id
   WHERE m.id = v_b.moto_id;

  -- staré kódy vždy zneplatnit (motorka už není tam, kde byla)
  UPDATE branch_door_codes SET is_active = false
   WHERE booking_id = p_booking_id AND is_active = true;

  IF v_branch_id IS NULL THEN RETURN false; END IF;

  IF v_lic = 'N' THEN
    v_withheld := NULL;
  ELSE
    v_withheld := check_booking_docs_status(v_b.user_id, v_b.end_date::date, v_b.moto_id);
  END IF;

  -- Kód šatny jen při nároku (2026-09-25)
  v_needs := public._booking_needs_locker(p_booking_id);

  -- Brána se schránkou na klíč nové pobočky (Velké Němčice, 2026-10-04) —
  -- i při změně motorky Mezná → Velké Němčice dostane zákazník všechny 3 kódy.
  v_gate := public._booking_gate_code(p_booking_id);   -- NULL u přistavení na adresu
  v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch_id) END;

  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  -- Šatna PŘED motorkou (trg_notify_door_codes na řádku motorky čte kód šatny)
  IF v_needs THEN
    INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
      is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
    VALUES
      (v_branch_id, p_booking_id, v_b.moto_id, 'accessories', v_code2,
       true, v_b.start_date, v_b.end_date, v_withheld IS NULL,
       CASE WHEN v_withheld IS NULL THEN NOW() ELSE NULL END, v_withheld);
  END IF;
  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, p_booking_id, v_b.moto_id, 'motorcycle', v_code1,
     true, v_b.start_date, v_b.end_date, v_withheld IS NULL,
     CASE WHEN v_withheld IS NULL THEN NOW() ELSE NULL END, v_withheld);

  -- BEFORE trigger withhold_swap_next_codes mohl kód zadržet → ověř reálný stav
  SELECT bool_and(sent_to_customer) INTO v_released
    FROM branch_door_codes
   WHERE booking_id = p_booking_id AND is_active = true;
  IF NOT COALESCE(v_released, false) THEN RETURN true; END IF;

  v_intro := CASE p_reason
    WHEN 'branch_move' THEN 'Vaše motorka byla přesunuta na pobočku ' || COALESCE(v_branch_name, '') || ' – nové kódy:'
    WHEN 'box_move'    THEN 'Vaše motorka byla přesunuta do jiné kóje' || CASE WHEN v_box IS NOT NULL THEN ' (č. ' || v_box || ')' ELSE '' END || ' – nové kódy:'
    ELSE 'Změnili jste motorku – nové kódy:' END;

  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (v_b.user_id, 'Nové přístupové kódy',
      v_intro || E'\n' ||
      public._door_codes_msg_lines(v_gate, v_door, CASE WHEN v_needs THEN v_code2 END, v_code1) || E'\n' ||
      public._door_codes_msg_valid(v_gate, v_needs, false) ||
      TO_CHAR(v_b.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_b.end_date::date, 'DD.MM.YYYY') || ').' ||
      CASE WHEN v_branch_name IS NOT NULL THEN E'\nPobočka: ' || v_branch_name ELSE '' END ||
      CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END ||
      public._gate_procedure_msg(v_gate, v_door, v_needs),
      'door_codes');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT phone, COALESCE(language, 'cs') INTO v_phone, v_lang FROM profiles WHERE id = v_b.user_id;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
      PERFORM send_sms_and_wa(v_phone,
        public._door_codes_sms_slug(v_gate, v_needs),
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', v_code1,
          'door_code_gear', CASE WHEN v_needs THEN v_code2 ELSE '' END
        ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
        v_b.user_id, p_booking_id, public._door_codes_sms_lang(v_b.user_id, p_booking_id));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- mail s novými kódy (dedup dle kódů → vždy odejde; GUC brání dvojímu
  -- odeslání, když ho už spustil trigger na admin_messages)
  PERFORM send_door_codes_email(p_booking_id, v_b.user_id);
  RETURN true;
END $$;
