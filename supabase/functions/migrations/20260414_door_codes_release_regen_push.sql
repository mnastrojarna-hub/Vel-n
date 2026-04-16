-- =============================================================================
-- MIGRACE: Uvolnění zadržených kódů + přegenerování při změně motorky + FCM push
-- Datum: 2026-04-14
--
-- Problémy:
-- 1. Kódy zadrženy s "Chybí doklady" i když jsou nahrány → chybí trigger na documents
-- 2. Při změně motorky v bookingu se nepřegenerují kódy
-- 3. Chybí FCM push notifikace při vložení admin_messages (door codes)
-- 4. Chybí RPC pro manuální uvolnění kódů (volá appka po platbě)
-- =============================================================================

-- ═══════════════════════════════════════════════════════
-- 1. FUNKCE: release_withheld_door_codes
-- Při nahrání dokumentů zkontroluje, zda uživatel má zadržené kódy.
-- Pokud má doklady → uvolní kódy + pošle zprávu + SMS/WA.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION release_withheld_door_codes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_has_docs boolean;
  v_booking record;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
BEGIN
  v_user_id := NEW.user_id;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  -- Existují zadržené kódy pro tohoto uživatele?
  IF NOT EXISTS (
    SELECT 1 FROM branch_door_codes bdc
    JOIN bookings b ON b.id = bdc.booking_id
    WHERE b.user_id = v_user_id
      AND bdc.is_active = true
      AND bdc.sent_to_customer = false
    LIMIT 1
  ) THEN
    RETURN NEW; -- žádné zadržené kódy
  END IF;

  -- Zkontroluj doklady (stejná logika jako auto_generate_door_codes)
  v_has_docs := false;

  -- Mindee check: id_card/passport + drivers_license
  IF EXISTS (
    SELECT 1 FROM documents
    WHERE user_id = v_user_id AND type IN ('id_card', 'passport')
    LIMIT 1
  ) AND EXISTS (
    SELECT 1 FROM documents
    WHERE user_id = v_user_id AND type = 'drivers_license'
    LIMIT 1
  ) THEN
    v_has_docs := true;
  END IF;

  -- Fallback: legacy docs + license_number
  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM documents
      WHERE user_id = v_user_id
        AND type IN ('contract', 'protocol', 'id_photo', 'license_photo')
      LIMIT 1
    ) AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = v_user_id
        AND license_number IS NOT NULL AND license_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  -- Fallback 2: profile license_number + id_number
  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM profiles
      WHERE id = v_user_id
        AND license_number IS NOT NULL AND license_number != ''
        AND id_number IS NOT NULL AND id_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  -- Pokud stále nemá doklady → nic neděláme
  IF NOT v_has_docs THEN RETURN NEW; END IF;

  -- Uvolni zadržené kódy pro VŠECHNY aktivní bookings tohoto uživatele
  FOR v_booking IN
    SELECT DISTINCT b.id AS booking_id, b.user_id, b.start_date, b.end_date
    FROM bookings b
    JOIN branch_door_codes bdc ON bdc.booking_id = b.id
    WHERE b.user_id = v_user_id
      AND bdc.is_active = true
      AND bdc.sent_to_customer = false
  LOOP
    -- Updatuj kódy na odeslané
    UPDATE branch_door_codes
    SET sent_to_customer = true,
        sent_at = NOW(),
        withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false;

    -- Načti kódy pro zprávu
    SELECT door_code INTO v_code_moto
    FROM branch_door_codes
    WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active = true
    LIMIT 1;

    SELECT door_code INTO v_code_gear
    FROM branch_door_codes
    WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active = true
    LIMIT 1;

    -- Pošli in-app zprávu (admin_messages) s typem door_codes
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || COALESCE(v_code_moto, '–') || E'\n' ||
        'Kód k příslušenství: ' || COALESCE(v_code_gear, '–') || E'\n' ||
        'Kódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(v_booking.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date, 'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'release_withheld_door_codes: admin_message insert failed: %', SQLERRM;
    END;

    -- Pošli SMS + WA
    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone != '' THEN
        PERFORM send_sms_and_wa(
          v_phone,
          'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text, 8)),
            'door_code_moto', COALESCE(v_code_moto, '–'),
            'door_code_gear', COALESCE(v_code_gear, '–')
          ),
          v_booking.user_id,
          v_booking.booking_id
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'release_withheld_door_codes: SMS/WA send failed: %', SQLERRM;
    END;
  END LOOP;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Trigger na documents — při nahrání nového dokumentu uvolni zadržené kódy
