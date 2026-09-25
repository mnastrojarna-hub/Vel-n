-- =============================================================================
-- MIGRACE: Vlastní výbava a kód šatny (rozhodnutí majitele 2026-09-25, návrh v2 §2a)
-- Datum: 2026-09-25 (a) — druhá část toku (protokol z kiosku) je v 20260925b.
-- Branch: claude/waveshare-doors-8-analysis-11h9zs
--
-- Pravidlo: kód ŠATNY dostane jen ten, kdo má v šatně co vyzvednout (půjčená
-- výbava řidiče NEBO boty NEBO výbava spolujezdce). Čistě „mám svoje" = žádný
-- kód šatny, šatna mu nejde otevřít. Dosud se VŽDY generovaly dva kódy.
--
--   1) bookings.own_gear (NULL = neuvedeno → odvodí se z prázdných velikostí
--      řidiče; staré appky/web posílají jen NULL velikosti), gear_collected_at
--      (první zavření šatny), handover_protocol_prompted_at (poslední výzva
--      k protokolu z kiosku — appka reaguje na KAŽDOU novou hodnotu).
--   2) _booking_needs_locker(uuid) = jediné místo, kde se nárok na šatnu
--      počítá; booking_needs_locker(uuid) = wrapper pro Velín (jen admin).
--   3) auto_generate_door_codes / regen_door_codes_for_booking vkládají
--      accessories řádek JEN při nároku; release_* a trg_notify_door_codes
--      posílají řádek „Kód šatny" jen když existuje (SMS/WA šablona
--      door_codes_moto_only bez kódu šatny). Texty „příslušenství" → „šatna".
--   4) update_booking_gear dostává p_own_gear (NULL = beze změny) — stará
--      signatura se DROPuje (overload = PGRST203 pro appku).
--   5) trg_sync_locker_code: změna výbavy po vygenerování kódů kód šatny
--      doplní (reaktivace neaktivního řádku / nový) nebo zadrží
--      (is_active=false, withheld_reason='Vlastní výbava'); po vyzvednutí
--      výbavy / podpisu protokolu už nic nemění.
--   6) trg_protect_handover_columns: zákazník (JWT) nesmí přes PostgREST
--      přepsat stav protokolu (RLS bookings_user_update nemá WITH CHECK).
-- Idempotentní; těla stávajících funkcí PŘEVZATA z živé DB (snapshot
-- 2026-09-25), změny jsou jen popsané bloky. Každá nová funkce má REVOKE.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Sloupce
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS own_gear boolean;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS gear_collected_at timestamptz;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS handover_protocol_prompted_at timestamptz;
COMMENT ON COLUMN public.bookings.own_gear IS 'Vlastní výbava řidiče: NULL = neuvedeno (odvodí se z prázdných velikostí řidiče), true/false = explicitní volba (appka/Velín). Nárok na kód šatny počítá _booking_needs_locker().';
COMMENT ON COLUMN public.bookings.gear_collected_at IS 'První zavření dveří šatny kódem této rezervace (trigger na branch_door_events). Po něm trg_sync_locker_code kód šatny už nemění.';
COMMENT ON COLUMN public.bookings.handover_protocol_prompted_at IS 'Poslední výzva k podpisu předávacího protokolu z kiosku (zavření šatny / zobrazení protokolu); appka reaguje na každou novou hodnotu. Zákazník sloupec měnit nesmí (trg_protect_handover_columns).';

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Nárok na šatnu
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._booking_needs_locker(p_booking_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_rider_own boolean;
BEGIN
  SELECT own_gear, helmet_size, jacket_size, pants_size, boots_size, gloves_size,
         passenger_helmet_size, passenger_jacket_size, passenger_pants_size,
         passenger_boots_size, passenger_gloves_size
    INTO r FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN false; END IF;

  -- řidič „mám svoje": explicitní volba, jinak prázdné velikosti řidiče
  v_rider_own := CASE WHEN r.own_gear IS NOT NULL THEN r.own_gear
                 ELSE (nullif(btrim(r.helmet_size), '') IS NULL
                   AND nullif(btrim(r.jacket_size), '') IS NULL
                   AND nullif(btrim(r.pants_size),  '') IS NULL
                   AND nullif(btrim(r.gloves_size), '') IS NULL) END;

  -- boty (placené extra) i výbava spolujezdce jsou v šatně vždy
  RETURN (NOT v_rider_own)
      OR nullif(btrim(r.boots_size), '')            IS NOT NULL
      OR nullif(btrim(r.passenger_helmet_size), '') IS NOT NULL
      OR nullif(btrim(r.passenger_jacket_size), '') IS NOT NULL
      OR nullif(btrim(r.passenger_pants_size),  '') IS NOT NULL
      OR nullif(btrim(r.passenger_boots_size),  '') IS NOT NULL
      OR nullif(btrim(r.passenger_gloves_size), '') IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._booking_needs_locker(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.booking_needs_locker(p_booking_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Velín (admin) nebo backend se service_role (auth.uid() NULL → is_admin() false)
  IF NOT (is_admin() OR auth.role() = 'service_role') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN public._booking_needs_locker(p_booking_id);
END;
$$;
REVOKE ALL ON FUNCTION public.booking_needs_locker(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.booking_needs_locker(uuid) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Generování kódů — accessories řádek jen při nároku na šatnu
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auto_generate_door_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_branch_id uuid;
  v_license_required text;
  v_has_docs boolean;
  v_withheld text;
  v_code1 text;
  v_code2 text;
  v_needs boolean;
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

  IF v_has_docs THEN
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        NEW.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || v_code1 ||
        CASE WHEN v_needs THEN E'\nKód šatny: ' || v_code2 ELSE '' END ||
        CASE WHEN v_needs THEN E'\nKódy jsou platné po dobu trvání pronájmu ('
             ELSE E'\nKód je platný po dobu trvání pronájmu (' END ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').',
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

CREATE OR REPLACE FUNCTION public.regen_door_codes_for_booking(p_booking_id uuid, p_reason text DEFAULT 'moto_change'::text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
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
      'Kód k motorce: ' || v_code1 || E'\n' ||
      CASE WHEN v_needs THEN 'Kód šatny: ' || v_code2 || E'\n' ELSE '' END ||
      CASE WHEN v_needs THEN 'Kódy jsou platné (' ELSE 'Kód je platný (' END ||
      TO_CHAR(v_b.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_b.end_date::date, 'DD.MM.YYYY') || ').' ||
      CASE WHEN v_branch_name IS NOT NULL THEN E'\nPobočka: ' || v_branch_name ELSE '' END ||
      CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END,
      'door_codes');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    SELECT phone, COALESCE(language, 'cs') INTO v_phone, v_lang FROM profiles WHERE id = v_b.user_id;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
      PERFORM send_sms_and_wa(v_phone,
        CASE WHEN v_needs THEN 'door_codes' ELSE 'door_codes_moto_only' END,
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', v_code1,
          'door_code_gear', CASE WHEN v_needs THEN v_code2 ELSE '' END
        ), v_b.user_id, p_booking_id, COALESCE(v_b.language, v_lang, 'cs'));
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- mail s novými kódy (dedup dle kódů → vždy odejde; GUC brání dvojímu
  -- odeslání, když ho už spustil trigger na admin_messages)
  PERFORM send_door_codes_email(p_booking_id, v_b.user_id);
  RETURN true;
END $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Uvolnění zadržených kódů — řádek „Kód šatny" jen když existuje
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.release_withheld_door_codes_for_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_booking record;
  v_withheld text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int;
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

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || COALESCE(v_code_moto,'–') || E'\n' ||
        CASE WHEN v_code_gear IS NOT NULL THEN 'Kód šatny: ' || v_code_gear || E'\n' ELSE '' END ||
        CASE WHEN v_code_gear IS NOT NULL THEN 'Kódy jsou platné po dobu trvání pronájmu ('
             ELSE 'Kód je platný po dobu trvání pronájmu (' END ||
        TO_CHAR(v_booking.start_date::date,'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date,'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone,
          CASE WHEN v_code_gear IS NOT NULL THEN 'door_codes' ELSE 'door_codes_moto_only' END,
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text,8)),
            'door_code_moto', COALESCE(v_code_moto,'–'),
            'door_code_gear', COALESCE(v_code_gear,'')
          ), v_booking.user_id, v_booking.booking_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM send_door_codes_email(v_booking.booking_id, v_booking.user_id);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes_for_user failed: %', SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_swap_next_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
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
    SELECT br.name, m.box_number, b.start_date::date, b.end_date::date
      INTO v_branch, v_box, v_start, v_end
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
      LEFT JOIN branches br   ON br.id = m.branch_id
     WHERE b.id = r.booking_id;

    -- a) in-app zpráva (+ push přes trg_push_on_admin_message) — zákazník stojí
    --    u kóje, e-mail sám o sobě nestačí
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (r.user_id, 'Nové přístupové kódy',
        'Původní motorka je vrácená — tady jsou kódy k nové:' || E'\n' ||
        'Kód k motorce: ' || COALESCE(v_code_moto, '—') || E'\n' ||
        CASE WHEN v_code_gear IS NOT NULL THEN 'Kód šatny: ' || v_code_gear || E'\n' ELSE '' END ||
        CASE WHEN v_code_gear IS NOT NULL THEN 'Kódy jsou platné (' ELSE 'Kód je platný (' END ||
        TO_CHAR(v_start, 'DD.MM.YYYY') || ' – ' || TO_CHAR(v_end, 'DD.MM.YYYY') || ').' ||
        CASE WHEN v_branch IS NOT NULL THEN E'\nPobočka: ' || v_branch ELSE '' END ||
        CASE WHEN v_box IS NOT NULL AND v_box > 0 THEN E'\nKóje: ' || v_box ELSE '' END,
        'door_codes');
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- b) SMS + WhatsApp (stejně jako při vydání kódů)
    BEGIN
      SELECT phone, COALESCE(language, 'cs') INTO v_phone, v_lang FROM profiles WHERE id = r.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' AND v_code_moto IS NOT NULL THEN
        PERFORM send_sms_and_wa(v_phone,
          CASE WHEN v_code_gear IS NOT NULL THEN 'door_codes' ELSE 'door_codes_moto_only' END,
          jsonb_build_object(
            'booking_number', upper(left(r.booking_id::text, 8)),
            'door_code_moto', v_code_moto,
            'door_code_gear', COALESCE(v_code_gear, '')
          ), r.user_id, r.booking_id, COALESCE(v_lang, 'cs'));
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

