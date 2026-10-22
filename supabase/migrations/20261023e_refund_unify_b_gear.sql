-- =============================================================================
-- 2026-10-23 (e_b): Výpůjčka výbavy — posun zdarma, extend_booking, odebrání kusu.
-- Navazuje na 20261023e_refund_unify.sql (_refund_tier_pct, _gear_lines_for_days,
-- _gear_change_dates_check). Motorky beze změny chování. Idempotentní.
-- =============================================================================

-- ---- 1) Posun zdarma ------------------------------------------------------------
-- Tělo dle živé DB. Výbava: místo kolize motorky/zákazníka (výbava se smí
-- překrývat, rozhodnutí §1.9) uzavírka + max. délka + sklad pro přidané dny;
-- zápis s GUC motogo.gear_rpc (strážce gear řádku). Cena se nemění (stejná délka).
CREATE OR REPLACE FUNCTION public.reschedule_booking_free(p_booking_id uuid, p_new_start date, p_new_end date, p_source text DEFAULT 'web_customer'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_bk      bookings%ROWTYPE;
  v_today   date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_hist    jsonb;
  v_chk     jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_bk.user_id <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- Motorka nesmí být převzatá: na samoobslužné pobočce překlápí rezervaci na
  -- 'active' zadání kódu do boxu, na obslužné předávací protokol.
  IF v_bk.status <> 'reserved' THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF v_bk.payment_status <> 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  -- NOVÉ: posun zdarma jen do konce dne začátku termínu.
  IF v_bk.start_date::date < v_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'term_started');
  END IF;

  IF (p_new_end - p_new_start) <> (v_bk.end_date::date - v_bk.start_date::date) THEN
    RETURN jsonb_build_object('success', false, 'error', 'length_mismatch');
  END IF;

  IF p_new_start < v_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'past_date');
  END IF;

  IF p_new_start = v_bk.start_date::date AND p_new_end = v_bk.end_date::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

  IF v_bk.booking_kind = 'gear' THEN
    -- 2026-10-23e: výbava — uzavírka pobočky, délka, sklad (přidané dny, bez sebe)
    v_chk := public._gear_change_dates_check(v_bk.id, p_new_start, p_new_end);
    IF v_chk IS NOT NULL THEN RETURN v_chk; END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM bookings b
       WHERE b.id <> v_bk.id
         AND b.moto_id = v_bk.moto_id
         AND b.status IN ('pending','reserved','active')
         AND b.start_date::date <= p_new_end
         AND b.end_date::date   >= p_new_start
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'moto_overlap');
    END IF;

    IF EXISTS (
      SELECT 1 FROM bookings b
       JOIN motorcycles m ON m.id = b.moto_id
       WHERE b.id <> v_bk.id
         AND b.user_id = v_bk.user_id
         AND b.status IN ('pending','reserved','active')
         AND m.license_required IS DISTINCT FROM 'N'
         AND b.start_date::date <= p_new_end
         AND b.end_date::date   >= p_new_start
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'customer_overlap');
    END IF;
  END IF;

  v_hist := COALESCE(v_bk.modification_history, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'at', now(),
      'from_start', v_bk.start_date::date, 'from_end', v_bk.end_date::date,
      'to_start', p_new_start, 'to_end', p_new_end,
      'source', COALESCE(p_source,'web_customer'), 'free_move', true
    )
  );

  IF v_bk.booking_kind = 'gear' THEN PERFORM set_config('motogo.gear_rpc', '1', true); END IF;
  UPDATE bookings SET
    start_date           = p_new_start,
    end_date             = p_new_end,
    original_start_date  = COALESCE(original_start_date, v_bk.start_date),
    original_end_date    = COALESCE(original_end_date,   v_bk.end_date),
    modification_history = v_hist
  WHERE id = v_bk.id;

  RETURN jsonb_build_object('success', true, 'new_start', p_new_start, 'new_end', p_new_end, 'free', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'server_error',
                            'detail', SQLERRM, 'sqlstate', SQLSTATE);