DROP TRIGGER IF EXISTS trg_release_codes_on_doc_upload ON documents;
CREATE TRIGGER trg_release_codes_on_doc_upload
  AFTER INSERT ON documents
  FOR EACH ROW
  WHEN (NEW.type IN ('id_card', 'passport', 'drivers_license', 'id_photo', 'license_photo'))
  EXECUTE FUNCTION release_withheld_door_codes();

COMMENT ON FUNCTION release_withheld_door_codes IS 'Při nahrání dokladů uvolní zadržené přístupové kódy a pošle notifikaci zákazníkovi.';


-- ═══════════════════════════════════════════════════════
-- 2. FUNKCE: regen_door_codes_on_moto_change
-- Při změně moto_id na aktivním bookingu: deaktivuj staré kódy,
-- vygeneruj nové pro novou motorku.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION regen_door_codes_on_moto_change()
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
  v_phone text;
BEGIN
  -- Pouze pokud se moto_id skutečně změnilo
  IF OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id THEN
    RETURN NEW;
  END IF;

  -- Pouze pro aktivní nebo nadcházející bookings
  IF NEW.status NOT IN ('active', 'reserved') THEN
    RETURN NEW;
  END IF;

  -- Deaktivuj staré kódy
  UPDATE branch_door_codes
  SET is_active = false
  WHERE booking_id = NEW.id AND is_active = true;

  -- Získej branch_id z nové motorky
  SELECT branch_id INTO v_branch_id FROM motorcycles WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Zkontroluj doklady zákazníka (stejná logika)
  v_has_docs := false;

  IF EXISTS (
    SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type IN ('id_card', 'passport') LIMIT 1
  ) AND EXISTS (
    SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type = 'drivers_license' LIMIT 1
  ) THEN
    v_has_docs := true;
  END IF;

  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type IN ('contract', 'protocol', 'id_photo', 'license_photo') LIMIT 1
    ) AND EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id AND license_number IS NOT NULL AND license_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id
        AND license_number IS NOT NULL AND license_number != ''
        AND id_number IS NOT NULL AND id_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  v_withheld := CASE WHEN v_has_docs THEN NULL ELSE 'Chybí doklady (OP/pas/ŘP)' END;

  -- Generuj nové 6-místné kódy
  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  -- Vlož 2 nové kódy
  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, NEW.id, NEW.moto_id, 'motorcycle', v_code1,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld),
    (v_branch_id, NEW.id, NEW.moto_id, 'accessories', v_code2,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld);

  -- Pokud má doklady → pošli nové kódy jako zprávu
  IF v_has_docs THEN
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        NEW.user_id,
        'Nové přístupové kódy',
        'Změnili jste motorku – nové kódy:' || E'\n' ||
        'Kód k motorce: ' || v_code1 || E'\n' ||
        'Kód k příslušenství: ' || v_code2 || E'\n' ||
        'Kódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'regen_door_codes_on_moto_change: admin_message insert failed: %', SQLERRM;
    END;

    -- Pošli SMS + WA
    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
      IF v_phone IS NOT NULL AND v_phone != '' THEN
        PERFORM send_sms_and_wa(
          v_phone,
          'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(NEW.id::text, 8)),
            'door_code_moto', v_code1,
            'door_code_gear', v_code2
          ),
          NEW.user_id,
          NEW.id
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'regen_door_codes_on_moto_change: SMS/WA send failed: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'regen_door_codes_on_moto_change failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_regen_codes_on_moto_change ON bookings;
CREATE TRIGGER trg_regen_codes_on_moto_change
  AFTER UPDATE OF moto_id ON bookings
  FOR EACH ROW
  WHEN (OLD.moto_id IS DISTINCT FROM NEW.moto_id AND NEW.status IN ('active', 'reserved'))
  EXECUTE FUNCTION regen_door_codes_on_moto_change();

