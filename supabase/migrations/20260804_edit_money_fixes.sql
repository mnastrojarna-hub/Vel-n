-- =============================================================================
-- MIGRACE 2026-08-04: Peněžní integrita úprav rezervace (web/app/Velín)
--
-- 1) _apply_booking_changes_core + shorten_booking_with_refund: vratka se
--    dispatchuje VŽDY, když je co vracet — dřív podmínka
--    "stripe_payment_intent_id IS NOT NULL" tiše zahodila vratku u rezervací
--    placených QR/převodem/hotově (zákazník viděl "vracíme X Kč", peníze ani
--    dobropis nikdy nevznikly). process-refund (2026-08-04) si PI umí dohledat
--    ze stripe_session_id a bez Stripe platby vystaví dobropis + označí
--    rezervaci 'refund_pending' (manuální vratka převodem na účet do 14 dnů;
--    Velín ukáže "Vrátit X Kč na účet zákazníka").
-- 2) _apply_booking_changes_core: overlap kontrola nově zahrnuje SERVISNÍ bloky
--    (maintenance_log) — změna motorky/termínu na stroj v servisu už neprojde
--    serverem; ŘP kontrola přes license_groups (OR-match, fallback
--    license_required) — parita s katalogem/appkou.
-- 3) cancel_booking_tracked: hranice storna '>=' 168/48 h (web i appka slibují
--    100 %/50 % už přesně na hranici; server vracel o tier méně).
-- 4) split_booking_moto_swap (rev.6): ŘP kontrola vlastníka rezervace pro
--    zákaznická volání (dosud jen frontend); admin/service_role beze změny.
--
-- Těla funkcí jsou 1:1 kopie posledních verzí (core+shorten z 20260625,
-- cancel z 20260503, swap z 20260731c) s výše popsanými cílenými změnami —
-- generováno skriptem, ne ručním přepisem.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."_apply_booking_changes_core"(
  "p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date",
  "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text",
  "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric,
  "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision,
  "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text",
  "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b               bookings%ROWTYPE;
  v_old_moto        motorcycles%ROWTYPE;
  v_new_moto        motorcycles%ROWTYPE;
  v_use_moto        motorcycles%ROWTYPE;
  v_fs date := NULL;  v_fe date := NULL;
  v_old_dates_total numeric := 0;
  v_new_dates_total numeric := 0;
  v_dates_diff      numeric := 0;
  v_moto_diff       numeric := 0;
  v_pickup_fee_diff numeric := 0;
  v_return_fee_diff numeric := 0;
  v_gross_diff      numeric := 0;
  v_net_diff        numeric := 0;
  v_refund          numeric := 0;
  v_storno_pct      int := 100;
  v_now             timestamptz := now();
  v_overlap_count   int;
  v_user_lic        text[];
  v_lic_required    text;
  v_d               date;
  v_dow             int;
  v_p_old           numeric;
  v_p_new           numeric;
  v_history_entry   jsonb;
  v_is_active       boolean;
  v_payment_required boolean := false;
  v_changed         boolean := false;
  v_dtype           text;
  v_calc            jsonb;
  v_new_total       numeric;
  v_new_discount    numeric;
  v_url             text;
  v_key             text;
  v_old_late        numeric := 0;
  v_new_late        numeric := 0;
  v_eff_pickup      time;
  v_pickup_changed  boolean := false;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.user_id <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_b.status NOT IN ('reserved','active') OR v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;

  v_is_active := (v_b.status = 'active');
  v_eff_pickup := COALESCE(p_new_pickup_time, v_b.pickup_time);
  v_pickup_changed := (p_new_pickup_time IS NOT NULL AND p_new_pickup_time IS DISTINCT FROM v_b.pickup_time);

  v_fs := COALESCE(p_new_start, v_b.start_date);
  v_fe := COALESCE(p_new_end,   v_b.end_date);
  IF v_is_active AND v_fs <> v_b.start_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_start_locked');
  END IF;
  IF v_fs > v_fe THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_range');
  END IF;

  SELECT * INTO v_old_moto FROM motorcycles WHERE id = v_b.moto_id;
  IF p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id THEN
    IF v_is_active THEN
      RETURN jsonb_build_object('success', false, 'error', 'active_moto_locked');
    END IF;
    SELECT * INTO v_new_moto FROM motorcycles WHERE id = p_new_moto_id AND status = 'active';
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'moto_not_found');
    END IF;
    -- 2026-08-04: OR-match přes VŠECHNY přijímané skupiny ŘP (license_groups;
    -- fallback [license_required]) — parita s katalogem/appkou. Skútr {A1,B}
    -- tak smí i zákazník se skupinou B.
    DECLARE
      v_groups text[] := (SELECT COALESCE(NULLIF(m.license_groups, '{}'::text[]),
                                          ARRAY[COALESCE(m.license_required::text, 'A')])
                            FROM motorcycles m WHERE m.id = v_new_moto.id);
    BEGIN
      IF NOT ('N' = ANY(COALESCE(v_groups, ARRAY['A']))) THEN
        SELECT license_group INTO v_user_lic FROM profiles WHERE id = p_user_id;
        IF v_user_lic IS NULL OR NOT EXISTS (
          SELECT 1 FROM unnest(COALESCE(v_groups, ARRAY['A'])) g
          WHERE v_user_lic && CASE g
            WHEN 'AM' THEN ARRAY['AM','A1','A2','A','B']
            WHEN 'A1' THEN ARRAY['A1','A2','A']
            WHEN 'A2' THEN ARRAY['A2','A']
            WHEN 'A'  THEN ARRAY['A']
            WHEN 'B'  THEN ARRAY['B']
            ELSE ARRAY[g]
          END
        ) THEN
          RETURN jsonb_build_object('success', false, 'error', 'license_insufficient');
        END IF;
      END IF;
    END;
    v_use_moto := v_new_moto;
  ELSE
    v_use_moto := v_old_moto;
  END IF;

  IF p_new_start IS NOT NULL OR p_new_end IS NOT NULL OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id) THEN
    SELECT COUNT(*) INTO v_overlap_count FROM bookings b2
      WHERE b2.moto_id = v_use_moto.id
        AND b2.id <> p_booking_id
        AND b2.status IN ('pending','reserved','active')
        AND NOT (b2.end_date < v_fs OR b2.start_date > v_fe);
    IF v_overlap_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'overlap');
    END IF;
    -- 2026-08-04: plánovaný SERVIS blokuje termín i server-side (frontend ho
    -- jen vykresluje, check_moto_availability ho ignoruje) — stejná logika
    -- jako split_booking_moto_swap.
    SELECT COUNT(*) INTO v_overlap_count FROM maintenance_log m
      WHERE m.moto_id = v_use_moto.id
        AND m.service_date IS NOT NULL AND m.completed_date IS NULL
        AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
        AND daterange(m.service_date::date, COALESCE(m.scheduled_date, m.service_date)::date, '[]')
            && daterange(v_fs, v_fe, '[]');
    IF v_overlap_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'overlap');
    END IF;
  END IF;

  v_d := v_b.start_date;
  WHILE v_d <= v_b.end_date LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_old := CASE v_dow
      WHEN 1 THEN COALESCE(v_old_moto.price_mon, v_old_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_old_moto.price_tue, v_old_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_old_moto.price_wed, v_old_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_old_moto.price_thu, v_old_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_old_moto.price_fri, v_old_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_old_moto.price_sat, v_old_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_old_moto.price_sun, v_old_moto.price_weekend, 0)
    END;
    v_old_dates_total := v_old_dates_total + v_p_old;
    v_d := v_d + 1;
  END LOOP;

  v_d := v_fs;
  WHILE v_d <= v_fe LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_new := CASE v_dow
      WHEN 1 THEN COALESCE(v_use_moto.price_mon, v_use_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_use_moto.price_tue, v_use_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_use_moto.price_wed, v_use_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_use_moto.price_thu, v_use_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_use_moto.price_fri, v_use_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_use_moto.price_sat, v_use_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_use_moto.price_sun, v_use_moto.price_weekend, 0)
    END;
    v_new_dates_total := v_new_dates_total + v_p_new;
    v_d := v_d + 1;
  END LOOP;

  -- ── LATE PICKUP ── stará = REÁLNĚ uložená hodnota (ne přepočet — jinak by
  -- legacy rezervace bez late vykázala fantomový rozdíl); nová = přepočet pro
  -- nový obsah + efektivní čas vyzvednutí.
  v_old_late := COALESCE(v_b.late_pickup_discount_amount, 0);
  v_new_late := public._late_pickup_discount(v_use_moto.id, v_fs,           v_fe,         v_eff_pickup);

  v_dates_diff := (v_new_dates_total - v_new_late) - (v_old_dates_total - v_old_late);
  IF v_dates_diff < 0 THEN
    v_storno_pct := CASE
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 168 THEN 100
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 48  THEN 50
      ELSE 0
    END;
    v_dates_diff := ROUND(v_dates_diff * v_storno_pct / 100.0);
  END IF;

  IF p_new_pickup_method IS NOT NULL OR p_new_pickup_fee IS NOT NULL THEN
    v_pickup_fee_diff := COALESCE(p_new_pickup_fee, 0) - COALESCE(v_b.delivery_fee, 0);
  END IF;
  IF p_new_return_method IS NOT NULL OR p_new_return_fee IS NOT NULL THEN
    v_return_fee_diff := COALESCE(p_new_return_fee, 0) - 0;
  END IF;

  v_gross_diff := v_dates_diff + v_moto_diff + v_pickup_fee_diff + v_return_fee_diff;

  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, v_gross_diff, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_changed := (
    v_fs <> v_b.start_date OR v_fe <> v_b.end_date
    OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id)
    OR v_pickup_changed
    OR (p_new_pickup_method IS NOT NULL AND p_new_pickup_method IS DISTINCT FROM v_b.pickup_method)
    OR (p_new_pickup_address IS NOT NULL AND p_new_pickup_address IS DISTINCT FROM v_b.pickup_address)
    OR (p_new_return_method IS NOT NULL AND p_new_return_method IS DISTINCT FROM v_b.return_method)
    OR (p_new_return_address IS NOT NULL AND p_new_return_address IS DISTINCT FROM v_b.return_address)
  );
  IF NOT v_changed THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

  v_payment_required := (v_net_diff > 0);
  v_refund := CASE WHEN v_net_diff < 0 THEN -v_net_diff ELSE 0 END;

  IF p_dry_run OR v_payment_required THEN
    RETURN jsonb_build_object(
      'success', true, 'payment_required', v_payment_required,
      'net_diff', v_net_diff, 'refund_amount', v_refund,
      'new_total', v_new_total, 'new_discount', v_new_discount,
      'breakdown', jsonb_build_object(
        'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
        'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
        'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
        'late_pickup_from', v_old_late, 'late_pickup_to', v_new_late
      )
    );
  END IF;

  v_history_entry := jsonb_build_object(
    'at', v_now,
    'from_start', v_b.start_date, 'from_end', v_b.end_date,
    'to_start', v_fs, 'to_end', v_fe,
    'from_moto', v_b.moto_id, 'to_moto', v_use_moto.id,
    'from_pickup_method', v_b.pickup_method, 'to_pickup_method', p_new_pickup_method,
    'from_pickup_address', v_b.pickup_address, 'to_pickup_address', p_new_pickup_address,
    'from_return_method', v_b.return_method, 'to_return_method', p_new_return_method,
    'from_return_address', v_b.return_address, 'to_return_address', p_new_return_address,
    'from_pickup_time', v_b.pickup_time::text, 'to_pickup_time', v_eff_pickup::text,
    'net_diff', v_net_diff, 'gross_diff', v_gross_diff,
    'refund_amount', v_refund, 'storno_pct', v_storno_pct,
    'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
    'from_late_pickup', v_old_late, 'to_late_pickup', v_new_late,
    'price_diff', v_net_diff,
    'reason', p_reason, 'source', COALESCE(p_source, 'web_customer')
  );

  UPDATE bookings SET
    original_start_date = COALESCE(original_start_date, start_date),
    original_end_date   = COALESCE(original_end_date,   end_date),
    start_date          = v_fs,
    end_date            = v_fe,
    moto_id             = v_use_moto.id,
    pickup_time         = COALESCE(p_new_pickup_time, pickup_time),
    pickup_method       = COALESCE(p_new_pickup_method, pickup_method),
    pickup_address      = COALESCE(p_new_pickup_address, pickup_address),
    pickup_lat          = COALESCE(p_new_pickup_lat, pickup_lat),
    pickup_lng          = COALESCE(p_new_pickup_lng, pickup_lng),
    return_method       = COALESCE(p_new_return_method, return_method),
    return_address      = COALESCE(p_new_return_address, return_address),
    return_lat          = COALESCE(p_new_return_lat, return_lat),
    return_lng          = COALESCE(p_new_return_lng, return_lng),
    delivery_fee        = CASE WHEN p_new_pickup_fee IS NOT NULL OR p_new_return_fee IS NOT NULL
                               THEN COALESCE(p_new_pickup_fee, 0) + COALESCE(p_new_return_fee, 0)
                               ELSE delivery_fee END,
    total_price         = v_new_total,
    discount_amount     = v_new_discount,
    late_pickup_discount_amount = v_new_late,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || v_history_entry
  WHERE id = p_booking_id;

  -- 2026-08-04: dispatch VŽDY když je co vracet — process-refund si PI dohledá
  -- ze stripe_session_id, a bez Stripe platby vystaví dobropis + označí
  -- 'refund_pending' (manuální vratka převodem na účet do 14 dnů).
  IF v_refund > 0 THEN
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', COALESCE(p_reason,'edit'), 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('_apply_booking_changes_core','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('_apply_booking_changes_core','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'payment_required', false,
    'net_diff', v_net_diff, 'refund_amount', v_refund,
    'new_total', v_new_total, 'new_discount', v_new_discount,
    'breakdown', jsonb_build_object(
      'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
      'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
      'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
      'late_pickup_from', v_old_late, 'late_pickup_to', v_new_late
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION "public"."shorten_booking_with_refund"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user        uuid := auth.uid();
  v_b           bookings%ROWTYPE;
  v_moto        motorcycles%ROWTYPE;
  v_orig_total  numeric;
  v_new_total_g numeric;
  v_diff        numeric;
  v_hours       numeric;
  v_percent     int;
  v_refund_gross numeric;
  v_refund      numeric;
  v_now         timestamptz := now();
  v_d           date;
  v_dow         int;
  v_price       numeric;
  v_dtype       text;
  v_calc        jsonb;
  v_new_total   numeric;
  v_new_discount numeric;
  v_url         text;
  v_key         text;
  v_old_late    numeric := 0;
  v_new_late    numeric := 0;
BEGIN
  IF v_user IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.user_id <> v_user THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF v_b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
  IF v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success', false, 'error', 'not_paid'); END IF;
  IF p_new_start < v_b.start_date OR p_new_end > v_b.end_date THEN RETURN jsonb_build_object('success', false, 'error', 'not_a_shortening'); END IF;
  IF p_new_start > p_new_end THEN RETURN jsonb_build_object('success', false, 'error', 'invalid_range'); END IF;
  IF v_b.status = 'active' AND p_new_start <> v_b.start_date THEN RETURN jsonb_build_object('success', false, 'error', 'active_start_locked'); END IF;
  IF p_new_start = v_b.start_date AND p_new_end = v_b.end_date THEN RETURN jsonb_build_object('success', false, 'error', 'no_change'); END IF;

  SELECT * INTO v_moto FROM motorcycles WHERE id = v_b.moto_id;

  v_orig_total := 0;
  v_d := v_b.start_date;
  WHILE v_d <= v_b.end_date LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_price := CASE v_dow
      WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_moto.price_sun, v_moto.price_weekend, 0)
    END;
    v_orig_total := v_orig_total + v_price;
    v_d := v_d + 1;
  END LOOP;

  v_new_total_g := 0;
  v_d := p_new_start;
  WHILE v_d <= p_new_end LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_price := CASE v_dow
      WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_moto.price_sun, v_moto.price_weekend, 0)
    END;
    v_new_total_g := v_new_total_g + v_price;
    v_d := v_d + 1;
  END LOOP;

  v_old_late := COALESCE(v_b.late_pickup_discount_amount, 0);   -- reálně uložená, ne přepočet
  v_new_late := public._late_pickup_discount(v_b.moto_id, p_new_start,    p_new_end,    v_b.pickup_time);

  v_diff := (v_orig_total - v_old_late) - (v_new_total_g - v_new_late);
  IF v_diff <= 0 THEN RETURN jsonb_build_object('success', false, 'error', 'no_diff'); END IF;

  IF p_new_end < v_b.end_date THEN
    v_hours := EXTRACT(EPOCH FROM (p_new_end::timestamptz - v_now)) / 3600.0;
  ELSE
    v_hours := EXTRACT(EPOCH FROM (p_new_start::timestamptz - v_now)) / 3600.0;
  END IF;

  v_percent := CASE WHEN v_hours >= 168 THEN 100 WHEN v_hours >= 48 THEN 50 ELSE 0 END;
  v_refund_gross := ROUND(v_diff * v_percent / 100.0);

  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, -v_refund_gross, false);
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;
  v_refund       := GREATEST(0, -((v_calc->>'net_diff')::numeric));

  UPDATE bookings SET
    original_start_date = COALESCE(original_start_date, start_date),
    original_end_date   = COALESCE(original_end_date,   end_date),
    start_date          = p_new_start,
    end_date            = p_new_end,
    total_price         = v_new_total,
    discount_amount     = v_new_discount,
    late_pickup_discount_amount = v_new_late,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', v_now, 'from_start', v_b.start_date, 'from_end', v_b.end_date,
      'to_start', p_new_start, 'to_end', p_new_end, 'source', 'web_customer',
      'refund_amount', v_refund, 'refund_percent', v_percent, 'gross_refund', v_refund_gross,
      'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
      'from_late_pickup', v_old_late, 'to_late_pickup', v_new_late, 'reason', p_reason
    )
  WHERE id = p_booking_id;

  -- 2026-08-04: dispatch VŽDY když je co vracet — process-refund si PI dohledá
  -- ze stripe_session_id, a bez Stripe platby vystaví dobropis + označí
  -- 'refund_pending' (manuální vratka převodem na účet do 14 dnů).
  IF v_refund > 0 THEN
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', COALESCE(p_reason,'shorten'), 'source', 'shorten')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('shorten_booking_with_refund','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('shorten_booking_with_refund','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'refund_amount', v_refund, 'refund_percent', v_percent, 'new_total', v_new_total);
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_booking_tracked(
  p_booking_id uuid,
  p_reason     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_booking      bookings%ROWTYPE;
  v_profile      profiles%ROWTYPE;
  v_moto_model   text;
  v_uid          uuid;
  v_hours_until  numeric;
  v_refund_pct   integer;
  v_refund_amt   numeric;
  v_was_paid     boolean;
  v_url          text;
  v_key          text;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;

  IF v_booking.user_id != v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'Rezervace je již stornována');
  END IF;

  v_was_paid    := (v_booking.payment_status = 'paid');
  v_hours_until := EXTRACT(EPOCH FROM (v_booking.start_date - now())) / 3600;
  -- 2026-08-04: '>=' místo '>' — web i appka slibují 100 % už PŘESNĚ na hranici
  -- 168 h (a 50 % na 48 h); server nesmí na hranici vracet méně, než UI slíbilo.
  IF v_hours_until >= 168 THEN v_refund_pct := 100;
  ELSIF v_hours_until >= 48    THEN v_refund_pct := 50;
  ELSE                              v_refund_pct := 0;
  END IF;
  v_refund_amt := ROUND(COALESCE(v_booking.total_price, 0) * v_refund_pct / 100);

  UPDATE bookings SET
    status               = 'cancelled',
    cancelled_at         = now(),
    cancelled_by         = v_uid,
    cancelled_by_source  = CASE WHEN v_uid = v_booking.user_id THEN 'customer' ELSE 'admin' END,
    cancellation_reason  = COALESCE(p_reason, 'Stornováno zákazníkem')
  WHERE id = p_booking_id;

  INSERT INTO booking_cancellations (booking_id, cancelled_by, reason, refund_amount, refund_percent)
  VALUES (p_booking_id, v_uid, p_reason, v_refund_amt, v_refund_pct);

  -- Pošle send-cancellation-email — ta sama zařídí Stripe refund + dobropis + mail
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'cancel_booking_tracked: app_settings missing — refund/mail skipped';
  ELSE
    SELECT * INTO v_profile FROM profiles WHERE id = v_booking.user_id;
    SELECT model INTO v_moto_model FROM motorcycles WHERE id = v_booking.moto_id;

    IF v_profile.email IS NOT NULL AND v_profile.email <> '' THEN
      BEGIN
        PERFORM net.http_post(
          url     := v_url || '/functions/v1/send-cancellation-email',
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_key
          ),
          body    := jsonb_build_object(
            'booking_id',           v_booking.id,
            'customer_email',       v_profile.email,
            'customer_name',        COALESCE(v_profile.full_name, ''),
            'motorcycle',           COALESCE(v_moto_model, ''),
            'start_date',           v_booking.start_date,
            'end_date',             v_booking.end_date,
            'cancellation_reason',  COALESCE(p_reason, 'Stornováno zákazníkem'),
            'cancelled_by_source',  CASE WHEN v_uid = v_booking.user_id THEN 'customer' ELSE 'admin' END,
            'refund_amount',        v_refund_amt,
            'refund_percent',       v_refund_pct,
            'source',               COALESCE(v_booking.booking_source, 'app')
          )
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'cancel_booking_tracked: mail call failed for %: %', v_booking.id, SQLERRM;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success',         true,
    'refund_percent',  v_refund_pct,
    'refund_amount',   v_refund_amt
  );