END;
$$;

-- ---- 2) extend_booking (jen service_role, appka ani web ho nevolají) --------------
-- Motorka beze změny. Výbava: kontrola přidaných dní + cena = gear_per_day × dny.
CREATE OR REPLACE FUNCTION public.extend_booking(p_booking_id uuid, p_new_end_date timestamp with time zone)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    booking RECORD;
    is_available BOOLEAN;
    price_result jsonb;
    extra_price NUMERIC;
    v_chk jsonb;
BEGIN
    SELECT * INTO booking FROM bookings WHERE id = p_booking_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
    END IF;
    IF booking.status NOT IN ('pending', 'active', 'reserved') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Booking cannot be modified');
    END IF;
    IF p_new_end_date <= booking.end_date THEN
        RETURN jsonb_build_object('success', false, 'error', 'New end date must be after current end date');
    END IF;

    IF booking.booking_kind = 'gear' THEN
        v_chk := public._gear_change_dates_check(p_booking_id, booking.start_date::date, p_new_end_date::date);
        IF v_chk IS NOT NULL THEN RETURN v_chk; END IF;
        extra_price := COALESCE(booking.gear_per_day, 0) * (p_new_end_date::date - booking.end_date::date);
        PERFORM set_config('motogo.gear_rpc', '1', true);
        UPDATE bookings
        SET end_date = p_new_end_date,
            total_price = COALESCE(total_price, 0) + extra_price,
            gear_lines = public._gear_lines_for_days(gear_lines, (p_new_end_date::date - start_date::date) + 1)
        WHERE id = p_booking_id;
        RETURN jsonb_build_object('success', true, 'extra_price', extra_price,
            'new_end_date', p_new_end_date, 'new_total', COALESCE(booking.total_price, 0) + extra_price);
    END IF;

    is_available := check_moto_availability(
        booking.moto_id, booking.end_date, p_new_end_date, p_booking_id
    );
    IF NOT is_available THEN
        RETURN jsonb_build_object('success', false, 'error', 'Motorcycle not available');
    END IF;

    -- calc_booking_price_v2 returns jsonb with total_price field
    price_result := calc_booking_price_v2(
        booking.moto_id,
        (booking.end_date + INTERVAL '1 day')::DATE,
        p_new_end_date::DATE
    );
    extra_price := COALESCE((price_result->>'total_price')::numeric, 0);

    UPDATE bookings
    SET end_date = p_new_end_date,
        total_price = COALESCE(total_price, 0) + extra_price
    WHERE id = p_booking_id;

    RETURN jsonb_build_object(
        'success', true,
        'extra_price', extra_price,
        'new_end_date', p_new_end_date,
        'new_total', COALESCE(booking.total_price, 0) + extra_price
    );
