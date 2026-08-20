-- =============================================================================
-- TESTOVACÍ OBSAZENOST KALENDÁŘŮ — září + říjen 2026 (zadání uživatele)
-- Účet: semorad@nastrojarstvi.com (Jiří Semorád, testovací rodinný účet)
--
-- Cíl: každá aktivní motorka má v 9/2026 i 10/2026 náhodně rozmístěné bloky
-- rezervací (1–2 dny, rozestupy 1–2 dny, celkem ~4 dny na motorku),
-- status 'reserved' + payment_status 'paid' + total_price 0 Kč, is_test=true.
--
-- Aby seed NEROZBIL provoz, jsou testovací rezervace (is_test=true) vyjmuty z:
--   1) check_user_booking_overlap — jeden účet drží desítky souběžných
--      rezervací; bez výjimky by trigger shodil nejen tento INSERT, ale hlavně
--      každý pozdější cron UPDATE stavů REÁLNÝCH rezervací téhož zákazníka.
--   2) auto_activate_reserved_bookings + auto_complete_expired_bookings —
--      testovací rezervace se NIKDY nesmí aktivovat/dokončit (jinak by
--      generovaly door codes, 0Kč koncové faktury a "completed" maily).
--      Zůstávají navždy 'reserved' = jen blokují kalendář.
--
-- Maily: reserved_email_sent_at/abandoned_email_sent_at/docs_reminder_sent_at
-- se rovnou nastaví na now() → záchranné mail crony seed přeskočí.
--
-- Idempotentní: opakovaný běh nic nepřidá (guard na marker v notes).
-- Úklid kdykoliv: DELETE FROM bookings WHERE notes LIKE 'SEED-KALENDAR-2026-0910%';
-- =============================================================================

-- 1) check_user_booking_overlap — tělo 1:1 z 20260720_moto_handoff_switch.sql,
--    + výjimka is_test v OBOU směrech.
CREATE OR REPLACE FUNCTION check_user_booking_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- SOS replacement bookings are exempt from overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Testovací rezervace (is_test) jsou z kontroly vyjmuté (NEW 2026-08-20):
  -- seed obsazenosti kalendáře = jeden účet, mnoho motorek souběžně.
  IF NEW.is_test IS TRUE THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- Check for overlapping bookings for the same user
  IF EXISTS (
    SELECT 1 FROM bookings o
    WHERE o.user_id = NEW.user_id
      AND o.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND o.status NOT IN ('cancelled', 'completed')
      AND o.sos_replacement IS NOT TRUE
      -- Testovací rezervace nikdy neblokují reálné (NEW 2026-08-20)
      AND o.is_test IS NOT TRUE
      AND o.start_date::date <= NEW.end_date::date
      AND o.end_date::date >= NEW.start_date::date
      -- Výjimka: dětské motorky (license_required = 'N')
      AND o.moto_id NOT IN (SELECT id FROM motorcycles WHERE license_required = 'N')
      -- Výjimka: výměna motorky (switch chain) — dvojice A↔B spojená přes
      -- continues_booking_id se nepovažuje za kolizi ani na sdílený hraniční den.
      AND o.id IS DISTINCT FROM NEW.continues_booking_id
      AND o.continues_booking_id IS DISTINCT FROM NEW.id
  ) THEN
    RAISE EXCEPTION 'Zákazník má překrývající se rezervaci v tomto období';
  END IF;

  RETURN NEW;
END;
$$;

-- 2) auto_activate_reserved_bookings — tělo 1:1 z 20260719_obsluzna_activate_on_handover.sql,
--    + přeskočení is_test.
CREATE OR REPLACE FUNCTION auto_activate_reserved_bookings()
RETURNS void AS $$
BEGIN
  UPDATE bookings b SET
    status = 'active',
    picked_up_at = COALESCE(b.picked_up_at, NOW())
  WHERE b.status = 'reserved'
    AND b.payment_status = 'paid'
    AND b.start_date::date <= CURRENT_DATE
    -- Testovací rezervace se nikdy neaktivují (NEW 2026-08-20)
    AND b.is_test IS NOT TRUE
    -- Obslužné pobočky se aktivují AŽ předávacím protokolem (viz strážce výše),
    -- nikoli půlnočním cronem.
    AND NOT EXISTS (
      SELECT 1 FROM motorcycles m
      JOIN branches br ON br.id = m.branch_id
      WHERE m.id = b.moto_id AND br.type = 'obslužná'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3) auto_complete_expired_bookings — tělo 1:1 z 20260722_moto_swap_calendar_fix.sql,
