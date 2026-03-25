-- =============================================================================
-- MIGRACE: Oprava Mindee skenování → door codes → notifikace
-- Datum: 2026-03-25
--
-- Problémy:
-- 1. auto_generate_door_codes kontroluje type IN ('contract','protocol')
--    ale scanner ukládá 'id_card', 'drivers_license', 'passport'
-- 2. trg_notify_door_codes posílá SMS/WA i když sent_to_customer=false
-- 3. profiles.id_number sloupec neexistuje — číslo dokladu se ztrácí
-- 4. verify_customer_docs RPC funkce chybí v migracích
-- =============================================================================

-- ═══════════════════════════════════════════════════════
-- 1. Přidat sloupec id_number do profiles
-- ═══════════════════════════════════════════════════════

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS id_number TEXT DEFAULT NULL;
COMMENT ON COLUMN profiles.id_number IS 'Číslo dokladu totožnosti (OP nebo pas) — z Mindee OCR';

-- ═══════════════════════════════════════════════════════
-- 2. Oprava auto_generate_door_codes — správné doc typy
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION auto_generate_door_codes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_branch_id uuid;
  v_has_docs boolean;
  v_withheld text;
  v_code1 text;
  v_code2 text;
BEGIN
  -- Pouze při přechodu na 'active' (z jakéhokoli jiného stavu)
  IF NEW.status != 'active' THEN
    RETURN NEW;
  END IF;
  IF OLD IS NOT NULL AND OLD.status = 'active' THEN
    RETURN NEW; -- už je active, nepřegenerovávej
  END IF;

  -- Přeskoč pokud kódy pro tento booking už existují
  IF EXISTS (SELECT 1 FROM branch_door_codes WHERE booking_id = NEW.id LIMIT 1) THEN
    RETURN NEW;
  END IF;

  -- Získej branch_id z motorky
  SELECT branch_id INTO v_branch_id FROM motorcycles WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN
    RETURN NEW; -- motorka nemá pobočku
  END IF;

  -- Zkontroluj doklady zákazníka
  -- Musí mít: 1) doklad totožnosti (id_card/passport) AND 2) řidičský průkaz (drivers_license)
  -- NEBO legacy typy (contract/protocol) + license_number v profilu
  v_has_docs := false;

  -- Nový check: naskenované doklady přes Mindee
  IF EXISTS (
    SELECT 1 FROM documents
    WHERE user_id = NEW.user_id
      AND type IN ('id_card', 'passport')
    LIMIT 1
  ) AND EXISTS (
    SELECT 1 FROM documents
    WHERE user_id = NEW.user_id
      AND type = 'drivers_license'
    LIMIT 1
  ) THEN
    v_has_docs := true;
  END IF;

  -- Fallback: legacy check (contract/protocol + license_number)
  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM documents
      WHERE user_id = NEW.user_id
        AND type IN ('contract', 'protocol', 'id_photo', 'license_photo')
      LIMIT 1
    ) THEN
      IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = NEW.user_id
          AND license_number IS NOT NULL AND license_number != ''
      ) THEN
        v_has_docs := true;
      END IF;
    END IF;
  END IF;

  -- Fallback 2: profil má license_number + id_number
  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM profiles
      WHERE id = NEW.user_id
        AND license_number IS NOT NULL AND license_number != ''
        AND id_number IS NOT NULL AND id_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  v_withheld := CASE WHEN v_has_docs THEN NULL ELSE 'Chybí doklady (OP/pas/ŘP)' END;

  -- Generuj 6-místné kódy
  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  -- Vlož 2 kódy: motorka + příslušenství
  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, NEW.id, NEW.moto_id, 'motorcycle', v_code1,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld),
    (v_branch_id, NEW.id, NEW.moto_id, 'accessories', v_code2,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld);

  -- Pokud má zákazník doklady, pošli mu kódy jako in-app zprávu
  IF v_has_docs THEN
    BEGIN
      INSERT INTO admin_messages (user_id, title, content, type)
      VALUES (
        NEW.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || v_code1 || E'\nKód k příslušenství: ' || v_code2 ||
        E'\nKódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').',
        'info'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_generate_door_codes: failed to send message for booking %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_generate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- ═══════════════════════════════════════════════════════
-- 3. Oprava trg_notify_door_codes — neposílat SMS když sent_to_customer=false
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_notify_door_codes() RETURNS trigger AS $$
DECLARE
  v_phone text;
  v_user_id uuid;
  v_code_moto text;
  v_code_gear text;
  v_already_sent boolean;
