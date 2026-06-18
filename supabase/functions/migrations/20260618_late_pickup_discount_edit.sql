-- =============================================================================
-- MIGRACE 2026-06-18 (B): Sleva 50 % na 1. den — PŘEPOČET PŘI ÚPRAVĚ (Milestone 2)
--
-- Čistá varianta: čas vyzvednutí řeší přímo _apply_booking_changes_core přes
-- nový parametr p_new_pickup_time (předává ho wrapper apply_booking_changes).
-- Při změně data / motorky / ČASU se sleva na 1. den přepočítá do hrubého
-- rozdílu (varianta B) → doplatek = rozdílový DP, vratka = dobropis.
--
-- Pokrývá:
--   1) _apply_booking_changes_core  — + p_new_pickup_time (poslední param,
--      DEFAULT NULL → apply_booking_changes_anon NEMUSÍ být měněn)
--   2) apply_booking_changes        — + p_new_pickup_time, předá do core
--   3) shorten_booking_with_refund  — late-pickup do efektivní hrubé (zkrácení
--      může spadnout pod 2 dny → ztráta slevy)
--
-- POZN.: reschedule_booking_free (volný posun) zůstává BEZE ZMĚNY — drží stejnou
-- cenu z principu (goodwill), late-pickup se na něm nepřepočítává.
-- =============================================================================

-- Úklid dřívější varianty (oddělená settle RPC) — nahrazena cestou přes core.
DROP FUNCTION IF EXISTS public.settle_late_pickup_time_change(uuid, time, boolean);

-- ── 1) _apply_booking_changes_core — + p_new_pickup_time + late-pickup ────────
-- Starou 18-arg verzi nahradíme 19-arg verzí (přidán p_new_pickup_time jako
-- poslední param s DEFAULT NULL).
DROP FUNCTION IF EXISTS public._apply_booking_changes_core(
  uuid, uuid, date, date, uuid, text, text, double precision, double precision,
  numeric, text, text, double precision, double precision, numeric, text, boolean, text);

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
    v_lic_required := COALESCE(v_new_moto.license_required, 'A');
    IF v_lic_required <> 'N' THEN
      SELECT license_group INTO v_user_lic FROM profiles WHERE id = p_user_id;
      IF v_user_lic IS NULL OR NOT (
        v_user_lic && CASE v_lic_required
          WHEN 'AM' THEN ARRAY['AM','A1','A2','A','B']
          WHEN 'A1' THEN ARRAY['A1','A2','A']
          WHEN 'A2' THEN ARRAY['A2','A']
          WHEN 'A'  THEN ARRAY['A']
          WHEN 'B'  THEN ARRAY['B']
          ELSE ARRAY[v_lic_required]
        END
      ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'license_insufficient');
      END IF;
    END IF;
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

  v_dtype := _booking_discount_type(v_b.promo_code_id, v_b.promo_code, v_b.discount_code, v_b.voucher_id);
  v_calc  := _apply_discount_variant_b(v_b.total_price, v_b.discount_amount, v_gross_diff, v_dtype);
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

  IF v_refund > 0 AND v_b.stripe_payment_intent_id IS NOT NULL THEN
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

-- ── 2) apply_booking_changes — + p_new_pickup_time (předá do core) ────────────
DROP FUNCTION IF EXISTS public.apply_booking_changes(
  uuid, date, date, uuid, text, text, double precision, double precision, numeric,
  text, text, double precision, double precision, numeric, text, boolean);

CREATE OR REPLACE FUNCTION public.apply_booking_changes(
  p_booking_id uuid,
  p_new_start date DEFAULT NULL,
  p_new_end date DEFAULT NULL,
  p_new_moto_id uuid DEFAULT NULL,
  p_new_pickup_method text DEFAULT NULL,
  p_new_pickup_address text DEFAULT NULL,
  p_new_pickup_lat double precision DEFAULT NULL,
  p_new_pickup_lng double precision DEFAULT NULL,
  p_new_pickup_fee numeric DEFAULT NULL,
  p_new_return_method text DEFAULT NULL,
  p_new_return_address text DEFAULT NULL,
  p_new_return_lat double precision DEFAULT NULL,
  p_new_return_lng double precision DEFAULT NULL,
  p_new_return_fee numeric DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_dry_run boolean DEFAULT false,
  p_new_pickup_time time DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  RETURN public._apply_booking_changes_core(
    v_user, p_booking_id,
    p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, p_new_pickup_lat, p_new_pickup_lng, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, p_new_return_lat, p_new_return_lng, p_new_return_fee,
    p_reason, p_dry_run, 'web_customer', p_new_pickup_time
  );
END;
$$;
REVOKE ALL ON FUNCTION public.apply_booking_changes(uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, time) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_booking_changes(uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, time) TO authenticated;

-- ── 3) shorten_booking_with_refund — + late-pickup do efektivní hrubé ────────
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

  v_dtype := _booking_discount_type(v_b.promo_code_id, v_b.promo_code, v_b.discount_code, v_b.voucher_id);
  v_calc  := _apply_discount_variant_b(v_b.total_price, v_b.discount_amount, -v_refund_gross, v_dtype);
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

  IF v_refund > 0 AND v_b.stripe_payment_intent_id IS NOT NULL THEN
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
