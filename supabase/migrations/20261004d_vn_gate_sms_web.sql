-- =============================================================================
-- Velké Němčice: kód brány v SMS/WhatsApp, zpráva o kódu šatny, potvrzení na webu
-- Migrace: 20261004d_vn_gate_sms_web.sql (4/5; potřebuje 20261004_vn_gate_access.sql)
--
-- 1) trg_notify_door_codes (SMS/WA při vydání kódu motorky): u pobočky s bránou
--    šablona door_codes_gate / door_codes_gate_moto_only (+ {{gate_code}});
--    dedup zná i nové slugy. OPRAVA: zadržený kód (sent_to_customer=false —
--    chybí doklady / výměna motorky) se už NEPOSÍLÁ hned při vložení (SMS pošle
--    uvolnění release_*); jinak by s kódem brány unikl i kód schránky.
--    Jazyk přes _door_codes_sms_lang (jen jazyky se šablonami, jinak cs).
-- 2) _sync_locker_code (dodatečně přidaný kód šatny): u brány zpráva brána →
--    šatna (dveře č. N) → motorka.
-- 3) get_web_booking_confirmation: branch.id + branch.has_gate (jen příznak,
--    NE kód) → děkovací stránka webu ukáže postup s bránou.
-- 4) message_templates: door_codes_gate + door_codes_gate_moto_only (sms +
--    whatsapp × cs,en,de,nl,es,fr,pl,uk) a chybějící uk pro door_codes /
--    door_codes_moto_only. ON CONFLICT DO NOTHING (úpravy z Velína zůstávají).
--
-- Těla 1:1 z živé DB (supabase-live-snapshot 2026-10-03) kromě označených změn.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."trg_notify_door_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
  SELECT door_code INTO v_code_moto
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'motorcycle' AND is_active = true
   ORDER BY created_at DESC LIMIT 1;
  SELECT door_code INTO v_code_gear
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'accessories' AND is_active = true
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
$$;

CREATE OR REPLACE FUNCTION "public"."_sync_locker_code"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
$$;