BEGIN
  -- Posíláme jen jednou — při insertu kódu typu 'motorcycle'
  IF NEW.code_type != 'motorcycle' THEN RETURN NEW; END IF;

  -- NEPOSÍLAT pokud zákazník nemá doklady (kódy zadrženy)
  IF NEW.sent_to_customer IS NOT TRUE THEN RETURN NEW; END IF;

  -- Dedup: už jsme pro tento booking poslali door_codes?
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id AND template_slug = 'door_codes' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  -- Načti user_id z bookingu
  SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  -- Načti telefon zákazníka
  SELECT phone INTO v_phone FROM profiles WHERE id = v_user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Kód motorky je z aktuálního řádku
  v_code_moto := NEW.door_code;

  -- Načti kód pro příslušenství (accessories)
  SELECT door_code INTO v_code_gear
  FROM branch_door_codes
  WHERE booking_id = NEW.booking_id AND code_type = 'accessories'
  LIMIT 1;

  -- Odešli SMS + WA
  PERFORM send_sms_and_wa(
    v_phone,
    'door_codes',
    jsonb_build_object(
      'booking_number', upper(left(NEW.booking_id::text, 8)),
      'door_code_moto', coalesce(v_code_moto, '—'),
      'door_code_gear', coalesce(v_code_gear, '—')
    ),
    v_user_id,
    NEW.booking_id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_door_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger (unchanged, ale pro jistotu)
DROP TRIGGER IF EXISTS trg_notify_door_codes ON branch_door_codes;
CREATE TRIGGER trg_notify_door_codes
  AFTER INSERT ON branch_door_codes
  FOR EACH ROW
  WHEN (NEW.code_type = 'motorcycle')
  EXECUTE FUNCTION trg_notify_door_codes();

-- ═══════════════════════════════════════════════════════
-- 4. verify_customer_docs RPC funkce
-- Porovnává OCR data s profilem, kontroluje platnost ŘP
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION verify_customer_docs(
  p_ocr_name text DEFAULT NULL,
  p_ocr_dob text DEFAULT NULL,
  p_ocr_id_number text DEFAULT NULL,
  p_ocr_license_number text DEFAULT NULL,
  p_ocr_license_category text DEFAULT NULL,
  p_ocr_license_expiry text DEFAULT NULL,
  p_rental_end text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile record;
  v_mismatches jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_status text := 'verified';
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profile not found');
  END IF;

  -- Cross-check: jméno
  IF p_ocr_name IS NOT NULL AND p_ocr_name != '' THEN
    IF v_profile.full_name IS NOT NULL AND v_profile.full_name != '' THEN
      IF lower(trim(p_ocr_name)) != lower(trim(v_profile.full_name)) THEN
        v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
          'field', 'name', 'label', 'Jméno',
          'ocr', p_ocr_name, 'profile', v_profile.full_name
        ));
        v_status := 'mismatch';
      END IF;
    END IF;
  END IF;

  -- Cross-check: datum narození
  IF p_ocr_dob IS NOT NULL AND p_ocr_dob != '' THEN
    IF v_profile.date_of_birth IS NOT NULL THEN
      IF p_ocr_dob::date != v_profile.date_of_birth THEN
        v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
          'field', 'dob', 'label', 'Datum narození',
          'ocr', p_ocr_dob, 'profile', v_profile.date_of_birth::text
        ));
        v_status := 'mismatch';
      END IF;
    END IF;
  END IF;

  -- Cross-check: číslo ŘP
  IF p_ocr_license_number IS NOT NULL AND p_ocr_license_number != '' THEN
    IF v_profile.license_number IS NOT NULL AND v_profile.license_number != '' THEN
      IF lower(trim(p_ocr_license_number)) != lower(trim(v_profile.license_number)) THEN
        v_mismatches := v_mismatches || jsonb_build_array(jsonb_build_object(
          'field', 'license_number', 'label', 'Číslo ŘP',
          'ocr', p_ocr_license_number, 'profile', v_profile.license_number
        ));
        v_status := 'mismatch';
      END IF;
    END IF;
  END IF;

  -- Kontrola platnosti ŘP
  IF p_ocr_license_expiry IS NOT NULL AND p_ocr_license_expiry != '' THEN
    BEGIN
      IF p_ocr_license_expiry::date < CURRENT_DATE THEN
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'type', 'license_expired', 'label', 'Řidičský průkaz je neplatný (expiroval ' || p_ocr_license_expiry || ')'
        ));
        v_status := 'mismatch';
      END IF;
      -- Kontrola proti datu konce rezervace
      IF p_rental_end IS NOT NULL AND p_rental_end != '' THEN
        IF p_ocr_license_expiry::date < p_rental_end::date THEN
          v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
            'type', 'license_expires_before_rental_end',
            'label', 'ŘP vyprší (' || p_ocr_license_expiry || ') před koncem rezervace (' || p_rental_end || ')'
          ));
          v_status := 'mismatch';
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Invalid date format — skip check
      NULL;
    END;
  END IF;

  -- Kontrola skupin ŘP
  IF p_ocr_license_category IS NOT NULL AND p_ocr_license_category != '' THEN
    DECLARE
      v_cats text[];
      v_has_moto boolean := false;
    BEGIN
      v_cats := string_to_array(regexp_replace(p_ocr_license_category, '\s+', ',', 'g'), ',');
      v_cats := array_remove(v_cats, '');
      FOR i IN 1..array_length(v_cats, 1) LOOP
        IF upper(trim(v_cats[i])) IN ('A', 'A1', 'A2', 'AM') THEN
          v_has_moto := true;
        END IF;
      END LOOP;
      IF NOT v_has_moto THEN
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'type', 'no_motorcycle_license',
          'label', 'ŘP neobsahuje skupinu pro motorky (A/A2/A1/AM). Nalezeno: ' || p_ocr_license_category
        ));
      END IF;
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_status,
    'mismatches', v_mismatches,
    'warnings', v_warnings
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

COMMENT ON FUNCTION verify_customer_docs IS 'Verifikace naskenovaných dokladů proti profilu. Kontroluje jméno, datum narození, číslo ŘP, platnost ŘP, skupiny ŘP.';