CREATE OR REPLACE FUNCTION public.release_my_door_codes(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid;
  v_booking record;
  v_reason text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int := 0;
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

  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (
      v_uid,
      'Přístupové kódy k pobočce',
      'Kód k motorce: ' || COALESCE(v_code_moto, '–') || E'\n' ||
      CASE WHEN v_code_gear IS NOT NULL THEN 'Kód šatny: ' || v_code_gear || E'\n' ELSE '' END ||
      CASE WHEN v_code_gear IS NOT NULL THEN 'Kódy jsou platné po dobu trvání pronájmu ('
           ELSE 'Kód je platný po dobu trvání pronájmu (' END ||
      TO_CHAR(v_booking.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_booking.end_date::date, 'DD.MM.YYYY') || ').',
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
        CASE WHEN v_code_gear IS NOT NULL THEN 'door_codes' ELSE 'door_codes_moto_only' END,
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', COALESCE(v_code_moto, '–'),
          'door_code_gear', COALESCE(v_code_gear, '')
        ),
        v_uid, p_booking_id
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

-- ─────────────────────────────────────────────────────────────────────────
-- 5) SMS/WA při vydání kódů: bez kódu šatny šablona door_codes_moto_only
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_notify_door_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_phone text;
  v_user_id uuid;
  v_booking_id uuid;
  v_lang text;
  v_code_moto text;
  v_code_gear text;
  v_already_sent boolean;
