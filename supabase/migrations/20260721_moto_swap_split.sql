-- =============================================================================
-- MIGRACE 2026-07-21: Výměna motorky uprostřed rezervace = SPLIT na dvě rezervace
--                     (NET rozdíl přes stávající edit-platbu — rev. 2)
--
-- Výměna motorky v rámci jedné rezervace (web/app „úprava rezervace" + DATUM a ČAS
-- výměny) = na pozadí DVĚ po sobě jdoucí rezervace:
--   • původní A se zkrátí na [start .. swap_date-1],
--   • nová B vznikne na [swap_date .. end] na nové motorce, propojená přes
--     continues_booking_id → dostane VLASTNÍ smlouvu + „reserved" mail.
-- Switch (aktivace B, uzavření A) proběhne PŘEDÁVACÍM PROTOKOLEM na obslužné pobočce
-- (swap_handoff_bookings z 20260720).
--
-- PLATBA = NET ROZDÍL (rozhodnutí uživatele): zákazník doplatí/dostane zpět JEN
-- rozdíl (cena nové motorky za zbývající dny − hodnota odebraných dní staré) přes
-- STÁVAJÍCÍ edit-platbu (doplatek / process-refund) — žádná nová platební obrazovka.
--   1) frontend `p_dry_run=true` → vrátí net (+a_removed/b_total),
--   2) frontend vypořádá net (doplatek / vrácení) stávající cestou,
--   3) frontend `p_dry_run=false` (COMMIT) → zkrátí A, vytvoří B jako ZAPLACENOU,
--      rozešle „reserved" mail B (server-side → web i app stejně).
--
-- POZOR — ÚČETNICTVÍ (ZF/DP/KF, dobropisy) tohoto net/reallocation modelu NENÍ
-- v této migraci řešeno (odloženo uživatelem). RPC zapisuje POUZE data rezervací
-- + rozešle mail; NEvytváří dobropisy ani faktury. Před ostrým provozem dořešit.
--
-- Staví na 20260720_moto_handoff_switch.sql.
-- =============================================================================

-- Pomocná: součet denní ceny motorky za rozsah [p_start .. p_end] (inkluzivně) ---
CREATE OR REPLACE FUNCTION _moto_dayprice_sum(p_moto_id uuid, p_start date, p_end date)
RETURNS numeric
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(SUM(
    CASE EXTRACT(ISODOW FROM d)::int
      WHEN 1 THEN m.price_mon WHEN 2 THEN m.price_tue WHEN 3 THEN m.price_wed
      WHEN 4 THEN m.price_thu WHEN 5 THEN m.price_fri WHEN 6 THEN m.price_sat
      WHEN 7 THEN m.price_sun END
  ), 0)::numeric
  FROM generate_series(p_start, p_end, interval '1 day') d
  CROSS JOIN motorcycles m
  WHERE m.id = p_moto_id AND p_end >= p_start;
$$;

-- Výměna motorky: preview (dry_run) + commit ---------------------------------
CREATE OR REPLACE FUNCTION split_booking_moto_swap(
  p_booking_id  uuid,
  p_new_moto_id uuid,
  p_swap_date   date,
  p_swap_time   text DEFAULT NULL,
  p_dry_run     boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_admin    boolean := is_admin();
  b          bookings;
  v_conflict int;
  v_a_removed numeric;
  v_b_total   numeric;
  v_net       numeric;
  v_new_id    uuid;
  v_url text; v_key text; v_email text; v_name text; v_moto text;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  IF b.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF NOT v_admin AND (v_uid IS NULL OR b.user_id IS DISTINCT FROM v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF b.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;
  IF p_new_moto_id IS NULL OR p_new_moto_id = b.moto_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_new_moto');
  END IF;
  IF p_swap_date <= b.start_date::date OR p_swap_date > b.end_date::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'swap_date_out_of_range');
  END IF;
  IF EXISTS (SELECT 1 FROM bookings s WHERE s.continues_booking_id = p_booking_id AND s.status <> 'cancelled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_split');
  END IF;

  -- Dostupnost NOVÉ motorky pro [swap_date .. end], MIMO tuto rezervaci.
  SELECT count(*) INTO v_conflict FROM (
    SELECT 1 FROM bookings ob
    WHERE ob.moto_id = p_new_moto_id AND ob.id <> p_booking_id
      AND ob.status IN ('pending','reserved','active')
      AND daterange(ob.start_date::date, ob.end_date::date, '[]')
          && daterange(p_swap_date, b.end_date::date, '[]')
    UNION ALL
    SELECT 1 FROM maintenance_log m
    WHERE m.moto_id = p_new_moto_id AND m.service_date IS NOT NULL AND m.completed_date IS NULL
      AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
      AND daterange(m.service_date::date, COALESCE(m.scheduled_date, m.service_date)::date, '[]')
          && daterange(p_swap_date, b.end_date::date, '[]')
  ) x;
  IF v_conflict > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'new_moto_unavailable');
  END IF;

  -- NET rozdíl: hodnota nové motorky za [swap..end] − hodnota odebraných dní staré.
  v_a_removed := _moto_dayprice_sum(b.moto_id, p_swap_date, b.end_date::date);
  v_b_total   := _moto_dayprice_sum(p_new_moto_id, p_swap_date, b.end_date::date);
  v_net       := v_b_total - v_a_removed;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true, 'dry_run', true,
      'net', v_net, 'a_removed', v_a_removed, 'b_total', v_b_total,
      'a_new_end', (p_swap_date - 1), 'b_start', p_swap_date, 'b_end', b.end_date::date
    );
  END IF;

  -- COMMIT (voláno AŽ po vypořádání net rozdílu frontendem — doplatek/vrácení):
  -- 1) Zkrať původní rezervaci (jen data; účetní rozpad ZF/DP/KF NEŘEŠÍ tato RPC).
  UPDATE bookings SET
    end_date = (p_swap_date - 1),
    original_end_date = COALESCE(original_end_date, end_date),
    total_price = GREATEST(total_price - v_a_removed, 0),
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'type', 'moto_swap_shorten', 'to_end', (p_swap_date - 1),
      'new_moto_id', p_new_moto_id, 'net', v_net, 'source', 'moto_swap')
  WHERE id = p_booking_id;

  -- 2) Vytvoř druhou rezervaci B jako ZAPLACENOU (net už vypořádán). Overlap s A
  --    pustí výjimka check_user_booking_overlap (continues_booking_id).
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time, return_time,
    status, payment_status, total_price, delivery_fee, deposit,
    booking_source, continues_booking_id, notes
  ) VALUES (
    b.user_id, p_new_moto_id, p_swap_date, b.end_date, COALESCE(p_swap_time, b.pickup_time), b.return_time,
    'reserved', 'paid', v_b_total, 0, 0,
    COALESCE(b.booking_source, 'web'), p_booking_id,
    'Výměna motorky — navazuje na rezervaci ' || upper(right(p_booking_id::text, 8))
  ) RETURNING id INTO v_new_id;

  -- 3) Rozešli „reserved" mail (+ smlouva) pro B server-side → web i app stejně.
  --    Best-effort, izolovaně — nikdy neshodí commit.
  BEGIN
    SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
    SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
    SELECT p.email, p.full_name, m.model INTO v_email, v_name, v_moto
    FROM profiles p, motorcycles m WHERE p.id = b.user_id AND m.id = p_new_moto_id;
    IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' AND COALESCE(v_email,'') <> '' THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body := jsonb_build_object(
          'type', 'booking_reserved', 'booking_id', v_new_id,
          'customer_email', v_email, 'customer_name', COALESCE(v_name,''),
          'motorcycle', COALESCE(v_moto,''),
          'start_date', p_swap_date, 'end_date', b.end_date::date,
          'source', COALESCE(b.booking_source,'web')
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('split_booking_moto_swap','reserved_mail_dispatch_failed','error', SQLERRM,
            jsonb_build_object('new_booking_id', v_new_id));
  END;

  RETURN jsonb_build_object('success', true, 'new_booking_id', v_new_id, 'net', v_net);
