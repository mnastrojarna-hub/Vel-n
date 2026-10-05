-- 2026-10-05 — přístupové kódy musí být VŽDY aktuální a VŽDY fungovat (zadání majitele, samoobsluha Velké Němčice):
-- „Jakmile změním motorku / pozici v kiosku ve Velíně, nebo zákazník už nějak dostal kódy, kiosek musí vždy
--  reflektovat, že se motorka změnila. Kódy ve Velíně, v posledním mailu / úpravě a v detailu rezervace musí vždy
--  fungovat.“ Incident: kódy přestaly fungovat po přesunech kójí a po smazání rezervace ve Velíně.
--
-- (1) KÓD = IDENTITA REZERVACE, ne kóje ani motorky. Dosud přesun motorky do jiné kóje, změna motorky v rezervaci
--     i přesun na jinou pobočku vždy vygenerovaly NOVÉ kódy (regen_door_codes_for_booking) — staré ze SMS / mailu
--     přestaly platit a zákazníci je zadávali do kiosku (PIN lockout pro všechny). Kiosk si kóji bere z motorky
--     rezervace (20261005b), nový kód kvůli kóji není potřeba. Nově `_door_codes_follow_moto`:
--       - přesun do jiné kóje / změna motorky na téže pobočce → ČÍSLA SE NEMĚNÍ (jen moto_id + kiosk_request_sync);
--       - jiná pobočka → stejná čísla se přenesou (branch_id, moto_id); nové číslo JEN při kolizi na cílové pobočce
--         (starý řádek superseded_by_regen); zákazník dostane zprávu s pobočkou + kódy (appka + SMS/WA + mail);
--       - rezervace bez aktivního kódu → původní plné vydání (regen_door_codes_for_booking: doklady, zprávy);
--       - motorka mimo pobočku (branch_id NULL) → kódy zneplatnit (jako dřív).
-- (2) SMAZÁNÍ ŽIVÉ REZERVACE (Velín „Smazat“ = tvrdý DELETE bez storna: kódy zmizely beze stopy, zákazník nic
--     nedostal, staré kódy ze SMS zablokovaly kiosk) → BEFORE DELETE trigger odmítne smazat rezervaci reserved/active
--     nebo s vydanými kódy („nejdřív Storno“); testovací rezervace / účty a GUC motogo.allow_booking_delete = '1' projdou.
-- (3) Doklady zákazníka (documents) přežijí smazání rezervace: FK booking_id ON DELETE SET NULL (dřív CASCADE —
--     smazání rezervace smazalo fotky dokladů z webu a další kódy pak zůstaly zadržené „Chybí doklady“).
--     Při změně motorky jiné kategorie řidičáku (license_required) se znovu ověří doklady (bez ověřeného ŘP se kód
--     zadrží / po změně na motorku bez ŘP se zadržený kód uvolní + zpráva); výměna motorky (continues_booking_id) na
--     samoobslužné pobočce kód zadrží „Vraťte nejdřív původní motorku“ i při přenosu (dřív to dělal jen INSERT).
-- (4) Výměna motorky: kód navazující rezervace se uvolní i při STORNU původní rezervace, ale JEN když původní motorka
--     nebyla předaná (picked_up_at / protokol prázdné) — dřív po stornu zůstal zadržený navždy; stejné pravidlo
--     v withhold_swap_next_codes (sdílený helper _swap_predecessor_pending).
-- (5) Alias (superseded_by_regen) jde zrušit: ruční změna is_active (Velín Aktivovat / Zneplatnit, storno …) příznak
--     řádku vynuluje a ruční zneplatnění kódu zruší i aliasy téže rezervace a typu (únik staré SMS → obsluha zneplatní).
-- Idempotentní (CREATE OR REPLACE, DROP … IF EXISTS).