END;
$$;

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
  -- service_role (webhook/backend) smí commit — auth.uid() je NULL, ale JWT
  -- role klíče je 'service_role'; klientské anon/authenticated to mít nemohou.
  v_admin    boolean := is_admin() OR COALESCE((NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb->>'role','') = 'service_role';
  b          bookings;
  v_conflict int;
  v_a_removed numeric;
  v_b_total   numeric;
  v_net       numeric;
  v_new_id    uuid;
  v_full_swap boolean;      -- výměna od PRVNÍHO dne rezervace
  v_replace   boolean;      -- plná výměna u 'reserved' → in-place změna moto_id
  v_a_end     date;         -- nový konec původní rezervace A (split větev)
  -- Strop vratky dle skutečně zaplacené ceny (rev.4 2026-07-31b).
  v_a_full       numeric;   -- ceníková hodnota CELÉHO termínu staré motorky
  v_paid_rental  numeric;   -- skutečně zaplacený pronájem (bez dopravy/výbavy)
  v_removed_paid numeric;   -- poměrná zaplacená část za odebrané dny
  v_a_credit     numeric;   -- finální dobropisovaná hodnota odebraných dní
  -- Věrnostní sleva (JEN booking_source='app', aktuální rank zákazníka).
  v_loy_level int := 0;
  v_loy_pct   int := 0;
  v_b_disc    numeric := 0;   -- sleva na cenu B
  v_a_disc    numeric := 0;   -- sleva na odebrané dny A (net vypořádání)
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
  -- Povolený rozsah: KTERÝKOLI den rezervace včetně prvního a posledního.
  IF p_swap_date < b.start_date::date OR p_swap_date > b.end_date::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'swap_date_out_of_range');
  END IF;
  v_full_swap := (p_swap_date = b.start_date::date);
  -- Plná výměna jen od dneška (retroaktivní kompletní náhrada nedává smysl).
  IF v_full_swap AND p_swap_date < CURRENT_DATE THEN
    RETURN jsonb_build_object('success', false, 'error', 'swap_date_out_of_range');
  END IF;
  v_replace := v_full_swap AND b.status = 'reserved';
  -- Plná výměna u aktivní (převzato dnes): A si nechá den jako den předání,
  -- jinak standardně den před výměnou.
  v_a_end := CASE WHEN v_full_swap THEN p_swap_date ELSE p_swap_date - 1 END;
  IF EXISTS (SELECT 1 FROM bookings s WHERE s.continues_booking_id = p_booking_id AND s.status <> 'cancelled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_split');
  END IF;

  -- 2026-08-04: ŘP kontrola VLASTNÍKA rezervace (OR-match license_groups,
  -- fallback [license_required]) — dosud ji hlídal jen frontend. Admin /
  -- service_role (Velín, webhook commit po zaplaceném doplatku) neblokujeme.
  IF NOT v_admin THEN
    DECLARE
      v_groups   text[];
      v_user_lic text[];
    BEGIN
      SELECT COALESCE(NULLIF(m.license_groups, '{}'::text[]),
                      ARRAY[COALESCE(m.license_required::text, 'A')])
        INTO v_groups FROM motorcycles m WHERE m.id = p_new_moto_id;
      IF v_groups IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'invalid_new_moto');
      END IF;
      IF NOT ('N' = ANY(v_groups)) THEN
        SELECT license_group INTO v_user_lic FROM profiles WHERE id = b.user_id;
        IF v_user_lic IS NULL OR NOT EXISTS (
          SELECT 1 FROM unnest(v_groups) g
          WHERE v_user_lic && CASE g
            WHEN 'AM' THEN ARRAY['AM','A1','A2','A','B']
            WHEN 'A1' THEN ARRAY['A1','A2','A']
            WHEN 'A2' THEN ARRAY['A2','A']
            WHEN 'A'  THEN ARRAY['A']
            WHEN 'B'  THEN ARRAY['B']
            ELSE ARRAY[g]
          END
        ) THEN
          RETURN jsonb_build_object('success', false, 'error', 'license_insufficient');
        END IF;
      END IF;
    END;
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

  -- Ceníkové hodnoty: odebrané dny staré motorky a nová motorka za [swap..end].
  v_a_removed := _moto_dayprice_sum(b.moto_id, p_swap_date, b.end_date::date);
  v_b_total   := _moto_dayprice_sum(p_new_moto_id, p_swap_date, b.end_date::date);

  -- Věrnostní sleva JEN pro app rezervace (aktuální rank zákazníka). Level = %:
  --   level = min(20, ceil((počet dokončených app rezervací + 1)/2)); % = discount_percent.
  IF b.booking_source = 'app' THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_b_disc := round(v_b_total   * v_loy_pct / 100.0);
    v_a_disc := round(v_a_removed * v_loy_pct / 100.0);
  END IF;

  -- STROP VRATKY: odebrané dny se dobropisují max. do výše poměrné části
  -- SKUTEČNĚ zaplacené ceny pronájmu (promo/voucher/slevy → zákazník nesmí
  -- dostat zpět víc, než reálně zaplatil).
  v_a_full := _moto_dayprice_sum(b.moto_id, b.start_date::date, b.end_date::date);
  v_paid_rental := GREATEST(COALESCE(b.total_price, 0) - COALESCE(b.delivery_fee, 0) - COALESCE(b.extras_price, 0), 0);
  v_removed_paid := CASE WHEN v_a_full > 0
    THEN LEAST(round(v_paid_rental * v_a_removed / v_a_full), v_paid_rental)
    ELSE 0 END;
  v_a_credit := LEAST(v_a_removed - v_a_disc, v_removed_paid);

  -- Net = (cena B po slevě) − dobropisovaná hodnota odebraných dní A.
  v_net := (v_b_total - v_b_disc) - v_a_credit;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true, 'dry_run', true,
      'net', v_net,
      'mode', CASE WHEN v_replace THEN 'replace' ELSE 'split' END,
      'a_removed', v_a_credit, 'b_total', (v_b_total - v_b_disc),
      'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'a_new_end', CASE WHEN v_replace THEN NULL ELSE v_a_end END,
      'b_start', p_swap_date, 'b_end', b.end_date::date
    );
  END IF;

  -- COMMIT — REPLACE větev: výměna od prvního dne u 'reserved' (nic nepřevzato)
  -- = jen výměna motorky a ceny v TÉŽE rezervaci, žádný split. Mail o úpravě +
  -- rozdílový doklad + app zprávu odešle trg_booking_modified_email (moto_id/cena).
  IF v_replace THEN
    UPDATE bookings SET
      moto_id = p_new_moto_id,
      pickup_time = COALESCE(p_swap_time, pickup_time),
      total_price = GREATEST(total_price + v_net, 0),
      modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
        'at', now(), 'type', 'moto_swap_replace', 'from_moto_id', b.moto_id,
        'new_moto_id', p_new_moto_id, 'net', v_net, 'source', 'moto_swap')
    WHERE id = p_booking_id;
    RETURN jsonb_build_object('success', true, 'new_booking_id', p_booking_id, 'net', v_net, 'mode', 'replace');
  END IF;

  -- COMMIT — SPLIT (voláno AŽ po vypořádání net rozdílu frontendem — doplatek/vrácení):
  -- 1) Zkrať původní rezervaci (jen data; účetní rozpad ZF/DP/KF NEŘEŠÍ tato RPC).
  UPDATE bookings SET
    end_date = v_a_end,
    original_end_date = COALESCE(original_end_date, end_date),
    total_price = GREATEST(total_price - v_a_credit, 0),
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'type', 'moto_swap_shorten', 'to_end', v_a_end,
      'new_moto_id', p_new_moto_id, 'net', v_net, 'source', 'moto_swap')
  WHERE id = p_booking_id;

  -- 2) Vytvoř druhou rezervaci B jako ZAPLACENOU (net už vypořádán). Overlap s A
  --    pustí výjimka check_user_booking_overlap (continues_booking_id).
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time, return_time,
    status, payment_status, total_price, delivery_fee, deposit,
    loyalty_level, loyalty_percent, loyalty_discount_amount,
    booking_source, continues_booking_id, notes
  ) VALUES (
    b.user_id, p_new_moto_id, p_swap_date, b.end_date, COALESCE(p_swap_time, b.pickup_time), b.return_time,
    'reserved', 'paid', (v_b_total - v_b_disc), 0, 0,
    NULLIF(v_loy_level, 0), NULLIF(v_loy_pct, 0), v_b_disc,
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

  RETURN jsonb_build_object('success', true, 'new_booking_id', v_new_id, 'net', v_net, 'mode', 'split');
END;
$$;

REVOKE ALL ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