COMMENT ON FUNCTION regen_door_codes_on_moto_change IS 'Při změně motorky na bookingu: deaktivuj staré kódy, vygeneruj nové, notifikuj zákazníka.';


-- ═══════════════════════════════════════════════════════
-- 3. FUNKCE: send_push_via_edge
-- Pošle FCM push přes Edge Function send-push.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION send_push_via_edge(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
) RETURNS void AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  v_url := coalesce(current_setting('app.settings.supabase_url', true), '');
  v_key := coalesce(current_setting('app.settings.service_role_key', true), '');

  IF v_url = '' OR v_key = '' THEN
    RAISE WARNING 'send_push_via_edge: app.settings not configured, skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'user_id', p_user_id,
      'title', p_title,
      'body', p_body,
      'data', p_data
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_push_via_edge failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION send_push_via_edge IS 'Odešle FCM push notifikaci přes Edge Function send-push.';


-- ═══════════════════════════════════════════════════════
-- 4. TRIGGER: push notifikace při vložení admin_messages
-- Pro typy door_codes, info, sos_response → pošle FCM push
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION trg_push_on_admin_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_data jsonb;
BEGIN
  -- Sestav data payload pro deep link
  v_data := jsonb_build_object(
    'type', CASE
      WHEN NEW.type = 'door_codes' THEN 'door_codes'
      ELSE 'message'
    END,
    'id', NEW.id
  );

  -- Pošli push
  PERFORM send_push_via_edge(
    NEW.user_id,
    COALESCE(NEW.title, 'MotoGo24'),
    COALESCE(left(NEW.message, 200), ''),
    v_data
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_push_on_admin_message failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_on_admin_message ON admin_messages;
CREATE TRIGGER trg_push_on_admin_message
  AFTER INSERT ON admin_messages
  FOR EACH ROW
  EXECUTE FUNCTION trg_push_on_admin_message();

COMMENT ON FUNCTION trg_push_on_admin_message IS 'Při nové admin_messages pošle FCM push přes send-push edge function.';


-- ═══════════════════════════════════════════════════════
-- 5. Aktualizace auto_generate_door_codes — typ door_codes místo info
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
  IF NEW.status != 'active' THEN RETURN NEW; END IF;
  IF OLD IS NOT NULL AND OLD.status = 'active' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM branch_door_codes WHERE booking_id = NEW.id LIMIT 1) THEN RETURN NEW; END IF;

  SELECT branch_id INTO v_branch_id FROM motorcycles WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN RETURN NEW; END IF;

  v_has_docs := false;

  IF EXISTS (
    SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type IN ('id_card', 'passport') LIMIT 1
  ) AND EXISTS (
    SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type = 'drivers_license' LIMIT 1
  ) THEN
    v_has_docs := true;
  END IF;

  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM documents WHERE user_id = NEW.user_id AND type IN ('contract', 'protocol', 'id_photo', 'license_photo') LIMIT 1
    ) AND EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id AND license_number IS NOT NULL AND license_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM profiles WHERE id = NEW.user_id
        AND license_number IS NOT NULL AND license_number != ''
        AND id_number IS NOT NULL AND id_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  v_withheld := CASE WHEN v_has_docs THEN NULL ELSE 'Chybí doklady (OP/pas/ŘP)' END;

  v_code1 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');
  v_code2 := LPAD(FLOOR(100000 + RANDOM() * 900000)::text, 6, '0');

  INSERT INTO branch_door_codes (branch_id, booking_id, moto_id, code_type, door_code,
    is_active, valid_from, valid_until, sent_to_customer, sent_at, withheld_reason)
  VALUES
    (v_branch_id, NEW.id, NEW.moto_id, 'motorcycle', v_code1,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld),
    (v_branch_id, NEW.id, NEW.moto_id, 'accessories', v_code2,
     true, NEW.start_date, NEW.end_date, v_has_docs,
     CASE WHEN v_has_docs THEN NOW() ELSE NULL END, v_withheld);

  -- Typ 'door_codes' místo 'info' → správné ikona + routing v appce
  IF v_has_docs THEN
    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        NEW.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || v_code1 || E'\nKód k příslušenství: ' || v_code2 ||
        E'\nKódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_generate_door_codes: admin_message insert failed: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_generate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