-- (4) výměna motorky: čeká navazující rezervace na vrácení původní motorky?
CREATE OR REPLACE FUNCTION public._swap_predecessor_pending(p_booking_id uuid, p_branch_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_cont uuid;
BEGIN
  SELECT continues_booking_id INTO v_cont FROM bookings WHERE id = p_booking_id;
  IF v_cont IS NULL THEN RETURN false; END IF;
  IF NOT EXISTS (SELECT 1 FROM branches br WHERE br.id = p_branch_id AND br.type = 'samoobslužná') THEN RETURN false; END IF;
  -- vrácená / dokončená, nebo stornovaná a NIKDY nepředaná původní rezervace = nečeká se
  RETURN NOT EXISTS (SELECT 1 FROM bookings a WHERE a.id = v_cont
                       AND (a.returned_at IS NOT NULL OR a.status = 'completed'
                            OR (a.status = 'cancelled' AND a.picked_up_at IS NULL AND a.handover_protocol_filled_at IS NULL)));
END $$;
ALTER FUNCTION public._swap_predecessor_pending(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._swap_predecessor_pending(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.withhold_swap_next_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_branch uuid;
BEGIN
  IF NEW.code_type <> 'motorcycle' THEN RETURN NEW; END IF;
  SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF public._swap_predecessor_pending(NEW.booking_id, v_branch) THEN
    NEW.sent_to_customer := false;
    NEW.withheld_reason := 'Vraťte nejdřív původní motorku';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END $$;

-- (1) kódy následují motorku rezervace
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

CREATE OR REPLACE FUNCTION public.regen_door_codes_on_moto_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('active','reserved') THEN RETURN NEW; END IF;
  PERFORM public._door_codes_follow_moto(NEW.id, 'moto_change');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'regen_door_codes_on_moto_change failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION public.regen_door_codes_on_moto_change() IS
  'Změna motorky v rezervaci → _door_codes_follow_moto (od 2026-10-05 čísla kódů beze změny, jiná pobočka = přenos).';

CREATE OR REPLACE FUNCTION public.regen_door_codes_on_moto_relocation()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_reason text;
BEGIN
  IF OLD.branch_id IS NOT DISTINCT FROM NEW.branch_id
     AND OLD.box_number IS NOT DISTINCT FROM NEW.box_number THEN
    RETURN NEW;
  END IF;
  -- dočasná / nepřiřazená kóje (Velín při prohazování ukládá -1) → až finální hodnota
  IF OLD.branch_id IS NOT DISTINCT FROM NEW.branch_id
     AND (NEW.box_number IS NULL OR NEW.box_number < 0) THEN
    RETURN NEW;
  END IF;
  v_reason := CASE WHEN OLD.branch_id IS DISTINCT FROM NEW.branch_id THEN 'branch_move' ELSE 'box_move' END;

  FOR r IN
    SELECT id FROM bookings
     WHERE moto_id = NEW.id AND status IN ('active','reserved') AND is_test IS NOT TRUE
     ORDER BY start_date
  LOOP
    BEGIN
      PERFORM public._door_codes_follow_moto(r.id, v_reason);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'regen_door_codes_on_moto_relocation: booking % failed: %', r.id, SQLERRM;
    END;
  END LOOP;
  -- offline cache obou jednotek (kóje motorky v codes[]) i bez rezervací
  IF NEW.branch_id IS NOT NULL THEN PERFORM public.kiosk_request_sync(NEW.branch_id); END IF;
  IF OLD.branch_id IS NOT NULL AND OLD.branch_id IS DISTINCT FROM NEW.branch_id THEN
    PERFORM public.kiosk_request_sync(OLD.branch_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'regen_door_codes_on_moto_relocation failed for moto %: %', NEW.id, SQLERRM;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION public.regen_door_codes_on_moto_relocation() IS
  'Přesun motorky (kóje / pobočka) → _door_codes_follow_moto pro živé rezervace + kiosk_request_sync (od 2026-10-05 přesun kóje kódy nemění).';

-- (2) živou rezervaci nelze tvrdě smazat
CREATE OR REPLACE FUNCTION public.guard_booking_delete()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.is_test IS TRUE OR current_setting('motogo.allow_booking_delete', true) = '1'
     OR EXISTS (SELECT 1 FROM profiles p WHERE p.id = OLD.user_id AND p.is_test_account IS TRUE) THEN
    RETURN OLD;
  END IF;
  IF OLD.status IN ('reserved','active')
     OR EXISTS (SELECT 1 FROM branch_door_codes c WHERE c.booking_id = OLD.id AND c.is_active AND c.sent_to_customer) THEN
    RAISE EXCEPTION 'Rezervaci nelze smazat — je potvrzená nebo probíhá a zákazník má přístupové kódy. Nejdřív ji stornujte (zákazník dostane oznámení a kódy se zneplatní), pak ji lze smazat.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN OLD;
END $$;
ALTER FUNCTION public.guard_booking_delete() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.guard_booking_delete() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_booking_delete ON public.bookings;
CREATE TRIGGER trg_guard_booking_delete BEFORE DELETE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.guard_booking_delete();

-- (3) doklady zákazníka nepatří rezervaci — smazání rezervace je nesmaže
ALTER TABLE public.documents DROP CONSTRAINT IF EXISTS documents_booking_id_fkey;
ALTER TABLE public.documents ADD CONSTRAINT documents_booking_id_fkey
  FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL;

-- (4) výměna motorky: uvolnit navazující kód i po stornu původní rezervace
-- tělo = živý snapshot 2026-10-05 + jen text zprávy u storna (původní motorka nebyla vrácená, ale nikdy předaná)
CREATE OR REPLACE FUNCTION "public"."release_swap_next_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
$$;

DROP TRIGGER IF EXISTS trg_release_swap_next_codes ON public.bookings;
CREATE TRIGGER trg_release_swap_next_codes AFTER UPDATE OF status, returned_at ON public.bookings
  FOR EACH ROW WHEN (((new.status = 'completed'::booking_status) OR (new.returned_at IS NOT NULL)
                      OR (new.status = 'cancelled'::booking_status AND new.picked_up_at IS NULL
                          AND new.handover_protocol_filled_at IS NULL))
                     AND ((old.status IS DISTINCT FROM new.status) OR (old.returned_at IS DISTINCT FROM new.returned_at)))
  EXECUTE FUNCTION public.release_swap_next_codes();

-- (5) alias jde zrušit: ruční změna is_active vynuluje příznak řádku; ruční zneplatnění zruší i aliasy rezervace
CREATE OR REPLACE FUNCTION public._door_code_superseded_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- _door_codes_follow_moto mění is_active i superseded_by_regen v jednom UPDATE → zůstane; jinak (Velín
  -- Aktivovat / Zneplatnit, storno, vlastní výbava) už řádek není „automaticky nahrazený“
  IF NEW.is_active IS DISTINCT FROM OLD.is_active AND NEW.superseded_by_regen IS NOT DISTINCT FROM OLD.superseded_by_regen THEN
    NEW.superseded_by_regen := false;
  END IF;
  RETURN NEW;
END $$;
ALTER FUNCTION public._door_code_superseded_guard() OWNER TO postgres;
DROP TRIGGER IF EXISTS trg_door_code_superseded_guard ON public.branch_door_codes;
CREATE TRIGGER trg_door_code_superseded_guard BEFORE UPDATE OF is_active ON public.branch_door_codes
  FOR EACH ROW EXECUTE FUNCTION public._door_code_superseded_guard();

CREATE OR REPLACE FUNCTION public._door_code_manual_revoke()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ručně zneplatněný kód (např. únik staré SMS) → přestanou platit i dřívější aliasy téže rezervace a typu
  UPDATE branch_door_codes SET superseded_by_regen = false
   WHERE booking_id = NEW.booking_id AND code_type = NEW.code_type AND superseded_by_regen AND id <> NEW.id;
  RETURN NULL;
END $$;
ALTER FUNCTION public._door_code_manual_revoke() OWNER TO postgres;
REVOKE ALL ON FUNCTION public._door_code_manual_revoke() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_door_code_manual_revoke ON public.branch_door_codes;
CREATE TRIGGER trg_door_code_manual_revoke AFTER UPDATE OF is_active ON public.branch_door_codes
  FOR EACH ROW WHEN (OLD.is_active AND NOT NEW.is_active AND NOT NEW.superseded_by_regen)
  EXECUTE FUNCTION public._door_code_manual_revoke();