END;
$$;
REVOKE ALL ON FUNCTION public.extend_booking(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.extend_booking(uuid, timestamptz) TO service_role;

-- ---- 3) Odebrání kusu ze zaplacené výpůjčky výbavy (zákazník, web) ------------------
-- Jen rezervovaná (nepřevzatá) výbava, zůstat musí aspoň 1 kus (jinak storno).
-- Nová cena/den: nedotčené řádky drží uloženou cenu; řádek s odebraným kusem —
-- kus zmizí, komplet se rozpadne na zbylé kusy přeceněné ceníkem (nikdy dráž než
-- komplet; jinak zůstane komplet bez kusu za stejnou cenu). Vratka = rozdíl
-- ceny/den × zbývající dny × pásmo (_refund_tier_pct + _storno_cap_after_move),
-- rozpad slevy přes _recalc_booking_discount. p_dry_run = jen náhled.
-- Mail „Rezervace upravena" (changes.gear) přes _gear_notify_modified (20261023b);
-- při změně ceny ho pošle už trigger úprav rezervace (bez řádku kusů).
CREATE OR REPLACE FUNCTION public.customer_remove_gear_item(p_booking_id uuid, p_key text, p_dry_run boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_b bookings%ROWTYPE; v_key text := lower(btrim(COALESCE(p_key, '')));
  v_from jsonb; v_to jsonb; ln jsonb; v_lines jsonb := '[]'::jsonb; v_rest text[]; v_q jsonb;
  v_old_pd numeric; v_new_pd numeric := 0; v_lines_pd numeric := 0; v_set_pd numeric; v_days int; v_pct int; v_gross numeric;
  v_calc jsonb; v_new_total numeric; v_new_disc numeric; v_refund numeric; v_now timestamptz := now();
  v_url text; v_srk text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_b.user_id IS DISTINCT FROM v_uid OR v_b.booking_kind IS DISTINCT FROM 'gear' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_b.status <> 'reserved' OR v_b.picked_up_at IS NOT NULL OR v_b.handover_protocol_filled_at IS NOT NULL
     OR v_b.gear_collected_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF v_b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  v_from := jsonb_strip_nulls(jsonb_build_object('helmet', NULLIF(btrim(v_b.helmet_size), ''),
    'jacket', NULLIF(btrim(v_b.jacket_size), ''), 'pants', NULLIF(btrim(v_b.pants_size), ''),
    'gloves', NULLIF(btrim(v_b.gloves_size), ''), 'boots', NULLIF(btrim(v_b.boots_size), '')));
  IF NOT (v_from ? v_key) THEN RETURN jsonb_build_object('success', false, 'error', 'bad_item', 'key', v_key); END IF;
  v_to := v_from - v_key;
  IF v_to = '{}'::jsonb THEN RETURN jsonb_build_object('success', false, 'error', 'last_item'); END IF;

  -- nové řádky a cena za den
  FOR ln IN SELECT * FROM jsonb_array_elements(COALESCE(v_b.gear_lines, '[]'::jsonb)) LOOP
    v_lines_pd := v_lines_pd + COALESCE((ln->>'price_per_day')::numeric, 0);
    IF NOT (COALESCE(ln->'includes', jsonb_build_array(ln->>'key')) ? v_key) THEN
      v_lines := v_lines || ln; v_new_pd := v_new_pd + COALESCE((ln->>'price_per_day')::numeric, 0);
    ELSIF ln->>'kind' = 'set' THEN
      v_set_pd := COALESCE((ln->>'price_per_day')::numeric, 0);
      SELECT array_agg(x) INTO v_rest FROM jsonb_array_elements_text(ln->'includes') x WHERE x <> v_key;
      v_q := CASE WHEN v_rest IS NULL THEN NULL ELSE public._gear_rental_quote(
        (SELECT jsonb_agg(jsonb_build_object('key', k, 'size', v_to->>k)) FROM unnest(v_rest) k)) END;
      IF v_q IS NOT NULL AND NOT (v_q ? 'error') AND (v_q->>'per_day')::numeric < v_set_pd THEN
        v_lines := v_lines || (v_q->'lines'); v_new_pd := v_new_pd + (v_q->>'per_day')::numeric;
      ELSIF v_rest IS NOT NULL THEN
        v_lines := v_lines || jsonb_build_array(ln || jsonb_build_object('includes', to_jsonb(v_rest),
          'sizes', COALESCE(ln->'sizes', '{}'::jsonb) - v_key));
        v_new_pd := v_new_pd + v_set_pd;
      END IF;
    END IF;   -- samostatný kus: řádek zmizí
  END LOOP;
  -- nová cena/den = uložená − úspora na řádcích (nikdy víc než dosud, nikdy < 0)
  v_old_pd := COALESCE(v_b.gear_per_day, 0);
  v_new_pd := GREATEST(0, v_old_pd - GREATEST(0, v_lines_pd - v_new_pd));

  -- vratka za zbývající dny (od dneška, Praha), pásmo k aktuálnímu začátku
  v_days := GREATEST(0, (v_b.end_date::date - GREATEST(v_b.start_date::date, (v_now AT TIME ZONE 'Europe/Prague')::date)) + 1);
  v_pct := LEAST(public._refund_tier_pct(v_b.start_date, v_b.pickup_time, v_now),
                 public._storno_cap_after_move(v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
  v_gross := ROUND((v_old_pd - v_new_pd) * v_days * v_pct / 100.0);
  v_calc := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, -v_gross, false);
  v_new_total := (v_calc->>'new_total')::numeric;
  v_new_disc  := (v_calc->>'new_discount')::numeric;
  v_refund    := GREATEST(0, -((v_calc->>'net_diff')::numeric));
  v_lines := public._gear_lines_for_days(v_lines, (v_b.end_date::date - v_b.start_date::date) + 1);

  IF p_dry_run THEN
    RETURN jsonb_build_object('success', true, 'dry_run', true, 'refund_amount', v_refund, 'refund_percent', v_pct,
      'removed_value', (v_old_pd - v_new_pd) * v_days, 'old_per_day', v_old_pd, 'new_per_day', v_new_pd,
      'new_total', v_new_total, 'lines', v_lines, 'from', v_from, 'to', v_to);
  END IF;

  PERFORM set_config('motogo.gear_rpc', '1', true);
  UPDATE bookings SET
    helmet_size = CASE WHEN v_key = 'helmet' THEN NULL ELSE helmet_size END,
    jacket_size = CASE WHEN v_key = 'jacket' THEN NULL ELSE jacket_size END,
    pants_size  = CASE WHEN v_key = 'pants'  THEN NULL ELSE pants_size  END,
    gloves_size = CASE WHEN v_key = 'gloves' THEN NULL ELSE gloves_size END,
    boots_size  = CASE WHEN v_key = 'boots'  THEN NULL ELSE boots_size  END,
    gear_lines = v_lines, gear_per_day = v_new_pd, total_price = v_new_total, discount_amount = v_new_disc,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', v_now, 'source', 'web', 'type', 'gear_remove', 'key', v_key, 'from', v_from, 'to', v_to,
      'from_per_day', v_old_pd, 'to_per_day', v_new_pd, 'from_total', v_b.total_price, 'to_total', v_new_total,
      'from_discount', v_b.discount_amount, 'to_discount', v_new_disc,
      'refund_amount', v_refund, 'refund_percent', v_pct, 'gross_refund', v_gross, 'price_diff', v_new_total - v_b.total_price)
  WHERE id = p_booking_id;

  IF v_refund > 0 THEN
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_srk FROM app_settings WHERE key = 'service_role_key';
      IF COALESCE(v_url, '') <> '' AND COALESCE(v_srk, '') <> '' THEN
        PERFORM net.http_post(url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_srk),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'gear_edit', 'source', 'gear_remove'));
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('customer_remove_gear_item', 'refund_dispatch_skipped_no_settings', 'error',
                'app_settings supabase_url/service_role_key missing', jsonb_build_object('booking_id', p_booking_id, 'refund', v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('customer_remove_gear_item', 'refund_dispatch_failed', 'error', SQLERRM,
              jsonb_build_object('booking_id', p_booking_id, 'refund', v_refund));
    END;
  END IF;
  -- Mail „Rezervace upravena": při změně ceny ho poslal už trigger úprav (dedup
  -- v _gear_notify_modified ho nezdvojí), jinak ho pošle tento helper (20261023b).
  BEGIN
    PERFORM public._gear_notify_modified(p_booking_id,
      jsonb_build_object('gear', jsonb_build_object('from', v_from, 'to', v_to)));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('customer_remove_gear_item', 'notify_failed', 'error', SQLERRM, jsonb_build_object('booking_id', p_booking_id));
  END;

  RETURN jsonb_build_object('success', true, 'refund_amount', v_refund, 'refund_percent', v_pct,
    'removed_key', v_key, 'old_per_day', v_old_pd, 'new_per_day', v_new_pd, 'new_total', v_new_total, 'lines', v_lines);
END $$;
REVOKE ALL ON FUNCTION public.customer_remove_gear_item(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_remove_gear_item(uuid, text, boolean) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
