-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — regenerace, kód šatny, brána, změna pobočky (4/14)
-- regen_door_codes_for_booking (výbava → jen kód šatny), _sync_locker_code (výbava: kotva = kód šatny),
-- admin_notify_branch_gate_code + get_booking_gate_info (i výpůjčky výbavy), trigger trg_gear_codes_follow_branch.
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.regen_door_codes_for_booking(p_booking_id uuid, p_reason text DEFAULT 'moto_change'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 2026-10-23: výpůjčka výbavy — znovu JEN kód šatny na pobočce rezervace (bookings.branch_id) + zprávy
  IF v_b.booking_kind = 'gear' THEN
    RETURN public._gear_regen_door_codes(p_booking_id, p_reason);
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
END $function$
;

CREATE OR REPLACE FUNCTION public._sync_locker_code()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_moto branch_door_codes%ROWTYPE;
  v_acc  branch_door_codes%ROWTYPE;
  v_old  branch_door_codes%ROWTYPE;
  v_needs boolean;
  v_code  text;
  v_gate  text;
  v_door  integer;
BEGIN
  -- Výbava už vyzvednutá / protokol podepsaný / testovací rezervace → nic
  IF NEW.is_test IS TRUE OR NEW.gear_collected_at IS NOT NULL
     OR NEW.handover_protocol_filled_at IS NOT NULL THEN
    RETURN NULL;
  END IF;
  -- 2026-10-23: výpůjčka výbavy — kotvou je sám kód šatny (kód motorky neexistuje) a šatna je potřeba vždy
  -- (aspoň jeden kus hlídá trg_zz_gear_booking_guard) → změna velikostí kód nevydává ani nestahuje
  IF NEW.booking_kind = 'gear' THEN
    RETURN NULL;
  END IF;
  -- Bez aktivního kódu k motorce rezervace kódy nemá (pending / completed) → nic
  SELECT * INTO v_moto FROM branch_door_codes
   WHERE booking_id = NEW.id AND code_type = 'motorcycle' AND is_active = true
   ORDER BY updated_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_needs := public._booking_needs_locker(NEW.id);
  SELECT * INTO v_acc FROM branch_door_codes
   WHERE booking_id = NEW.id AND code_type = 'accessories' AND is_active = true
   ORDER BY updated_at DESC LIMIT 1;

  IF v_needs AND v_acc.id IS NULL THEN
    -- a) šatna nově potřeba: reaktivovat neaktivní řádek (žádné dva kódy šatny
    --    na rezervaci), jinak vložit nový; vydání/zadržení/okno dle kódu k motorce
    SELECT * INTO v_old FROM branch_door_codes
     WHERE booking_id = NEW.id AND code_type = 'accessories' AND is_active = false
     ORDER BY updated_at DESC LIMIT 1;
    IF FOUND THEN
      UPDATE branch_door_codes
         SET is_active = true, withheld_reason = v_moto.withheld_reason,
             sent_to_customer = v_moto.sent_to_customer,
             sent_at = CASE WHEN v_moto.sent_to_customer THEN now() ELSE NULL END,
             branch_id = v_moto.branch_id, moto_id = v_moto.moto_id,
             valid_from = v_moto.valid_from, valid_until = v_moto.valid_until,
             created_at = now()   -- „nově vydaný" kód: dedup mailu i výběr nejnovějšího kódu
       WHERE id = v_old.id;
      v_code := v_old.door_code;
    ELSE
      v_code := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
      INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
        is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
      VALUES (v_moto.branch_id, NEW.id, v_moto.moto_id, 'accessories', v_code,
        true, v_moto.valid_from, v_moto.valid_until, v_moto.sent_to_customer,
        CASE WHEN v_moto.sent_to_customer THEN now() ELSE NULL END, v_moto.withheld_reason);
    END IF;

    -- Zadržený kód (doklady) oznámí až uvolnění; vydaný kód oznámit hned.
    -- type='info' (NE door_codes — ten spouští cizí e-mail trigger pro jinou
    -- rezervaci); push posílá trg_push_on_admin_message; e-mail s oběma kódy
    -- explicitně k TÉTO rezervaci. SMS/WA se u dodatečného kódu šatny neposílá
    -- (trg_notify_door_codes reaguje jen na INSERT kódu k motorce).
    IF v_moto.sent_to_customer AND NEW.user_id IS NOT NULL THEN
      -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04): pořadí brána → šatna → motorka
      v_gate := public._booking_gate_code(NEW.id);   -- NULL u přistavení na adresu
      v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_moto.branch_id) END;
      BEGIN
        INSERT INTO admin_messages (user_id, booking_id, title, message, type)
        VALUES (NEW.user_id, NEW.id, 'Kód šatny',
          CASE WHEN v_gate IS NOT NULL THEN 'Kód schránky s klíčem od brány: ' || v_gate || E'\n' ELSE '' END ||
          'Byl vám přidán kód šatny' ||
          CASE WHEN v_door IS NOT NULL THEN ' (dveře č. ' || v_door || ')' ELSE '' END ||
          ': ' || v_code || E'\nKód k motorce zůstává: ' || v_moto.door_code || '.',
          'info');
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '_sync_locker_code: admin_message insert failed: %', SQLERRM;
      END;
      PERFORM send_door_codes_email(NEW.id, NEW.user_id);
    END IF;

  ELSIF NOT v_needs AND v_acc.id IS NOT NULL THEN
    -- b) šatna už není potřeba: kód zadržet (Velín ho může znovu aktivovat
    --    jen při nároku — booking_needs_locker)
    UPDATE branch_door_codes
       SET is_active = false, withheld_reason = 'Vlastní výbava'
     WHERE id = v_acc.id;
  END IF;

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_sync_locker_code failed for booking %: %', NEW.id, SQLERRM;
  RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_notify_branch_gate_code(p_branch_id uuid, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- 2026-10-23: i výpůjčky výbavy (pobočka z rezervace, kotva = vydaný kód šatny); motorka beze změny
    SELECT b.id, b.booking_kind
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END = p_branch_id
       AND b.is_test IS NOT TRUE
       AND b.status IN ('reserved', 'active')
       AND b.end_date::date >= (now() AT TIME ZONE 'Europe/Prague')::date
       AND EXISTS (SELECT 1 FROM branch_door_codes c
                    WHERE c.booking_id = b.id
                      AND c.code_type = CASE WHEN b.booking_kind = 'gear' THEN 'accessories' ELSE 'motorcycle' END
                      AND c.is_active AND c.sent_to_customer)
       -- jen rezervace s nárokem na kód brány (vyzvednutí na pobočce; přistavení = NULL)
       AND public._booking_gate_code(b.id) IS NOT NULL
     ORDER BY b.start_date
  LOOP
    IF p_dry_run THEN
      v_n := v_n + 1;
      CONTINUE;
    END IF;
    BEGIN
      IF public._door_codes_notify(r.id, 'Kód schránky s klíčem od brány',
           CASE WHEN r.booking_kind = 'gear'   -- 2026-10-23: výpůjčka výbavy — text tykáním (zbytek zprávy taky)
                THEN 'K tvé výpůjčce výbavy přibyl kód schránky s klíčem od vjezdové brány — aktuální kódy:'
                ELSE 'K vaší rezervaci přibyl kód schránky s klíčem od vjezdové brány — aktuální kódy:' END, true) THEN
        v_n := v_n + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'admin_notify_branch_gate_code %: %', r.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_n, 'notified', CASE WHEN p_dry_run THEN 0 ELSE v_n END);
