-- =============================================================================
-- RETRY: testovací obsazenost kalendářů 9+10/2026 (oprava 20260820_test_calendar_seed_sep_oct.sql)
--
-- Proč seed 2026-08-20 vložil 0 rezervací: INSERT obsahoval sloupec `deposit`,
-- který v ŽIVÉ tabulce `bookings` NEEXISTUJE (docs STATE_2 ho uváděly chybně;
-- pozn. stejný neexistující sloupec vkládá i živá RPC split_booking_moto_swap
-- — latentní bug commitu výměny motorky, řešit samostatně). Chyba 42703 se
-- chytla v ochranném EXCEPTION bloku → "56 bloků se nikam nevešlo" bez příčiny.
--
-- Tento retry:
--   1) auto_generate_door_codes: přeskočí is_test rezervace (tělo 1:1 z živého
--      snapshotu 2026-08-19 + guard). Živá verze totiž generuje kódy UŽ při
--      INSERTU `reserved` a zákazníkovi s ověřenými doklady hned posílá
--      e-mail + in-app zprávu s kódy — u ~40 testovacích rezervací nežádoucí.
--      (Funkční úpravy z 20260820 — check_user_booking_overlap + lifecycle
--      crony přeskakují is_test — už jsou aplikované.)
--   2) seed znovu, BEZ sloupce `deposit`; při selhání vkládání vypíše PRVNÍ
--      zachycenou chybu (RAISE WARNING), aby už nikdy nespadl potichu.
--
-- Idempotentní. Úklid: DELETE FROM bookings WHERE notes LIKE 'SEED-KALENDAR-2026-0910%';
-- =============================================================================

-- 1) auto_generate_door_codes — guard is_test hned na začátku
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

    -- Email s kódy (deduplikováno přes message_log v send_door_codes_email)
    PERFORM send_door_codes_email(NEW.id, NEW.user_id);
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_generate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


-- 2) Seed — stejná logika jako 20260820, BEZ sloupce `deposit`,
--    + první zachycená chyba se vypíše (nikdy už tichý fail).
DO $seed$
DECLARE
  v_user     uuid;
  m          record;
  v_month    int;
  v_h        bigint;
  v_pat      int;      -- 0 = jeden blok 2 dny; 1 = dva bloky 1 den s mezerou
  v_gap      int;      -- mezera mezi bloky 1-2 dny
  v_d0       int;      -- výchozí den v měsíci
  v_blk      int;
  v_len      int;
  v_day_base int;
  v_mod      int;
  v_off      int;
  v_s        date;
  v_e        date;
  v_placed   boolean;
  v_ins      int := 0;
  v_miss     int := 0;
  v_err      text := NULL;
BEGIN
  SELECT id INTO v_user
  FROM profiles
  WHERE lower(email) = 'semorad@nastrojarstvi.com'
  LIMIT 1;

  IF v_user IS NULL THEN
    RAISE WARNING 'SEED-KALENDAR-2026-0910 (retry): profil semorad@nastrojarstvi.com nenalezen — seed přeskočen.';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM bookings WHERE user_id = v_user AND is_test IS TRUE AND notes LIKE 'SEED-KALENDAR-2026-0910%') THEN
    RAISE NOTICE 'SEED-KALENDAR-2026-0910 (retry): už aplikováno — přeskočeno.';
    RETURN;
  END IF;

  FOR m IN
    SELECT id FROM motorcycles
    WHERE status = 'active'
      AND COALESCE(is_trailer, false) = false
    ORDER BY model, id
  LOOP
    FOR v_month IN 9..10 LOOP
      v_h   := abs(hashtext(m.id::text || '/' || v_month::text)::bigint);
      v_pat := (v_h % 2)::int;
      v_gap := 1 + ((v_h / 7) % 2)::int;
      v_d0  := 1 + ((v_h / 13) % 24)::int;

      FOR v_blk IN 1..2 LOOP
        IF v_pat = 0 THEN
          EXIT WHEN v_blk = 2;         -- jeden dvoudenní blok
          v_len := 2; v_day_base := v_d0;
        ELSE
          v_len := 1;
          v_day_base := CASE WHEN v_blk = 1 THEN v_d0 ELSE v_d0 + 1 + v_gap END;
        END IF;
        v_mod := CASE WHEN v_len = 2 THEN 24 ELSE 27 END;

        v_placed := false;
        FOR v_off IN 0..(v_mod - 1) LOOP
          v_s := make_date(2026, v_month, ((v_day_base - 1 + v_off) % v_mod) + 1);
          v_e := v_s + (v_len - 1);

          -- volno na motorce (±1 den odstup od čehokoliv živého) + žádný servis
          IF NOT EXISTS (
               SELECT 1 FROM bookings b
               WHERE (b.moto_id = m.id OR b.trailer_moto_id = m.id)
                 AND b.status NOT IN ('cancelled','completed')
                 AND b.start_date::date <= v_e + 1
                 AND b.end_date::date   >= v_s - 1
             )
             AND NOT EXISTS (
               SELECT 1 FROM maintenance_log ml
               WHERE ml.moto_id = m.id
                 AND ml.service_date IS NOT NULL
                 AND ml.completed_date IS NULL
                 AND COALESCE(ml.status,'') NOT IN ('completed','cancelled')
                 AND ml.service_date::date <= v_e
                 AND COALESCE(ml.scheduled_date, ml.service_date)::date >= v_s
             )
          THEN
            BEGIN
              INSERT INTO bookings (
                user_id, moto_id, start_date, end_date, pickup_time, return_time,
                status, payment_status, total_price, delivery_fee,
                booking_source, is_test, notes, confirmed_at,
                reserved_email_sent_at, abandoned_email_sent_at, docs_reminder_sent_at
              ) VALUES (
                v_user, m.id, v_s, v_e, '10:00', '19:00',
                'reserved', 'paid', 0, 0,
                'app', true,
                'SEED-KALENDAR-2026-0910 — testovací obsazenost kalendáře (0 Kč)',
                now(), now(), now(), now()
              );
              v_ins := v_ins + 1;
              v_placed := true;
            EXCEPTION WHEN OTHERS THEN
              IF v_err IS NULL THEN v_err := SQLSTATE || ': ' || SQLERRM; END IF;
              v_placed := false;  -- kolize/trigger — zkusí další posun
            END;
            EXIT WHEN v_placed;
          END IF;
        END LOOP;

        IF NOT v_placed THEN
          v_miss := v_miss + 1;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'SEED-KALENDAR-2026-0910 (retry): vloženo % testovacích rezervací, % bloků se nikam nevešlo.', v_ins, v_miss;
  IF v_err IS NOT NULL THEN
    RAISE WARNING 'SEED-KALENDAR-2026-0910 (retry): první zachycená chyba INSERTu: %', v_err;
  END IF;
END $seed$;