BEGIN
  IF NEW.code_type != 'motorcycle' THEN RETURN NEW; END IF;

  -- Najdi user_id přes booking_id
  SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;
  v_booking_id := NEW.booking_id;

  -- Dedup (obě šablony kódů)
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id AND template_slug IN ('door_codes', 'door_codes_moto_only') AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = v_user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Načti oba kódy (kód šatny existuje jen při nároku na šatnu)
  SELECT door_code INTO v_code_moto
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'motorcycle' AND is_active = true
   ORDER BY created_at DESC LIMIT 1;
  SELECT door_code INTO v_code_gear
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'accessories' AND is_active = true
   ORDER BY created_at DESC LIMIT 1;

  v_lang := detect_customer_language(v_user_id, v_booking_id, NULL);

  PERFORM send_sms_and_wa(
    v_phone,
    CASE WHEN v_code_gear IS NOT NULL THEN 'door_codes' ELSE 'door_codes_moto_only' END,
    jsonb_build_object(
      'booking_number',  upper(left(v_booking_id::text, 8)),
      'door_code_moto',  coalesce(v_code_moto, ''),
      'door_code_gear',  coalesce(v_code_gear, '')
    ),
    v_user_id,
    v_booking_id,
    v_lang
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_door_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Šablona SMS/WA bez kódu šatny (seed; Velín ji může upravit). Stávající
-- cs šablona door_codes: „Výbava:" → „Šatna:" jen pokud má dosud text ze seedu.
INSERT INTO public.message_templates (slug, channel, language, name, body_template, content, is_marketing, is_active)
SELECT 'door_codes_moto_only', c.channel, t.lang, 'Přístupový kód (jen motorka)', t.body, t.body, false, true
FROM (VALUES
  ('cs', 'Kód pro rezervaci {{booking_number}}: Motorka: {{door_code_moto}}. Šťastnou jízdu! MOTO GO 24'),
  ('en', 'Code for booking {{booking_number}}: Motorcycle: {{door_code_moto}}. Enjoy the ride! MOTO GO 24'),
  ('de', 'Code für Buchung {{booking_number}}: Motorrad: {{door_code_moto}}. Gute Fahrt! MOTO GO 24'),
  ('nl', 'Code voor boeking {{booking_number}}: Motor: {{door_code_moto}}. Goede rit! MOTO GO 24'),
  ('es', 'Código de la reserva {{booking_number}}: Moto: {{door_code_moto}}. ¡Buen viaje! MOTO GO 24'),
  ('fr', 'Code de la réservation {{booking_number}} : Moto : {{door_code_moto}}. Bonne route ! MOTO GO 24'),
  ('pl', 'Kod do rezerwacji {{booking_number}}: Motocykl: {{door_code_moto}}. Szerokiej drogi! MOTO GO 24')
) AS t(lang, body)
CROSS JOIN (VALUES ('sms'), ('whatsapp')) AS c(channel)
ON CONFLICT (slug, channel, language) DO NOTHING;

UPDATE public.message_templates
   SET body_template = replace(body_template, 'Výbava: {{door_code_gear}}', 'Šatna: {{door_code_gear}}'),
       content       = replace(content,       'Výbava: {{door_code_gear}}', 'Šatna: {{door_code_gear}}')
 WHERE slug = 'door_codes' AND language = 'cs'
   AND (body_template LIKE '%Výbava: {{door_code_gear}}%' OR content LIKE '%Výbava: {{door_code_gear}}%');

-- ─────────────────────────────────────────────────────────────────────────
-- 6) update_booking_gear + p_own_gear (NULL = beze změny) — DROP staré
--    signatury, jinak overload → PGRST203 pro appku. Tělo jinak 1:1.
-- ─────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.update_booking_gear(uuid, jsonb, boolean, boolean);
DROP FUNCTION IF EXISTS public.update_booking_gear(uuid, jsonb, boolean);
CREATE OR REPLACE FUNCTION public.update_booking_gear(p_booking_id uuid, p_sizes jsonb, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false, p_own_gear boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  b record;
  v_pp int; v_pbr int; v_pbp int;
  v_new_pass boolean; v_new_br boolean; v_new_bp boolean;
  v_old_paid int := 0; v_new_paid int := 0; v_diff int;
  s_h text; s_j text; s_p text; s_b text; s_g text;
  s_ph text; s_pj text; s_pp_ text; s_pb text; s_pg text;
  v_dtype text;
  v_calc jsonb;
  v_net_diff numeric;
  v_new_total numeric;
  v_new_discount numeric;
  v_loy_level int := 0;
  -- NOVÉ 2026-09-15: od ranku 3 je placená výbava u APP rezervací zdarma
  -- (parita s appkou: booking_models.dart loyaltyFreeGearLevel = 3).
  v_gear_free boolean := false;
  v_loy_pct numeric := 0;
  v_loy_disc numeric := 0;
  v_refund numeric := 0;
  v_manual boolean := false;
  v_url text; v_key text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','unauthenticated'); END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','not_found'); END IF;
  IF b.user_id <> v_uid AND NOT is_admin() THEN RETURN jsonb_build_object('success',false,'error','not_owner'); END IF;
  IF b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success',false,'error','wrong_status'); END IF;
  IF b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success',false,'error','not_paid'); END IF;

  SELECT COALESCE(MAX(CASE WHEN key='passenger_gear'  AND pricing_unit<>'free' THEN price_czk END),690),
         COALESCE(MAX(CASE WHEN key='boots_rider'     AND pricing_unit<>'free' THEN price_czk END),290),
         COALESCE(MAX(CASE WHEN key='boots_passenger' AND pricing_unit<>'free' THEN price_czk END),290)
    INTO v_pp, v_pbr, v_pbp
    FROM accessory_types WHERE key IN ('passenger_gear','boots_rider','boots_passenger');

  -- Rank spočítej VŽDY (ne jen u doplatku) — rozhoduje o nároku na výbavu
  -- zdarma. Gate na booking_source='app' je stejný jako u věrnostní % slevy:
  -- web rezervace nemá věrnostní výhodu, ať ji upravuje kdokoli odkudkoli.
  IF COALESCE(b.booking_source, 'web') = 'app' THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    v_gear_free := v_loy_level >= 3;
  END IF;

  s_h  := NULLIF(p_sizes->>'helmet','');  s_j := NULLIF(p_sizes->>'jacket','');
  s_p  := NULLIF(p_sizes->>'pants','');   s_b := NULLIF(p_sizes->>'boots','');
  s_g  := NULLIF(p_sizes->>'gloves','');
  s_ph := NULLIF(p_sizes->>'passenger_helmet','');  s_pj := NULLIF(p_sizes->>'passenger_jacket','');
  s_pp_:= NULLIF(p_sizes->>'passenger_pants','');   s_pb := NULLIF(p_sizes->>'passenger_boots','');
  s_pg := NULLIF(p_sizes->>'passenger_gloves','');

  v_new_pass := (s_ph IS NOT NULL OR s_pj IS NOT NULL OR s_pp_ IS NOT NULL OR s_pg IS NOT NULL);
  v_new_br   := (s_b  IS NOT NULL);
  v_new_bp   := (s_pb IS NOT NULL);
  IF v_new_pass THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pp  END; END IF;
  IF v_new_br   THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pbr END; END IF;
  IF v_new_bp   THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pbp END; END IF;

  -- OPRAVA 2026-09-15: baseline = co je REÁLNĚ uložené v booking_extras, ne
  -- dnešní ceník. Původní verze dopočítávala cenu z NÁZVU řádku, takže řádek
  -- za 0 Kč (výbava zdarma od ranku 3) ocenila plnou cenou → při odebrání
  -- výbavy se vracely peníze, které zákazník nikdy nezaplatil. Filtr je
  -- shodný s DELETE níže, aby se nepočítaly nemodelované doplňky (vozík…).
  SELECT COALESCE(ROUND(SUM(COALESCE(unit_price,0) * COALESCE(quantity,1))),0)::int
  INTO v_old_paid FROM booking_extras WHERE booking_id = p_booking_id
    AND ( lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%'
       OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );

  v_diff := v_new_paid - v_old_paid;

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — app rezervace, kladný rozdíl výbavy ──
  -- Výbava je součást loyalty base i při vzniku rezervace; doplatek za
  -- přidanou výbavu se sníží o pct dle aktuálního ranku.
  IF COALESCE(b.booking_source, 'web') = 'app' AND v_diff > 0 THEN
    -- v_loy_level je spočítaný výše (nároky na výbavu zdarma) — nepočítat 2×.
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND(v_diff * v_loy_pct / 100.0);
  END IF;

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  -- v_diff je HRUBÝ rozdíl výbavy; net_diff (po slevě) je to, co se účtuje /
  -- vrací zákazníkovi. Loyalty sleva se odečítá už z gross rozdílu.
  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(b.id, b.total_price, b.discount_amount, v_diff - v_loy_disc, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_manual := (b.stripe_payment_intent_id IS NULL AND b.stripe_session_id IS NULL);

  IF p_dry_run THEN
    RETURN jsonb_build_object('success',true,'payment_required', v_net_diff>0,'net_diff',v_net_diff,
      'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
      'refund_manual', v_manual,
      'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
  END IF;

  UPDATE bookings SET
    helmet_size=s_h, jacket_size=s_j, pants_size=s_p, boots_size=s_b, gloves_size=s_g,
    passenger_helmet_size = CASE WHEN v_new_pass THEN s_ph  ELSE NULL END,
    passenger_jacket_size = CASE WHEN v_new_pass THEN s_pj  ELSE NULL END,
    passenger_pants_size  = CASE WHEN v_new_pass THEN s_pp_ ELSE NULL END,
    passenger_gloves_size = CASE WHEN v_new_pass THEN s_pg  ELSE NULL END,
    passenger_boots_size  = CASE WHEN v_new_bp   THEN s_pb  ELSE NULL END,
    -- 2026-09-25: vlastní výbava (NULL = beze změny) → trg_sync_locker_code řeší kód šatny
    own_gear = COALESCE(p_own_gear, own_gear),
    extras_price = GREATEST(0, COALESCE(extras_price,0) + v_diff),
    total_price  = v_new_total,
    discount_amount = v_new_discount,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level   = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END
  WHERE id = p_booking_id;

  DELETE FROM booking_extras WHERE booking_id = p_booking_id
    AND ( lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%'
       OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );
  -- Řádky se ukládají za cenu, která se SKUTEČNĚ účtovala (0 Kč od ranku 3),
  -- aby SUM(booking_extras.unit_price) = bookings.extras_price a faktury
  -- (ZF/DP/KF) vykázaly správnou cenu pronájmu.
  IF v_new_pass THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Výbava spolujezdce',CASE WHEN v_gear_free THEN 0 ELSE v_pp  END,1); END IF;
  IF v_new_br   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty řidič',      CASE WHEN v_gear_free THEN 0 ELSE v_pbr END,1); END IF;
  IF v_new_bp   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty spolujezdce',CASE WHEN v_gear_free THEN 0 ELSE v_pbp END,1); END IF;

  -- Vratka AŽ PO úspěšném commitu (2026-08-22) — dřív ji klient volal PŘED
  -- uložením a selhaný commit nechal „osiřelý" refund (incident DB-2026-0008/9).
  IF p_settle_refund AND v_net_diff < -0.5 THEN
    v_refund := -v_net_diff;
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'gear_edit', 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('update_booking_gear','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('update_booking_gear','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object('success',true,'payment_required',false,'net_diff',v_net_diff,
    'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
    'refund_dispatched', (v_refund > 0), 'refund_manual', v_manual,
    'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
END;
$$;
REVOKE ALL ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 7) Změna výbavy po vygenerování kódů → kód šatny doplnit / zadržet
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._sync_locker_code()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moto branch_door_codes%ROWTYPE;
  v_acc  branch_door_codes%ROWTYPE;
  v_old  branch_door_codes%ROWTYPE;
  v_needs boolean;
  v_code  text;
BEGIN
  -- Výbava už vyzvednutá / protokol podepsaný / testovací rezervace → nic
  IF NEW.is_test IS TRUE OR NEW.gear_collected_at IS NOT NULL
     OR NEW.handover_protocol_filled_at IS NOT NULL THEN
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
      BEGIN
        INSERT INTO admin_messages (user_id, booking_id, title, message, type)
        VALUES (NEW.user_id, NEW.id, 'Kód šatny',
          'Byl vám přidán kód šatny: ' || v_code || E'\nKód k motorce zůstává: ' || v_moto.door_code || '.',
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
$$;
REVOKE ALL ON FUNCTION public._sync_locker_code() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_locker_code ON public.bookings;
CREATE TRIGGER trg_sync_locker_code
  AFTER UPDATE OF own_gear, helmet_size, jacket_size, pants_size, boots_size, gloves_size,
    passenger_helmet_size, passenger_jacket_size, passenger_pants_size, passenger_boots_size, passenger_gloves_size
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._sync_locker_code();

-- ─────────────────────────────────────────────────────────────────────────
-- 8) Historie změn: own_gear do gear diffu (tělo jinak 1:1 z živé DB)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.track_booking_content_changes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry  jsonb;
  v_gear   jsonb := '{}'::jsonb;
  v_uid    uuid;
  v_source text;
  v_from_moto text;
  v_to_moto   text;
  v_changed boolean;
BEGIN
  -- Volající už zapsal vlastní záznam v tomto UPDATE → nic nepřidávat
  IF NEW.modification_history IS DISTINCT FROM OLD.modification_history THEN
    RETURN NEW;
  END IF;

  BEGIN
    -- Výbava (jen změněná pole)
    IF NEW.helmet_size IS DISTINCT FROM OLD.helmet_size THEN
      v_gear := v_gear || jsonb_build_object('helmet', jsonb_build_object('from', OLD.helmet_size, 'to', NEW.helmet_size));
    END IF;
    IF NEW.jacket_size IS DISTINCT FROM OLD.jacket_size THEN
      v_gear := v_gear || jsonb_build_object('jacket', jsonb_build_object('from', OLD.jacket_size, 'to', NEW.jacket_size));
    END IF;
    IF NEW.pants_size IS DISTINCT FROM OLD.pants_size THEN
      v_gear := v_gear || jsonb_build_object('pants', jsonb_build_object('from', OLD.pants_size, 'to', NEW.pants_size));
    END IF;
    IF NEW.boots_size IS DISTINCT FROM OLD.boots_size THEN
      v_gear := v_gear || jsonb_build_object('boots', jsonb_build_object('from', OLD.boots_size, 'to', NEW.boots_size));
    END IF;
    IF NEW.gloves_size IS DISTINCT FROM OLD.gloves_size THEN
      v_gear := v_gear || jsonb_build_object('gloves', jsonb_build_object('from', OLD.gloves_size, 'to', NEW.gloves_size));
    END IF;
    IF NEW.passenger_helmet_size IS DISTINCT FROM OLD.passenger_helmet_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_helmet', jsonb_build_object('from', OLD.passenger_helmet_size, 'to', NEW.passenger_helmet_size));
    END IF;
    IF NEW.passenger_jacket_size IS DISTINCT FROM OLD.passenger_jacket_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_jacket', jsonb_build_object('from', OLD.passenger_jacket_size, 'to', NEW.passenger_jacket_size));
    END IF;
    IF NEW.passenger_pants_size IS DISTINCT FROM OLD.passenger_pants_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_pants', jsonb_build_object('from', OLD.passenger_pants_size, 'to', NEW.passenger_pants_size));
    END IF;
    IF NEW.passenger_boots_size IS DISTINCT FROM OLD.passenger_boots_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_boots', jsonb_build_object('from', OLD.passenger_boots_size, 'to', NEW.passenger_boots_size));
    END IF;
    IF NEW.passenger_gloves_size IS DISTINCT FROM OLD.passenger_gloves_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_gloves', jsonb_build_object('from', OLD.passenger_gloves_size, 'to', NEW.passenger_gloves_size));
    END IF;
    -- 2026-09-25: vlastní výbava (rozhoduje o kódu šatny)
    IF NEW.own_gear IS DISTINCT FROM OLD.own_gear THEN
      v_gear := v_gear || jsonb_build_object('own_gear', jsonb_build_object('from', OLD.own_gear, 'to', NEW.own_gear));
    END IF;

    v_changed := (
      NEW.start_date      IS DISTINCT FROM OLD.start_date
      OR NEW.end_date     IS DISTINCT FROM OLD.end_date
      OR NEW.pickup_time  IS DISTINCT FROM OLD.pickup_time
      OR NEW.return_time  IS DISTINCT FROM OLD.return_time
      OR NEW.moto_id      IS DISTINCT FROM OLD.moto_id
      OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
      OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
      OR NEW.return_method  IS DISTINCT FROM OLD.return_method
      OR NEW.return_address IS DISTINCT FROM OLD.return_address
      OR v_gear <> '{}'::jsonb
    );
    IF NOT v_changed THEN
      RETURN NEW;
    END IF;

    v_uid := auth.uid();
    IF v_uid IS NULL THEN
      v_source := 'system';
    ELSIF v_uid = COALESCE(NEW.user_id, OLD.user_id) THEN
      v_source := 'customer';
    ELSIF public.is_admin() THEN
      v_source := 'admin';
    ELSE
      v_source := 'system';
    END IF;

    v_entry := jsonb_build_object(
      'at', now(), 'auto', true, 'source', v_source,
      'from_start', OLD.start_date, 'from_end', OLD.end_date,
      'to_start',   NEW.start_date, 'to_end',   NEW.end_date
    );

    IF NEW.pickup_time IS DISTINCT FROM OLD.pickup_time THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_time', OLD.pickup_time::text, 'to_pickup_time', NEW.pickup_time::text);
    END IF;
    IF NEW.return_time IS DISTINCT FROM OLD.return_time THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_time', OLD.return_time::text, 'to_return_time', NEW.return_time::text);
    END IF;

    IF NEW.moto_id IS DISTINCT FROM OLD.moto_id THEN
      SELECT model INTO v_from_moto FROM motorcycles WHERE id = OLD.moto_id;
      SELECT model INTO v_to_moto   FROM motorcycles WHERE id = NEW.moto_id;
      v_entry := v_entry || jsonb_build_object(
        'from_moto', COALESCE(v_from_moto, OLD.moto_id::text),
        'to_moto',   COALESCE(v_to_moto,   NEW.moto_id::text));
    END IF;

    IF NEW.pickup_method IS DISTINCT FROM OLD.pickup_method THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_method', OLD.pickup_method, 'to_pickup_method', NEW.pickup_method);
    END IF;
    IF NEW.pickup_address IS DISTINCT FROM OLD.pickup_address THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_address', OLD.pickup_address, 'to_pickup_address', NEW.pickup_address);
    END IF;
    IF NEW.return_method IS DISTINCT FROM OLD.return_method THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_method', OLD.return_method, 'to_return_method', NEW.return_method);
    END IF;
    IF NEW.return_address IS DISTINCT FROM OLD.return_address THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_address', OLD.return_address, 'to_return_address', NEW.return_address);
    END IF;

    IF v_gear <> '{}'::jsonb THEN
      v_entry := v_entry || jsonb_build_object('gear_changes', v_gear);
    END IF;

    NEW.modification_history := COALESCE(OLD.modification_history, '[]'::jsonb) || v_entry;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO debug_log(source, action, status, error_message)
      VALUES ('track_booking_content_changes', 'append_history', 'error', SQLERRM);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 9) Zákazník si nesmí sám „podepsat" protokol přes PostgREST
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._protect_handover_columns()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Běžný JWT zákazníka (service_role, edge fn i triggery mají auth.uid() NULL;
  -- Velín = admin). Stav protokolu / šatny nastavuje jen backend.
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    NEW.handover_protocol_started_at   := OLD.handover_protocol_started_at;
    NEW.handover_protocol_filled_at    := OLD.handover_protocol_filled_at;
    NEW.handover_protocol_autofilled   := OLD.handover_protocol_autofilled;
    NEW.handover_protocol_prompted_at  := OLD.handover_protocol_prompted_at;
    NEW.gear_collected_at              := OLD.gear_collected_at;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._protect_handover_columns() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_protect_handover_columns ON public.bookings;
CREATE TRIGGER trg_protect_handover_columns
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._protect_handover_columns();

NOTIFY pgrst, 'reload schema';