END $function$
;

CREATE OR REPLACE FUNCTION public.get_booking_gate_info(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_b record;
  v_gate text;
  v_released boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('has_gate', false); END IF;
  -- 2026-10-23: výpůjčka výbavy — pobočka z rezervace; kód brány s jakýmkoli vydaným kódem (jen šatna)
  SELECT b.status, CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END AS branch_id,
         b.booking_kind INTO v_b
    FROM bookings b LEFT JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id AND b.user_id = v_uid;
  IF NOT FOUND OR v_b.branch_id IS NULL THEN RETURN jsonb_build_object('has_gate', false); END IF;
  v_gate := _booking_gate_code(p_booking_id);   -- NULL i u přistavení na adresu
  IF v_gate IS NULL THEN RETURN jsonb_build_object('has_gate', false); END IF;
  SELECT EXISTS (SELECT 1 FROM branch_door_codes c
                  WHERE c.booking_id = p_booking_id
                    AND (c.code_type = 'motorcycle' OR v_b.booking_kind = 'gear')
                    AND c.is_active AND c.sent_to_customer)
    INTO v_released;
  RETURN jsonb_build_object(
    'has_gate', true,
    'gate_code', CASE WHEN v_released AND v_b.status IN ('reserved', 'active') THEN v_gate END,
    'locker_door', _branch_locker_door_no(v_b.branch_id));
END;
$function$
;

-- Výpůjčka výbavy přesunutá na jinou pobočku → nový kód šatny tam + oznámení
DROP TRIGGER IF EXISTS trg_gear_codes_follow_branch ON public.bookings;
CREATE TRIGGER trg_gear_codes_follow_branch AFTER UPDATE OF branch_id ON public.bookings
  FOR EACH ROW WHEN (new.booking_kind = 'gear' AND old.branch_id IS DISTINCT FROM new.branch_id)
  EXECUTE FUNCTION public._gear_codes_follow_branch();