END;
$$;

REVOKE ALL ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean) TO anon, authenticated;

-- SAMOOBSLUŽNÁ pobočka: kódy k nové motorce zadrž, dokud zákazník nevrátí ------
--   původní (dle zadání). Obslužná/svoz beze změny.
--   (a) Při vzniku kódu k nové motorce navazující rezervace → zadrž.
CREATE OR REPLACE FUNCTION withhold_swap_next_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cont        uuid;
  v_selfservice boolean;
  v_a_returned  boolean;
BEGIN
  IF NEW.code_type <> 'motorcycle' THEN RETURN NEW; END IF;
  SELECT continues_booking_id INTO v_cont FROM bookings WHERE id = NEW.booking_id;
  IF v_cont IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(br.type = 'samoobslužná', false) INTO v_selfservice
  FROM motorcycles m JOIN branches br ON br.id = m.branch_id WHERE m.id = NEW.moto_id;
  IF NOT COALESCE(v_selfservice, false) THEN RETURN NEW; END IF;
  SELECT (returned_at IS NOT NULL OR status = 'completed') INTO v_a_returned
  FROM bookings WHERE id = v_cont;
  IF COALESCE(v_a_returned, false) THEN RETURN NEW; END IF;
  NEW.sent_to_customer := false;
  NEW.withheld_reason := 'Vraťte nejdřív původní motorku';
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_withhold_swap_next_codes ON branch_door_codes;
CREATE TRIGGER trg_withhold_swap_next_codes
  BEFORE INSERT ON branch_door_codes
  FOR EACH ROW EXECUTE FUNCTION withhold_swap_next_codes();

--   (b) Po vrácení původní (A completed / returned_at) → uvolni kódy navazující B.
CREATE OR REPLACE FUNCTION release_swap_next_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  v_released int;
BEGIN
  FOR r IN
    SELECT id AS booking_id, user_id FROM bookings
    WHERE continues_booking_id = NEW.id
      AND status IN ('reserved','active','pending')
  LOOP
    UPDATE branch_door_codes
       SET sent_to_customer = true, sent_at = now(), withheld_reason = NULL
     WHERE booking_id = r.booking_id AND is_active = true
       AND withheld_reason = 'Vraťte nejdřív původní motorku';
    GET DIAGNOSTICS v_released = ROW_COUNT;
    IF v_released > 0 THEN
      BEGIN PERFORM send_door_codes_email(r.booking_id, r.user_id); EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_swap_next_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_release_swap_next_codes ON bookings;
CREATE TRIGGER trg_release_swap_next_codes
  AFTER UPDATE OF status, returned_at ON bookings
  FOR EACH ROW
  WHEN ((NEW.status = 'completed' OR NEW.returned_at IS NOT NULL)
        AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.returned_at IS DISTINCT FROM NEW.returned_at))
  EXECUTE FUNCTION release_swap_next_codes();

NOTIFY pgrst, 'reload schema';