-- ═══════════════════════════════════════════════════════
-- 6. RPC: release_my_door_codes
-- Zákazník zavolá po platbě z appky → ověří doklady a uvolní kódy.
-- Bezpečná — funguje jen pro vlastní bookings přihlášeného usera.
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION release_my_door_codes(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid;
  v_booking record;
  v_has_docs boolean;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int := 0;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  -- Ověř že booking patří uživateli
  SELECT id, user_id, start_date, end_date, status
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
    -- Kódy už odeslány nebo neexistují
    RETURN jsonb_build_object('success', true, 'released', 0, 'message', 'No withheld codes');
  END IF;

  -- Zkontroluj doklady (kompletní logika)
  v_has_docs := false;

  IF EXISTS (
    SELECT 1 FROM documents WHERE user_id = v_uid AND type IN ('id_card', 'passport') LIMIT 1
  ) AND EXISTS (
    SELECT 1 FROM documents WHERE user_id = v_uid AND type = 'drivers_license' LIMIT 1
  ) THEN
    v_has_docs := true;
  END IF;

  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM documents WHERE user_id = v_uid AND type IN ('contract', 'protocol', 'id_photo', 'license_photo') LIMIT 1
    ) AND EXISTS (
      SELECT 1 FROM profiles WHERE id = v_uid AND license_number IS NOT NULL AND license_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  IF NOT v_has_docs THEN
    IF EXISTS (
      SELECT 1 FROM profiles WHERE id = v_uid
        AND license_number IS NOT NULL AND license_number != ''
        AND id_number IS NOT NULL AND id_number != ''
    ) THEN
      v_has_docs := true;
    END IF;
  END IF;

  IF NOT v_has_docs THEN
    RETURN jsonb_build_object('success', false, 'error', 'Documents missing',
      'withheld_reason', 'Chybí doklady (OP/pas/ŘP)');
  END IF;

  -- Uvolni kódy
  UPDATE branch_door_codes
  SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
  WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false;

  GET DIAGNOSTICS v_released = ROW_COUNT;

  -- Načti kódy
  SELECT door_code INTO v_code_moto
  FROM branch_door_codes WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;

  SELECT door_code INTO v_code_gear
  FROM branch_door_codes WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

  -- In-app zpráva
  BEGIN
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (
      v_uid,
      'Přístupové kódy k pobočce',
      'Kód k motorce: ' || COALESCE(v_code_moto, '–') || E'\n' ||
      'Kód k příslušenství: ' || COALESCE(v_code_gear, '–') || E'\n' ||
      'Kódy jsou platné po dobu trvání pronájmu (' ||
      TO_CHAR(v_booking.start_date::date, 'DD.MM.YYYY') || ' – ' ||
      TO_CHAR(v_booking.end_date::date, 'DD.MM.YYYY') || ').',
      'door_codes'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'release_my_door_codes: admin_message insert failed: %', SQLERRM;
  END;

  -- SMS + WA
  BEGIN
    SELECT phone INTO v_phone FROM profiles WHERE id = v_uid;
    IF v_phone IS NOT NULL AND v_phone != '' THEN
      PERFORM send_sms_and_wa(
        v_phone, 'door_codes',
        jsonb_build_object(
          'booking_number', upper(left(p_booking_id::text, 8)),
          'door_code_moto', COALESCE(v_code_moto, '–'),
          'door_code_gear', COALESCE(v_code_gear, '–')
        ),
        v_uid, p_booking_id
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'release_my_door_codes: SMS/WA failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object('success', true, 'released', v_released);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

COMMENT ON FUNCTION release_my_door_codes IS 'RPC: zákazník zavolá po platbě — ověří doklady a uvolní zadržené přístupové kódy.';

-- Grant pro authenticated users
GRANT EXECUTE ON FUNCTION release_my_door_codes TO authenticated;