CREATE OR REPLACE FUNCTION "public"."get_web_booking_confirmation"("p_session_id" "text" DEFAULT NULL::"text", "p_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_booking RECORD;
  v_docs_status text;
BEGIN
  IF p_session_id IS NULL AND p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_identifier');
  END IF;

  SELECT
    b.id, b.user_id, b.moto_id, b.start_date, b.end_date,
    b.total_price, b.payment_status, b.status, b.booking_source,
    b.pickup_method, b.pickup_address,
    p.full_name AS customer_name, p.email AS customer_email,
    m.license_required,
    br.id AS branch_id, br.name AS branch_name, br.address AS branch_address,
    br.zip AS branch_zip, br.city AS branch_city,
    br.gps_lat AS branch_gps_lat, br.gps_lng AS branch_gps_lng
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p     ON p.id = b.user_id
  LEFT JOIN motorcycles m  ON m.id = b.moto_id
  LEFT JOIN branches br    ON br.id = m.branch_id
  WHERE
    (p_booking_id IS NOT NULL AND b.id = p_booking_id)
    OR
    (p_session_id IS NOT NULL AND b.stripe_session_id = p_session_id)
  ORDER BY b.created_at DESC
  LIMIT 1;

  IF v_booking.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  IF v_booking.booking_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'not_web_booking');
  END IF;

  -- Dětské motorky (license_required='N') nepotřebují doklady → NULL = OK
  IF v_booking.license_required = 'N' THEN
    v_docs_status := NULL;
  ELSE
    BEGIN
      v_docs_status := public.check_booking_docs_status(
        v_booking.user_id,
        v_booking.end_date::date
      );
    EXCEPTION WHEN OTHERS THEN
      v_docs_status := NULL;
    END;
  END IF;

  RETURN jsonb_build_object(
    'id',             v_booking.id,
    'moto_id',        v_booking.moto_id,
    'start_date',     v_booking.start_date,
    'end_date',       v_booking.end_date,
    'total_price',    v_booking.total_price,
    'payment_status', v_booking.payment_status,
    'status',         v_booking.status,
    'customer_name',  v_booking.customer_name,
    'customer_email', v_booking.customer_email,
    'docs_status',    v_docs_status,
    'is_delivery',    (v_booking.pickup_method = 'delivery'
                       OR NULLIF(btrim(v_booking.pickup_address), '') IS NOT NULL),
    'branch',         CASE WHEN v_booking.branch_id IS NULL THEN NULL
                      ELSE jsonb_build_object(
                        'id',      v_booking.branch_id,
                        -- jen příznak brány se schránkou (Velké Němčice), NIKDY kód
                        'has_gate', public.branch_has_gate(v_booking.branch_id),
                        'name',    v_booking.branch_name,
                        'address', v_booking.branch_address,
                        'zip',     v_booking.branch_zip,
                        'city',    v_booking.branch_city,
                        'gps_lat', v_booking.branch_gps_lat,
                        'gps_lng', v_booking.branch_gps_lng
                      ) END
  );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) SMS/WA šablony s kódem brány (pořadí brána → šatna → motorka + povinnost
--    zavřít bránu, vrátit klíč a přetočit kód) — sms + whatsapp × 8 jazyků;
--    + chybějící uk pro door_codes / door_codes_moto_only. WA šablony nemají
--    Meta SID (posílá se text). Seed nepřepisuje úpravy z Velína.
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO public.message_templates (slug, channel, language, name, body_template, content, category, is_marketing, is_active)
SELECT t.slug, c.channel, t.lang, t.name, t.body, t.body, 'booking', false, true
FROM (VALUES
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'cs', $t$Kódy k rezervaci {{booking_number}}: 1) brána – horní schránka vpravo: {{gate_code}} 2) šatna: {{door_code_gear}} 3) motorka: {{door_code_moto}}. Zavřenou bránu po odjezdu zamkněte, klíč vraťte a kód přetočte. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'cs', $t$Kódy k rezervaci {{booking_number}}: 1) brána – horní schránka vpravo: {{gate_code}} 2) motorka: {{door_code_moto}}. Zavřenou bránu po odjezdu zamkněte, klíč vraťte a kód přetočte. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'en', $t$Booking {{booking_number}} codes: 1) gate - upper lockbox, right: {{gate_code}} 2) locker room: {{door_code_gear}} 3) motorcycle: {{door_code_moto}}. Gate was closed? Lock it after leaving, return key, scramble code. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'en', $t$Booking {{booking_number}} codes: 1) gate - upper lockbox, right: {{gate_code}} 2) motorcycle: {{door_code_moto}}. Gate was closed? Lock it after leaving, return key, scramble code. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'de', $t$Buchung {{booking_number}}, Codes: 1) Tor - Schlüsselbox oben rechts: {{gate_code}} 2) Umkleide: {{door_code_gear}} 3) Motorrad: {{door_code_moto}}. Tor war zu? Nach Abfahrt abschließen, Schlüssel zurück, Code verstellen. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'de', $t$Buchung {{booking_number}}, Codes: 1) Tor - Schlüsselbox oben rechts: {{gate_code}} 2) Motorrad: {{door_code_moto}}. Tor war zu? Nach Abfahrt abschließen, Schlüssel zurück, Code verstellen. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'nl', $t$Codes {{booking_number}}: 1) poortkastje rechtsboven: {{gate_code}} 2) kleedkamer: {{door_code_gear}} 3) motor: {{door_code_moto}}. Was poort dicht: op slot, sleutel terug, code verdraaien. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'nl', $t$Codes reservering {{booking_number}}: 1) poortkastje rechtsboven: {{gate_code}} 2) motor: {{door_code_moto}}. Was de poort dicht? Na vertrek weer op slot, sleutel terug, code verdraaien. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'es', $t$Reserva {{booking_number}}, códigos: 1) portón – caja sup. dcha.: {{gate_code}} 2) vestuario: {{door_code_gear}} 3) moto: {{door_code_moto}}. Si el portón estaba cerrado, al salir échele el candado, devuelva la llave y gire los números. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'es', $t$Reserva {{booking_number}}, códigos: 1) portón – caja sup. dcha.: {{gate_code}} 2) moto: {{door_code_moto}}. Si el portón estaba cerrado, al salir échele el candado, devuelva la llave y gire los números. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'fr', $t$Codes de la réservation {{booking_number}} : 1) portail, boîte du haut à droite : {{gate_code}} 2) vestiaire : {{door_code_gear}} 3) moto : {{door_code_moto}}. Portail fermé ? En partant, refermez-le au cadenas, remettez la clé, brouillez le code. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'fr', $t$Codes de la réservation {{booking_number}} : 1) portail, boîte du haut à droite : {{gate_code}} 2) moto : {{door_code_moto}}. Portail fermé ? En partant, refermez-le au cadenas, remettez la clé, brouillez le code. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'pl', $t$Kody rezerwacji {{booking_number}}: 1) brama – górna skrytka z prawej: {{gate_code}} 2) szatnia: {{door_code_gear}} 3) motocykl: {{door_code_moto}}. Zamkniętą bramę po wyjeździe zamknąć na kłódkę, klucz odłożyć, szyfr przekręcić. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'pl', $t$Kody rezerwacji {{booking_number}}: 1) brama – górna skrytka z prawej: {{gate_code}} 2) motocykl: {{door_code_moto}}. Zamkniętą bramę po wyjeździe zamknąć na kłódkę, klucz odłożyć, szyfr przekręcić. MOTO GO 24$t$),
  ('door_codes_gate', 'Přístupové kódy – brána, šatna, motorka', 'uk', $t$Коди бронювання {{booking_number}}: 1) ворота – верхня скринька справа: {{gate_code}} 2) роздягальня: {{door_code_gear}} 3) мотоцикл: {{door_code_moto}}. Зачинені ворота після відʼїзду замкніть, ключ поверніть, код збийте. MOTO GO 24$t$),
  ('door_codes_gate_moto_only', 'Přístupové kódy – brána, motorka', 'uk', $t$Коди бронювання {{booking_number}}: 1) ворота – верхня скринька справа: {{gate_code}} 2) мотоцикл: {{door_code_moto}}. Зачинені ворота після відʼїзду замкніть, ключ поверніть, код збийте. MOTO GO 24$t$),
  ('door_codes', 'Přístupové kódy', 'uk', $t$Коди до бронювання {{booking_number}}: мотоцикл: {{door_code_moto}}, роздягальня: {{door_code_gear}}. Гарної поїздки! MOTO GO 24$t$),
  ('door_codes_moto_only', 'Přístupový kód (jen motorka)', 'uk', $t$Код до бронювання {{booking_number}}: мотоцикл: {{door_code_moto}}. Гарної поїздки! MOTO GO 24$t$)
) AS t(slug, name, lang, body)
CROSS JOIN (VALUES ('sms'), ('whatsapp')) AS c(channel)
ON CONFLICT (slug, channel, language) DO NOTHING;
