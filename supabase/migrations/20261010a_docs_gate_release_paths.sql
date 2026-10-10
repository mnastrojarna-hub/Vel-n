-- ============================================================================
-- PŘÍSTUPOVÉ KÓDY JEN S KOMPLETNÍMI DOKLADY — cesty vydání (2026-10-10, 2/4)
-- Pravidlo a jádro viz `20261010_docs_gate_core.sql` (`booking_docs_gate`).
--
-- * `auto_generate_door_codes`: místo vlastní (ještě volnější, bez platnosti
--   ŘP) inline kontroly volá `booking_docs_gate` — tělo jinak 1:1 z živé DB.
-- * `release_withheld_door_codes_for_user`: kontrola PER REZERVACE s motorkou
--   (dřív bez motorky → bez dětské výjimky a bez skupiny); zprávy / SMS
--   skládá jen z OPRAVDU vydaných kódů; EXECUTE jen interně (dřív anon/auth
--   pro libovolného uživatele). Totéž `send_door_codes_email`.
-- * Přepočet i po doplnění data narození / skupiny / platnosti ŘP v profilu
--   a po opravě strany / typu dokladu ve Velínu (UPDATE documents).
-- Další cesty (release_my / swap / SMS trigger, pojistný cron) `20261010d`.
-- ============================================================================

-- 1) auto_generate_door_codes ------------------------------------------------
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
$function$;

-- 2) release_withheld_door_codes_for_user -------------------------------------
CREATE OR REPLACE FUNCTION public.release_withheld_door_codes_for_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_booking record;
  v_withheld text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int;
  v_branch uuid;
  v_gate text;
  v_door integer;
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
      -- kódy držené kvůli nevrácené původní motorce uvolní až vrácení stroje
      AND bdc.withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
  LOOP
    -- 2026-10-10: přísná brána PER REZERVACE (motorka → skupina / dětská, začátek → věk)
    v_withheld := public.booking_docs_gate(v_booking.booking_id);
    IF v_withheld IS NOT NULL THEN
      UPDATE branch_door_codes
      SET withheld_reason = v_withheld
      WHERE booking_id = v_booking.booking_id
        AND is_active = true
        AND sent_to_customer = false
        AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku'
        AND withheld_reason IS DISTINCT FROM v_withheld;
      CONTINUE; -- neuvolňujeme
    END IF;

    UPDATE branch_door_codes
    SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false
      AND withheld_reason IS DISTINCT FROM 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released = 0 THEN CONTINUE; END IF;

    -- Do zprávy JEN opravdu vydané kódy (pojistka trg_zz_door_codes_docs_gate)
    v_code_moto := NULL; v_code_gear := NULL;
    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active AND sent_to_customer LIMIT 1;
    IF v_code_moto IS NULL THEN CONTINUE; END IF;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active AND sent_to_customer LIMIT 1;

    -- Brána se schránkou na klíč (Velké Němčice, 2026-10-04)
    SELECT m.branch_id INTO v_branch FROM bookings b JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.id = v_booking.booking_id;
    v_gate := public._booking_gate_code(v_booking.booking_id);   -- NULL u přistavení na adresu
    v_door := CASE WHEN v_gate IS NOT NULL THEN public._branch_locker_door_no(v_branch) END;

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        public._door_codes_msg_lines(v_gate, v_door, v_code_gear, v_code_moto) || E'\n' ||
        public._door_codes_msg_valid(v_gate, v_code_gear IS NOT NULL, true) ||
        TO_CHAR(v_booking.start_date::date,'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date,'DD.MM.YYYY') || ').' ||
        public._gate_procedure_msg(v_gate, v_door, v_code_gear IS NOT NULL),
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone,
          public._door_codes_sms_slug(v_gate, v_code_gear IS NOT NULL),
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text,8)),
            'door_code_moto', v_code_moto,
            'door_code_gear', COALESCE(v_code_gear,'')
          ) || CASE WHEN v_gate IS NOT NULL THEN jsonb_build_object('gate_code', v_gate) ELSE '{}'::jsonb END,
          v_booking.user_id, v_booking.booking_id,
          public._door_codes_sms_lang(v_booking.user_id, v_booking.booking_id));
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM send_door_codes_email(v_booking.booking_id, v_booking.user_id);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes_for_user failed: %', SQLERRM;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.release_withheld_door_codes_for_user(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_withheld_door_codes_for_user(uuid) TO service_role;
-- Mail s kódy posílají jen DB funkce (dřív ho šlo spustit anonymně pro cizí rezervaci)
REVOKE EXECUTE ON FUNCTION public.send_door_codes_email(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_door_codes_email(uuid, uuid) TO service_role;

-- 3) Přepočet po změně profilu: i datum narození, skupina a platnost ŘP --------
CREATE OR REPLACE FUNCTION public.release_codes_on_profile_verify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF NEW.id_verified_at      IS DISTINCT FROM OLD.id_verified_at
  OR NEW.passport_verified_at IS DISTINCT FROM OLD.passport_verified_at
  OR NEW.license_verified_at IS DISTINCT FROM OLD.license_verified_at
  OR NEW.id_number           IS DISTINCT FROM OLD.id_number
  OR NEW.license_number      IS DISTINCT FROM OLD.license_number
  OR NEW.date_of_birth       IS DISTINCT FROM OLD.date_of_birth
  OR NEW.license_group       IS DISTINCT FROM OLD.license_group
  OR NEW.license_expiry      IS DISTINCT FROM OLD.license_expiry
  OR NEW.license_verified_until IS DISTINCT FROM OLD.license_verified_until
  THEN
    PERFORM release_withheld_door_codes_for_user(NEW.id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_release_codes_on_profile_verify ON public.profiles;
CREATE TRIGGER trg_release_codes_on_profile_verify
  AFTER UPDATE OF id_verified_at, passport_verified_at, license_verified_at, id_number, license_number,
                  date_of_birth, license_group, license_expiry, license_verified_until
  ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.release_codes_on_profile_verify();

-- 4) Oprava strany / typu dokladu (Velín „⇄ Je to rub“) → přepočet -----------
DROP TRIGGER IF EXISTS trg_release_codes_on_doc_update ON public.documents;
CREATE TRIGGER trg_release_codes_on_doc_update
  AFTER UPDATE OF type, metadata, file_path, user_id ON public.documents
  FOR EACH ROW
  WHEN (NEW.type IN ('id_card', 'passport', 'drivers_license', 'id_photo', 'license_photo'))
  EXECUTE FUNCTION public.release_withheld_door_codes();