--    + přeskočení is_test v obou krocích.
CREATE OR REPLACE FUNCTION auto_complete_expired_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Krok 1: dozvednuté paid reserved po end_date → active (obslužná bez ručního
  -- předání). Označ protokol jako auto-vyplněný.
  UPDATE bookings SET
    status = 'active'::booking_status,
    picked_up_at = COALESCE(picked_up_at, NOW()),
    handover_protocol_autofilled = CASE
      WHEN handover_protocol_filled_at IS NULL THEN true
      ELSE handover_protocol_autofilled END,
    handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, NOW())
  WHERE status = 'reserved'
    AND end_date < CURRENT_DATE
    AND is_test IS NOT TRUE  -- testovací rezervace nedokončovat (NEW 2026-08-20)
    AND payment_status IN ('paid', 'partial_refund', 'refund_pending');

  -- Krok 2: dokonči aktivní po end_date → KF. VÝJIMKA: nedokončuj motorku s
  -- ČEKAJÍCÍ navazující výměnou (jiná moto téhož zákazníka, start = boundary,
  -- navazující ještě běží) — tu dokončí až switch (swap_handoff_bookings).
  UPDATE bookings b SET
    status = 'completed'::booking_status,
    returned_at = NOW()
  WHERE b.status = 'active'
    AND b.end_date < CURRENT_DATE
    AND b.is_test IS NOT TRUE  -- testovací rezervace nedokončovat (NEW 2026-08-20)
    AND b.payment_status IN ('paid', 'partial_refund', 'refund_pending')
    AND NOT EXISTS (
      SELECT 1 FROM bookings nb
      WHERE nb.user_id = b.user_id
        AND nb.moto_id <> b.moto_id
        AND nb.status NOT IN ('cancelled','completed')
        AND nb.end_date::date >= CURRENT_DATE
        AND nb.start_date::date BETWEEN b.end_date::date AND b.end_date::date + 1
    );
END;
$$;

-- 4) Seed samotný — deterministicky "náhodný" (hash z moto id), nikdy neshodí
--    transakci: kolizní bloky se posouvají, neumístitelné se přeskočí.
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
BEGIN
  SELECT id INTO v_user
  FROM profiles
  WHERE lower(email) = 'semorad@nastrojarstvi.com'
  LIMIT 1;

  IF v_user IS NULL THEN
    RAISE NOTICE 'SEED-KALENDAR-2026-0910: profil semorad@nastrojarstvi.com nenalezen — seed přeskočen (nic se nevložilo).';
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM bookings WHERE user_id = v_user AND is_test IS TRUE AND notes LIKE 'SEED-KALENDAR-2026-0910%') THEN
    RAISE NOTICE 'SEED-KALENDAR-2026-0910: už aplikováno — přeskočeno.';
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
                status, payment_status, total_price, delivery_fee, deposit,
                booking_source, is_test, notes, confirmed_at,
                reserved_email_sent_at, abandoned_email_sent_at, docs_reminder_sent_at
              ) VALUES (
                v_user, m.id, v_s, v_e, '10:00', '19:00',
                'reserved', 'paid', 0, 0, 0,
                'app', true,
                'SEED-KALENDAR-2026-0910 — testovací obsazenost kalendáře (0 Kč)',
                now(), now(), now(), now()
              );
              v_ins := v_ins + 1;
              v_placed := true;
            EXCEPTION WHEN OTHERS THEN
              v_placed := false;  -- trigger kolize apod. → zkus další posun
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

  RAISE NOTICE 'SEED-KALENDAR-2026-0910: vloženo % testovacích rezervací, % bloků se nikam nevešlo.', v_ins, v_miss;
END $seed$;
