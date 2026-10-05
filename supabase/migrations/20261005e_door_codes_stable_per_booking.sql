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
-- (4) Výměna motorky: kód navazující rezervace zadržený „Vraťte nejdřív původní motorku“ se uvolní i při STORNU
--     původní rezervace (dřív jen vrácení / dokončení → po stornu zůstal zadržený navždy).
-- Idempotentní (CREATE OR REPLACE, DROP … IF EXISTS).

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

  -- offline cache jednotky (kóje motorky / řádky kódů) — trg_door_codes_kiosk_sync na moto_id nereaguje
  PERFORM public.kiosk_request_sync(v_branch);
  IF NOT v_moved THEN RETURN; END IF;   -- jiná kóje / motorka na téže pobočce: kódy platí dál, kiosk ukáže kóji

  -- jiná pobočka → zákazník musí vědět kam (appka + SMS/WA + mail), jen u vydaných kódů
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
    VALUES (v_b.user_id, p_booking_id, 'Přístupové kódy — jiná pobočka',
      'Vaše motorka byla přesunuta na pobočku ' || coalesce(v_branch_name, '') ||
      CASE WHEN v_changed THEN ' – nové kódy:' ELSE ' – kódy platí dál:' END || E'\n' ||
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
  'Kódy rezervace následují její motorku (2026-10-05): jiná kóje / motorka na téže pobočce = čísla beze změny; jiná pobočka = táž čísla přenesená (nové jen při kolizi) + zpráva zákazníkovi; bez aktivního kódu = regen_door_codes_for_booking (první vydání); motorka bez pobočky = zneplatnit.';

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
DROP TRIGGER IF EXISTS trg_release_swap_next_codes ON public.bookings;
CREATE TRIGGER trg_release_swap_next_codes AFTER UPDATE OF status, returned_at ON public.bookings
  FOR EACH ROW WHEN (((new.status = ANY (ARRAY['completed'::booking_status, 'cancelled'::booking_status]))
                      OR (new.returned_at IS NOT NULL))
                     AND ((old.status IS DISTINCT FROM new.status) OR (old.returned_at IS DISTINCT FROM new.returned_at)))
  EXECUTE FUNCTION public.release_swap_next_codes();
