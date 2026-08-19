


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."admin_role" AS ENUM (
    'superadmin',
    'manager',
    'operator',
    'viewer'
);


ALTER TYPE "public"."admin_role" OWNER TO "postgres";


CREATE TYPE "public"."ai_suggestion_status" AS ENUM (
    'pending',
    'approved',
    'edited',
    'rejected',
    'sent',
    'auto_sent',
    'failed'
);


ALTER TYPE "public"."ai_suggestion_status" OWNER TO "postgres";


CREATE TYPE "public"."booking_status" AS ENUM (
    'pending',
    'active',
    'completed',
    'cancelled',
    'reserved'
);


ALTER TYPE "public"."booking_status" OWNER TO "postgres";


CREATE TYPE "public"."document_type" AS ENUM (
    'contract',
    'protocol',
    'invoice',
    'license_photo',
    'id_photo',
    'vop',
    'invoice_advance',
    'invoice_final'
);


ALTER TYPE "public"."document_type" OWNER TO "postgres";


CREATE TYPE "public"."entry_type" AS ENUM (
    'income',
    'expense'
);


ALTER TYPE "public"."entry_type" OWNER TO "postgres";


CREATE TYPE "public"."license_group" AS ENUM (
    'A',
    'A1',
    'A2',
    'AM',
    'B',
    'N'
);


ALTER TYPE "public"."license_group" OWNER TO "postgres";


CREATE TYPE "public"."message_channel" AS ENUM (
    'sms',
    'whatsapp',
    'email'
);


ALTER TYPE "public"."message_channel" OWNER TO "postgres";


CREATE TYPE "public"."moto_status" AS ENUM (
    'active',
    'maintenance',
    'unavailable',
    'retired'
);


ALTER TYPE "public"."moto_status" OWNER TO "postgres";


CREATE TYPE "public"."payment_status" AS ENUM (
    'unpaid',
    'paid',
    'refund_pending',
    'refunded',
    'partial_refund'
);


ALTER TYPE "public"."payment_status" OWNER TO "postgres";


CREATE TYPE "public"."sos_status" AS ENUM (
    'reported',
    'acknowledged',
    'in_progress',
    'resolved',
    'closed'
);


ALTER TYPE "public"."sos_status" OWNER TO "postgres";


CREATE TYPE "public"."sos_type" AS ENUM (
    'accident_minor',
    'accident_major',
    'theft',
    'breakdown_minor',
    'breakdown_major',
    'location_share'
);


ALTER TYPE "public"."sos_type" OWNER TO "postgres";


CREATE TYPE "public"."tax_type" AS ENUM (
    'dph_monthly',
    'dph_quarterly',
    'dppo_annual',
    'kontrolni_hlaseni',
    'silnicni_dan'
);


ALTER TYPE "public"."tax_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_activate_on_handover_protocol_doc"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_obsluzna boolean;
  v_status   text;
  v_pay      text;
BEGIN
  -- Jen elektronický PŘEDÁVACÍ protokol (ne damage/contract/vop/gdpr).
  IF COALESCE(NEW.filled_data->>'_doc_type', '') <> 'handover_protocol' THEN
    RETURN NEW;
  END IF;
  IF NEW.booking_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT b.status::text, b.payment_status::text,
         COALESCE(br.type = 'obslužná', false)
    INTO v_status, v_pay, v_obsluzna
  FROM bookings b
  JOIN motorcycles m ON m.id = b.moto_id
  JOIN branches br   ON br.id = m.branch_id
  WHERE b.id = NEW.booking_id;

  -- Aktivace předáním protokolu se týká OBSLUŽNÉ pobočky (samoobslužná = kód
  -- v appce, svoz/delivery = jinak). Mimo obslužnou neaktivujeme.
  IF NOT COALESCE(v_obsluzna, false) THEN
    RETURN NEW;
  END IF;

  IF v_status = 'reserved'
     AND v_pay IN ('paid', 'partial_refund', 'refund_pending') THEN
    -- Podpis předávacího protokolu = motorka reálně předána → aktivuj.
    -- handover_protocol_filled_at PŘÍMO ve stejném UPDATE → projde strážcem.
    UPDATE bookings SET
      status = 'active',
      picked_up_at = COALESCE(picked_up_at, now()),
      handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now())
    WHERE id = NEW.booking_id
      AND status = 'reserved';
  ELSE
    -- Mimo aktivaci alespoň zaznamenej podpis protokolu (idempotentně).
    UPDATE bookings SET
      handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now())
    WHERE id = NEW.booking_id
      AND handover_protocol_filled_at IS NULL;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."_activate_on_handover_protocol_doc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_apply_booking_changes_core"("p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time without time zone DEFAULT NULL::time without time zone) RETURNS "jsonb"
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
  v_loy_level       int := 0;
  v_loy_pct         numeric := 0;
  v_loy_disc        numeric := 0;
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
    -- OR-match přes VŠECHNY přijímané skupiny ŘP (license_groups; fallback
    -- [license_required]) — parita s katalogem/appkou.
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
    -- Plánovaný SERVIS blokuje termín i server-side (stejná logika jako
    -- split_booking_moto_swap).
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

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — JEN app rezervace, JEN kladný rozdíl
  -- pronájmu (doplatek za přidané dny / dražší motorku). Aktuální rank
  -- zákazníka, stejný vzorec jako split_booking_moto_swap. Delivery poplatky
  -- slevě nepodléhají (parita se vznikem rezervace).
  IF COALESCE(v_b.booking_source, 'web') = 'app' AND v_dates_diff > 0 THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(v_b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND(v_dates_diff * v_loy_pct / 100.0);
  END IF;

  v_gross_diff := v_dates_diff - v_loy_disc + v_moto_diff + v_pickup_fee_diff + v_return_fee_diff;

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
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'breakdown', jsonb_build_object(
        'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
        'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
        'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
        'late_pickup_from', v_old_late, 'late_pickup_to', v_new_late,
        'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct
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
    'loyalty_surcharge_discount', v_loy_disc, 'loyalty_percent', v_loy_pct,
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
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level       = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent     = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || v_history_entry
  WHERE id = p_booking_id;

  -- Dispatch VŽDY když je co vracet — process-refund si PI dohledá ze
  -- stripe_session_id, a bez Stripe platby vystaví dobropis + 'refund_pending'.
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
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
    'breakdown', jsonb_build_object(
      'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
      'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
      'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
      'late_pickup_from', v_old_late, 'late_pickup_to', v_new_late,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct
    )
  );
END;
$$;


ALTER FUNCTION "public"."_apply_booking_changes_core"("p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_apply_discount_variant_b"("p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_dtype" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  v_old_total numeric := COALESCE(p_old_total,0);
  v_old_disc  numeric := GREATEST(COALESCE(p_old_discount,0),0);
  v_old_gross numeric := COALESCE(p_old_total,0) + GREATEST(COALESCE(p_old_discount,0),0);
  v_new_gross numeric; v_new_disc numeric; v_new_total numeric;
BEGIN
  v_new_gross := GREATEST(0, v_old_gross + COALESCE(p_gross_diff,0));
  IF COALESCE(p_gross_diff,0) >= 0 THEN
    v_new_disc := v_old_disc;                                    -- DOPLATEK: plná cena
  ELSIF v_old_gross > 0 THEN
    v_new_disc := ROUND(v_new_gross * v_old_disc / v_old_gross); -- VRATKA: poměr zaplaceného
  ELSE
    v_new_disc := 0;
  END IF;
  v_new_total := GREATEST(0, v_new_gross - v_new_disc);
  RETURN jsonb_build_object('new_gross',v_new_gross,'new_discount',v_new_disc,
    'new_total',v_new_total,'net_diff',v_new_total - v_old_total);
END; $$;


ALTER FUNCTION "public"."_apply_discount_variant_b"("p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_dtype" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_booking_discount_type"("p_promo_code_id" "uuid", "p_promo_code" "text", "p_discount_code" "text", "p_voucher_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_type text;
BEGIN
  IF p_voucher_id IS NOT NULL THEN
    RETURN 'fixed';
  END IF;
  IF p_promo_code_id IS NOT NULL THEN
    SELECT type INTO v_type FROM promo_codes WHERE id = p_promo_code_id;
    IF v_type IS NOT NULL THEN RETURN v_type; END IF;
  END IF;
  IF COALESCE(p_promo_code, p_discount_code) IS NOT NULL THEN
    SELECT type INTO v_type FROM promo_codes
     WHERE upper(code) = upper(COALESCE(p_promo_code, p_discount_code))
     LIMIT 1;
    IF v_type IS NOT NULL THEN RETURN v_type; END IF;
  END IF;
  RETURN 'fixed';
END;
$$;


ALTER FUNCTION "public"."_booking_discount_type"("p_promo_code_id" "uuid", "p_promo_code" "text", "p_discount_code" "text", "p_voucher_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_calc_stacked_discount"("p_gross" numeric, "p_discounts" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  d jsonb; v_pct_count int := 0; v_pct_rate numeric := 0;
  v_pct_amt numeric := 0; v_fixed_sum numeric := 0; v_fixed_amt numeric := 0;
BEGIN
  IF p_discounts IS NULL THEN
    RETURN jsonb_build_object('percent_rate',0,'percent_amount',0,'fixed_amount',0,'total',0);
  END IF;
  FOR d IN SELECT * FROM jsonb_array_elements(p_discounts) LOOP
    IF (d->>'discount_type') = 'percent' THEN
      v_pct_count := v_pct_count + 1;
      IF v_pct_count > 1 THEN RAISE EXCEPTION 'Lze uplatnit nejvýše jednu procentní slevu'; END IF;
      v_pct_rate := COALESCE((d->>'value')::numeric, 0);
    ELSE
      v_fixed_sum := v_fixed_sum + COALESCE((d->>'value')::numeric, 0);
    END IF;
  END LOOP;
  v_pct_amt   := ROUND(p_gross * v_pct_rate / 100);
  v_fixed_amt := LEAST(v_fixed_sum, GREATEST(0, p_gross - v_pct_amt));
  RETURN jsonb_build_object(
    'percent_rate', v_pct_rate, 'percent_amount', v_pct_amt,
    'fixed_amount', v_fixed_amt, 'total', v_pct_amt + v_fixed_amt);
END;
$$;


ALTER FUNCTION "public"."_calc_stacked_discount"("p_gross" numeric, "p_discounts" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_cap_refund_to_paid"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_paid     numeric;
  v_refunded numeric;
  v_cap      numeric;
BEGIN
  IF NEW.type = 'credit_note' AND NEW.booking_id IS NOT NULL THEN
    SELECT COALESCE(SUM(total), 0) INTO v_paid
      FROM invoices
     WHERE booking_id = NEW.booking_id AND type = 'payment_receipt' AND status <> 'cancelled';
    SELECT COALESCE(SUM(ABS(total)), 0) INTO v_refunded
      FROM invoices
     WHERE booking_id = NEW.booking_id AND type = 'credit_note' AND status <> 'cancelled'
       AND id IS DISTINCT FROM NEW.id;
    IF v_paid > 0 THEN
      v_cap := GREATEST(0, v_paid - v_refunded);
      IF ABS(NEW.total) > v_cap THEN
        BEGIN
          INSERT INTO debug_log(source, action, status, error_message, request_data)
          VALUES ('_cap_refund_to_paid','credit_note_capped','warning',
                  'Dobropis ořezán na zbývající zaplacenou částku',
                  jsonb_build_object('booking_id',NEW.booking_id,'requested',NEW.total,
                                     'paid_dp_sum',v_paid,'already_refunded',v_refunded,'cap',v_cap));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        NEW.total := -v_cap;
        NEW.subtotal := -v_cap;
      END IF;
    ELSE
      BEGIN
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('_cap_refund_to_paid','no_dp_rows_skip_cap','warning',
                'Booking nemá žádné DP — dobropis se neořezává (Stripe clamp drží finance)',
                jsonb_build_object('booking_id',NEW.booking_id,'requested',NEW.total));
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."_cap_refund_to_paid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_create_gear_po"("p_shortage_id" "uuid", "p_qty" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_sh record; v_inv record; v_qty int; v_order uuid; v_num text;
begin
  select * into v_sh from gear_shortages where id=p_shortage_id;
  if not found then return jsonb_build_object('success',false,'error','not_found'); end if;
  v_qty := coalesce(p_qty, v_sh.deficit_qty);
  if v_qty <= 0 then return jsonb_build_object('success',false,'error','no_deficit'); end if;
  select * into v_inv from inventory where sku='prislusenstvi-'||v_sh.accessory_type||'-'||v_sh.size limit 1;
  if not found then return jsonb_build_object('success',false,'error','no_inventory_item',
    'sku','prislusenstvi-'||v_sh.accessory_type||'-'||v_sh.size); end if;
  if v_inv.supplier_id is null then return jsonb_build_object('success',false,'error','no_supplier',
    'inventory_item_id',v_inv.id); end if;

  v_num := 'PO-'||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||substr(md5(random()::text),1,4);
  insert into purchase_orders(supplier_id, order_number, status, total_amount, notes)
    values(v_inv.supplier_id, v_num, 'draft', v_qty*coalesce(v_inv.unit_price,0),
      'Auto z deficitu výbavy: '||v_sh.accessory_type||' '||v_sh.size) returning id into v_order;
  insert into purchase_order_items(order_id, item_id, quantity, unit_price)
    values(v_order, v_inv.id, v_qty, coalesce(v_inv.unit_price,0));
  update gear_shortages set status='order_created', purchase_order_id=v_order, updated_at=now() where id=p_shortage_id;
  return jsonb_build_object('success',true,'order_id',v_order,'order_number',v_num);
end $$;


ALTER FUNCTION "public"."_create_gear_po"("p_shortage_id" "uuid", "p_qty" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_gate_obsluzna_activation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_obsluzna boolean;
BEGIN
  -- Reaguj jen na přechod DO active z jiného stavu.
  IF NEW.status <> 'active' OR OLD.status = 'active' THEN
    RETURN NEW;
  END IF;

  -- Předávací protokol vyplněn (podpis / uložení / potvrzení tištěného) → pusť.
  -- Nastavuje ho Velín (markPickedUp / tištěný protokol) i auto-complete promote.
  IF NEW.handover_protocol_filled_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Je rezervace na obslužné pobočce?
  SELECT COALESCE(br.type = 'obslužná', false) INTO v_obsluzna
  FROM motorcycles m
  JOIN branches br ON br.id = m.branch_id
  WHERE m.id = NEW.moto_id;

  IF COALESCE(v_obsluzna, false) THEN
    -- Aktivace až předáním protokolu — držíme reserved a nedáváme picked_up_at.
    NEW.status := 'reserved';
    NEW.picked_up_at := OLD.picked_up_at;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."_gate_obsluzna_activation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_is_self_service_booking"("p_booking_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(br.type = 'samoobslužná', false)
  FROM bookings b
  JOIN motorcycles m ON m.id = b.moto_id
  JOIN branches br   ON br.id = m.branch_id
  WHERE b.id = p_booking_id
$$;


ALTER FUNCTION "public"."_is_self_service_booking"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_late_pickup_discount"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_pickup_time" time without time zone) RETURNS numeric
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_moto motorcycles%ROWTYPE; v_days int; v_dow int; v_first_price numeric;
BEGIN
  IF p_moto_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_pickup_time IS NULL THEN RETURN 0; END IF;
  IF p_pickup_time < TIME '12:00' THEN RETURN 0; END IF;
  v_days := (p_end::date - p_start::date) + 1;
  IF v_days < 2 THEN RETURN 0; END IF;
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF NOT FOUND THEN RETURN 0; END IF;
  v_dow := EXTRACT(ISODOW FROM p_start::date)::int;
  v_first_price := CASE v_dow
    WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
    WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
    WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
    WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
    WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
    WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekend, v_moto.price_weekday, 0)
    WHEN 7 THEN COALESCE(v_moto.price_sun, v_moto.price_weekend, v_moto.price_weekday, 0)
  END;
  RETURN ROUND(COALESCE(v_first_price, 0) * 0.5);
END;
$$;


ALTER FUNCTION "public"."_late_pickup_discount"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_pickup_time" time without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_license_moto_rank"("p_g" "public"."license_group") RETURNS integer
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT CASE p_g
    WHEN 'A'  THEN 4
    WHEN 'A2' THEN 3
    WHEN 'A1' THEN 2
    WHEN 'AM' THEN 1
    ELSE 0
  END;
$$;


ALTER FUNCTION "public"."_license_moto_rank"("p_g" "public"."license_group") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_loyalty_effective_count"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT _loyalty_qualifying_count(p_user_id)
       + COALESCE((SELECT loyalty_bonus_points FROM profiles WHERE id = p_user_id), 0);
$$;


ALTER FUNCTION "public"."_loyalty_effective_count"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_loyalty_qualifying_count"("p_user_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(SUM(
    CASE WHEN (end_date::date - start_date::date + 1) > 7 THEN 4 ELSE 1 END
  ), 0)::int
  FROM bookings
  WHERE user_id = p_user_id
    AND status = 'completed'
    AND COALESCE(is_test, false) = false;
$$;


ALTER FUNCTION "public"."_loyalty_qualifying_count"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_moto_dayprice_sum"("p_moto_id" "uuid", "p_start" "date", "p_end" "date") RETURNS numeric
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."_moto_dayprice_sum"("p_moto_id" "uuid", "p_start" "date", "p_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_norm_supplier"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select lower(translate(coalesce(p, ''),
    'áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ',
    'acdeeinorstuuyzACDEEINORSTUUYZ'))
$$;


ALTER FUNCTION "public"."_norm_supplier"("p" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_reallocate_booking_discounts"("p_booking_id" "uuid", "p_target" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_sum numeric; v_target numeric := GREATEST(0, COALESCE(p_target,0));
  r record; v_acc numeric := 0; v_first uuid; v_amt numeric;
BEGIN
  SELECT SUM(amount) INTO v_sum FROM booking_discounts WHERE booking_id = p_booking_id;
  IF v_sum IS NULL OR v_sum <= 0 THEN RETURN; END IF;
  FOR r IN SELECT id, amount FROM booking_discounts WHERE booking_id = p_booking_id ORDER BY created_at, id LOOP
    v_amt := ROUND(r.amount * v_target / v_sum);
    UPDATE booking_discounts SET amount = v_amt WHERE id = r.id;
    v_acc := v_acc + v_amt; IF v_first IS NULL THEN v_first := r.id; END IF;
  END LOOP;
  IF v_first IS NOT NULL AND v_acc <> v_target THEN
    UPDATE booking_discounts SET amount = amount + (v_target - v_acc) WHERE id = v_first;
  END IF;
END; $$;


ALTER FUNCTION "public"."_reallocate_booking_discounts"("p_booking_id" "uuid", "p_target" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_recalc_booking_discount"("p_booking_id" "uuid", "p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_apply" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN RETURN public._apply_discount_variant_b(p_old_total, p_old_discount, p_gross_diff, NULL); END; $$;


ALTER FUNCTION "public"."_recalc_booking_discount"("p_booking_id" "uuid", "p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_apply" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_customer"("p_full_name" "text", "p_email" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_street" "text" DEFAULT NULL::"text", "p_city" "text" DEFAULT NULL::"text", "p_zip" "text" DEFAULT NULL::"text", "p_country" "text" DEFAULT 'CZ'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id uuid;
  v_email   text;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  IF p_full_name IS NULL OR trim(p_full_name) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_name');
  END IF;

  v_email := NULLIF(lower(trim(COALESCE(p_email, ''))), '');

  -- Zákazník s tímto emailem už existuje → nevytvářet duplicitní účet
  IF v_email IS NOT NULL THEN
    SELECT u.id INTO v_user_id FROM auth.users u
    WHERE lower(u.email) = v_email
    LIMIT 1;
    IF v_user_id IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'email_exists',
                                'user_id', v_user_id);
    END IF;
  END IF;

  v_user_id := gen_random_uuid();

  -- Stejný vzor jako create_web_booking: reálný auth účet s náhodným heslem.
  -- Email potvrzený → zákazník si později může heslo nastavit přes recovery.
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password,
    email_confirmed_at, aud, role,
    raw_user_meta_data, created_at, updated_at
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    v_email,
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    CASE WHEN v_email IS NOT NULL THEN now() ELSE NULL END,
    'authenticated', 'authenticated',
    jsonb_build_object('full_name', trim(p_full_name), 'phone', NULLIF(trim(COALESCE(p_phone,'')), '')),
    now(), now()
  );

  -- handle_new_user() trigger už mohl profil založit → upsert dat z formuláře
  INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source)
  VALUES (
    v_user_id,
    trim(p_full_name),
    v_email,
    NULLIF(trim(COALESCE(p_phone,   '')), ''),
    NULLIF(trim(COALESCE(p_street,  '')), ''),
    NULLIF(trim(COALESCE(p_city,    '')), ''),
    NULLIF(trim(COALESCE(p_zip,     '')), ''),
    COALESCE(NULLIF(trim(COALESCE(p_country, '')), ''), 'CZ'),
    'velin'
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email     = COALESCE(EXCLUDED.email, profiles.email),
    phone     = COALESCE(EXCLUDED.phone, profiles.phone),
    street    = COALESCE(EXCLUDED.street, profiles.street),
    city      = COALESCE(EXCLUDED.city, profiles.city),
    zip       = COALESCE(EXCLUDED.zip, profiles.zip),
    country   = EXCLUDED.country,
    -- 'auth_trigger' = technický placeholder živého handle_new_user (viz 20260728) → přepsat
    registration_source = CASE WHEN profiles.registration_source IS NULL
                                 OR profiles.registration_source = 'auth_trigger'
                          THEN 'velin' ELSE profiles.registration_source END,
    updated_at = now();

  -- Audit správnými sloupci (admin_audit_log NEMÁ sloupec `details`)
  BEGIN
    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, new_data)
    VALUES (auth.uid(), 'customer_created', 'profiles', v_user_id,
            jsonb_build_object('full_name', trim(p_full_name), 'email', v_email));
  EXCEPTION WHEN OTHERS THEN
    NULL; -- audit nesmí shodit vytvoření zákazníka
  END;

  RETURN jsonb_build_object('success', true, 'user_id', v_user_id);
END;
$$;


ALTER FUNCTION "public"."admin_create_customer"("p_full_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_booking_readiness"("p_ref" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_raw    text := trim(coalesce(p_ref, ''));
  v_uuid   uuid;
  v_id     uuid;
  v_short  text;
  v_cnt    int;
  v_user   uuid;
  v_end    date;
  v_moto   uuid;
  v_status text;
  v_pay    text;
  v_src    text;
  v_docs_reason text;
  v_codes_active boolean;
  v_codes_sent   boolean;
  v_withheld     text;
BEGIN
  IF length(v_raw) < 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  BEGIN
    v_uuid := (regexp_match(v_raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'))[1]::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_uuid := NULL;
  END;

  IF v_uuid IS NOT NULL THEN
    v_id := v_uuid;
  ELSE
    v_short := upper(regexp_replace(v_raw, '[^0-9a-fA-F]', '', 'g'));
    IF length(v_short) < 8 THEN
      RETURN jsonb_build_object('success', false, 'error', 'bad_ref');
    END IF;
    v_short := right(v_short, 8);
    SELECT count(*) INTO v_cnt FROM bookings b
      WHERE upper(right(replace(b.id::text, '-', ''), 8)) = v_short;
    IF v_cnt > 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'ambiguous');
    END IF;
    SELECT b.id INTO v_id FROM bookings b
      WHERE upper(right(replace(b.id::text, '-', ''), 8)) = v_short LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  SELECT b.user_id, b.end_date::date, b.moto_id, b.status::text, b.payment_status::text, b.booking_source
  INTO v_user, v_end, v_moto, v_status, v_pay, v_src
  FROM bookings b WHERE b.id = v_id;

  IF v_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- doklady: NULL = OK, jinak konkrétní důvod (chybí OP/ŘP/propadlý…)
  v_docs_reason := check_booking_docs_status(v_user, v_end, v_moto);

  -- přístupové kódy (NIKDY nevracíme samotný kód, jen stav)
  SELECT EXISTS (SELECT 1 FROM branch_door_codes d WHERE d.booking_id = v_id AND d.is_active = true),
         EXISTS (SELECT 1 FROM branch_door_codes d WHERE d.booking_id = v_id AND d.sent_to_customer = true)
  INTO v_codes_active, v_codes_sent;

  SELECT d.withheld_reason INTO v_withheld
  FROM branch_door_codes d
  WHERE d.booking_id = v_id AND d.withheld_reason IS NOT NULL
  LIMIT 1;

  RETURN jsonb_build_object(
    'success',               true,
    'booking_number',        upper(right(v_id::text, 8)),
    'status',                v_status,
    'payment_status',        v_pay,
    'booking_source',        v_src,
    'docs_ok',               (v_docs_reason IS NULL),
    'docs_missing_reason',   v_docs_reason,                       -- NULL když OK
    'codes_issued',          (v_codes_active AND v_codes_sent),
    'codes_active',          v_codes_active,
    'codes_sent',            v_codes_sent,
    'codes_withheld_reason', v_withheld                           -- typicky „Chybí doklady…"
  );
END;
$$;


ALTER FUNCTION "public"."ai_booking_readiness"("p_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_get_booking_emails"("p_ref" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_raw    text := trim(coalesce(p_ref, ''));
  v_uuid   uuid;
  v_id     uuid;
  v_short  text;
  v_cnt    int;
  v_status text;
  v_pay    text;
  v_emails jsonb;
BEGIN
  IF length(v_raw) < 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  -- plné UUID kdekoli ve vstupu (klidně celý ?id=… odkaz)
  BEGIN
    v_uuid := (regexp_match(v_raw, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'))[1]::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_uuid := NULL;
  END;

  IF v_uuid IS NOT NULL THEN
    v_id := v_uuid;
  ELSE
    v_short := upper(regexp_replace(v_raw, '[^0-9a-fA-F]', '', 'g'));
    IF length(v_short) < 8 THEN
      RETURN jsonb_build_object('success', false, 'error', 'bad_ref');
    END IF;
    v_short := right(v_short, 8);

    SELECT count(*) INTO v_cnt
    FROM bookings b
    WHERE upper(right(replace(b.id::text, '-', ''), 8)) = v_short;

    IF v_cnt > 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'ambiguous');
    END IF;

    SELECT b.id INTO v_id
    FROM bookings b
    WHERE upper(right(replace(b.id::text, '-', ''), 8)) = v_short
    LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  SELECT b.status::text, b.payment_status::text
  INTO v_status, v_pay
  FROM bookings b
  WHERE b.id = v_id;

  IF v_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'template_slug', se.template_slug,
           'subject',       se.subject,
           'status',        se.status,
           'sent_at',       se.created_at
         ) ORDER BY se.created_at DESC), '[]'::jsonb)
  INTO v_emails
  FROM sent_emails se
  WHERE se.booking_id = v_id;

  RETURN jsonb_build_object(
    'success',        true,
    'booking_number', upper(right(v_id::text, 8)),
    'status',         v_status,
    'payment_status', v_pay,
    'email_count',    jsonb_array_length(v_emails),
    'emails',         v_emails
  );
END;
$$;


ALTER FUNCTION "public"."ai_get_booking_emails"("p_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_get_order_status"("p_contact" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_raw     text := trim(coalesce(p_contact, ''));
  v_is_email boolean;
  v_orders  jsonb;
  v_vouchers jsonb;
BEGIN
  IF length(v_raw) < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;
  v_is_email := position('@' in v_raw) > 0;

  -- e-shop objednávky: dle e-mailu NEBO čísla objednávky (PII-minimal)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'order_number',    o.order_number,
           'status',          o.status,
           'payment_status',  o.payment_status,
           'total',           o.total,
           'tracking_number', o.tracking_number,
           'created_at',      o.created_at
         ) ORDER BY o.created_at DESC), '[]'::jsonb)
  INTO v_orders
  FROM shop_orders o
  WHERE (v_is_email AND lower(o.customer_email) = lower(v_raw))
     OR (NOT v_is_email AND upper(o.order_number) = upper(v_raw));

  -- poukazy: dle e-mailu kupujícího, čísla objednávky, nebo zadaného kódu
  -- (kód NIKDY nevracíme celý — jen maskovaný)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'code_masked',  left(v.code, 2) || '****',
           'status',       v.status,
           'amount',       v.amount,
           'valid_until',  v.valid_until,
           'source',       v.source
         ) ORDER BY v.valid_until DESC NULLS LAST), '[]'::jsonb)
  INTO v_vouchers
  FROM vouchers v
  WHERE (v_is_email AND lower(v.buyer_email) = lower(v_raw))
     OR (NOT v_is_email AND (
           upper(v.code) = upper(v_raw)
           OR v.order_id IN (SELECT o.id FROM shop_orders o WHERE upper(o.order_number) = upper(v_raw))
        ));

  RETURN jsonb_build_object(
    'success',  true,
    'matched_by', CASE WHEN v_is_email THEN 'email' ELSE 'order_or_code' END,
    'orders',   v_orders,
    'vouchers', v_vouchers
  );
END;
$$;


ALTER FUNCTION "public"."ai_get_order_status"("p_contact" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ai_lookup_bookings_by_contact"("p_contact" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_raw     text := trim(coalesce(p_contact, ''));
  v_is_email boolean;
  v_digits  text;
  v_rows    jsonb;
BEGIN
  IF length(v_raw) < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  v_is_email := position('@' in v_raw) > 0;
  v_digits   := regexp_replace(v_raw, '\D', '', 'g');

  IF NOT v_is_email AND length(v_digits) < 9 THEN
    RETURN jsonb_build_object('success', false, 'error', 'bad_contact');
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      upper(right(b.id::text, 8))                          AS booking_number,
      b.id::text                                           AS booking_id,
      b.status::text                                       AS status,
      b.payment_status::text                               AS payment_status,
      b.booking_source                                     AS booking_source,
      b.start_date                                         AS start_date,
      b.end_date                                           AS end_date,
      b.total_price                                        AS total_price,
      b.pickup_method                                      AS pickup_method,
      b.created_at                                         AS created_at,
      b.confirmed_at                                       AS confirmed_at,
      (b.abandoned_email_sent_at IS NOT NULL)              AS abandoned_email_sent,
      (b.reserved_email_sent_at IS NOT NULL)               AS reserved_email_sent,
      coalesce(
        nullif(trim(coalesce(m.brand, '') || ' ' || coalesce(m.model, '')), ''),
        'Motorka'
      )                                                    AS moto_name,
      (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
                 'template_slug', se.template_slug,
                 'subject',       se.subject,
                 'status',        se.status,
                 'sent_at',       se.created_at
               ) ORDER BY se.created_at DESC), '[]'::jsonb)
        FROM sent_emails se
        WHERE se.booking_id = b.id
      )                                                    AS emails
    FROM bookings b
    JOIN profiles p        ON p.id = b.user_id
    LEFT JOIN motorcycles m ON m.id = b.moto_id
    WHERE coalesce(b.is_test, false) = false
      AND (
        CASE WHEN v_is_email
          THEN lower(p.email) = lower(v_raw)
          ELSE p.phone IS NOT NULL
               AND length(regexp_replace(p.phone, '\D', '', 'g')) >= 9
               AND right(regexp_replace(p.phone, '\D', '', 'g'), 9) = right(v_digits, 9)
        END
      )
    ORDER BY b.created_at DESC
    LIMIT 15
  ) t;

  RETURN jsonb_build_object(
    'success',    true,
    'count',      jsonb_array_length(v_rows),
    'matched_by', CASE WHEN v_is_email THEN 'email' ELSE 'phone' END,
    'bookings',   v_rows
  );
END;
$$;


ALTER FUNCTION "public"."ai_lookup_bookings_by_contact"("p_contact" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analytics_customer_km"() RETURNS TABLE("user_id" "uuid", "total_km" bigint, "rentals_with_km" bigint, "km_per_rental" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  SELECT user_id,
         COALESCE(SUM(km_driven),0)::bigint AS total_km,
         COUNT(*) FILTER (WHERE km_driven > 0)::bigint AS rentals_with_km,
         ROUND(AVG(NULLIF(km_driven,0)), 0) AS km_per_rental
    FROM analytics_moto_rental_km()
   WHERE next_reading IS NOT NULL AND user_id IS NOT NULL
   GROUP BY user_id;
$$;


ALTER FUNCTION "public"."analytics_customer_km"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analytics_moto_km"() RETURNS TABLE("moto_id" "uuid", "model" "text", "spz" "text", "tracking_unit" "text", "current_km" integer, "purchase_km" integer, "total_driven" integer, "rentals_with_km" bigint, "km_per_rental" numeric, "avg_km_per_calendar_day" numeric, "avg_km_per_rental_day" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  WITH rk AS (
    SELECT moto_id,
           COALESCE(SUM(km_driven),0) AS km_from_rentals,
           COUNT(*) FILTER (WHERE km_driven > 0) AS rentals_with_km
      FROM analytics_moto_rental_km()
     WHERE next_reading IS NOT NULL
     GROUP BY moto_id
  ),
  rdays AS (
    SELECT b.moto_id,
           SUM(GREATEST((b.end_date::date - b.start_date::date) + 1, 1)) AS rental_days
      FROM bookings b
     WHERE b.mileage_start IS NOT NULL AND b.mileage_start > 0
       AND COALESCE(b.is_test,false) = false
     GROUP BY b.moto_id
  )
  SELECT m.id, m.model, m.spz, COALESCE(m.tracking_unit,'km'),
         COALESCE(m.mileage,0), COALESCE(m.purchase_mileage,0),
         GREATEST(COALESCE(m.mileage,0) - COALESCE(m.purchase_mileage,0), 0) AS total_driven,
         COALESCE(rk.rentals_with_km,0),
         CASE WHEN COALESCE(rk.rentals_with_km,0) > 0
              THEN ROUND(rk.km_from_rentals::numeric / rk.rentals_with_km, 0) END,
         CASE WHEN m.acquired_at IS NOT NULL
               AND (CURRENT_DATE - m.acquired_at::date) > 0
              THEN ROUND(GREATEST(COALESCE(m.mileage,0)-COALESCE(m.purchase_mileage,0),0)::numeric
                         / (CURRENT_DATE - m.acquired_at::date), 1) END,
         CASE WHEN COALESCE(rd.rental_days,0) > 0
              THEN ROUND(COALESCE(rk.km_from_rentals,0)::numeric / rd.rental_days, 1) END
    FROM motorcycles m
    LEFT JOIN rk    ON rk.moto_id = m.id
    LEFT JOIN rdays rd ON rd.moto_id = m.id;
$$;


ALTER FUNCTION "public"."analytics_moto_km"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analytics_moto_rental_km"() RETURNS TABLE("moto_id" "uuid", "booking_id" "uuid", "user_id" "uuid", "start_date" timestamp with time zone, "reading" integer, "next_reading" integer, "km_driven" integer)
    LANGUAGE "sql" STABLE
    AS $$
  WITH readings AS (
    SELECT b.moto_id, b.id AS booking_id, b.user_id, b.start_date,
           b.mileage_start::int AS reading,
           LEAD(b.mileage_start::int) OVER (PARTITION BY b.moto_id ORDER BY b.start_date) AS next_reading
      FROM bookings b
     WHERE b.mileage_start IS NOT NULL AND b.mileage_start > 0
       AND COALESCE(b.is_test, false) = false
  )
  SELECT moto_id, booking_id, user_id, start_date, reading, next_reading,
         GREATEST(COALESCE(next_reading,0) - reading, 0) AS km_driven
    FROM readings;
$$;


ALTER FUNCTION "public"."analytics_moto_rental_km"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analytics_service_plan"("p_default_daily_km" numeric DEFAULT 50) RETURNS TABLE("moto_id" "uuid", "model" "text", "spz" "text", "tracking_unit" "text", "service_type" "text", "label" "text", "interval_km" integer, "interval_days" integer, "current_km" integer, "last_service_km" integer, "km_since_last" integer, "km_remaining" integer, "due_soon" boolean, "overdue" boolean, "avg_daily_km" numeric, "estimated_due_date" "date")
    LANGUAGE "sql" STABLE
    AS $$
  WITH avg_km AS (
    SELECT a.moto_id, a.avg_km_per_calendar_day AS daily FROM analytics_moto_km() a
  ),
  moto_types AS (
    SELECT m.id AS moto_id, m.model, m.spz, COALESCE(m.tracking_unit,'km') AS unit,
           COALESCE(m.mileage,0) AS cur, t.stype, t.lbl, t.ikm, t.idays
      FROM motorcycles m
      CROSS JOIN LATERAL (VALUES
        ('oil_change','Výměna oleje',          m.oil_interval_km,          m.oil_interval_days),
        ('tire_change','Výměna pneumatik',     m.tire_interval_km,         NULL::int),
        ('full_service','Kompletní servis',    m.full_service_interval_km, m.full_service_interval_days)
      ) AS t(stype, lbl, ikm, idays)
     WHERE t.ikm IS NOT NULL AND t.ikm > 0
  ),
  last_km AS (
    SELECT s.moto_id, s.schedule_type AS stype, MAX(s.last_service_km) AS lkm
      FROM maintenance_schedules s
     WHERE s.active = true
     GROUP BY s.moto_id, s.schedule_type
  )
  SELECT mt.moto_id, mt.model, mt.spz, mt.unit,
         mt.stype, mt.lbl, mt.ikm, mt.idays, mt.cur,
         COALESCE(lk.lkm,0),
         GREATEST(mt.cur - COALESCE(lk.lkm,0), 0) AS km_since_last,
         (COALESCE(lk.lkm,0) + mt.ikm) - mt.cur   AS km_remaining,
         ((COALESCE(lk.lkm,0) + mt.ikm) - mt.cur) <= (mt.ikm * 0.20) AS due_soon,
         ((COALESCE(lk.lkm,0) + mt.ikm) - mt.cur) <= 0               AS overdue,
         COALESCE(av.daily, p_default_daily_km) AS avg_daily_km,
         CASE
           WHEN ((COALESCE(lk.lkm,0) + mt.ikm) - mt.cur) <= 0 THEN CURRENT_DATE
           WHEN COALESCE(av.daily, p_default_daily_km) > 0
             THEN CURRENT_DATE + (CEIL(((COALESCE(lk.lkm,0)+mt.ikm) - mt.cur)
                                       / COALESCE(av.daily, p_default_daily_km)))::int
         END AS estimated_due_date
    FROM moto_types mt
    LEFT JOIN last_km lk ON lk.moto_id = mt.moto_id AND lk.stype = mt.stype
    LEFT JOIN avg_km av  ON av.moto_id = mt.moto_id;
$$;


ALTER FUNCTION "public"."analytics_service_plan"("p_default_daily_km" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_installations_touch"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin new.updated_at := now(); return new; end $$;


ALTER FUNCTION "public"."app_installations_touch"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_save_full_profile"("p_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_groups license_group[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- skupina ŘP: JSON pole stringů → license_group[] (jen platné hodnoty)
  IF p_data ? 'license_group' AND jsonb_typeof(p_data->'license_group') = 'array' THEN
    SELECT array_agg(DISTINCT upper(g)::license_group)
      INTO v_groups
      FROM jsonb_array_elements_text(p_data->'license_group') AS g
     WHERE upper(g) IN ('AM','A1','A2','A','B','N');
  END IF;

  -- pojistka: pokud řádek ještě neexistuje (trigger ho obvykle vytvoří), dotvoř
  INSERT INTO public.profiles (id, email)
  SELECT v_uid, u.email FROM auth.users u WHERE u.id = v_uid
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.profiles SET
    full_name      = COALESCE(NULLIF(p_data->>'full_name',''), full_name),
    phone          = COALESCE(NULLIF(p_data->>'phone',''), phone),
    date_of_birth  = COALESCE(NULLIF(p_data->>'date_of_birth','')::date, date_of_birth),
    street         = COALESCE(NULLIF(p_data->>'street',''), street),
    city           = COALESCE(NULLIF(p_data->>'city',''), city),
    zip            = COALESCE(NULLIF(p_data->>'zip',''), zip),
    country        = COALESCE(NULLIF(p_data->>'country',''), country),
    id_number      = COALESCE(NULLIF(p_data->>'id_number',''), id_number),
    license_number = COALESCE(NULLIF(p_data->>'license_number',''), license_number),
    license_expiry = COALESCE(NULLIF(p_data->>'license_expiry','')::date, license_expiry),
    license_group  = COALESCE(v_groups, license_group),
    language       = COALESCE(NULLIF(p_data->>'language',''), language),
    registration_source = COALESCE(registration_source, 'app'),
    -- Povinné souhlasy (gaceované v UI registrace) — respektuj poslanou hodnotu, fallback true
    consent_vop             = COALESCE((p_data->>'consent_vop')::boolean, true),
    consent_gdpr            = COALESCE((p_data->>'consent_gdpr')::boolean, true),
    consent_data_processing = COALESCE((p_data->>'consent_data_processing')::boolean, true),
    -- Transakční / servisní kanály beze změny (transakční komunikace jde vždy)
    consent_email = true, consent_sms = true, consent_push = true,
    consent_whatsapp = true, consent_photo = true, consent_contract = true,
    -- Marketing = OPT-IN: RPC ho už nezapíná; respektuje jen explicitní volbu z appky
    marketing_consent = COALESCE((p_data->>'marketing_consent')::boolean, false),
    updated_at = now()
  WHERE id = v_uid;

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."app_save_full_profile"("p_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_booking_change_light"("p_booking_id" "uuid", "p_new_start" "date" DEFAULT NULL::"date", "p_new_end" "date" DEFAULT NULL::"date", "p_new_moto_id" "uuid" DEFAULT NULL::"uuid", "p_new_pickup_method" "text" DEFAULT NULL::"text", "p_new_pickup_address" "text" DEFAULT NULL::"text", "p_new_pickup_fee" numeric DEFAULT NULL::numeric, "p_new_return_method" "text" DEFAULT NULL::"text", "p_new_return_address" "text" DEFAULT NULL::"text", "p_new_return_fee" numeric DEFAULT NULL::numeric, "p_new_pickup_time" time without time zone DEFAULT NULL::time without time zone, "p_reason" "text" DEFAULT NULL::"text", "p_dry_run" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_mods_today int := 0;
  v_preview jsonb;
  v_zero boolean;
  v_net numeric;
BEGIN
  IF p_booking_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'missing_inputs'); END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF COALESCE(v_b.booking_source,'') <> 'web' THEN RETURN jsonb_build_object('success', false, 'error', 'not_web_booking'); END IF;
  IF v_b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
  IF v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success', false, 'error', 'not_paid'); END IF;

  SELECT count(*) INTO v_mods_today
  FROM jsonb_array_elements(COALESCE(v_b.modification_history,'[]'::jsonb)) e
  WHERE COALESCE(e->>'source','') = 'ai_agent' AND (e->>'at')::timestamptz::date = current_date;
  IF NOT p_dry_run AND v_mods_today >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'daily_limit_reached');
  END IF;

  -- VŽDY nejdřív dry-run přes jádro → dopad počítá server
  v_preview := public._apply_booking_changes_core(
    v_b.user_id, p_booking_id, p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, NULL, NULL, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, NULL, NULL, p_new_return_fee,
    COALESCE(p_reason,'light_preview'), true, 'ai_agent', p_new_pickup_time);

  IF COALESCE((v_preview->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_preview;  -- overlap / license_insufficient / no_change / active_* ...
  END IF;

  v_net := COALESCE((v_preview->>'net_diff')::numeric, 0);
  v_zero := (v_net = 0)
        AND COALESCE((v_preview->>'payment_required')::boolean, false) = false
        AND COALESCE((v_preview->>'refund_amount')::numeric, 0) = 0;

  IF p_dry_run THEN
    RETURN v_preview || jsonb_build_object('light', true, 'light_allowed', v_zero);
  END IF;

  IF NOT v_zero THEN
    RETURN jsonb_build_object('success', false, 'error', 'full_verification_required',
      'net_diff', v_net,
      'payment_required', COALESCE((v_preview->>'payment_required')::boolean, false),
      'refund_amount', COALESCE((v_preview->>'refund_amount')::numeric, 0));
  END IF;

  -- nulový dopad → reálně proveď
  RETURN public._apply_booking_changes_core(
    v_b.user_id, p_booking_id, p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, NULL, NULL, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, NULL, NULL, p_new_return_fee,
    COALESCE(p_reason,'light_edit'), false, 'ai_agent', p_new_pickup_time);
END; $$;


ALTER FUNCTION "public"."apply_booking_change_light"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_fee" numeric, "p_new_pickup_time" time without time zone, "p_reason" "text", "p_dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_booking_changes"("p_booking_id" "uuid", "p_new_start" "date" DEFAULT NULL::"date", "p_new_end" "date" DEFAULT NULL::"date", "p_new_moto_id" "uuid" DEFAULT NULL::"uuid", "p_new_pickup_method" "text" DEFAULT NULL::"text", "p_new_pickup_address" "text" DEFAULT NULL::"text", "p_new_pickup_lat" double precision DEFAULT NULL::double precision, "p_new_pickup_lng" double precision DEFAULT NULL::double precision, "p_new_pickup_fee" numeric DEFAULT NULL::numeric, "p_new_return_method" "text" DEFAULT NULL::"text", "p_new_return_address" "text" DEFAULT NULL::"text", "p_new_return_lat" double precision DEFAULT NULL::double precision, "p_new_return_lng" double precision DEFAULT NULL::double precision, "p_new_return_fee" numeric DEFAULT NULL::numeric, "p_reason" "text" DEFAULT NULL::"text", "p_dry_run" boolean DEFAULT false, "p_new_pickup_time" time without time zone DEFAULT NULL::time without time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;
  RETURN public._apply_booking_changes_core(
    v_user, p_booking_id, p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, p_new_pickup_lat, p_new_pickup_lng, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, p_new_return_lat, p_new_return_lng, p_new_return_fee,
    p_reason, p_dry_run, 'web_customer', p_new_pickup_time
  );
END;
$$;


ALTER FUNCTION "public"."apply_booking_changes"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_new_pickup_time" time without time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_booking_changes_anon"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text", "p_new_start" "date" DEFAULT NULL::"date", "p_new_end" "date" DEFAULT NULL::"date", "p_new_moto_id" "uuid" DEFAULT NULL::"uuid", "p_new_pickup_method" "text" DEFAULT NULL::"text", "p_new_pickup_address" "text" DEFAULT NULL::"text", "p_new_pickup_lat" double precision DEFAULT NULL::double precision, "p_new_pickup_lng" double precision DEFAULT NULL::double precision, "p_new_pickup_fee" numeric DEFAULT NULL::numeric, "p_new_return_method" "text" DEFAULT NULL::"text", "p_new_return_address" "text" DEFAULT NULL::"text", "p_new_return_lat" double precision DEFAULT NULL::double precision, "p_new_return_lng" double precision DEFAULT NULL::double precision, "p_new_return_fee" numeric DEFAULT NULL::numeric, "p_reason" "text" DEFAULT NULL::"text", "p_dry_run" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id uuid;
  v_email text;
  v_phone text;
  v_phone_norm text;
  v_contact_norm text;
  v_pwd_hash text;
  v_is_email boolean;
  v_match boolean := false;
  v_status text;
  v_payment_status text;
  v_source text;
  v_history jsonb;
  v_mods_today int;
BEGIN
  IF p_booking_id IS NULL OR length(coalesce(p_contact,'')) < 4 OR length(coalesce(p_password_last4,'')) <> 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  SELECT b.user_id, b.status, b.payment_status, b.booking_source, b.modification_history,
         p.email, p.phone, p.password_last4_bcrypt
    INTO v_user_id, v_status, v_payment_status, v_source, v_history, v_email, v_phone, v_pwd_hash
    FROM bookings b JOIN profiles p ON p.id = b.user_id
   WHERE b.id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  v_is_email := position('@' in p_contact) > 0;
  IF v_is_email THEN
    v_match := lower(trim(v_email)) = lower(trim(p_contact));
  ELSE
    v_phone_norm := regexp_replace(coalesce(v_phone,''), '[^0-9]', '', 'g');
    v_contact_norm := regexp_replace(p_contact, '[^0-9]', '', 'g');
    v_match := right(v_phone_norm, 9) = right(v_contact_norm, 9) AND length(v_contact_norm) >= 9;
  END IF;
  IF NOT v_match THEN
    RETURN jsonb_build_object('success', false, 'error', 'verification_failed');
  END IF;

  IF v_pwd_hash IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'password_check_unavailable',
      'hint', 'Heslo bylo nastaveno před zavedením této funkce. Doporuč zákazníkovi otevřít úpravu rezervace přes web po přihlášení.');
  END IF;
  IF crypt(p_password_last4, v_pwd_hash) <> v_pwd_hash THEN
    RETURN jsonb_build_object('success', false, 'error', 'verification_failed');
  END IF;

  IF v_source <> 'web' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_web_booking');
  END IF;
  IF v_status NOT IN ('reserved','active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status', 'status', v_status);
  END IF;
  IF v_payment_status <> 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  -- Limit: 3 reálné změny/den/rezervace přes AI (dry-run nezapočítáváme)
  IF NOT p_dry_run THEN
    SELECT count(*)::int INTO v_mods_today
      FROM jsonb_array_elements(coalesce(v_history,'[]'::jsonb)) e
     WHERE (e->>'source') = 'ai_agent'
       AND (e->>'at')::timestamptz::date = current_date;
    IF v_mods_today >= 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'daily_limit_reached',
        'message', 'Tato rezervace dnes dosáhla limitu 3 úprav přes asistenta. Další úprava až zítra, nebo se přihlas a uprav přes Moje rezervace.',
        'mods_today', v_mods_today);
    END IF;
  END IF;

  RETURN public._apply_booking_changes_core(
    v_user_id, p_booking_id,
    p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, p_new_pickup_lat, p_new_pickup_lng, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, p_new_return_lat, p_new_return_lng, p_new_return_fee,
    p_reason, p_dry_run, 'ai_agent'
  );
END;
$$;


ALTER FUNCTION "public"."apply_booking_changes_anon"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_paid_gear_change"("p_booking_id" "uuid", "p_sizes" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_user uuid; v_res jsonb;
BEGIN
  SELECT user_id INTO v_user FROM bookings WHERE id = p_booking_id;
  IF v_user IS NULL THEN RETURN jsonb_build_object('success',false,'error','not_found'); END IF;
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user::text)::text, true);
  SELECT update_booking_gear(p_booking_id, p_sizes, false) INTO v_res;
  RETURN v_res;
END $$;


ALTER FUNCTION "public"."apply_paid_gear_change"("p_booking_id" "uuid", "p_sizes" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_profile_license_group"("p_user_id" "uuid", "p_group" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF p_user_id IS NULL OR p_group IS NULL OR btrim(p_group) = '' THEN RETURN; END IF;
  UPDATE profiles
    SET license_group = public.merge_license_group_multi(license_group, p_group),
        updated_at = now()
  WHERE id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."apply_profile_license_group"("p_user_id" "uuid", "p_group" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_accounting_on_booking_paid"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  BEGIN
    IF NEW.payment_status = 'paid' AND (OLD IS NULL OR OLD.payment_status IS DISTINCT FROM 'paid') THEN
      INSERT INTO accounting_entries (booking_id, type, amount, description, category, date, created_at)
      VALUES (NEW.id, 'income', COALESCE(NEW.total_price, 0),
              'Platba za rezervaci #' || substr(NEW.id::text, 1, 8),
              'pronájem', CURRENT_DATE, now());
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'auto_accounting_on_booking_paid: % — accounting skipped', SQLERRM;
  END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_accounting_on_booking_paid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_activate_reserved_bookings"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE bookings b SET
    status = 'active',
    picked_up_at = COALESCE(b.picked_up_at, NOW())
  WHERE b.status = 'reserved'
    AND b.payment_status = 'paid'
    AND b.start_date::date <= CURRENT_DATE
    -- Obslužné pobočky se aktivují AŽ předávacím protokolem (viz strážce výše),
    -- nikoli půlnočním cronem.
    AND NOT EXISTS (
      SELECT 1 FROM motorcycles m
      JOIN branches br ON br.id = m.branch_id
      WHERE m.id = b.moto_id AND br.type = 'obslužná'
    );
END;
$$;


ALTER FUNCTION "public"."auto_activate_reserved_bookings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_cancel_expired_pending"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_row record;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  FOR v_row IN
    WITH cancelled AS (
      UPDATE bookings SET
        status               = 'cancelled',
        cancellation_reason  = CASE
          WHEN booking_source = 'app'
            THEN 'Automaticky zrušeno — nezaplaceno do 10 minut'
          ELSE  'Automaticky zrušeno — nezaplaceno do 4 hodin'
        END,
        cancelled_at         = now(),
        cancelled_by_source  = 'auto'
      WHERE status = 'pending'
        AND payment_status = 'unpaid'
        AND restored_at IS NULL  -- obnovené rezervace neruší cron, řeší je admin
        AND (
          (booking_source = 'app' AND created_at < now() - interval '10 minutes')
          OR (booking_source = 'web' AND created_at < now() - interval '4 hours')
        )
      RETURNING id, user_id, moto_id, start_date, end_date,
                booking_source, cancellation_reason
    )
    SELECT c.id, c.user_id, c.moto_id, c.start_date, c.end_date,
           c.booking_source, c.cancellation_reason,
           p.email AS customer_email, p.full_name AS customer_name,
           m.model AS motorcycle_model
      FROM cancelled c
      LEFT JOIN profiles p     ON p.id = c.user_id
      LEFT JOIN motorcycles m  ON m.id = c.moto_id
  LOOP
    -- Web rezervace už dostaly "Nedokončená rezervace" mail z
    -- send_abandoned_booking_emails() po 15 min — neposílej druhý "Storno" mail.
    IF v_row.booking_source = 'web' THEN
      CONTINUE;
    END IF;

    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;
    IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
      RAISE WARNING 'auto_cancel_expired_pending: app_settings missing — skipping mail for %', v_row.id;
      CONTINUE;
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-cancellation-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'booking_id',           v_row.id,
          'customer_email',       v_row.customer_email,
          'customer_name',        COALESCE(v_row.customer_name, ''),
          'motorcycle',           COALESCE(v_row.motorcycle_model, ''),
          'start_date',           v_row.start_date,
          'end_date',             v_row.end_date,
          'cancellation_reason',  v_row.cancellation_reason,
          'cancelled_by_source',  'auto',
          'refund_amount',        0,
          'refund_percent',       0,
          'source',               COALESCE(v_row.booking_source, 'app')
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_cancel_expired_pending: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."auto_cancel_expired_pending"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_check_service_parts"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  rec RECORD;
  part RECORD;
  sup RECORD;
  inv RECORD;
  order_id UUID;
  items_arr JSONB := '[]';
  created_orders INT := 0;
  v_daily_km NUMERIC;
  v_remaining INT;
  v_next_at INT;
  v_current_km INT;
  v_base_km INT;
  v_days_threshold INT := 30; -- calendar days
  v_already_ordered BOOLEAN;
BEGIN
  -- Loop through active schedules with parts
  FOR rec IN
    SELECT DISTINCT ms.id AS schedule_id, ms.moto_id, ms.interval_km, ms.first_service_km,
           ms.last_service_km, ms.description,
           m.mileage, m.purchase_mileage, m.year, m.model, m.spz
    FROM maintenance_schedules ms
    JOIN motorcycles m ON m.id = ms.moto_id
    WHERE ms.active = true
      AND ms.interval_km IS NOT NULL
      AND EXISTS (SELECT 1 FROM service_parts sp WHERE sp.schedule_id = ms.id)
  LOOP
    -- Calculate remaining km
    v_current_km := COALESCE(rec.mileage, 0);
    v_base_km := COALESCE(rec.purchase_mileage, 0);

    IF rec.last_service_km IS NOT NULL THEN
      v_next_at := rec.last_service_km + COALESCE(rec.interval_km, 0);
    ELSIF rec.first_service_km IS NOT NULL THEN
      v_next_at := v_base_km + rec.first_service_km;
    ELSE
      v_next_at := v_base_km + COALESCE(rec.interval_km, 0);
    END IF;

    v_remaining := v_next_at - v_current_km;

    -- Skip if overdue (already handled) or too far away
    IF v_remaining <= 0 THEN CONTINUE; END IF;

    -- Estimate avg km/calendar-day from mileage and year
    IF rec.year IS NOT NULL AND rec.year < EXTRACT(YEAR FROM now()) THEN
      v_daily_km := COALESCE(rec.mileage, 0)::NUMERIC /
        GREATEST(1, (EXTRACT(YEAR FROM now()) - rec.year) * 365);
    ELSE
      v_daily_km := 30; -- default 30 km/day
    END IF;

    -- Check if service is within threshold (30 calendar days)
    IF v_daily_km > 0 AND (v_remaining / v_daily_km) > v_days_threshold THEN
      CONTINUE; -- too far away
    END IF;

    -- Check parts for this schedule
    items_arr := '[]'::jsonb;
    FOR part IN
      SELECT sp.inventory_item_id, sp.quantity AS needed_qty, sp.notes AS part_notes,
             i.name, i.sku, i.stock, i.unit_price, i.supplier_id
      FROM service_parts sp
      JOIN inventory i ON i.id = sp.inventory_item_id
      WHERE sp.schedule_id = rec.schedule_id
    LOOP
      -- Only order if stock is insufficient
      IF part.stock >= part.needed_qty THEN CONTINUE; END IF;

      -- Check if this specific item already has an open (not received) purchase order
      SELECT EXISTS (
        SELECT 1
        FROM purchase_order_items poi
        JOIN purchase_orders po ON po.id = poi.order_id
        WHERE poi.item_id = part.inventory_item_id
          AND po.status IN ('draft', 'sent')
      ) INTO v_already_ordered;

      IF v_already_ordered THEN CONTINUE; END IF;

      items_arr := items_arr || jsonb_build_object(
        'inventory_item_id', part.inventory_item_id,
        'name', part.name,
        'sku', part.sku,
        'quantity', part.needed_qty - part.stock,
        'unit_price', COALESCE(part.unit_price, 0),
        'supplier_id', part.supplier_id
      );
    END LOOP;

    -- If any parts need ordering, group by supplier and create POs
    IF jsonb_array_length(items_arr) > 0 THEN
      -- Group by supplier_id
      FOR sup IN
        SELECT DISTINCT (item->>'supplier_id')::UUID AS supplier_id
        FROM jsonb_array_elements(items_arr) AS item
        WHERE item->>'supplier_id' IS NOT NULL
      LOOP
        -- Create purchase order
        INSERT INTO purchase_orders (supplier_id, notes, status, total_amount)
        VALUES (
          sup.supplier_id,
          'Auto-objednávka dílů pro servis: ' || rec.description || ' (' || COALESCE(rec.model, '') || ' ' || COALESCE(rec.spz, '') || ')',
          'draft',
          0
        )
        RETURNING id INTO order_id;

        -- Insert items for this supplier
        INSERT INTO purchase_order_items (order_id, item_id, quantity, unit_price)
        SELECT
          order_id,
          (item->>'inventory_item_id')::UUID,
          (item->>'quantity')::INT,
          (item->>'unit_price')::NUMERIC
        FROM jsonb_array_elements(items_arr) AS item
        WHERE (item->>'supplier_id')::UUID = sup.supplier_id;

        -- Update total
        UPDATE purchase_orders
        SET total_amount = (
          SELECT COALESCE(SUM(quantity * unit_price), 0)
          FROM purchase_order_items WHERE order_id = purchase_orders.id
        )
        WHERE id = order_id;

        created_orders := created_orders + 1;
      END LOOP;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('created_orders', created_orders);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."auto_check_service_parts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_complete_expired_bookings"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
    AND payment_status IN ('paid', 'partial_refund', 'refund_pending');

  -- Krok 2: dokonči aktivní po end_date → KF. VÝJIMKA: nedokončuj motorku s
  -- ČEKAJÍCÍ navazující výměnou (jiná moto téhož zákazníka, start = boundary,
  -- navazující ještě běží) — tu dokončí až switch (swap_handoff_bookings).
  UPDATE bookings b SET
    status = 'completed'::booking_status,
    returned_at = NOW()
  WHERE b.status = 'active'
    AND b.end_date < CURRENT_DATE
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


ALTER FUNCTION "public"."auto_complete_expired_bookings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_deactivate_door_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Pouze při přechodu na completed nebo cancelled
  IF NEW.status NOT IN ('completed', 'cancelled') THEN
    RETURN NEW;
  END IF;
  -- Pouze pokud se status skutečně změnil
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Deaktivuj všechny aktivní kódy pro tento booking
  UPDATE branch_door_codes
  SET is_active = false
  WHERE booking_id = NEW.id
    AND is_active = true;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_deactivate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_deactivate_door_codes"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."auto_generate_door_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_liabilities_from_payroll"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Social insurance liability (employer + employee)
  IF (NEW.social_employer + NEW.social_employee) > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      'CSSZ',
      'social',
      NEW.social_employer + NEW.social_employee,
      'SP ' || NEW.month || '/' || NEW.year || ' - ' || (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-20')::date,
      'pending'
    );
  END IF;

  -- Health insurance liability
  IF (NEW.health_employer + NEW.health_employee) > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      'Zdravotni pojistovna',
      'health',
      NEW.health_employer + NEW.health_employee,
      'ZP ' || NEW.month || '/' || NEW.year || ' - ' || (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-20')::date,
      'pending'
    );
  END IF;

  -- Tax advance liability
  IF NEW.tax_advance > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      'Financni urad',
      'tax',
      NEW.tax_advance,
      'Zaloha dan ' || NEW.month || '/' || NEW.year || ' - ' || (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-20')::date,
      'pending'
    );
  END IF;

  -- Salary liability
  IF NEW.net_salary > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      'salary',
      NEW.net_salary,
      'Mzda ' || NEW.month || '/' || NEW.year,
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-15')::date,
      'pending'
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_liabilities_from_payroll"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_order_gear_shortages"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record; res jsonb; v_sku text; v_dup_order uuid;
  v_created int:=0; v_no_item int:=0; v_no_supplier int:=0; v_dup int:=0;
begin
  for r in select gs.* from gear_shortages gs
           where gs.status='open' and gs.deficit_qty>0 order by gs.shortage_date loop
    v_sku := 'prislusenstvi-'||r.accessory_type||'-'||r.size;
    -- už existuje otevřená (draft/sent) objednávka na tuto položku?
    select po.id into v_dup_order
      from purchase_order_items poi
      join purchase_orders po on po.id=poi.order_id
      join inventory inv on inv.id=poi.item_id
      where inv.sku=v_sku and po.status in ('draft','sent') limit 1;
    if v_dup_order is not null then
      update gear_shortages set status='order_created', purchase_order_id=v_dup_order, updated_at=now() where id=r.id;
      v_dup:=v_dup+1; continue;
    end if;
    res := public._create_gear_po(r.id, null);
    if (res->>'success')::boolean then v_created:=v_created+1;
    elsif res->>'error'='no_inventory_item' then v_no_item:=v_no_item+1;
    elsif res->>'error'='no_supplier' then v_no_supplier:=v_no_supplier+1;
    end if;
  end loop;
  return jsonb_build_object('created',v_created,'skipped_dup',v_dup,
    'skipped_no_item',v_no_item,'skipped_no_supplier',v_no_supplier);
end $$;


ALTER FUNCTION "public"."auto_order_gear_shortages"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_process_voucher_order"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_item RECORD;
  v_all_items_count INT;
  v_voucher_items_count INT;
  v_is_all_vouchers BOOL;
  v_has_physical_voucher BOOL := false;
  v_code TEXT;
  v_valid_until DATE;
  v_codes TEXT[] := '{}';
  v_codes_with_amounts TEXT[] := '{}';
  v_codes_str TEXT;
  v_i INT;
BEGIN
  IF OLD.status NOT IN ('new', 'pending') THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO v_all_items_count
  FROM shop_order_items WHERE order_id = NEW.id;

  SELECT COUNT(*) INTO v_voucher_items_count
  FROM shop_order_items WHERE order_id = NEW.id
    AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%');

  IF v_all_items_count = 0 THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM shop_order_items WHERE order_id = NEW.id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
      AND (LOWER(product_name) LIKE '%tišt%' OR LOWER(product_name) LIKE '%fyzick%' OR LOWER(product_name) LIKE '%printed%')
  ) INTO v_has_physical_voucher;

  IF NOT v_has_physical_voucher AND COALESCE(NEW.notes, '') ILIKE '%fyzick%' THEN
    v_has_physical_voucher := true;
  END IF;

  v_is_all_vouchers := (v_voucher_items_count = v_all_items_count);

  -- Idempotence: vouchery už existují, jen aktualizuj status
  IF EXISTS (SELECT 1 FROM vouchers WHERE order_id = NEW.id) THEN
    IF v_is_all_vouchers AND NOT v_has_physical_voucher THEN
      NEW.status := 'delivered';
      NEW.delivered_at := COALESCE(NEW.delivered_at, NOW());
    ELSE
      NEW.status := 'confirmed';
    END IF;
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
    RETURN NEW;
  END IF;

  IF v_voucher_items_count > 0 THEN
    v_valid_until := CURRENT_DATE + INTERVAL '3 years';

    FOR v_item IN
      SELECT * FROM shop_order_items WHERE order_id = NEW.id
        AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
    LOOP
      FOR v_i IN 1..GREATEST(v_item.quantity, 1) LOOP
        v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text || v_i::text) FROM 1 FOR 6));
        WHILE EXISTS (SELECT 1 FROM vouchers WHERE code = v_code) LOOP
          v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));
        END LOOP;

        v_codes := array_append(v_codes, v_code);
        v_codes_with_amounts := array_append(v_codes_with_amounts,
          v_code || ' (' || COALESCE(v_item.unit_price, v_item.total_price, 0)::int || ' Kč)');

        INSERT INTO vouchers (
          code, amount, currency, status,
          buyer_id, buyer_name, buyer_email,
          valid_from, valid_until,
          source, order_id, category
        ) VALUES (
          v_code,
          COALESCE(v_item.unit_price, v_item.total_price, 0),
          'CZK', 'active',
          NEW.customer_id,
          COALESCE(NULLIF(NEW.customer_name, ''), 'Web zákazník'),
          COALESCE(NULLIF(NEW.customer_email, ''), ''),
          CURRENT_DATE, v_valid_until,
          'eshop', NEW.id, 'gift'
        );
      END LOOP;
    END LOOP;

    -- In-app notifikace pro registrované zákazníky (Velín & Flutter app)
    IF NEW.customer_id IS NOT NULL AND array_length(v_codes, 1) > 0 THEN
      v_codes_str := array_to_string(v_codes_with_amounts, E'\n');
      INSERT INTO admin_messages (user_id, title, message, type, read)
      VALUES (
        NEW.customer_id,
        'Dárkový poukaz MotoGo24',
        E'Děkujeme za nákup dárkového poukazu!\n\n' ||
        E'Vaše poukazy:\n' || v_codes_str || E'\n\n' ||
        'Platnost do ' || to_char(v_valid_until, 'DD.MM.YYYY') || E'.\n' ||
        E'Kód uplatníte při rezervaci motorky v sekci „Slevový kód".\n\n' ||
        'Přejeme krásnou jízdu!',
        'voucher', false
      );
    END IF;

    -- ❌ ŽÁDNÝ pg_net mail. Mail "voucher_purchased" výhradně posílá
    -- webhook-receiver/confirmShopPayment (s přílohami DP + HTML voucher).
  END IF;

  IF v_is_all_vouchers AND NOT v_has_physical_voucher THEN
    NEW.status := 'delivered';
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
    NEW.delivered_at := NOW();
  ELSIF v_voucher_items_count > 0 THEN
    NEW.status := 'confirmed';
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_process_voucher_order error for order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_process_voucher_order"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_reply_sos"("p_incident_id" "uuid", "p_reply_type" "text" DEFAULT 'sos_response'::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_user_id UUID;
    v_sos_type TEXT;
    v_title TEXT;
    v_message TEXT;
BEGIN
    SELECT user_id, type::TEXT INTO v_user_id, v_sos_type
    FROM sos_incidents WHERE id = p_incident_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Incident nenalezen';
    END IF;

    CASE p_reply_type
        WHEN 'thanks' THEN
            CASE v_sos_type
                WHEN 'accident_minor' THEN
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Děkujeme za nahlášení drobné nehody. Šťastnou cestu! Pokud budete potřebovat cokoliv dalšího, neváhejte nás kontaktovat.';
                WHEN 'accident_major' THEN
                    v_title := 'Přijali jsme vaše hlášení';
                    v_message := 'Vaše hlášení vážné nehody bylo přijato. Náš tým se tím okamžitě zabývá. Zůstaňte v bezpečí a čekejte na další instrukce.';
                WHEN 'breakdown_minor' THEN
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Děkujeme za nahlášení poruchy. Šťastnou cestu! Závadu prověříme při nejbližším servisu.';
                WHEN 'breakdown_major' THEN
                    v_title := 'Přijali jsme vaše hlášení';
                    v_message := 'Vaše hlášení poruchy bylo přijato. Pracujeme na řešení. Prosím vyčkejte na místě.';
                WHEN 'theft' THEN
                    v_title := 'Hlášení krádeže přijato';
                    v_message := 'Vaše hlášení krádeže bylo přijato. Kontaktovali jsme Policii ČR. Prosím volejte také 158. Ozveme se co nejdříve.';
                ELSE
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Vaše hlášení bylo přijato. Děkujeme a šťastnou cestu!';
            END CASE;
        WHEN 'replacement' THEN
            v_title := 'Vezeme vám náhradní motorku';
            v_message := 'Vydržte! Vezeme vám náhradní motorku. Budeme u vás co nejdříve. Sledujte prosím telefon pro další informace.';
        WHEN 'tow' THEN
            v_title := 'Odtahová služba na cestě';
            v_message := 'Zavolali jsme vám odtahovou službu. Prosím vyčkejte na místě. Řidič vás bude kontaktovat telefonicky.';
        ELSE
            v_title := 'Zpráva z MotoGo24';
            v_message := 'Vaše hlášení bylo přijato. Děkujeme za informaci.';
    END CASE;

    RETURN send_admin_message(
        v_user_id, v_title, v_message, p_reply_type, p_incident_id, NULL
    );
END;
$$;


ALTER FUNCTION "public"."auto_reply_sos"("p_incident_id" "uuid", "p_reply_type" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."auto_reply_sos"("p_incident_id" "uuid", "p_reply_type" "text") IS 'RPC: Automatická odpověď na SOS incident podle typu';



CREATE OR REPLACE FUNCTION "public"."auto_schedule_services"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  moto RECORD;
  sched RECORD;
  last_km INT;
  next_date DATE;
BEGIN
  FOR moto IN SELECT * FROM motorcycles WHERE status = 'active' LOOP

    FOR sched IN
      SELECT * FROM maintenance_schedules
      WHERE moto_id = moto.id AND active = true
    LOOP

      -- Časový interval: spočítej příští datum
      IF sched.schedule_type IN ('time', 'both') AND sched.interval_days IS NOT NULL THEN
        next_date := COALESCE(sched.last_performed, moto.last_service_date, CURRENT_DATE)
                     + (sched.interval_days || ' days')::INTERVAL;
        IF next_date <= CURRENT_DATE + INTERVAL '30 days' THEN
          UPDATE maintenance_schedules SET next_due = next_date WHERE id = sched.id;
        END IF;
      END IF;

      -- Kilometrový interval: pokud jsme na 80%+ intervalu, naplánuj
      IF sched.schedule_type IN ('mileage', 'both') AND sched.interval_km IS NOT NULL THEN
        SELECT COALESCE(mileage_at_service, 0) INTO last_km
        FROM maintenance_log
        WHERE moto_id = moto.id
        ORDER BY service_date DESC LIMIT 1;

        IF last_km IS NULL THEN last_km := 0; END IF;

        IF moto.mileage >= (last_km + sched.interval_km * 0.8) AND sched.next_due IS NULL THEN
          UPDATE maintenance_schedules
          SET next_due = CURRENT_DATE + INTERVAL '14 days'
          WHERE id = sched.id;
        END IF;
      END IF;

    END LOOP;

    -- STK: pokud vyprší do 60 dnů a není naplánováno
    IF moto.stk_valid_until IS NOT NULL
       AND moto.stk_valid_until <= CURRENT_DATE + INTERVAL '60 days'
       AND NOT EXISTS (
         SELECT 1 FROM maintenance_schedules
         WHERE moto_id = moto.id AND description = 'STK' AND active = true
       ) THEN
      INSERT INTO maintenance_schedules (moto_id, schedule_type, next_due, description, active)
      VALUES (moto.id, 'time', moto.stk_valid_until - INTERVAL '14 days', 'STK', true);
    END IF;

  END LOOP;
END;
$$;


ALTER FUNCTION "public"."auto_schedule_services"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."autofill_overdue_handover_protocols"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_row record;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  -- 2a) PŘIPOMÍNKA: okno > 50 min, nevyplněno, připomínka neodeslaná
  FOR v_row IN
    SELECT b.id, b.user_id
    FROM bookings b
    JOIN motorcycles m ON m.id = b.moto_id
    JOIN branches br   ON br.id = m.branch_id
    WHERE br.type = 'samoobslužná'
      AND b.status IN ('reserved','active')
      AND b.user_id IS NOT NULL
      AND b.handover_protocol_filled_at IS NULL
      AND b.handover_protocol_reminder_sent_at IS NULL
      AND b.handover_protocol_started_at IS NOT NULL
      AND b.handover_protocol_started_at < now() - interval '50 minutes'
    LIMIT 50
  LOOP
    BEGIN
      PERFORM send_push_via_edge(
        v_row.user_id,
        'Předávací protokol — poslední výzva',
        'Zbývá pár minut na vyplnění předávacího protokolu. Pokud ho nevyplníte, vyplníme ho za vás (vše dle rezervace).',
        jsonb_build_object('type', 'handover_protocol', 'id', v_row.id::text)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'handover reminder push failed for %: %', v_row.id, SQLERRM;
    END;
    UPDATE bookings SET handover_protocol_reminder_sent_at = now() WHERE id = v_row.id;
  END LOOP;

  -- 2b) AUTO-FILL: okno > 1 h, nevyplněno → edge fn (mode=auto)
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'autofill_overdue_handover_protocols: app_settings(supabase_url|service_role_key) chybí';
    RETURN;
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id
    FROM bookings b
    JOIN motorcycles m ON m.id = b.moto_id
    JOIN branches br   ON br.id = m.branch_id
    WHERE br.type = 'samoobslužná'
      AND b.status IN ('reserved','active')
      AND b.handover_protocol_started_at IS NOT NULL
      AND b.handover_protocol_filled_at IS NULL
      AND b.handover_protocol_started_at < now() - interval '1 hour'
    LIMIT 50
  LOOP
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/submit-handover-protocol',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object('booking_id', v_row.id, 'mode', 'auto')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'autofill_overdue_handover_protocols: dispatch failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."autofill_overdue_handover_protocols"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bridge_admin_message_to_app"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_thread message_threads%ROWTYPE;
  v_customer_id uuid;
BEGIN
  -- Pouze admin zprávy
  IF NEW.direction != 'admin' THEN RETURN NEW; END IF;

  -- Najdi thread a zákazníka
  SELECT * INTO v_thread FROM message_threads WHERE id = NEW.thread_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_customer_id := v_thread.customer_id;
  IF v_customer_id IS NULL THEN RETURN NEW; END IF;

  -- Vytvoř záznam v admin_messages pro aplikaci
  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    v_customer_id,
    COALESCE(v_thread.subject, 'Zpráva z Moto Go'),
    NEW.content,
    'info'
  );

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."bridge_admin_message_to_app"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calc_booking_price_v2"("p_moto_id" "uuid", "p_start" "date", "p_end" "date", "p_promo" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    base_price NUMERIC := 0;
    current_day DATE := p_start;
    dow INTEGER;
    day_price NUMERIC;
    moto RECORD;
    num_days INT;
    seasonal_mod NUMERIC := 1.0;
    promo_mod NUMERIC := 1.0;
    long_term_mod NUMERIC := 1.0;
    rule RECORD;
    total_price NUMERIC;
    deposit NUMERIC;
BEGIN
    SELECT * INTO moto FROM motorcycles WHERE id = p_moto_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Motorcycle not found');
    END IF;

    num_days := (p_end - p_start) + 1;
    deposit := COALESCE(moto.deposit_amount, 5000);

    -- Výpočet základní ceny po dnech
    WHILE current_day <= p_end LOOP
        dow := EXTRACT(DOW FROM current_day);
        day_price := CASE dow
            WHEN 1 THEN COALESCE(moto.price_mon, moto.price_weekday)
            WHEN 2 THEN COALESCE(moto.price_tue, moto.price_weekday)
            WHEN 3 THEN COALESCE(moto.price_wed, moto.price_weekday)
            WHEN 4 THEN COALESCE(moto.price_thu, moto.price_weekday)
            WHEN 5 THEN COALESCE(moto.price_fri, moto.price_weekend)
            WHEN 6 THEN COALESCE(moto.price_sat, moto.price_weekend)
            WHEN 0 THEN COALESCE(moto.price_sun, moto.price_weekend)
            ELSE moto.price_weekday
        END;
        base_price := base_price + day_price;
        current_day := current_day + INTERVAL '1 day';
    END LOOP;

    -- Sezónní modifier
    FOR rule IN
        SELECT * FROM pricing_rules
        WHERE type = 'seasonal' AND active = true
          AND (moto_id IS NULL OR moto_id = p_moto_id)
          AND p_start >= valid_from AND p_end <= valid_to
    LOOP
        seasonal_mod := rule.modifier;
    END LOOP;

    -- Long-term modifier
    FOR rule IN
        SELECT * FROM pricing_rules
        WHERE type = 'long_term' AND active = true
          AND (moto_id IS NULL OR moto_id = p_moto_id)
          AND (min_days IS NULL OR num_days >= min_days)
        ORDER BY min_days DESC NULLS LAST
        LIMIT 1
    LOOP
        long_term_mod := rule.modifier;
    END LOOP;

    -- Promo kód modifier
    IF p_promo IS NOT NULL THEN
        FOR rule IN
            SELECT * FROM pricing_rules
            WHERE type = 'promo' AND active = true
              AND promo_code = p_promo
              AND (moto_id IS NULL OR moto_id = p_moto_id)
              AND (valid_from IS NULL OR CURRENT_DATE >= valid_from)
              AND (valid_to IS NULL OR CURRENT_DATE <= valid_to)
            LIMIT 1
        LOOP
            promo_mod := rule.modifier;
        END LOOP;
    END IF;

    total_price := ROUND(base_price * seasonal_mod * long_term_mod * promo_mod, 2);

    RETURN jsonb_build_object(
        'base_price', base_price,
        'total_price', total_price,
        'num_days', num_days,
        'seasonal_mod', seasonal_mod,
        'promo_mod', promo_mod,
        'long_term_mod', long_term_mod,
        'deposit', deposit,
        'currency', 'CZK'
    );
END;
$$;


ALTER FUNCTION "public"."calc_booking_price_v2"("p_moto_id" "uuid", "p_start" "date", "p_end" "date", "p_promo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_moto_roi"("p_moto_id" "uuid", "p_from" "date", "p_to" "date") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    total_revenue NUMERIC;
    total_maintenance NUMERIC;
    total_bookings INT;
    total_days INT;
    booked_days INT;
    utilization NUMERIC;
    avg_price NUMERIC;
    profit NUMERIC;
    roi_val NUMERIC;
BEGIN
    total_days := (p_to - p_from) + 1;

    SELECT COALESCE(SUM(total_price), 0), COUNT(*)
    INTO total_revenue, total_bookings
    FROM bookings
    WHERE moto_id = p_moto_id
      AND start_date::DATE >= p_from AND end_date::DATE <= p_to
      AND status IN ('active', 'completed')
      AND payment_status = 'paid';

    SELECT COALESCE(SUM(total_cost), 0)
    INTO total_maintenance
    FROM maintenance_log
    WHERE moto_id = p_moto_id
      AND service_date >= p_from AND service_date <= p_to;

    SELECT COALESCE(SUM(LEAST(end_date::DATE, p_to) - GREATEST(start_date::DATE, p_from) + 1), 0)
    INTO booked_days
    FROM bookings
    WHERE moto_id = p_moto_id
      AND start_date::DATE <= p_to AND end_date::DATE >= p_from
      AND status IN ('active', 'completed');

    utilization := ROUND(booked_days::NUMERIC / NULLIF(total_days, 0) * 100, 2);
    avg_price := ROUND(total_revenue / NULLIF(booked_days, 0), 2);
    profit := total_revenue - total_maintenance;
    roi_val := ROUND(profit / NULLIF(total_maintenance, 0) * 100, 2);

    RETURN jsonb_build_object(
        'moto_id', p_moto_id,
        'period_from', p_from,
        'period_to', p_to,
        'revenue', total_revenue,
        'maintenance_cost', total_maintenance,
        'profit', profit,
        'bookings_count', total_bookings,
        'booked_days', booked_days,
        'total_days', total_days,
        'utilization_pct', utilization,
        'avg_daily_price', avg_price,
        'roi_pct', roi_val
    );
END;
$$;


ALTER FUNCTION "public"."calculate_moto_roi"("p_moto_id" "uuid", "p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_booking_tracked"("p_booking_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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


ALTER FUNCTION "public"."cancel_booking_tracked"("p_booking_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_pending_web_booking"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_row bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- Zrušit jen rozpracovanou (pending) a nezaplacenou web rezervaci
  IF v_row.status = 'pending' AND v_row.payment_status = 'unpaid' THEN
    UPDATE bookings
       SET status = 'cancelled', updated_at = now()
     WHERE id = p_booking_id;
    RETURN jsonb_build_object('success', true);
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'not_cancelable');
END;
$$;


ALTER FUNCTION "public"."cancel_pending_web_booking"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_admin_permission"("p_user_id" "uuid", "p_permission" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
    v_role admin_role;
    v_perms JSONB;
BEGIN
    SELECT role, permissions INTO v_role, v_perms
    FROM admin_users WHERE id = p_user_id;

    IF NOT FOUND THEN RETURN false; END IF;
    IF v_role = 'superadmin' THEN RETURN true; END IF;
    IF v_role = 'manager' THEN RETURN true; END IF;

    RETURN COALESCE((v_perms->>p_permission)::BOOLEAN, false);
END;
$$;


ALTER FUNCTION "public"."check_admin_permission"("p_user_id" "uuid", "p_permission" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_asset_status"("p_asset_type" "text", "p_vin" "text" DEFAULT NULL::"text", "p_spz" "text" DEFAULT NULL::"text", "p_name" "text" DEFAULT NULL::"text", "p_amount" numeric DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_vin text := nullif(upper(regexp_replace(coalesce(p_vin, ''), '\s', '', 'g')), '');
  v_spz text := nullif(upper(regexp_replace(coalesce(p_spz, ''), '\s', '', 'g')), '');
  v_name text := public._norm_supplier(p_name);
  v_moto record;
  v_asset record;
  v_status text := 'new';
  v_kind text := null;
  v_moto_id uuid := null;
  v_asset_id uuid := null;
  v_label text := null;
begin
  -- 1) Vozidlo/motorka dle VIN nebo SPZ (nezaměnitelné)
  if v_vin is not null or v_spz is not null then
    select * into v_moto from public.motorcycles m
    where (v_vin is not null and upper(regexp_replace(coalesce(m.vin, ''), '\s', '', 'g')) = v_vin)
       or (v_spz is not null and upper(regexp_replace(coalesce(m.spz, ''), '\s', '', 'g')) = v_spz)
    limit 1;
    if v_moto.id is not null then
      v_kind := 'motorcycle'; v_moto_id := v_moto.id;
      v_label := concat_ws(' ', v_moto.model, coalesce(v_moto.spz, v_moto.vin));
      select * into v_asset from public.acc_long_term_assets a where a.motorcycle_id = v_moto.id limit 1;
      if v_asset.id is not null then
        v_asset_id := v_asset.id;
        v_status := case when coalesce(v_asset.missing_purchase_doc, false)
                          or coalesce(v_asset.purchase_price, 0) = 0
                          or v_asset.invoice_number is null
                         then 'asset_exists_needs_doc' else 'duplicate_full' end;
      else
        v_status := 'asset_exists_needs_doc';   -- motorka ve flotile, ještě ne v majetku
      end if;
    end if;
  end if;

  -- 2) Ostatní dlouhodobý majetek dle názvu
  if v_kind is null and p_asset_type = 'dlouhodoby_majetek' and v_name <> '' then
    select * into v_asset from public.acc_long_term_assets a
    where public._norm_supplier(a.name) = v_name
       or (length(v_name) > 4 and public._norm_supplier(a.name) like '%' || v_name || '%')
    order by a.acquired_date desc nulls last limit 1;
    if v_asset.id is not null then
      v_kind := 'long_term'; v_asset_id := v_asset.id; v_label := v_asset.name;
      v_status := case when coalesce(v_asset.missing_purchase_doc, false)
                        or coalesce(v_asset.purchase_price, 0) = 0
                        or v_asset.invoice_number is null
                       then 'asset_exists_needs_doc' else 'duplicate_full' end;
    end if;
  end if;

  -- 3) Krátkodobý majetek dle názvu
  if v_kind is null and p_asset_type = 'kratkodoby_majetek' and v_name <> '' then
    select * into v_asset from public.acc_short_term_assets a
    where public._norm_supplier(a.name) = v_name
    order by a.acquired_date desc nulls last limit 1;
    if v_asset.id is not null then
      v_kind := 'short_term'; v_asset_id := v_asset.id; v_label := v_asset.name;
      v_status := 'duplicate_full';
    end if;
  end if;

  return jsonb_build_object('status', v_status, 'kind', v_kind,
    'motorcycle_id', v_moto_id, 'asset_id', v_asset_id, 'label', v_label);
end $$;


ALTER FUNCTION "public"."check_asset_status"("p_asset_type" "text", "p_vin" "text", "p_spz" "text", "p_name" "text", "p_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_booking_docs_status"("p_user_id" "uuid", "p_end_date" "date", "p_moto_id" "uuid" DEFAULT NULL::"uuid") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_license_required text;
  v_has_id_doc boolean := false;
  v_has_dl_doc boolean := false;
  v_id_verified timestamptz;
  v_pp_verified timestamptz;
  v_lic_verified timestamptz;
  v_lic_until date;
BEGIN
  IF p_user_id IS NULL THEN RETURN 'Chybí uživatel'; END IF;

  -- Dětská motorka → doklady nepotřeba
  IF p_moto_id IS NOT NULL THEN
    SELECT license_required INTO v_license_required FROM motorcycles WHERE id = p_moto_id;
    IF v_license_required = 'N' THEN RETURN NULL; END IF;
  END IF;

  SELECT id_verified_at, passport_verified_at, license_verified_at, license_verified_until
    INTO v_id_verified, v_pp_verified, v_lic_verified, v_lic_until
  FROM profiles WHERE id = p_user_id;

  -- Doklad totožnosti: fotka (i při neúspěšném OCR) NEBO reálné OCR. Holé číslo NESTAČÍ (jen do smlouvy).
  v_has_id_doc :=
       EXISTS (SELECT 1 FROM documents WHERE user_id = p_user_id AND type IN ('id_card','id_photo','passport'))
    OR v_id_verified IS NOT NULL
    OR v_pp_verified IS NOT NULL;

  -- ŘP: fotka NEBO reálné OCR. Holé číslo NESTAČÍ.
  v_has_dl_doc :=
       EXISTS (SELECT 1 FROM documents WHERE user_id = p_user_id AND type IN ('drivers_license','license_photo'))
    OR v_lic_verified IS NOT NULL;

  IF NOT v_has_id_doc AND NOT v_has_dl_doc THEN RETURN 'Chybí doklady (OP/pas/ŘP)'; END IF;
  IF NOT v_has_id_doc THEN RETURN 'Chybí doklad totožnosti (OP/pas)'; END IF;
  IF NOT v_has_dl_doc THEN RETURN 'Chybí ŘP'; END IF;

  -- Expirace ŘP (jen pokud platnost známe z OCR)
  IF v_lic_until IS NOT NULL AND p_end_date IS NOT NULL AND v_lic_until < p_end_date THEN
    RETURN 'ŘP propadlý ' || TO_CHAR(v_lic_until, 'DD.MM.YYYY');
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."check_booking_docs_status"("p_user_id" "uuid", "p_end_date" "date", "p_moto_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_booking_overlap"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- SOS replacement bookings are exempt from moto overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Překrývající se rezervace pro moto_id %', NEW.moto_id;
  END IF;

  -- NOVÉ: kus je v termínu přiřazený jako vozík-příslušenství jiné rezervace
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE trailer_moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Kus % je v tomto termínu přiřazen jako vozík k jiné rezervaci', NEW.moto_id;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_booking_overlap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_document_status"("p_doc_type" "text", "p_doc_number" "text" DEFAULT NULL::"text", "p_doc_date" "date" DEFAULT NULL::"date", "p_variable_symbol" "text" DEFAULT NULL::"text", "p_supplier_ico" "text" DEFAULT NULL::"text", "p_supplier_name" "text" DEFAULT NULL::"text", "p_amount" numeric DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_norm text := public._norm_supplier(p_supplier_name);
  v_tol numeric := greatest(coalesce(p_amount, 0) * 0.02, 1);
  v_num text := nullif(lower(trim(coalesce(p_doc_number, ''))), '');
  v_same public.stock_receipts;
  v_in_finance boolean := false;
  v_in_stock boolean := false;
  v_found boolean := false;
  v_cp_stocked boolean := false;
  v_status text;
  v_match jsonb := null;
begin
  -- Shoda STEJNÉHO dokladu = klíč „č. dokladu + datum" (100% jistota proti duplicitě).
  -- Bez č. dokladu fallback na dodavatel + částka + blízké datum (±3 dny).
  -- WHERE výraz drží v jedné proměnné, ať se neopakuje (použijeme 2×).
  select * into v_same from public.stock_receipts r
  where r.doc_type = p_doc_type
    and (
      (v_num is not null and lower(trim(coalesce(r.doc_number, ''))) = v_num
        and (p_doc_date is null or r.doc_date is null or r.doc_date = p_doc_date))
      or (v_num is null and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm
        and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
        and (p_doc_date is null or r.doc_date is null or abs(r.doc_date - p_doc_date) <= 3))
    )
  order by r.created_at desc
  limit 1;

  if v_same.id is not null then
    v_found := true;
    select bool_or(financial_event_id is not null), bool_or(stocked)
      into v_in_finance, v_in_stock
    from public.stock_receipts r
    where r.doc_type = p_doc_type
      and (
        (v_num is not null and lower(trim(coalesce(r.doc_number, ''))) = v_num
          and (p_doc_date is null or r.doc_date is null or r.doc_date = p_doc_date))
        or (v_num is null and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm
          and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
          and (p_doc_date is null or r.doc_date is null or abs(r.doc_date - p_doc_date) <= 3))
      );
    v_match := jsonb_build_object('receipt_id', v_same.id, 'doc_number', v_same.doc_number,
      'doc_date', v_same.doc_date, 'amount_czk', v_same.amount_czk, 'created_at', v_same.created_at,
      'financial_event_id', v_same.financial_event_id);
  end if;

  -- Zboží mohlo být naskladněno protějškem (opačný typ — DL↔faktura)
  select bool_or(stocked) into v_cp_stocked from public.stock_receipts r
  where r.doc_type <> p_doc_type
    and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
    and r.created_at > now() - interval '120 days'
    and ((p_supplier_ico is not null and r.supplier_ico = p_supplier_ico)
      or (coalesce(p_supplier_ico, '') = '' and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm));
  if v_cp_stocked then v_in_stock := true; end if;

  -- Faktura už mohla být ve financích i mimo Logistiku (financial_events dle č. faktury + datum)
  if p_doc_type = 'invoice' and v_num is not null and not v_in_finance then
    begin
      select exists(select 1 from public.financial_events fe
        where lower(trim(coalesce(fe.metadata->>'invoice_number', ''))) = v_num
          and (p_doc_date is null or fe.duzp is null or abs(fe.duzp - p_doc_date) <= 5)) into v_in_finance;
    exception when others then null;
    end;
  end if;

  if p_doc_type = 'delivery_note' then
    v_status := case when v_in_stock then 'duplicate_full' else 'new' end;
  else
    if v_in_finance and v_in_stock then v_status := 'duplicate_full';
    elsif v_in_stock and not v_in_finance then v_status := 'need_finance';
    elsif v_in_finance and not v_in_stock then v_status := 'need_stock';
    else v_status := 'new';
    end if;
  end if;

  return jsonb_build_object('found', v_found, 'in_finance', v_in_finance,
    'in_stock', v_in_stock, 'status', v_status, 'match', v_match);
end $$;


ALTER FUNCTION "public"."check_document_status"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_license_for_moto"("p_moto_id" "uuid", "p_rental_end" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
  v_profile profiles%ROWTYPE;
  v_moto motorcycles%ROWTYPE;
  v_required text;
  v_check_date date;
  v_license_exp date;
  v_groups text;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'Profil nenalezen');
  END IF;

  IF v_profile.docs_verification_status <> 'verified' THEN
    RETURN jsonb_build_object('allowed', false, 'reason',
      'Doklady nejsou ověřeny. Naskenujte OP a ŘP v sekci Doklady.');
  END IF;

  v_check_date := COALESCE(p_rental_end, CURRENT_DATE);

  -- Převod license_expiry z TEXT na DATE (bezpečně)
  BEGIN
    v_license_exp := v_profile.license_expiry::date;
  EXCEPTION WHEN OTHERS THEN
    v_license_exp := NULL;
  END;

  -- Kontrola expirace ŘP po dobu výpůjčky
  IF v_license_exp IS NOT NULL AND v_license_exp < v_check_date THEN
    IF v_license_exp < CURRENT_DATE THEN
      RETURN jsonb_build_object('allowed', false, 'reason',
        'Váš řidičský průkaz expiroval ' ||
        to_char(v_license_exp, 'DD.MM.YYYY') || '.');
    ELSE
      RETURN jsonb_build_object('allowed', false, 'reason',
        'Váš ŘP expiruje ' || to_char(v_license_exp, 'DD.MM.YYYY') ||
        ', ale výpůjčka trvá do ' || to_char(v_check_date, 'DD.MM.YYYY') ||
        '. ŘP musí být platný po celou dobu výpůjčky.');
    END IF;
  END IF;

  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'Motorka nenalezena');
  END IF;

  v_required := CASE
    WHEN v_moto.engine_cc <= 50 THEN 'AM'
    WHEN v_moto.engine_cc <= 125 THEN 'A1'
    WHEN v_moto.engine_cc <= 500 THEN 'A2'
    ELSE 'A'
  END;

  -- license_group je text[] — spojit do jednoho stringu pro regex match
  v_groups := array_to_string(v_profile.license_group, ',');

  IF v_groups IS NULL OR v_groups = '' THEN
    RETURN jsonb_build_object('allowed', false, 'reason',
      'Nemáte uloženou skupinu ŘP. Naskenujte řidičský průkaz.');
  END IF;

  IF v_required = 'AM' AND upper(v_groups) ~ '(^|[,\s])A[12M]?([,\s]|$)' THEN
    RETURN jsonb_build_object('allowed', true);
  ELSIF v_required = 'A1' AND upper(v_groups) ~ '(^|[,\s])A[12]?([,\s]|$)' THEN
    RETURN jsonb_build_object('allowed', true);
  ELSIF v_required = 'A2' AND upper(v_groups) ~ '(^|[,\s])A2?([,\s]|$)' THEN
    RETURN jsonb_build_object('allowed', true);
  ELSIF v_required = 'A' AND upper(v_groups) ~ '(^|[,\s])A([,\s]|$)' THEN
    RETURN jsonb_build_object('allowed', true);
  END IF;

  RETURN jsonb_build_object('allowed', false, 'reason',
    'Pro tuto motorku (' || v_moto.engine_cc || ' ccm) potřebujete skupinu ' ||
    v_required || '. Vaše skupiny: ' || v_groups);
END;
$_$;


ALTER FUNCTION "public"."check_license_for_moto"("p_moto_id" "uuid", "p_rental_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_moto_availability"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_exclude_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    conflict_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO conflict_count
    FROM bookings
    WHERE moto_id = p_moto_id
      AND status IN ('pending', 'reserved', 'active')
      AND id IS DISTINCT FROM p_exclude_booking_id
      AND start_date < p_end
      AND end_date > p_start;
    RETURN conflict_count = 0;
END;
$$;


ALTER FUNCTION "public"."check_moto_availability"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_exclude_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_one_active_sos"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_active_count int;
  v_booking_status text;
BEGIN
  IF NEW.type::text IN ('breakdown_minor', 'defect_question', 'location_share', 'other') THEN
    RETURN NEW;
  END IF;

  IF NEW.booking_id IS NULL THEN
    SELECT count(*) INTO v_active_count
    FROM sos_incidents
    WHERE user_id = NEW.user_id
      AND status::text NOT IN ('resolved', 'closed')
      AND type::text NOT IN ('breakdown_minor', 'defect_question', 'location_share', 'other');
    IF v_active_count > 0 THEN
      RAISE EXCEPTION 'Máte již aktivní SOS incident. Počkejte na vyřešení stávajícího incidentu velínem.';
    END IF;
    RETURN NEW;
  END IF;

  SELECT status::text INTO v_booking_status
  FROM bookings WHERE id = NEW.booking_id;

  IF v_booking_status IS NULL OR v_booking_status NOT IN ('reserved', 'active') THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_active_count
  FROM sos_incidents si
  WHERE si.booking_id = NEW.booking_id
    AND si.status::text NOT IN ('resolved', 'closed')
    AND si.type::text NOT IN ('breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'Na tuto rezervaci již existuje aktivní závažný SOS incident. Počkejte na vyřešení stávajícího incidentu.';
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN raise_exception THEN RAISE;
  WHEN OTHERS THEN
    RAISE NOTICE '[check_one_active_sos] unexpected error (allowing INSERT): %', SQLERRM;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_one_active_sos"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_trailer_overlap"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_units uuid[] := ARRAY[]::uuid[]; v_unit uuid;
BEGIN
  IF NEW.status NOT IN ('pending','reserved','active') THEN RETURN NEW; END IF;

  IF NEW.trailer_moto_id IS NOT NULL THEN
    v_units := array_append(v_units, NEW.trailer_moto_id);
  END IF;
  IF NEW.moto_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM motorcycles m WHERE m.id = NEW.moto_id AND m.is_trailer = true) THEN
    v_units := array_append(v_units, NEW.moto_id);
  END IF;
  IF array_length(v_units,1) IS NULL THEN RETURN NEW; END IF;

  FOREACH v_unit IN ARRAY v_units LOOP
    IF EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.id <> NEW.id
        AND (b.moto_id = v_unit OR b.trailer_moto_id = v_unit)
        AND b.status IN ('pending','reserved','active')
        AND b.start_date::date <= NEW.end_date::date
        AND b.end_date::date   >= NEW.start_date::date
    ) THEN
      RAISE EXCEPTION 'trailer_unavailable: %', v_unit USING ERRCODE = '23505';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."check_trailer_overlap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_user_booking_overlap"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- SOS replacement bookings are exempt from overlap check
  IF NEW.sos_replacement = true THEN
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


ALTER FUNCTION "public"."check_user_booking_overlap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_web_booking_email"("p_email" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
  SELECT jsonb_build_object(
    'exists', EXISTS(
      SELECT 1 FROM auth.users
      WHERE lower(email) = lower(trim(p_email))
        AND p_email IS NOT NULL
        AND trim(p_email) <> ''
    )
  );
$$;


ALTER FUNCTION "public"."check_web_booking_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_web_booking_user_overlap"("p_email" "text", "p_start" "date", "p_end" "date", "p_exclude_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_uid uuid;
  v_row record;
BEGIN
  IF p_email IS NULL OR trim(p_email) = '' OR p_start IS NULL OR p_end IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  SELECT id INTO v_uid FROM auth.users
   WHERE lower(email) = lower(trim(p_email))
   LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('overlap', false);  -- neznámý e-mail → žádná kolize
  END IF;

  SELECT b.id, b.start_date, b.end_date
    INTO v_row
    FROM bookings b
   WHERE b.user_id = v_uid
     AND b.status IN ('pending','reserved','active','completed')
     AND (p_exclude_booking_id IS NULL OR b.id <> p_exclude_booking_id)
     AND daterange(b.start_date::date, b.end_date::date, '[]')
         && daterange(p_start, p_end, '[]')
   ORDER BY b.start_date
   LIMIT 1;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('overlap', false);
  END IF;

  RETURN jsonb_build_object(
    'overlap',    true,
    'booking_id', v_row.id,
    'start_date', v_row.start_date,
    'end_date',   v_row.end_date
  );
END;
$$;


ALTER FUNCTION "public"."check_web_booking_user_overlap"("p_email" "text", "p_start" "date", "p_end" "date", "p_exclude_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_email_send"("p_booking_id" "uuid", "p_slug" "text", "p_window_minutes" integer DEFAULT 30) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_claimed boolean;
BEGIN
  INSERT INTO email_send_locks (booking_id, template_slug, locked_at)
  VALUES (p_booking_id, p_slug, now())
  ON CONFLICT (booking_id, template_slug) DO UPDATE
    SET locked_at = now()
    WHERE email_send_locks.locked_at < now() - make_interval(mins => GREATEST(p_window_minutes, 1))
  RETURNING true INTO v_claimed;
  RETURN COALESCE(v_claimed, false);
END $$;


ALTER FUNCTION "public"."claim_email_send"("p_booking_id" "uuid", "p_slug" "text", "p_window_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_all_test_data"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE 
  v_user_ids uuid[];
BEGIN
  -- Collect test user IDs before deleting profiles
  SELECT array_agg(id) INTO v_user_ids FROM profiles WHERE is_test_account = true;
  
  DELETE FROM sos_timeline WHERE incident_id IN (SELECT id FROM sos_incidents WHERE is_test = true);
  DELETE FROM messages WHERE thread_id IN (SELECT id FROM message_threads WHERE customer_id IN (SELECT id FROM profiles WHERE is_test_account = true));
  DELETE FROM message_threads WHERE customer_id IN (SELECT id FROM profiles WHERE is_test_account = true);
  DELETE FROM invoices WHERE booking_id IN (SELECT id FROM bookings WHERE is_test = true);
  DELETE FROM documents WHERE booking_id IN (SELECT id FROM bookings WHERE is_test = true);
  DELETE FROM bookings WHERE is_test = true;
  DELETE FROM sos_incidents WHERE is_test = true;
  DELETE FROM service_orders WHERE is_test = true;
  DELETE FROM maintenance_log WHERE is_test = true;
  DELETE FROM promo_codes WHERE is_test = true;
  DELETE FROM profiles WHERE is_test_account = true;
  
  -- Delete auth.users for test accounts
  IF v_user_ids IS NOT NULL THEN
    DELETE FROM auth.users WHERE id = ANY(v_user_ids);
  END IF;
  
  RETURN jsonb_build_object('ok', true, 'deleted_users', coalesce(array_length(v_user_ids, 1), 0));
END;
$$;


ALTER FUNCTION "public"."cleanup_all_test_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_old_verification_documents"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'storage'
    AS $$
DECLARE
  rec        record;
  removed    integer := 0;
  cutoff     timestamptz := now() - interval '3 years';
BEGIN
  FOR rec IN
    SELECT id, file_path
    FROM documents
    WHERE type IN ('id_card', 'drivers_license', 'passport', 'id_photo', 'license_photo')
      AND created_at < cutoff
  LOOP
    IF rec.file_path IS NOT NULL THEN
      DELETE FROM storage.objects
      WHERE bucket_id = 'documents' AND name = rec.file_path;
    END IF;
    DELETE FROM documents WHERE id = rec.id;
    removed := removed + 1;
  END LOOP;
  RETURN removed;
END;
$$;


ALTER FUNCTION "public"."cleanup_old_verification_documents"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_booking_surcharge"("p_booking_id" "uuid", "p_method" "text" DEFAULT 'bank_transfer'::"text", "p_vs" "text" DEFAULT NULL::"text", "p_paid_date" "date" DEFAULT NULL::"date", "p_transaction_ref" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b       bookings%ROWTYPE;
  v_due     numeric;
  v_url     text;
  v_key     text;
  v_payload jsonb;
  v_profile profiles%ROWTYPE;
  v_moto    text;
  v_app_msg text;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  v_due := COALESCE(v_b.mod_surcharge_due, 0);
  IF v_due <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_surcharge_pending');
  END IF;

  -- Potvrzení: vynulovat dluh, zapsat čas platby, payload vyčistit až PO odeslání.
  -- (Tento UPDATE nemění žádné pole sledované trg_booking_modified_email →
  -- trigger se neodpálí znovu.)
  UPDATE bookings
     SET mod_surcharge_due     = NULL,
         mod_surcharge_paid_at = COALESCE(p_paid_date::timestamptz, now()),
         payment_reference     = COALESCE(p_transaction_ref, payment_reference),
         updated_at            = now()
   WHERE id = p_booking_id;

  -- Odložený payload; fallback z aktuálního řádku (kdyby trigger payload neuložil).
  v_payload := v_b.mod_email_payload;
  IF v_payload IS NULL THEN
    SELECT * INTO v_profile FROM profiles WHERE id = v_b.user_id;
    SELECT model INTO v_moto FROM motorcycles WHERE id = v_b.moto_id;
    v_payload := jsonb_build_object(
      'booking_id',           v_b.id,
      'customer_email',       COALESCE(v_profile.email, ''),
      'customer_name',        COALESCE(v_profile.full_name, ''),
      'source',               COALESCE(v_b.booking_source, 'app'),
      'motorcycle',           COALESCE(v_moto, ''),
      'start_date',           v_b.start_date,
      'end_date',             v_b.end_date,
      'total_price',          v_b.total_price,
      'original_total_price', COALESCE(v_b.total_price, 0) - v_due
    );
  END IF;
  -- price_difference = skutečně zaplacený doplatek (rozdílový DP se vystaví na něj).
  v_payload := v_payload || jsonb_build_object('price_difference', v_due);

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  -- KROK 1: odložený booking_modified mail (izolovaně).
  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> ''
     AND COALESCE(v_payload->>'customer_email', '') <> '' THEN
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'Authorization', 'Bearer ' || v_key),
        body    := v_payload || jsonb_build_object('type', 'booking_modified')
      );
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('confirm_booking_surcharge', 'deferred_modified_mail_queued', 'info',
              jsonb_build_object('booking_id', p_booking_id, 'amount', v_due));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('confirm_booking_surcharge', 'deferred_modified_mail_failed', 'error', SQLERRM,
              jsonb_build_object('booking_id', p_booking_id));
    END;
  ELSE
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('confirm_booking_surcharge', 'deferred_mail_skipped_missing_cfg', 'info',
            jsonb_build_object('booking_id', p_booking_id,
                               'has_url', v_url IS NOT NULL, 'has_key', v_key IS NOT NULL,
                               'has_email', COALESCE(v_payload->>'customer_email', '') <> ''));
  END IF;

  -- KROK 2: dispatch custom šablon (izolovaně).
  BEGIN
    PERFORM dispatch_email_event('booking_updated', v_payload);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('confirm_booking_surcharge', 'dispatch_event_failed', 'error', SQLERRM,
            jsonb_build_object('booking_id', p_booking_id));
  END;

  -- KROK 3: in-app zpráva (appka Zprávy + FCM push) — izolovaně.
  BEGIN
    v_app_msg := 'Vaše rezervace č. ' || UPPER(RIGHT(v_b.id::text, 8))
      || ' byla upravena a doplatek ' || ROUND(v_due)::text
      || ' Kč jsme v pořádku přijali. Detaily a aktualizovanou smlouvu jsme poslali e-mailem.';
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (v_b.user_id, 'Rezervace upravena', v_app_msg, 'info');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('confirm_booking_surcharge', 'app_message_failed', 'error', SQLERRM,
            jsonb_build_object('booking_id', p_booking_id));
  END;

  -- Payload už není potřeba.
  UPDATE bookings SET mod_email_payload = NULL WHERE id = p_booking_id;

  RETURN jsonb_build_object('success', true, 'amount', v_due,
                            'vs', COALESCE(p_vs, v_b.mod_surcharge_vs));
END;
$$;


ALTER FUNCTION "public"."confirm_booking_surcharge"("p_booking_id" "uuid", "p_method" "text", "p_vs" "text", "p_paid_date" "date", "p_transaction_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_payment"("p_booking_id" "uuid", "p_method" "text" DEFAULT 'card'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_new_status text;
  v_row_count int;
  v_was_already_paid boolean := false;
  v_revived boolean := false;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rezervace nenalezena');
  END IF;

  -- Cílový stav: pending NEBO cancelled → reserved/active (podle start_date)
  IF v_booking.status IN ('pending', 'cancelled') THEN
    IF v_booking.start_date::date <= CURRENT_DATE THEN
      v_new_status := 'active';
    ELSE
      v_new_status := 'reserved';
    END IF;
    IF v_booking.status = 'cancelled' THEN
      v_revived := true;
    END IF;
  ELSE
    v_new_status := v_booking.status;
  END IF;

  BEGIN
    UPDATE bookings SET
      payment_status = 'paid',
      payment_method = p_method,
      status = v_new_status::booking_status,
      confirmed_at = CASE
        WHEN v_booking.status IN ('pending','cancelled') AND confirmed_at IS NULL
        THEN now() ELSE confirmed_at END,
      picked_up_at = CASE
        WHEN v_booking.status IN ('pending','cancelled')
          AND v_new_status = 'active'
          AND picked_up_at IS NULL
        THEN now() ELSE picked_up_at END,
      cancelled_at          = CASE WHEN v_revived THEN NULL ELSE cancelled_at END,
      cancelled_by          = CASE WHEN v_revived THEN NULL ELSE cancelled_by END,
      cancelled_by_source   = CASE WHEN v_revived THEN NULL ELSE cancelled_by_source END,
      cancellation_reason   = CASE WHEN v_revived THEN NULL ELSE cancellation_reason END,
      cancellation_notified = CASE WHEN v_revived THEN false ELSE cancellation_notified END
    WHERE id = p_booking_id
      AND payment_status <> 'paid';

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_was_already_paid := (v_row_count = 0);

    IF v_revived AND NOT v_was_already_paid THEN
      BEGIN
        INSERT INTO debug_log (source, action, component, status, request_data)
        VALUES ('confirm_payment', 'cancelled_booking_revived', 'booking', 'ok',
                jsonb_build_object('booking_id', p_booking_id,
                                   'previous_status', v_booking.status,
                                   'new_status', v_new_status,
                                   'previous_cancelled_by_source', v_booking.cancelled_by_source));
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'was_already_paid', v_was_already_paid,
      'revived', v_revived AND NOT v_was_already_paid,
      'new_status', v_new_status,
      'transaction_id', 'TXN-' || substr(p_booking_id::text, 1, 8)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'confirm_payment failed: %', SQLERRM;
    RETURN jsonb_build_object('success', false, 'error', 'Potvrzení platby selhalo: ' || SQLERRM);
  END;
END;
$$;


ALTER FUNCTION "public"."confirm_payment"("p_booking_id" "uuid", "p_method" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_shop_payment"("p_order_id" "uuid", "p_method" "text" DEFAULT 'card'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order   shop_orders%ROWTYPE;
  v_updated shop_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Objednávka nenalezena');
  END IF;

  -- Ověření vlastníka nebo admina.
  -- service_role (webhook) má auth.uid()=NULL → porovnání je NULL → projde.
  -- Anonymní web voucher (customer_id IS NULL) také projde.
  IF v_order.customer_id IS NOT NULL
     AND v_order.customer_id <> auth.uid()
     AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nemáte oprávnění');
  END IF;

  -- ATOMIC dedup: jen JEDNA paralelní Stripe webhook session projde
  -- UPDATE … WHERE payment_status <> 'paid'. Druhý event nezmění žádný řádek
  -- → was_already_paid=true a webhook skipne mail/dokumenty/voucher.
  UPDATE shop_orders SET
    payment_status = 'paid',
    payment_method = p_method,
    confirmed_at   = COALESCE(confirmed_at, now()),
    status         = CASE WHEN status = 'new' THEN 'confirmed' ELSE status END
  WHERE id = p_order_id
    AND payment_status IS DISTINCT FROM 'paid'
  RETURNING * INTO v_updated;

  IF NOT FOUND THEN
    -- Objednávka už byla 'paid' → duplicitní event, žádný side-effect
    RETURN jsonb_build_object(
      'success', true,
      'order_id', p_order_id,
      'was_already_paid', true,
      'transaction_id', 'TXN-SHOP-' || substr(p_order_id::text, 1, 8)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'was_already_paid', false,
    'transaction_id', 'TXN-SHOP-' || substr(p_order_id::text, 1, 8)
  );
END;
$$;


ALTER FUNCTION "public"."confirm_shop_payment"("p_order_id" "uuid", "p_method" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."motorcycles" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "branch_id" "uuid",
    "model" "text" NOT NULL,
    "vin" "text",
    "spz" "text",
    "category" "text" NOT NULL,
    "license_required" "public"."license_group" DEFAULT 'A'::"public"."license_group",
    "power_kw" numeric(6,1) DEFAULT 0,
    "engine_cc" integer DEFAULT 0,
    "weight_kg" integer DEFAULT 0,
    "seat_height_mm" integer DEFAULT 0,
    "fuel_tank_l" numeric(4,1) DEFAULT 0,
    "price_weekday" numeric(10,2) DEFAULT 0,
    "price_weekend" numeric(10,2) DEFAULT 0,
    "price_mon" numeric(10,2),
    "price_tue" numeric(10,2),
    "price_wed" numeric(10,2),
    "price_thu" numeric(10,2),
    "price_fri" numeric(10,2),
    "price_sat" numeric(10,2),
    "price_sun" numeric(10,2),
    "status" "public"."moto_status" DEFAULT 'active'::"public"."moto_status",
    "mileage" integer DEFAULT 0,
    "image_url" "text",
    "images" "text"[] DEFAULT '{}'::"text"[],
    "features" "text"[] DEFAULT '{}'::"text"[],
    "description" "text",
    "manual_url" "text",
    "last_service_date" "date",
    "next_service_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "year" integer,
    "color" "text",
    "deposit_amount" numeric(10,2) DEFAULT 5000,
    "insurance_price" numeric(10,2) DEFAULT 0,
    "min_rental_days" integer DEFAULT 1,
    "max_rental_days" integer DEFAULT 30,
    "stk_valid_until" "date",
    "oil_interval_km" integer DEFAULT 10000,
    "oil_interval_days" integer DEFAULT 365,
    "tire_interval_km" integer DEFAULT 15000,
    "full_service_interval_km" integer DEFAULT 20000,
    "full_service_interval_days" integer DEFAULT 730,
    "acquired_at" "date",
    "torque_nm" numeric(6,1),
    "has_abs" boolean DEFAULT true,
    "has_asc" boolean DEFAULT false,
    "ideal_usage" "text"[],
    "engine_type" "text",
    "power_hp" integer,
    "box_number" integer,
    "brand" "text",
    "purchase_price" numeric DEFAULT 0,
    "purchase_mileage" integer,
    "unavailable_until" timestamp with time zone,
    "tracking_unit" "text" DEFAULT 'km'::"text",
    "unavailable_reason" "text",
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "transmission" "text",
    "drivetrain" "text",
    "top_speed_kmh" integer,
    "fuel_consumption_l100km" numeric(4,2),
    "fuel_type" "text",
    "brake_type" "text",
    "seats_count" integer,
    "suitable_for" "text",
    "manual_external_url" "text",
    "short_desc_fields" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "image_alts" "text"[] DEFAULT '{}'::"text"[],
    "videos" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "license_groups" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "is_trailer" boolean DEFAULT false NOT NULL,
    "sort_order" integer,
    CONSTRAINT "motorcycles_drivetrain_check" CHECK ((("drivetrain" IS NULL) OR ("drivetrain" = ANY (ARRAY['chain'::"text", 'shaft'::"text", 'belt'::"text"])))),
    CONSTRAINT "motorcycles_tracking_unit_check" CHECK (("tracking_unit" = ANY (ARRAY['km'::"text", 'mh'::"text"])))
);


ALTER TABLE "public"."motorcycles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."motorcycles"."brand" IS 'Značka motorky (Honda, Yamaha, BMW...)';



COMMENT ON COLUMN "public"."motorcycles"."purchase_price" IS 'Pořizovací cena motorky v Kč';



COMMENT ON COLUMN "public"."motorcycles"."manual_external_url" IS 'Externí URL na návod k motorce (např. odkaz na stránku výrobce). Použije se pouze pokud není nahráno PDF (manual_url je prázdné).';



COMMENT ON COLUMN "public"."motorcycles"."image_alts" IS 'Per-fotka SEO popisek (paralelní index s images[]). Admin vyplňuje jen krátký popisek (např. „zepředu"), PHP složí finální alt jako "{model} {color} – {popisek}".';



COMMENT ON COLUMN "public"."motorcycles"."videos" IS 'Pole veřejných URL MP4 videí motorky (bucket media). Web: hero banner + detail + rezervace krok 2. App: detail. Přehled/seznam vždy fotka.';



COMMENT ON COLUMN "public"."motorcycles"."sort_order" IS 'Ruční pořadí zobrazení (1-X) na webu: vyber stroj, katalog, hero banner. NULL = neřazeno (řadí se za očíslované dle modelu, nullslast).';



CREATE OR REPLACE FUNCTION "public"."correct_motorcycle_mileage"("p_moto_id" "uuid", "p_km" integer, "p_note" "text" DEFAULT NULL::"text") RETURNS "public"."motorcycles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_row motorcycles%ROWTYPE;
  v_admin uuid := auth.uid();
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_km IS NULL OR p_km < 0 THEN
    RAISE EXCEPTION 'invalid_km';
  END IF;

  UPDATE motorcycles
     SET mileage = GREATEST(p_km, COALESCE(purchase_mileage, 0))
   WHERE id = p_moto_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'moto_not_found';
  END IF;

  BEGIN
    INSERT INTO admin_audit_log(admin_id, action, entity_type, entity_id, new_data)
    VALUES (v_admin, 'motorcycle_mileage_corrected', 'motorcycles', p_moto_id,
            jsonb_build_object('new_km', v_row.mileage, 'requested_km', p_km, 'note', p_note));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."correct_motorcycle_mileage"("p_moto_id" "uuid", "p_km" integer, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_api_key"("p_partner_name" "text", "p_partner_email" "text", "p_partner_url" "text" DEFAULT NULL::"text", "p_rate_limit_rpm" integer DEFAULT 1000, "p_scopes" "text"[] DEFAULT ARRAY['read'::"text"]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_raw_key text;
  v_hash text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  v_raw_key := 'mk_live_' || replace(replace(replace(encode(gen_random_bytes(32), 'base64'), '+', '-'), '/', '_'), '=', '');
  v_hash := encode(digest(v_raw_key, 'sha256'), 'hex');
  v_prefix := substring(v_raw_key, 1, 16);

  INSERT INTO api_keys (key_hash, key_prefix, partner_name, partner_email, partner_url, rate_limit_rpm, scopes, created_by)
  VALUES (v_hash, v_prefix, p_partner_name, p_partner_email, p_partner_url, p_rate_limit_rpm, p_scopes, auth.uid())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'api_key', v_raw_key,
    'prefix', v_prefix,
    'warning', 'Tento klíč se zobrazí jen jednou. Uložte ho bezpečně.'
  );
END;
$$;


ALTER FUNCTION "public"."create_api_key"("p_partner_name" "text", "p_partner_email" "text", "p_partner_url" "text", "p_rate_limit_rpm" integer, "p_scopes" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_gear_purchase_order"("p_shortage_id" "uuid", "p_qty" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  return public._create_gear_po(p_shortage_id, p_qty);
end $$;


ALTER FUNCTION "public"."create_gear_purchase_order"("p_shortage_id" "uuid", "p_qty" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_shop_order"("p_items" "jsonb", "p_shipping_method" "text" DEFAULT 'post'::"text", "p_shipping_address" "jsonb" DEFAULT NULL::"jsonb", "p_payment_method" "text" DEFAULT 'card'::"text", "p_promo_code" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_uid uuid; v_profile profiles%ROWTYPE; v_order_id uuid;
  v_subtotal numeric := 0; v_shipping_cost numeric := 0; v_discount numeric := 0;
  v_promo_result jsonb; v_item jsonb; v_addr text;
  v_pid uuid; v_size text; v_qty integer; v_avail integer;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Neprihlasen'); END IF;
  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_subtotal := v_subtotal + (v_item->>'price')::numeric * (v_item->>'qty')::integer;
  END LOOP;
  IF v_subtotal <= 0 THEN RETURN jsonb_build_object('error','Prazdna objednavka'); END IF;

  -- NOVÉ: kontrola skladu (per-size, jen pro položky s product_id)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_pid := NULLIF(v_item->>'product_id','')::uuid;
    v_size := NULLIF(v_item->>'size','');
    v_qty := (v_item->>'qty')::integer;
    IF v_pid IS NOT NULL THEN
      IF v_size IS NOT NULL THEN
        SELECT COALESCE((size_stock->>v_size)::integer,0) INTO v_avail FROM products WHERE id = v_pid;
      ELSE
        SELECT COALESCE(stock_quantity,0) INTO v_avail FROM products WHERE id = v_pid;
      END IF;
      IF v_avail < v_qty THEN
        RETURN jsonb_build_object('error','out_of_stock','product_id',v_pid,'size',v_size,'available',v_avail,'requested',v_qty);
      END IF;
    END IF;
  END LOOP;

  IF p_shipping_method = 'post' THEN v_shipping_cost := 99; END IF;

  -- Sleva: % ze subtotalu (BEZE ZMĚNY — viz pozn. C4 níže)
  IF p_promo_code IS NOT NULL AND p_promo_code <> '' THEN
    v_promo_result := validate_promo_code(p_promo_code);
    IF (v_promo_result->>'valid')::boolean THEN
      IF v_promo_result->>'type' = 'percent' THEN
        v_discount := ROUND(v_subtotal * (v_promo_result->>'value')::numeric / 100);
      ELSE
        v_discount := (v_promo_result->>'value')::numeric;
      END IF;
      UPDATE promo_codes SET used_count = COALESCE(used_count,0)+1 WHERE id = (v_promo_result->>'id')::uuid;
    END IF;
  END IF;

  IF p_shipping_address IS NOT NULL THEN
    v_addr := COALESCE(p_shipping_address->>'name', v_profile.full_name) || ', ' ||
              COALESCE(p_shipping_address->>'street', v_profile.street) || ', ' ||
              COALESCE(p_shipping_address->>'zip', v_profile.zip) || ' ' ||
              COALESCE(p_shipping_address->>'city', v_profile.city);
  END IF;

  INSERT INTO shop_orders (
    customer_id, customer_name, customer_email, customer_phone,
    shipping_address, status, payment_status, payment_method,
    subtotal, shipping_cost, discount, total, promo_code_id
  ) VALUES (
    v_uid, v_profile.full_name, v_profile.email, v_profile.phone,
    v_addr, 'new', 'pending', p_payment_method,
    v_subtotal, v_shipping_cost, v_discount, v_subtotal + v_shipping_cost - v_discount,
    CASE WHEN v_promo_result IS NOT NULL AND (v_promo_result->>'valid')::boolean
         THEN (v_promo_result->>'id')::uuid ELSE NULL END
  ) RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_pid := NULLIF(v_item->>'product_id','')::uuid;
    v_size := NULLIF(v_item->>'size','');
    v_qty := (v_item->>'qty')::integer;
    -- NOVÉ: ukládáme product_id + size
    INSERT INTO shop_order_items (order_id, product_id, product_name, product_sku, size, quantity, unit_price, total_price)
    VALUES (v_order_id, v_pid, v_item->>'name', v_item->>'id', v_size, v_qty,
            (v_item->>'price')::numeric, (v_item->>'price')::numeric * v_qty);
    -- NOVÉ: dekrement skladu
    IF v_pid IS NOT NULL THEN
      IF v_size IS NOT NULL THEN
        UPDATE products SET
          size_stock = jsonb_set(COALESCE(size_stock,'{}'::jsonb), ARRAY[v_size],
            to_jsonb(GREATEST(COALESCE((size_stock->>v_size)::integer,0) - v_qty, 0))),
          stock_quantity = GREATEST(COALESCE(stock_quantity,0) - v_qty, 0)
          WHERE id = v_pid;
      ELSE
        UPDATE products SET stock_quantity = GREATEST(COALESCE(stock_quantity,0) - v_qty, 0)
          WHERE id = v_pid;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id);
END;
$$;


ALTER FUNCTION "public"."create_shop_order"("p_items" "jsonb", "p_shipping_method" "text", "p_shipping_address" "jsonb", "p_payment_method" "text", "p_promo_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_sos_incident"("p_type" "public"."sos_type", "p_booking_id" "uuid" DEFAULT NULL::"uuid", "p_lat" numeric DEFAULT NULL::numeric, "p_lng" numeric DEFAULT NULL::numeric, "p_description" "text" DEFAULT NULL::"text", "p_is_fault" boolean DEFAULT NULL::boolean) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_id UUID;
    v_moto_id UUID;
BEGIN
    IF p_booking_id IS NOT NULL THEN
        SELECT moto_id INTO v_moto_id FROM bookings WHERE id = p_booking_id AND user_id = auth.uid();
    END IF;

    INSERT INTO sos_incidents (user_id, booking_id, moto_id, type, latitude, longitude, description, is_customer_fault)
    VALUES (auth.uid(), p_booking_id, v_moto_id, p_type, p_lat, p_lng, p_description, p_is_fault)
    RETURNING id INTO v_id;

    INSERT INTO sos_timeline (incident_id, action, performed_by, data)
    VALUES (v_id, 'reported', auth.uid(), jsonb_build_object('type', p_type::TEXT, 'lat', p_lat, 'lng', p_lng));

    RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."create_sos_incident"("p_type" "public"."sos_type", "p_booking_id" "uuid", "p_lat" numeric, "p_lng" numeric, "p_description" "text", "p_is_fault" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_test_booking"("p_user_id" "uuid", "p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO bookings (user_id, moto_id, start_date, end_date, status, payment_status, booking_source, is_test)
  VALUES (p_user_id, p_moto_id, p_start, p_end, 'reserved', 'unpaid', 'app', true)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."create_test_booking"("p_user_id" "uuid", "p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_test_customer"("p_email" "text", "p_full_name" "text", "p_phone" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_id uuid;
BEGIN
  -- Check if profile already exists (from previous auth.signUp)
  SELECT id INTO v_id FROM profiles WHERE email = p_email LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE profiles SET full_name = p_full_name, phone = p_phone, is_test_account = true WHERE id = v_id;
    RETURN v_id;
  END IF;
  -- Check auth.users
  SELECT id INTO v_id FROM auth.users WHERE email = p_email LIMIT 1;
  IF v_id IS NOT NULL THEN
    INSERT INTO profiles (id, email, full_name, phone, is_test_account)
    VALUES (v_id, p_email, p_full_name, p_phone, true)
    ON CONFLICT (id) DO UPDATE SET full_name = p_full_name, phone = p_phone, is_test_account = true;
    RETURN v_id;
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."create_test_customer"("p_email" "text", "p_full_name" "text", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_test_maintenance_log"("p_moto_id" "uuid", "p_service_type" "text", "p_description" "text", "p_labor_hours" numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO maintenance_log (moto_id, service_type, description, labor_hours, service_date, status, is_test)
  VALUES (p_moto_id, p_service_type, p_description, p_labor_hours, CURRENT_DATE, 'completed', true)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."create_test_maintenance_log"("p_moto_id" "uuid", "p_service_type" "text", "p_description" "text", "p_labor_hours" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_test_service_order"("p_moto_id" "uuid", "p_type" "text", "p_notes" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO service_orders (moto_id, type, notes, status, is_test)
  VALUES (p_moto_id, p_type, p_notes, 'pending', true)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."create_test_service_order"("p_moto_id" "uuid", "p_type" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_test_sos_incident"("p_user_id" "uuid", "p_booking_id" "uuid", "p_moto_id" "uuid", "p_type" "public"."sos_type", "p_description" "text", "p_lat" numeric, "p_lng" numeric) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO sos_incidents (user_id, booking_id, moto_id, type, description, status, latitude, longitude, is_test)
  VALUES (p_user_id, p_booking_id, p_moto_id, p_type, p_description, 'reported', p_lat, p_lng, true)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


ALTER FUNCTION "public"."create_test_sos_incident"("p_user_id" "uuid", "p_booking_id" "uuid", "p_moto_id" "uuid", "p_type" "public"."sos_type", "p_description" "text", "p_lat" numeric, "p_lng" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_test_sos_timeline"("p_incident_id" "uuid", "p_action" "text", "p_data" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, data) VALUES (p_incident_id, p_action, p_data);
END;
$$;


ALTER FUNCTION "public"."create_test_sos_timeline"("p_incident_id" "uuid", "p_action" "text", "p_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text" DEFAULT ''::"text", "p_city" "text" DEFAULT ''::"text", "p_zip" "text" DEFAULT ''::"text", "p_country" "text" DEFAULT 'CZ'::"text", "p_note" "text" DEFAULT ''::"text", "p_pickup_time" time without time zone DEFAULT NULL::time without time zone, "p_delivery_address" "text" DEFAULT NULL::"text", "p_return_address" "text" DEFAULT NULL::"text", "p_extras" "jsonb" DEFAULT '[]'::"jsonb", "p_discount_amount" numeric DEFAULT 0, "p_discount_code" "text" DEFAULT NULL::"text", "p_promo_code" "text" DEFAULT NULL::"text", "p_voucher_id" "uuid" DEFAULT NULL::"uuid", "p_license_group" "text" DEFAULT NULL::"text", "p_password" "text" DEFAULT NULL::"text", "p_helmet_size" "text" DEFAULT NULL::"text", "p_jacket_size" "text" DEFAULT NULL::"text", "p_pants_size" "text" DEFAULT NULL::"text", "p_boots_size" "text" DEFAULT NULL::"text", "p_gloves_size" "text" DEFAULT NULL::"text", "p_passenger_helmet_size" "text" DEFAULT NULL::"text", "p_passenger_jacket_size" "text" DEFAULT NULL::"text", "p_passenger_gloves_size" "text" DEFAULT NULL::"text", "p_passenger_boots_size" "text" DEFAULT NULL::"text", "p_return_time" "text" DEFAULT NULL::"text", "p_existing_booking_id" "uuid" DEFAULT NULL::"uuid", "p_passenger_pants_size" "text" DEFAULT NULL::"text", "p_consent_vop" boolean DEFAULT NULL::boolean, "p_consent_gdpr" boolean DEFAULT NULL::boolean, "p_marketing_consent" boolean DEFAULT NULL::boolean, "p_consent_photo" boolean DEFAULT NULL::boolean, "p_date_of_birth" "text" DEFAULT NULL::"text", "p_trailer_moto_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid;
  v_booking_id uuid;
  v_moto record;
  v_existing_auth_id uuid;
  v_existing_booking record;
  v_reuse_booking boolean := false;
  v_total numeric;
  v_extras_total numeric := 0;
  v_extra record;
  v_is_new_user boolean := false;
  v_allowed_groups text[];
  v_moto_license text;
  v_moto_groups text[];
  v_promo_id uuid := NULL;
  v_promo_type text;
  v_promo_value numeric;
  v_voucher_amount numeric;
  v_current_date date;
  v_day_of_week integer;
  v_day_price numeric;
  v_dob date;
  v_late_discount numeric := 0;
  v_codes text[];
  v_code text;
  v_sum_discount numeric := 0;
  v_seen text[] := ARRAY[]::text[];
  v_voucher_ids uuid[] := ARRAY[]::uuid[];
  v_promo_id_tmp uuid;
  v_voucher_id_tmp uuid;
  v_bd jsonb := '[]'::jsonb;          -- NEW: sběr slev pro booking_discounts
  v_voucher_code text;                -- NEW: kód voucheru z legacy p_voucher_id větve
BEGIN
  -- 1) VALIDACE
  IF p_email IS NULL OR trim(p_email) = '' THEN
    RETURN jsonb_build_object('error','Email je povinný');
  END IF;
  IF p_moto_id IS NULL THEN
    RETURN jsonb_build_object('error','Motorka není vybrána');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN jsonb_build_object('error','Neplatný termín rezervace');
  END IF;

  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN
      v_dob := p_date_of_birth::date;
    EXCEPTION WHEN OTHERS THEN
      v_dob := NULL;
    END;
  END IF;

  -- 2) MOTORKA + ŘP
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF v_moto.id IS NULL THEN
    RETURN jsonb_build_object('error','Motorka nenalezena');
  END IF;

  IF v_moto.license_groups IS NOT NULL AND array_length(v_moto.license_groups, 1) >= 1 THEN
    SELECT array_agg(upper(btrim(x))) INTO v_moto_groups
      FROM unnest(v_moto.license_groups) AS x
      WHERE btrim(x) <> '';
  END IF;
  IF v_moto_groups IS NULL OR array_length(v_moto_groups, 1) IS NULL THEN
    v_moto_groups := ARRAY[upper(COALESCE(v_moto.license_required::text, 'A'))];
  END IF;
  v_moto_license := COALESCE(v_moto.license_required::text, 'A');

  IF NOT ('N' = ANY(v_moto_groups)) AND p_license_group IS NOT NULL AND p_license_group <> '' THEN
    CASE upper(p_license_group)
      WHEN 'A'  THEN v_allowed_groups := ARRAY['A','A2','A1','AM'];
      WHEN 'A2' THEN v_allowed_groups := ARRAY['A2','A1','AM'];
      WHEN 'A1' THEN v_allowed_groups := ARRAY['A1','AM'];
      WHEN 'AM' THEN v_allowed_groups := ARRAY['AM'];
      WHEN 'B'  THEN v_allowed_groups := ARRAY['B','AM'];
      ELSE
        RETURN jsonb_build_object('error','Neplatná skupina ŘP: '||p_license_group);
    END CASE;
    IF NOT (v_moto_groups && v_allowed_groups) THEN
      RETURN jsonb_build_object('error','Pro tuto motorku potřebujete ŘP skupiny '||array_to_string(v_moto_groups,' / ')||'. Vaše skupina: '||p_license_group);
    END IF;
  END IF;

  -- 3) DEDUPLIKACE ZÁKAZNÍKA + UPSERT profilu
  SELECT id INTO v_existing_auth_id
    FROM auth.users
    WHERE lower(email) = lower(trim(p_email))
    LIMIT 1;

  IF v_existing_auth_id IS NOT NULL
     AND p_existing_booking_id IS NULL
     AND current_user = 'anon' THEN
    RETURN jsonb_build_object(
      'error', 'email_exists',
      'message', 'Tento e-mail je v systému. Pro pokračování se přihlaste, nebo si obnovte heslo.'
    );
  END IF;

  IF v_existing_auth_id IS NOT NULL
     AND auth.uid() IS NOT NULL
     AND auth.uid() <> v_existing_auth_id THEN
    RETURN jsonb_build_object(
      'error', 'email_mismatch',
      'message', 'Přihlášený účet nesouhlasí se zadaným e-mailem.'
    );
  END IF;

  IF v_existing_auth_id IS NOT NULL THEN
    v_user_id := v_existing_auth_id;

    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country,
                          registration_source, license_group, date_of_birth,
                          consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (
      v_user_id, p_name, lower(trim(p_email)), p_phone,
      p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> ''
           THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob,
      COALESCE(p_consent_vop, true),
      COALESCE(p_consent_gdpr, true),
      COALESCE(p_marketing_consent, true),
      COALESCE(p_consent_photo, true)
    )
    ON CONFLICT (id) DO UPDATE SET
      phone = CASE WHEN EXCLUDED.phone IS NOT NULL AND EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE profiles.phone END,
      street = CASE WHEN EXCLUDED.street <> '' THEN EXCLUDED.street ELSE profiles.street END,
      city = CASE WHEN EXCLUDED.city <> '' THEN EXCLUDED.city ELSE profiles.city END,
      zip = CASE WHEN EXCLUDED.zip <> '' THEN EXCLUDED.zip ELSE profiles.zip END,
      country = CASE WHEN EXCLUDED.country <> '' AND EXCLUDED.country <> 'CZ' THEN EXCLUDED.country ELSE profiles.country END,
      full_name = CASE WHEN profiles.full_name IS NULL OR profiles.full_name = '' THEN EXCLUDED.full_name ELSE profiles.full_name END,
      license_group = CASE
        WHEN EXCLUDED.license_group IS NOT NULL
             AND (profiles.license_group IS NULL OR array_length(profiles.license_group, 1) IS NULL)
        THEN EXCLUDED.license_group
        ELSE profiles.license_group
      END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth),
      registration_source = COALESCE(profiles.registration_source, 'web'),
      consent_vop = COALESCE(p_consent_vop, profiles.consent_vop),
      consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent),
      consent_photo = COALESCE(p_consent_photo, profiles.consent_photo),
      updated_at = now();

    IF p_password IS NOT NULL AND p_password <> '' THEN
      UPDATE auth.users
        SET encrypted_password = crypt(p_password, gen_salt('bf')),
            updated_at = now()
        WHERE id = v_user_id;
    END IF;
  ELSE
    v_user_id := gen_random_uuid();
    v_is_new_user := true;

    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password,
      email_confirmed_at, aud, role,
      raw_user_meta_data, created_at, updated_at
    ) VALUES (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      lower(trim(p_email)),
      crypt(COALESCE(NULLIF(p_password,''), gen_random_uuid()::text), gen_salt('bf')),
      now(), 'authenticated', 'authenticated',
      jsonb_build_object('full_name', p_name, 'phone', p_phone),
      now(), now()
    );

    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country,
                          registration_source, license_group, date_of_birth,
                          consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (
      v_user_id, p_name, lower(trim(p_email)), p_phone,
      p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> ''
           THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob,
      COALESCE(p_consent_vop, true),
      COALESCE(p_consent_gdpr, true),
      COALESCE(p_marketing_consent, true),
      COALESCE(p_consent_photo, true)
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = COALESCE(NULLIF(profiles.full_name,''), EXCLUDED.full_name),
      phone = COALESCE(NULLIF(EXCLUDED.phone,''), profiles.phone),
      street = COALESCE(NULLIF(EXCLUDED.street,''), profiles.street),
      city = COALESCE(NULLIF(EXCLUDED.city,''), profiles.city),
      zip = COALESCE(NULLIF(EXCLUDED.zip,''), profiles.zip),
      country = EXCLUDED.country,
      registration_source = COALESCE(profiles.registration_source,'web'),
      license_group = CASE
        WHEN EXCLUDED.license_group IS NOT NULL
             AND (profiles.license_group IS NULL OR array_length(profiles.license_group,1) IS NULL)
        THEN EXCLUDED.license_group
        ELSE profiles.license_group
      END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth),
      consent_vop = COALESCE(p_consent_vop, profiles.consent_vop),
      consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent),
      consent_photo = COALESCE(p_consent_photo, profiles.consent_photo),
      updated_at = now();
  END IF;

  -- 3c) RE-USE PENDING REZERVACE
  IF p_existing_booking_id IS NOT NULL THEN
    SELECT id, user_id, status, payment_status, booking_source
      INTO v_existing_booking
      FROM bookings WHERE id = p_existing_booking_id LIMIT 1;
    IF v_existing_booking.id IS NOT NULL
       AND v_existing_booking.user_id = v_user_id
       AND v_existing_booking.status = 'pending'
       AND v_existing_booking.payment_status = 'unpaid'
       AND v_existing_booking.booking_source = 'web' THEN
      v_reuse_booking := true;
    END IF;
  END IF;

  -- 4) OVERLAP
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = p_moto_id
      AND status IN ('pending','reserved','active')
      AND tstzrange(start_date, end_date,'[]') && tstzrange(p_start_date, p_end_date,'[]')
      AND (NOT v_reuse_booking OR id <> p_existing_booking_id)
      AND NOT (
        user_id = v_user_id
        AND status = 'pending'
        AND payment_status = 'unpaid'
        AND booking_source = 'web'
      )
  ) THEN
    RETURN jsonb_build_object('error','Booking overlap — motorka není v termínu dostupná');
  END IF;

  -- 5) CENA
  v_total := 0;
  v_current_date := p_start_date::date;
  WHILE v_current_date <= p_end_date::date LOOP
    v_day_of_week := EXTRACT(DOW FROM v_current_date)::integer;
    v_day_price := CASE v_day_of_week
      WHEN 0 THEN COALESCE(v_moto.price_sun, v_moto.price_weekday, 0)
      WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekday, 0)
    END;
    v_total := v_total + v_day_price;
    v_current_date := v_current_date + 1;
  END LOOP;
  IF v_total = 0 THEN v_total := COALESCE(v_moto.price_weekday,0); END IF;

  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extras_total := v_extras_total
        + COALESCE((v_extra.value->>'unit_price')::numeric,0)
        * COALESCE((v_extra.value->>'quantity')::numeric,1);
    END LOOP;
  END IF;
  v_total := v_total + v_extras_total;

  -- 5b) SLEVA 50 % NA 1. DEN
  v_late_discount := public._late_pickup_discount(p_moto_id, p_start_date, p_end_date, p_pickup_time);
  IF v_late_discount > 0 THEN
    v_total := GREATEST(0, v_total - v_late_discount);
  END IF;

  -- 5c) SLEVY
  p_discount_amount := 0;
  v_sum_discount := 0;
  v_promo_id := NULL;

  IF p_discount_code IS NOT NULL AND btrim(p_discount_code) <> '' THEN
    v_codes := string_to_array(p_discount_code, ',');
  ELSIF p_promo_code IS NOT NULL AND p_promo_code <> '' THEN
    v_codes := ARRAY[p_promo_code];
  ELSE
    v_codes := ARRAY[]::text[];
  END IF;

  IF v_codes IS NOT NULL THEN
    FOREACH v_code IN ARRAY v_codes LOOP
      v_code := upper(btrim(v_code));
      CONTINUE WHEN v_code = '' OR v_code = ANY(v_seen);
      v_seen := array_append(v_seen, v_code);

      SELECT id, type, value INTO v_promo_id_tmp, v_promo_type, v_promo_value
        FROM promo_codes WHERE upper(code) = v_code AND active = true LIMIT 1;
      IF v_promo_id_tmp IS NOT NULL THEN
        IF v_promo_type = 'percent' THEN
          v_sum_discount := v_sum_discount + ROUND(v_total * v_promo_value / 100);
        ELSE
          v_sum_discount := v_sum_discount + COALESCE(v_promo_value, 0);
        END IF;
        IF v_promo_id IS NULL THEN v_promo_id := v_promo_id_tmp; END IF;
        v_bd := v_bd || jsonb_build_object(            -- NEW
          'kind','promo_code','code',v_code,
          'promo_code_id',v_promo_id_tmp::text,'voucher_id',NULL,
          'discount_type',v_promo_type,'value',COALESCE(v_promo_value,0));
        CONTINUE;
      END IF;

      SELECT id, amount INTO v_voucher_id_tmp, v_voucher_amount
        FROM vouchers WHERE upper(code) = v_code AND status = 'active' LIMIT 1;
      IF v_voucher_id_tmp IS NOT NULL THEN
        v_sum_discount := v_sum_discount + COALESCE(v_voucher_amount, 0);
        v_voucher_ids := array_append(v_voucher_ids, v_voucher_id_tmp);
        v_bd := v_bd || jsonb_build_object(            -- NEW
          'kind','voucher','code',v_code,
          'promo_code_id',NULL,'voucher_id',v_voucher_id_tmp::text,
          'discount_type','fixed','value',COALESCE(v_voucher_amount,0));
      END IF;
    END LOOP;
  END IF;

  IF p_voucher_id IS NOT NULL AND NOT (p_voucher_id = ANY(v_voucher_ids)) THEN
    SELECT code, amount INTO v_voucher_code, v_voucher_amount
      FROM vouchers WHERE id = p_voucher_id AND status = 'active';
    IF v_voucher_amount IS NOT NULL THEN
      v_sum_discount := v_sum_discount + v_voucher_amount;
      v_voucher_ids := array_append(v_voucher_ids, p_voucher_id);
      v_bd := v_bd || jsonb_build_object(              -- NEW
        'kind','voucher','code',COALESCE(upper(v_voucher_code),'VOUCHER'),
        'promo_code_id',NULL,'voucher_id',p_voucher_id::text,
        'discount_type','fixed','value',COALESCE(v_voucher_amount,0));
    END IF;
  END IF;

  IF p_voucher_id IS NULL AND array_length(v_voucher_ids, 1) IS NOT NULL THEN
    p_voucher_id := v_voucher_ids[1];
  END IF;

  p_discount_amount := LEAST(GREATEST(v_sum_discount, 0), v_total);
  IF p_discount_amount > 0 THEN v_total := GREATEST(0, v_total - p_discount_amount); END IF;

  -- 6) UPDATE / INSERT BOOKING
  IF v_reuse_booking THEN
    UPDATE bookings SET
      moto_id = p_moto_id, start_date = p_start_date, end_date = p_end_date,
      total_price = v_total, extras_price = v_extras_total,
      late_pickup_discount_amount = v_late_discount,
      pickup_time = p_pickup_time, pickup_address = p_delivery_address,
      return_address = p_return_address, return_time = p_return_time,
      discount_amount = p_discount_amount, discount_code = p_discount_code,
      promo_code_id = v_promo_id, voucher_id = p_voucher_id, notes = p_note,
      trailer_moto_id = p_trailer_moto_id,
      helmet_size = p_helmet_size, jacket_size = p_jacket_size, pants_size = p_pants_size,
      boots_size = p_boots_size, gloves_size = p_gloves_size,
      passenger_helmet_size = p_passenger_helmet_size, passenger_jacket_size = p_passenger_jacket_size,
      passenger_pants_size = p_passenger_pants_size,
      passenger_gloves_size = p_passenger_gloves_size, passenger_boots_size = p_passenger_boots_size
    WHERE id = p_existing_booking_id;
    v_booking_id := p_existing_booking_id;
    DELETE FROM booking_extras WHERE booking_id = v_booking_id;
  ELSE
    INSERT INTO bookings (
      user_id, moto_id, start_date, end_date,
      status, payment_status, total_price, extras_price,
      late_pickup_discount_amount,
      booking_source, pickup_time,
      pickup_address, return_address, return_time,
      discount_amount, discount_code,
      promo_code_id, voucher_id, notes, trailer_moto_id,
      helmet_size, jacket_size, pants_size, boots_size, gloves_size,
      passenger_helmet_size, passenger_jacket_size, passenger_pants_size,
      passenger_gloves_size, passenger_boots_size
    ) VALUES (
      v_user_id, p_moto_id, p_start_date, p_end_date,
      'pending','unpaid', v_total, v_extras_total,
      v_late_discount,
      'web', p_pickup_time,
      p_delivery_address, p_return_address, p_return_time,
      p_discount_amount, p_discount_code,
      v_promo_id, p_voucher_id, p_note, p_trailer_moto_id,
      p_helmet_size, p_jacket_size, p_pants_size, p_boots_size, p_gloves_size,
      p_passenger_helmet_size, p_passenger_jacket_size, p_passenger_pants_size,
      p_passenger_gloves_size, p_passenger_boots_size
    ) RETURNING id INTO v_booking_id;
  END IF;

  -- 7) EXTRAS
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      INSERT INTO booking_extras (booking_id, name, unit_price, quantity)
      VALUES (
        v_booking_id,
        v_extra.value->>'name',
        COALESCE((v_extra.value->>'unit_price')::numeric, 0),
        COALESCE((v_extra.value->>'quantity')::integer, 1)
      );
    END LOOP;
  END IF;

  -- 8) BOOKING_DISCOUNTS — NEW: zdroj pravdy pro uplatnění slev.
  --    Bez tohoto se promo used_count neinkrementoval a voucher se po zaplacení
  --    neoznačil jako 'redeemed' (redeem_booking_discounts_on_paid iteruje tuto
  --    tabulku). Plní se i při re-use draftu (smaž a vlož znovu).
  DELETE FROM booking_discounts WHERE booking_id = v_booking_id;
  IF jsonb_array_length(v_bd) > 0 THEN
    INSERT INTO booking_discounts (booking_id, kind, code, promo_code_id, voucher_id, discount_type, value, amount)
    SELECT v_booking_id, e->>'kind', e->>'code',
           NULLIF(e->>'promo_code_id','')::uuid,
           NULLIF(e->>'voucher_id','')::uuid,
           e->>'discount_type', COALESCE((e->>'value')::numeric,0), 0
    FROM jsonb_array_elements(v_bd) AS e;
    -- rozpočítej skutečně odečtené částky proti hrubé ceně (po late slevě, před slevou)
    PERFORM public._reallocate_booking_discounts(v_booking_id, v_total + p_discount_amount);
  END IF;

  RETURN jsonb_build_object(
    'booking_id', v_booking_id,
    'amount', v_total,
    'late_pickup_discount', v_late_discount,
    'user_id', v_user_id,
    'is_new_user', v_is_new_user,
    'reused', v_reuse_booking
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text" DEFAULT ''::"text", "p_city" "text" DEFAULT ''::"text", "p_zip" "text" DEFAULT ''::"text", "p_country" "text" DEFAULT 'CZ'::"text", "p_note" "text" DEFAULT ''::"text", "p_pickup_time" time without time zone DEFAULT NULL::time without time zone, "p_delivery_address" "text" DEFAULT NULL::"text", "p_return_address" "text" DEFAULT NULL::"text", "p_extras" "jsonb" DEFAULT '[]'::"jsonb", "p_discount_amount" numeric DEFAULT 0, "p_discount_code" "text" DEFAULT NULL::"text", "p_promo_code" "text" DEFAULT NULL::"text", "p_voucher_id" "uuid" DEFAULT NULL::"uuid", "p_license_group" "text" DEFAULT NULL::"text", "p_password" "text" DEFAULT NULL::"text", "p_helmet_size" "text" DEFAULT NULL::"text", "p_jacket_size" "text" DEFAULT NULL::"text", "p_pants_size" "text" DEFAULT NULL::"text", "p_boots_size" "text" DEFAULT NULL::"text", "p_gloves_size" "text" DEFAULT NULL::"text", "p_passenger_helmet_size" "text" DEFAULT NULL::"text", "p_passenger_jacket_size" "text" DEFAULT NULL::"text", "p_passenger_gloves_size" "text" DEFAULT NULL::"text", "p_passenger_boots_size" "text" DEFAULT NULL::"text", "p_return_time" "text" DEFAULT NULL::"text", "p_existing_booking_id" "uuid" DEFAULT NULL::"uuid", "p_passenger_pants_size" "text" DEFAULT NULL::"text", "p_consent_vop" boolean DEFAULT NULL::boolean, "p_consent_gdpr" boolean DEFAULT NULL::boolean, "p_marketing_consent" boolean DEFAULT NULL::boolean, "p_consent_photo" boolean DEFAULT NULL::boolean, "p_date_of_birth" "text" DEFAULT NULL::"text", "p_trailer_moto_id" "uuid" DEFAULT NULL::"uuid", "p_discounts" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid; v_booking_id uuid; v_moto record; v_existing_auth_id uuid;
  v_existing_booking record; v_reuse_booking boolean := false; v_total numeric;
  v_extras_total numeric := 0; v_extra record; v_is_new_user boolean := false;
  v_allowed_groups text[]; v_moto_license text; v_promo_id uuid := NULL;
  v_voucher_amount numeric; v_current_date date; v_day_of_week integer;
  v_day_price numeric; v_dob date; v_late_discount numeric := 0;
  v_disc jsonb := '[]'::jsonb; v_disc_final jsonb := '[]'::jsonb; v_item jsonb;
  v_pc record; v_vc record; v_pct_rate numeric := 0; v_pct_seen boolean := false;
  v_pct_amt numeric := 0; v_fixed_remaining numeric := 0; v_item_amount numeric := 0;
  v_primary_voucher_id uuid := NULL;
BEGIN
  IF p_email IS NULL OR trim(p_email) = '' THEN RETURN jsonb_build_object('error','Email je povinný'); END IF;
  IF p_moto_id IS NULL THEN RETURN jsonb_build_object('error','Motorka není vybrána'); END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN RETURN jsonb_build_object('error','Neplatný termín rezervace'); END IF;
  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN v_dob := p_date_of_birth::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END;
  END IF;
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF v_moto.id IS NULL THEN RETURN jsonb_build_object('error','Motorka nenalezena'); END IF;
  v_moto_license := COALESCE(v_moto.license_required,'A');
  IF v_moto_license <> 'N' AND p_license_group IS NOT NULL AND p_license_group <> '' THEN
    CASE upper(p_license_group)
      WHEN 'A'  THEN v_allowed_groups := ARRAY['A','A2','A1','AM'];
      WHEN 'A2' THEN v_allowed_groups := ARRAY['A2','A1','AM'];
      WHEN 'A1' THEN v_allowed_groups := ARRAY['A1','AM'];
      WHEN 'AM' THEN v_allowed_groups := ARRAY['AM'];
      WHEN 'B'  THEN v_allowed_groups := ARRAY['B','AM'];
      ELSE RETURN jsonb_build_object('error','Neplatná skupina ŘP: '||p_license_group);
    END CASE;
    IF NOT (v_moto_license = ANY(v_allowed_groups)) THEN
      RETURN jsonb_build_object('error','Pro tuto motorku potřebujete ŘP skupiny '||v_moto_license||'. Vaše skupina: '||p_license_group);
    END IF;
  END IF;
  SELECT id INTO v_existing_auth_id FROM auth.users WHERE lower(email) = lower(trim(p_email)) LIMIT 1;
  IF v_existing_auth_id IS NOT NULL AND p_existing_booking_id IS NULL AND current_user = 'anon' THEN
    RETURN jsonb_build_object('error','email_exists','message','Tento e-mail je v systému. Pro pokračování se přihlaste, nebo si obnovte heslo.');
  END IF;
  IF v_existing_auth_id IS NOT NULL AND auth.uid() IS NOT NULL AND auth.uid() <> v_existing_auth_id THEN
    RETURN jsonb_build_object('error','email_mismatch','message','Přihlášený účet nesouhlasí se zadaným e-mailem.');
  END IF;
  IF v_existing_auth_id IS NOT NULL THEN
    v_user_id := v_existing_auth_id;
    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source, license_group, date_of_birth, consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (v_user_id, p_name, lower(trim(p_email)), p_phone, p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> '' THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob, COALESCE(p_consent_vop,true), COALESCE(p_consent_gdpr,true), COALESCE(p_marketing_consent,true), COALESCE(p_consent_photo,true))
    ON CONFLICT (id) DO UPDATE SET
      phone = CASE WHEN EXCLUDED.phone IS NOT NULL AND EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE profiles.phone END,
      street = CASE WHEN EXCLUDED.street <> '' THEN EXCLUDED.street ELSE profiles.street END,
      city = CASE WHEN EXCLUDED.city <> '' THEN EXCLUDED.city ELSE profiles.city END,
      zip = CASE WHEN EXCLUDED.zip <> '' THEN EXCLUDED.zip ELSE profiles.zip END,
      country = CASE WHEN EXCLUDED.country <> '' AND EXCLUDED.country <> 'CZ' THEN EXCLUDED.country ELSE profiles.country END,
      full_name = CASE WHEN profiles.full_name IS NULL OR profiles.full_name = '' THEN EXCLUDED.full_name ELSE profiles.full_name END,
      license_group = CASE WHEN EXCLUDED.license_group IS NOT NULL AND (profiles.license_group IS NULL OR array_length(profiles.license_group,1) IS NULL) THEN EXCLUDED.license_group ELSE profiles.license_group END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth), registration_source = COALESCE(profiles.registration_source,'web'),
      consent_vop = COALESCE(p_consent_vop, profiles.consent_vop), consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent), consent_photo = COALESCE(p_consent_photo, profiles.consent_photo), updated_at = now();
    IF p_password IS NOT NULL AND p_password <> '' THEN
      UPDATE auth.users SET encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() WHERE id = v_user_id;
    END IF;
  ELSE
    v_user_id := gen_random_uuid(); v_is_new_user := true;
    INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role, raw_user_meta_data, created_at, updated_at)
    VALUES (v_user_id, '00000000-0000-0000-0000-000000000000', lower(trim(p_email)), crypt(COALESCE(NULLIF(p_password,''), gen_random_uuid()::text), gen_salt('bf')),
      now(), 'authenticated', 'authenticated', jsonb_build_object('full_name', p_name, 'phone', p_phone), now(), now());
    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source, license_group, date_of_birth, consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (v_user_id, p_name, lower(trim(p_email)), p_phone, p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> '' THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob, COALESCE(p_consent_vop,true), COALESCE(p_consent_gdpr,true), COALESCE(p_marketing_consent,true), COALESCE(p_consent_photo,true))
    ON CONFLICT (id) DO UPDATE SET
      full_name = COALESCE(NULLIF(profiles.full_name,''), EXCLUDED.full_name), phone = COALESCE(NULLIF(EXCLUDED.phone,''), profiles.phone),
      street = COALESCE(NULLIF(EXCLUDED.street,''), profiles.street), city = COALESCE(NULLIF(EXCLUDED.city,''), profiles.city),
      zip = COALESCE(NULLIF(EXCLUDED.zip,''), profiles.zip), country = EXCLUDED.country, registration_source = COALESCE(profiles.registration_source,'web'),
      license_group = CASE WHEN EXCLUDED.license_group IS NOT NULL AND (profiles.license_group IS NULL OR array_length(profiles.license_group,1) IS NULL) THEN EXCLUDED.license_group ELSE profiles.license_group END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth), consent_vop = COALESCE(p_consent_vop, profiles.consent_vop), consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent), consent_photo = COALESCE(p_consent_photo, profiles.consent_photo), updated_at = now();
  END IF;
  IF p_existing_booking_id IS NOT NULL THEN
    SELECT id, user_id, status, payment_status, booking_source INTO v_existing_booking FROM bookings WHERE id = p_existing_booking_id LIMIT 1;
    IF v_existing_booking.id IS NOT NULL AND v_existing_booking.user_id = v_user_id AND v_existing_booking.status = 'pending'
       AND v_existing_booking.payment_status = 'unpaid' AND v_existing_booking.booking_source = 'web' THEN v_reuse_booking := true; END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM bookings WHERE moto_id = p_moto_id AND status IN ('pending','reserved','active')
      AND tstzrange(start_date, end_date,'[]') && tstzrange(p_start_date, p_end_date,'[]')
      AND (NOT v_reuse_booking OR id <> p_existing_booking_id)) THEN
    RETURN jsonb_build_object('error','Booking overlap — motorka není v termínu dostupná');
  END IF;
  v_total := 0; v_current_date := p_start_date::date;
  WHILE v_current_date <= p_end_date::date LOOP
    v_day_of_week := EXTRACT(DOW FROM v_current_date)::integer;
    v_day_price := CASE v_day_of_week
      WHEN 0 THEN COALESCE(v_moto.price_sun, v_moto.price_weekday, 0) WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0) WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0) WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekday, 0) END;
    v_total := v_total + v_day_price; v_current_date := v_current_date + 1;
  END LOOP;
  IF v_total = 0 THEN v_total := COALESCE(v_moto.price_weekday,0); END IF;
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extras_total := v_extras_total + COALESCE((v_extra.value->>'unit_price')::numeric,0) * COALESCE((v_extra.value->>'quantity')::numeric,1);
    END LOOP;
  END IF;
  v_total := v_total + v_extras_total;
  v_late_discount := public._late_pickup_discount(p_moto_id, p_start_date, p_end_date, p_pickup_time);
  IF v_late_discount > 0 THEN v_total := GREATEST(0, v_total - v_late_discount); END IF;
  -- 5c) MULTI-SLEVA
  IF p_discounts IS NOT NULL AND jsonb_typeof(p_discounts) = 'array' AND jsonb_array_length(p_discounts) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_discounts) LOOP
      IF lower(COALESCE(v_item->>'kind','')) = 'voucher' THEN
        SELECT id, code, amount INTO v_vc FROM vouchers WHERE code = upper(v_item->>'code') AND status='active' AND (valid_until IS NULL OR valid_until >= current_date) LIMIT 1;
        IF v_vc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','voucher','code',v_vc.code,'voucher_id',v_vc.id,'discount_type','fixed','value',v_vc.amount); END IF;
      ELSE
        SELECT id, code, type, value INTO v_pc FROM promo_codes WHERE code = upper(v_item->>'code') AND active = true LIMIT 1;
        IF v_pc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','promo_code','code',v_pc.code,'promo_code_id',v_pc.id,'discount_type',v_pc.type,'value',v_pc.value); END IF;
      END IF;
    END LOOP;
  ELSE
    IF p_promo_code IS NOT NULL AND p_promo_code <> '' THEN
      SELECT id, code, type, value INTO v_pc FROM promo_codes WHERE code = p_promo_code AND active = true LIMIT 1;
      IF v_pc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','promo_code','code',v_pc.code,'promo_code_id',v_pc.id,'discount_type',v_pc.type,'value',v_pc.value); END IF;
    END IF;
    IF p_voucher_id IS NOT NULL THEN
      SELECT id, code, amount INTO v_vc FROM vouchers WHERE id = p_voucher_id AND status='active' LIMIT 1;
      IF v_vc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','voucher','code',v_vc.code,'voucher_id',v_vc.id,'discount_type','fixed','value',v_vc.amount); END IF;
    END IF;
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_disc) LOOP
    IF (v_item->>'discount_type') = 'percent' THEN
      IF v_pct_seen THEN RETURN jsonb_build_object('error','Lze uplatnit nejvýše jednu procentní slevu'); END IF;
      v_pct_seen := true; v_pct_rate := COALESCE((v_item->>'value')::numeric, 0);
    END IF;
  END LOOP;
  v_pct_amt := ROUND(v_total * v_pct_rate / 100);
  v_fixed_remaining := GREATEST(0, v_total - v_pct_amt);
  p_discount_amount := 0;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_disc) LOOP
    IF (v_item->>'discount_type') = 'percent' THEN v_item_amount := v_pct_amt;
    ELSE v_item_amount := LEAST(COALESCE((v_item->>'value')::numeric,0), v_fixed_remaining); v_fixed_remaining := v_fixed_remaining - v_item_amount; END IF;
    p_discount_amount := p_discount_amount + v_item_amount;
    v_disc_final := v_disc_final || (v_item || jsonb_build_object('amount', v_item_amount));
    IF (v_item->>'kind') = 'promo_code' AND v_promo_id IS NULL THEN v_promo_id := (v_item->>'promo_code_id')::uuid; END IF;
    IF (v_item->>'kind') = 'voucher' AND v_primary_voucher_id IS NULL THEN v_primary_voucher_id := (v_item->>'voucher_id')::uuid; END IF;
  END LOOP;
  v_total := GREATEST(0, v_total - p_discount_amount);
  IF v_reuse_booking THEN
    UPDATE bookings SET moto_id = p_moto_id, start_date = p_start_date, end_date = p_end_date, total_price = v_total, extras_price = v_extras_total,
      late_pickup_discount_amount = v_late_discount, pickup_time = p_pickup_time, pickup_address = p_delivery_address, return_address = p_return_address, return_time = p_return_time,
      discount_amount = p_discount_amount, discount_code = p_discount_code, promo_code_id = v_promo_id, voucher_id = v_primary_voucher_id, notes = p_note, trailer_moto_id = p_trailer_moto_id,
      helmet_size = p_helmet_size, jacket_size = p_jacket_size, pants_size = p_pants_size, boots_size = p_boots_size, gloves_size = p_gloves_size,
      passenger_helmet_size = p_passenger_helmet_size, passenger_jacket_size = p_passenger_jacket_size, passenger_pants_size = p_passenger_pants_size,
      passenger_gloves_size = p_passenger_gloves_size, passenger_boots_size = p_passenger_boots_size WHERE id = p_existing_booking_id;
    v_booking_id := p_existing_booking_id; DELETE FROM booking_extras WHERE booking_id = v_booking_id;
  ELSE
    INSERT INTO bookings (user_id, moto_id, start_date, end_date, status, payment_status, total_price, extras_price, late_pickup_discount_amount, booking_source, pickup_time,
      pickup_address, return_address, return_time, discount_amount, discount_code, promo_code_id, voucher_id, notes, trailer_moto_id,
      helmet_size, jacket_size, pants_size, boots_size, gloves_size, passenger_helmet_size, passenger_jacket_size, passenger_pants_size, passenger_gloves_size, passenger_boots_size)
    VALUES (v_user_id, p_moto_id, p_start_date, p_end_date, 'pending','unpaid', v_total, v_extras_total, v_late_discount, 'web', p_pickup_time,
      p_delivery_address, p_return_address, p_return_time, p_discount_amount, p_discount_code, v_promo_id, v_primary_voucher_id, p_note, p_trailer_moto_id,
      p_helmet_size, p_jacket_size, p_pants_size, p_boots_size, p_gloves_size, p_passenger_helmet_size, p_passenger_jacket_size, p_passenger_pants_size, p_passenger_gloves_size, p_passenger_boots_size)
    RETURNING id INTO v_booking_id;
  END IF;
  -- 6b) BOOKING_DISCOUNTS
  DELETE FROM booking_discounts WHERE booking_id = v_booking_id;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_disc_final) LOOP
    INSERT INTO booking_discounts (booking_id, kind, code, promo_code_id, voucher_id, discount_type, value, amount)
    VALUES (v_booking_id, v_item->>'kind', v_item->>'code', NULLIF(v_item->>'promo_code_id','')::uuid, NULLIF(v_item->>'voucher_id','')::uuid,
      v_item->>'discount_type', COALESCE((v_item->>'value')::numeric,0), COALESCE((v_item->>'amount')::numeric,0));
  END LOOP;
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      INSERT INTO booking_extras (booking_id, name, unit_price, quantity)
      VALUES (v_booking_id, v_extra.value->>'name', COALESCE((v_extra.value->>'unit_price')::numeric, 0), COALESCE((v_extra.value->>'quantity')::integer, 1));
    END LOOP;
  END IF;
  RETURN jsonb_build_object('booking_id', v_booking_id, 'amount', v_total, 'discount_amount', p_discount_amount,
    'late_pickup_discount', v_late_discount, 'discounts', v_disc_final, 'user_id', v_user_id, 'is_new_user', v_is_new_user, 'reused', v_reuse_booking);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid", "p_discounts" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_web_shop_order"("items" "jsonb", "customer_name" "text", "customer_email" "text", "customer_phone" "text", "shipping_method" "text", "shipping_address" "text" DEFAULT NULL::"text", "payment_method" "text" DEFAULT 'stripe'::"text", "promo_code" "text" DEFAULT NULL::"text", "notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order_id uuid := gen_random_uuid();
  v_subtotal numeric := 0;
  v_shipping numeric := 0;
  v_total numeric := 0;
  it jsonb;
  prod RECORD;
  v_qty int;
  v_size text;
  v_avail int;
BEGIN
  IF jsonb_typeof(items) <> 'array' OR jsonb_array_length(items) = 0 THEN
    RETURN jsonb_build_object('error','no_items');
  END IF;

  v_shipping := CASE shipping_method
    WHEN 'pickup' THEN 0
    WHEN 'post' THEN 99
    WHEN 'zasilkovna' THEN 79
    ELSE 0 END;

  FOR it IN SELECT * FROM jsonb_array_elements(items) LOOP
    v_qty := COALESCE((it->>'qty')::int, 1);
    v_size := NULLIF(it->>'size','');
    IF v_qty < 1 THEN
      RETURN jsonb_build_object('error','bad_qty');
    END IF;

    SELECT id, name, sku, price, sizes, stock_quantity, size_stock, is_active
      INTO prod
    FROM products
    WHERE id = (it->>'product_id')::uuid
    FOR UPDATE;

    IF NOT FOUND OR NOT prod.is_active THEN
      RETURN jsonb_build_object('error','product_not_found','product_id', it->>'product_id');
    END IF;

    IF prod.sizes IS NOT NULL AND array_length(prod.sizes,1) > 0 THEN
      IF v_size IS NULL OR NOT (v_size = ANY(prod.sizes)) THEN
        RETURN jsonb_build_object('error','bad_size','product_id',prod.id,'size',v_size);
      END IF;
      v_avail := COALESCE((prod.size_stock->>v_size)::int, 0);
    ELSE
      v_avail := COALESCE(prod.stock_quantity, 0);
    END IF;

    IF v_avail < v_qty THEN
      RETURN jsonb_build_object('error','out_of_stock','product_id',prod.id,
        'size',v_size,'available',v_avail,'requested',v_qty);
    END IF;

    v_subtotal := v_subtotal + (prod.price * v_qty);
  END LOOP;

  v_total := v_subtotal + v_shipping;

  INSERT INTO shop_orders (
    id, customer_name, customer_email, customer_phone,
    shipping_method, shipping_address, payment_method,
    status, payment_status, subtotal, shipping_cost, total, notes
  ) VALUES (
    v_order_id, customer_name, customer_email, customer_phone,
    shipping_method, shipping_address, payment_method,
    'new', 'pending', v_subtotal, v_shipping, v_total, notes
  );

  FOR it IN SELECT * FROM jsonb_array_elements(items) LOOP
    v_qty := COALESCE((it->>'qty')::int, 1);
    v_size := NULLIF(it->>'size','');

    SELECT id, name, sku, price, sizes, stock_quantity, size_stock
      INTO prod
    FROM products
    WHERE id = (it->>'product_id')::uuid
    FOR UPDATE;

    INSERT INTO shop_order_items (order_id, product_id, product_name, product_sku, size, quantity, unit_price, total_price)
    VALUES (v_order_id, prod.id, prod.name, prod.sku, v_size, v_qty, prod.price, prod.price * v_qty);

    IF prod.sizes IS NOT NULL AND array_length(prod.sizes,1) > 0 AND v_size IS NOT NULL THEN
      UPDATE products
        SET size_stock = jsonb_set(
              COALESCE(size_stock,'{}'::jsonb),
              ARRAY[v_size],
              to_jsonb(GREATEST(0, COALESCE((size_stock->>v_size)::int,0) - v_qty))
            ),
            stock_quantity = GREATEST(0, COALESCE(stock_quantity,0) - v_qty)
      WHERE id = prod.id;
    ELSE
      UPDATE products
        SET stock_quantity = GREATEST(0, COALESCE(stock_quantity,0) - v_qty)
      WHERE id = prod.id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id);
END $$;


ALTER FUNCTION "public"."create_web_shop_order"("items" "jsonb", "customer_name" "text", "customer_email" "text", "customer_phone" "text", "shipping_method" "text", "shipping_address" "text", "payment_method" "text", "promo_code" "text", "notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_active int;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_user_id');
  END IF;

  IF NOT (public.is_admin() OR auth.uid() = p_user_id) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT count(*) INTO v_active
    FROM bookings
    WHERE user_id = p_user_id
      AND status IN ('pending','reserved','active');
  IF v_active > 0 THEN
    RETURN jsonb_build_object('error','active_bookings','count',v_active);
  END IF;

  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true, 'user_id', p_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") IS 'Atomické smazání zákazníka: profiles + auth.users. Kontroluje aktivní rezervace.';



CREATE OR REPLACE FUNCTION "public"."delete_poi_review"("p_route_poi_id" "uuid" DEFAULT NULL::"uuid", "p_user_poi_id" "uuid" DEFAULT NULL::"uuid", "p_poi_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  delete from poi_ratings where user_id = auth.uid()
    and route_poi_id is not distinct from p_route_poi_id
    and user_poi_id  is not distinct from p_user_poi_id
    and poi_id       is not distinct from p_poi_id;
end;
$$;


ALTER FUNCTION "public"."delete_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_route_review"("p_route_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  delete from route_reviews where user_id = auth.uid() and route_id = p_route_id;
end;
$$;


ALTER FUNCTION "public"."delete_route_review"("p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_user_route"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  delete from user_saved_routes where id = p_id and user_id = auth.uid();
  return jsonb_build_object('success', found);
end;
$$;


ALTER FUNCTION "public"."delete_user_route"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."detect_consecutive_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_prev uuid;
BEGIN
  BEGIN
    -- Jen reálné nové rezervace s kompletními údaji
    IF NEW.user_id IS NULL OR NEW.moto_id IS NULL
       OR NEW.start_date IS NULL OR NEW.end_date IS NULL THEN
      RETURN NEW;
    END IF;
    -- Nesahat na swap/handoff pokračování (výměna motorky má vlastní flow)
    -- ani na řádky, kde už je vazba nastavená explicitně.
    IF NEW.extends_booking_id IS NOT NULL OR NEW.continues_booking_id IS NOT NULL THEN
      RETURN NEW;
    END IF;
    IF COALESCE(NEW.status::text, 'pending') NOT IN ('pending', 'reserved', 'active') THEN
      RETURN NEW;
    END IF;

    -- Navazující = stejný zákazník + stejná motorka + termíny na sebe navazují
    -- den po dni (sdílený den blokuje check_user_booking_overlap, čas nehraje
    -- roli). Původní rezervace musí být živá (reserved/active) — po vrácení
    -- motorky (completed) nebo stornu jde o běžnou novou rezervaci.
    SELECT b.id INTO v_prev
      FROM public.bookings b
     WHERE b.user_id = NEW.user_id
       AND b.moto_id = NEW.moto_id
       AND b.id IS DISTINCT FROM NEW.id
       AND b.status IN ('reserved', 'active')
       AND (b.end_date::date + 1 = NEW.start_date::date
            OR NEW.end_date::date + 1 = b.start_date::date)
     ORDER BY (b.end_date::date + 1 = NEW.start_date::date) DESC, b.end_date DESC
     LIMIT 1;

    IF v_prev IS NOT NULL THEN
      NEW.extends_booking_id := v_prev;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Detekce nikdy nesmí shodit INSERT rezervace — při chybě jen zaloguj.
    BEGIN
      INSERT INTO public.debug_log (source, action, status, error_message, request_data)
      VALUES ('detect_consecutive_booking', 'detect_failed', 'error', SQLERRM,
              jsonb_build_object('user_id', NEW.user_id, 'moto_id', NEW.moto_id,
                                 'start_date', NEW.start_date, 'end_date', NEW.end_date));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."detect_consecutive_booking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."detect_customer_language"("p_user_id" "uuid" DEFAULT NULL::"uuid", "p_booking_id" "uuid" DEFAULT NULL::"uuid", "p_order_id" "uuid" DEFAULT NULL::"uuid") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE v_lang text;
BEGIN
  IF p_booking_id IS NOT NULL THEN
    SELECT b.language INTO v_lang FROM bookings b WHERE b.id = p_booking_id;
    IF v_lang IS NOT NULL AND v_lang <> '' THEN RETURN v_lang; END IF;
  END IF;
  IF p_order_id IS NOT NULL THEN
    SELECT o.language INTO v_lang FROM shop_orders o WHERE o.id = p_order_id;
    IF v_lang IS NOT NULL AND v_lang <> '' THEN RETURN v_lang; END IF;
  END IF;
  IF p_user_id IS NOT NULL THEN
    SELECT language INTO v_lang FROM profiles WHERE id = p_user_id;
    IF v_lang IS NOT NULL AND v_lang <> '' THEN RETURN v_lang; END IF;
  END IF;
  RETURN 'cs';
END; $$;


ALTER FUNCTION "public"."detect_customer_language"("p_user_id" "uuid", "p_booking_id" "uuid", "p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."detect_gear_shortages"("p_horizon_days" integer DEFAULT 120) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare r record;
begin
  for r in select id from branches loop
    perform public.detect_gear_shortages_for_window(r.id, current_date, current_date + p_horizon_days);
  end loop;
end $$;


ALTER FUNCTION "public"."detect_gear_shortages"("p_horizon_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."detect_gear_shortages_for_window"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_from date := greatest(p_from, current_date);
  v_to   date := p_to;
begin
  if p_branch_id is null or v_to is null or v_to < v_from then return; end if;

  with days as (select generate_series(v_from, v_to, interval '1 day')::date d),
  bk as (
    select b.id, b.start_date::date sd, b.end_date::date ed,
           coalesce(m.license_required,'A') lic, x.type, x.size
    from bookings b
    join motorcycles m on m.id = b.moto_id
    cross join lateral (values
      ('helmet', b.helmet_size), ('jacket', b.jacket_size), ('pants', b.pants_size),
      ('boots', b.boots_size),   ('gloves', b.gloves_size),
      ('helmet', b.passenger_helmet_size), ('jacket', b.passenger_jacket_size),
      ('pants', b.passenger_pants_size),   ('boots', b.passenger_boots_size),
      ('gloves', b.passenger_gloves_size)
    ) as x(type, size)
    where m.branch_id = p_branch_id
      and b.status in ('pending','reserved','active')
      and coalesce(b.pickup_method,'') <> 'delivery'
      and x.size is not null and x.size <> ''
      and exists (select 1 from branch_accessories b2 where b2.type = x.type)  -- jen skladované typy
  ),
  calc as (
    select d.d shortage_date, bk.type, bk.size,
           case when bk.lic = 'N' then 'child' else 'adult' end audience,
           count(*)::int needed, coalesce(ba.quantity,0)::int stock_qty,
           greatest(count(*) - coalesce(ba.quantity,0), 0)::int deficit,
           array_agg(distinct bk.id) booking_ids
    from days d
    join bk on d.d between bk.sd and bk.ed
    left join branch_accessories ba
      on ba.branch_id = p_branch_id and ba.type = bk.type and ba.size = bk.size
    group by d.d, bk.type, bk.size, case when bk.lic='N' then 'child' else 'adult' end, coalesce(ba.quantity,0)
  )
  insert into gear_shortages
    (branch_id, accessory_type, size, audience, shortage_date, needed_qty, stock_qty, deficit_qty, booking_ids, status)
  select p_branch_id, type, size, audience, shortage_date, needed, stock_qty, deficit, booking_ids, 'open'
  from calc where deficit > 0
  on conflict (branch_id, accessory_type, size, shortage_date) do update set
    needed_qty=excluded.needed_qty, stock_qty=excluded.stock_qty, deficit_qty=excluded.deficit_qty,
    booking_ids=excluded.booking_ids, updated_at=now(),
    status = case when gear_shortages.status in ('resolved','dismissed') then 'open' else gear_shortages.status end,
    resolved_at = case when gear_shortages.status in ('resolved','dismissed') then null else gear_shortages.resolved_at end;

  update gear_shortages gs
  set deficit_qty=0, status='resolved', resolved_at=now(), updated_at=now()
  where gs.branch_id=p_branch_id and gs.shortage_date between v_from and v_to and gs.status='open'
    and not exists (
      select 1 from bookings b join motorcycles m on m.id=b.moto_id
      cross join lateral (values
        ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
        ('boots',b.boots_size),('gloves',b.gloves_size),
        ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
        ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
      ) x(type,size)
      where m.branch_id=p_branch_id and b.status in ('pending','reserved','active')
        and coalesce(b.pickup_method,'')<>'delivery'
        and x.type=gs.accessory_type and x.size=gs.size
        and gs.shortage_date between b.start_date::date and b.end_date::date
      group by x.type,x.size
      having count(*) > coalesce((select quantity from branch_accessories
        where branch_id=p_branch_id and type=gs.accessory_type and size=gs.size),0)
    );
end $$;


ALTER FUNCTION "public"."detect_gear_shortages_for_window"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dispatch_email_event"("p_event_slug" "text", "p_payload" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- No-op od 2026-05-08. Dynamic dispatcher cesta byla odstraněna ze
  -- send-booking-email kvůli duplicitním mailům. Šablonové dispatch dělá
  -- nyní pouze legacy `type=` cesta (1:1 s slugem).
  RETURN;
END;
$$;


ALTER FUNCTION "public"."dispatch_email_event"("p_event_slug" "text", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_vouchers"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE vouchers
  SET status = 'expired'
  WHERE status = 'active'
    AND valid_until < CURRENT_DATE;
END;
$$;


ALTER FUNCTION "public"."expire_vouchers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."expire_vouchers_and_promos"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE vouchers SET status = 'expired', updated_at = NOW()
  WHERE status = 'active' AND valid_until < CURRENT_DATE;
  UPDATE promo_codes SET active = false
  WHERE active = true AND valid_to IS NOT NULL AND valid_to < CURRENT_DATE;
END;
$$;


ALTER FUNCTION "public"."expire_vouchers_and_promos"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."extend_booking"("p_booking_id" "uuid", "p_new_end_date" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    booking RECORD;
    is_available BOOLEAN;
    price_result jsonb;
    extra_price NUMERIC;
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


ALTER FUNCTION "public"."extend_booking"("p_booking_id" "uuid", "p_new_end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_booking_for_modification"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_b record;
  v_phone_norm text;
  v_contact_norm text;
  v_is_email boolean;
  v_match boolean := false;
BEGIN
  IF p_booking_id IS NULL OR length(coalesce(p_contact,'')) < 4 OR length(coalesce(p_password_last4,'')) <> 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  SELECT b.id, b.user_id, b.status, b.payment_status, b.booking_source,
         b.moto_id, b.start_date, b.end_date,
         b.pickup_method, b.pickup_address,
         b.return_method, b.return_address,
         b.delivery_fee, b.total_price, b.modification_history,
         p.email, p.phone, p.full_name, p.password_last4_bcrypt
    INTO v_b
    FROM bookings b
    JOIN profiles p ON p.id = b.user_id
   WHERE b.id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  v_is_email := position('@' in p_contact) > 0;
  IF v_is_email THEN
    v_match := lower(trim(v_b.email)) = lower(trim(p_contact));
  ELSE
    v_phone_norm := regexp_replace(coalesce(v_b.phone,''), '[^0-9]', '', 'g');
    v_contact_norm := regexp_replace(p_contact, '[^0-9]', '', 'g');
    v_match := right(v_phone_norm, 9) = right(v_contact_norm, 9) AND length(v_contact_norm) >= 9;
  END IF;

  IF NOT v_match THEN
    RETURN jsonb_build_object('success', false, 'error', 'verification_failed');
  END IF;

  IF v_b.password_last4_bcrypt IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'password_check_unavailable',
      'hint', 'Heslo bylo nastaveno před zavedením této funkce. Doporuč zákazníkovi otevřít úpravu rezervace přes web po přihlášení.');
  END IF;

  IF crypt(p_password_last4, v_b.password_last4_bcrypt) <> v_b.password_last4_bcrypt THEN
    RETURN jsonb_build_object('success', false, 'error', 'verification_failed');
  END IF;

  IF v_b.booking_source <> 'web' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_web_booking');
  END IF;

  IF v_b.status NOT IN ('reserved','active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status', 'status', v_b.status);
  END IF;

  IF v_b.payment_status <> 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'booking_id', v_b.id,
    'user_id', v_b.user_id,
    'status', v_b.status,
    'moto_id', v_b.moto_id,
    'start_date', v_b.start_date,
    'end_date', v_b.end_date,
    'pickup_method', v_b.pickup_method,
    'pickup_address', v_b.pickup_address,
    'return_method', v_b.return_method,
    'return_address', v_b.return_address,
    'delivery_fee', v_b.delivery_fee,
    'total_price', v_b.total_price,
    'customer_name', v_b.full_name,
    'mods_today_count', (
      SELECT count(*)::int FROM jsonb_array_elements(coalesce(v_b.modification_history,'[]'::jsonb)) e
       WHERE (e->>'source') = 'ai_agent'
         AND (e->>'at')::timestamptz::date = current_date
    )
  );
END;
$$;


ALTER FUNCTION "public"."find_booking_for_modification"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_booking_light"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_moto motorcycles%ROWTYPE;
  v_mods_today int := 0;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF COALESCE(v_b.booking_source,'') <> 'web' THEN RETURN jsonb_build_object('success', false, 'error', 'not_web_booking'); END IF;
  IF v_b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
  IF v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success', false, 'error', 'not_paid'); END IF;

  SELECT * INTO v_moto FROM motorcycles WHERE id = v_b.moto_id;
  SELECT count(*) INTO v_mods_today
  FROM jsonb_array_elements(COALESCE(v_b.modification_history,'[]'::jsonb)) e
  WHERE COALESCE(e->>'source','') = 'ai_agent'
    AND (e->>'at')::timestamptz::date = current_date;

  RETURN jsonb_build_object(
    'success', true, 'light', true,
    'booking_id', v_b.id, 'status', v_b.status,
    'start_date', v_b.start_date, 'end_date', v_b.end_date,
    'moto_id', v_b.moto_id, 'moto_name', v_moto.model,
    'pickup_method', v_b.pickup_method, 'return_method', v_b.return_method,
    'mods_today_count', v_mods_today
  );
END; $$;


ALTER FUNCTION "public"."find_booking_light"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_email_templates_for_event"("p_event_slug" "text") RETURNS TABLE("id" "uuid", "slug" "text", "name" "text", "subject" "text", "body_html" "text", "active" boolean, "attachments" "jsonb", "triggers" "jsonb", "subject_translations" "jsonb", "body_translations" "jsonb")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT t.id, t.slug, t.name, t.subject, t.body_html, t.active,
         t.attachments, t.triggers, t.subject_translations, t.body_translations
    FROM email_templates t
   WHERE t.active = true
     AND t.triggers @> jsonb_build_array(p_event_slug);
$$;


ALTER FUNCTION "public"."find_email_templates_for_event"("p_event_slug" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_gear_surplus_branches"("p_type" "text", "p_size" "text", "p_from" "date", "p_to" "date", "p_exclude_branch" "uuid") RETURNS TABLE("branch_id" "uuid", "branch_name" "text", "free_qty" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with days as (select generate_series(greatest(p_from,current_date), p_to, interval '1 day')::date d),
  stock as (select ba.branch_id, ba.quantity from branch_accessories ba
            where ba.type=p_type and ba.size=p_size and ba.quantity>0 and ba.branch_id<>p_exclude_branch),
  booked as (
    select m.branch_id, d.d, count(*)::int n
    from days d
    join bookings b on b.status in ('pending','reserved','active')
      and coalesce(b.pickup_method,'')<>'delivery' and d.d between b.start_date::date and b.end_date::date
    join motorcycles m on m.id=b.moto_id
    cross join lateral (values
      ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
      ('boots',b.boots_size),('gloves',b.gloves_size),
      ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
      ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
    ) x(type,size)
    where x.type=p_type and x.size=p_size
    group by m.branch_id, d.d
  ),
  perday as (
    select s.branch_id, d.d, s.quantity - coalesce(bo.n,0) free
    from stock s cross join days d
    left join booked bo on bo.branch_id=s.branch_id and bo.d=d.d
  )
  select pd.branch_id, br.name, min(pd.free)::int
  from perday pd join branches br on br.id=pd.branch_id
  group by pd.branch_id, br.name having min(pd.free)>0 order by 3 desc
$$;


ALTER FUNCTION "public"."find_gear_surplus_branches"("p_type" "text", "p_size" "text", "p_from" "date", "p_to" "date", "p_exclude_branch" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fix_auth_users_null_tokens"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
BEGIN
  NEW.confirmation_token         := COALESCE(NEW.confirmation_token, '');
  NEW.recovery_token             := COALESCE(NEW.recovery_token, '');
  NEW.email_change_token_new     := COALESCE(NEW.email_change_token_new, '');
  NEW.email_change_token_current := COALESCE(NEW.email_change_token_current, '');
  NEW.phone_change_token         := COALESCE(NEW.phone_change_token, '');
  NEW.reauthentication_token     := COALESCE(NEW.reauthentication_token, '');
  NEW.email_change               := COALESCE(NEW.email_change, '');
  NEW.phone_change               := COALESCE(NEW.phone_change, '');
  NEW.aud                        := COALESCE(NULLIF(NEW.aud, ''), 'authenticated');
  NEW.role                       := COALESCE(NULLIF(NEW.role, ''), 'authenticated');
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."fix_auth_users_null_tokens"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_final_invoice_on_complete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_inv_num text; v_seq int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_items jsonb; v_total numeric;
  v_moto_model text; v_moto_spz text;
  v_base_rental numeric; v_extras numeric; v_delivery numeric;
  v_discount numeric; v_discount_code text;
  v_loyalty numeric; v_loyalty_pct int;
  v_late_pickup numeric;
  v_booking_short text; v_promo_code text;
  v_cn_number text;                              -- NOVÉ #3
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN RETURN NEW; END IF;
  IF NEW.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN RETURN NEW; END IF;
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT model, spz INTO v_moto_model, v_moto_spz FROM motorcycles WHERE id = NEW.moto_id;

  v_inv_num := next_document_number('KF');       -- NOVÉ #3: atomické číslo (místo MAX+1)

  v_extras   := COALESCE(NEW.extras_price, 0);
  v_delivery := COALESCE(NEW.delivery_fee, 0);
  v_discount := COALESCE(NEW.discount_amount, 0);
  v_discount_code := COALESCE(NEW.discount_code, '');
  v_loyalty     := COALESCE(NEW.loyalty_discount_amount, 0);
  v_loyalty_pct := COALESCE(NEW.loyalty_percent, 0);
  v_late_pickup := COALESCE(NEW.late_pickup_discount_amount, 0);
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery
                   + v_discount + v_loyalty + v_late_pickup;

  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', v_base_rental
  ));

  IF v_extras > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Příslušenství a výbava', 'qty', 1, 'unit_price', v_extras));
  END IF;

  IF v_delivery > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Přistavení / odvoz motorky', 'qty', 1, 'unit_price', v_delivery));
  END IF;

  IF v_discount > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', CASE WHEN v_discount_code <> '' THEN 'Sleva (kód: ' || v_discount_code || ')'
                          ELSE 'Sleva / voucher' END,
      'qty', 1, 'unit_price', -v_discount));
  END IF;

  IF v_loyalty > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Věrnostní sleva' ||
        CASE WHEN v_loyalty_pct > 0 THEN ' ' || v_loyalty_pct || ' %' ELSE '' END ||
        ' — rezervace přes aplikaci MotoGo24',
      'qty', 1, 'unit_price', -v_loyalty));
  END IF;

  IF v_late_pickup > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Sleva 50 % na 1. den (pozdní vyzvednutí)',
      'qty', 1, 'unit_price', -v_late_pickup));
  END IF;

  -- Odpočet všech přijatých plateb (DP)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  -- Vrácené peníze (existující dobropisy z úprav / refundů)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'credit_note' AND status != 'cancelled'
  ), '[]'::jsonb);

  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- NOVÉ #3: záporná KF = zákazník přeplatil (záloha > finální cena).
  -- Vystav dobropis na přeplatek a KF dorovnej na 0 (místo záporné KF).
  IF ROUND(v_total::numeric, 2) < 0 THEN
    v_cn_number := next_document_number('DB');
    INSERT INTO invoices (number, type, customer_id, booking_id, items,
      subtotal, tax_amount, total, issue_date, due_date, status, variable_symbol, source)
    VALUES (v_cn_number, 'credit_note', NEW.user_id, NEW.id,
      jsonb_build_array(jsonb_build_object(
        'description', 'Přeplatek – záloha převyšuje finální cenu rezervace',
        'qty', 1, 'unit_price', v_total)),     -- v_total je záporné = částka dobropisu
      v_total, 0, v_total, CURRENT_DATE, CURRENT_DATE, 'issued', v_cn_number, 'final_overpay');

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || v_cn_number, 'qty', 1, 'unit_price', -v_total));
    v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
                FROM jsonb_array_elements(v_items) AS item);   -- = 0
  END IF;

  IF ROUND(v_total::numeric, 2) <> 0 THEN
    INSERT INTO debug_log (source, action, component, status, error_message, request_data)
    VALUES (
      'generate_final_invoice_on_complete', 'kf_total_not_zero', 'KF assertion', 'warning',
      'KF total != 0 (booking: ' || NEW.id || ', total: ' || v_total || ' Kč) — chybí DP/dobropis pro plné pokrytí?',
      jsonb_build_object(
        'booking_id', NEW.id, 'kf_number', v_inv_num, 'computed_total', v_total,
        'base_rental', v_base_rental, 'extras', v_extras, 'delivery', v_delivery,
        'discount', v_discount, 'loyalty_discount', v_loyalty,
        'late_pickup_discount', v_late_pickup, 'items', v_items,
        'sum_dp', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='payment_receipt' AND status!='cancelled'),
        'sum_credit_notes', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='credit_note' AND status!='cancelled')
      )
    );
    RAISE WARNING 'KF % pro booking % má total=% Kč (očekáváno 0). Zaloggováno do debug_log.',
      v_inv_num, NEW.id, v_total;
  END IF;

  v_booking_short := UPPER(RIGHT(REPLACE(NEW.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;

  INSERT INTO promo_codes (code, type, value, active, valid_from, valid_to, max_uses, used_count)
  VALUES (v_promo_code, 'fixed', 200, true, now(),
          (CURRENT_DATE + INTERVAL '1 year')::timestamptz, 1, 0)
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO invoices (
    number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
    issue_date, due_date, status, variable_symbol, source
  )
  VALUES (
    v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
    CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary'
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_final_invoice_on_complete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invoice_number"("prefix" "text" DEFAULT 'FV'::"text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    current_year TEXT;
    seq INT;
    result TEXT;
BEGIN
    current_year := EXTRACT(YEAR FROM CURRENT_DATE)::TEXT;
    SELECT COALESCE(MAX(
        CAST(NULLIF(SPLIT_PART(number, '-', 3), '') AS INT)
    ), 0) + 1
    INTO seq
    FROM invoices
    WHERE number LIKE prefix || '-' || current_year || '-%';

    result := prefix || '-' || current_year || '-' || LPAD(seq::TEXT, 4, '0');
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."generate_invoice_number"("prefix" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_shop_final_on_ship"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NEW.status NOT IN ('shipped', 'delivered') THEN RETURN NEW; END IF;
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.payment_status <> 'paid' THEN RETURN NEW; END IF;

  IF EXISTS (SELECT 1 FROM invoices WHERE order_id = NEW.id AND type = 'shop_final') THEN
    RETURN NEW;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'generate_shop_final_on_ship: app_settings missing, skipping order %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/generate-invoice',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'Authorization','Bearer ' || v_key),
    body    := jsonb_build_object('type','shop_final','order_id', NEW.id, 'send_email', false)
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_shop_final_on_ship error for order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_shop_final_on_ship"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_shop_order_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
    NEW.order_number := 'OBJ-' || to_char(now(), 'YYYY') || '-' ||
      lpad(nextval('shop_order_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_shop_order_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ai_traffic_stats"("p_from" timestamp with time zone DEFAULT ("now"() - '30 days'::interval), "p_to" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT jsonb_build_object(
    'total_requests', (SELECT count(*) FROM ai_traffic_log WHERE ts BETWEEN p_from AND p_to),
    'by_source', (
      SELECT jsonb_object_agg(source, c)
      FROM (SELECT source, count(*) c FROM ai_traffic_log WHERE ts BETWEEN p_from AND p_to GROUP BY source) s
    ),
    'by_bot', (
      SELECT jsonb_object_agg(coalesce(bot_name,'unknown'), c)
      FROM (SELECT bot_name, count(*) c FROM ai_traffic_log WHERE ts BETWEEN p_from AND p_to AND bot_name IS NOT NULL GROUP BY bot_name ORDER BY c DESC LIMIT 30) s
    ),
    'top_paths', (
      SELECT jsonb_agg(jsonb_build_object('path', path, 'count', c) ORDER BY c DESC)
      FROM (SELECT path, count(*) c FROM ai_traffic_log WHERE ts BETWEEN p_from AND p_to AND path IS NOT NULL GROUP BY path ORDER BY c DESC LIMIT 20) s
    ),
    'bookings_from_ai', (
      SELECT count(*) FROM ai_traffic_log WHERE ts BETWEEN p_from AND p_to AND outcome = 'booking_created'
    ),
    'top_partners', (
      SELECT jsonb_agg(jsonb_build_object('partner_name', k.partner_name, 'count', c.cnt) ORDER BY c.cnt DESC)
      FROM (
        SELECT partner_id, count(*) cnt FROM ai_traffic_log
        WHERE ts BETWEEN p_from AND p_to AND partner_id IS NOT NULL
        GROUP BY partner_id ORDER BY cnt DESC LIMIT 10
      ) c JOIN api_keys k ON k.id = c.partner_id
    ),
    'daily_timeline', (
      SELECT jsonb_agg(jsonb_build_object('date', d, 'count', c) ORDER BY d)
      FROM (
        SELECT date_trunc('day', ts)::date d, count(*) c
        FROM ai_traffic_log WHERE ts BETWEEN p_from AND p_to
        GROUP BY 1 ORDER BY 1
      ) s
    )
  ) INTO result;

  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_ai_traffic_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_app_install_stats"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  result json;
begin
  if not is_admin() then
    raise exception 'admin only';
  end if;

  select json_build_object(
    -- === Přesná data z app_installations (build s heartbeatem) ===
    'installs_total',       (select count(*) from app_installations),
    'app_users',            (select count(distinct user_id) from app_installations),
    'dau',                  (select count(*) from app_installations where last_seen_at > now() - interval '1 day'),
    'wau',                  (select count(*) from app_installations where last_seen_at > now() - interval '7 days'),
    'mau',                  (select count(*) from app_installations where last_seen_at > now() - interval '30 days'),
    -- „Aktivní zařízení" = MAU (zařízení viděné za posl. 30 dní)
    'active_devices',       (select count(*) from app_installations where last_seen_at > now() - interval '30 days'),
    'android',              (select count(*) from app_installations where last_seen_at > now() - interval '30 days' and lower(platform) = 'android'),
    'ios',                  (select count(*) from app_installations where last_seen_at > now() - interval '30 days' and lower(platform) = 'ios'),
    'push_enabled_devices', (select count(*) from app_installations where last_seen_at > now() - interval '30 days' and push_enabled is true),
    'total_devices',        (select count(*) from app_installations),

    -- === Rezervace přes appku ===
    'app_bookings',         (select count(*) from bookings where booking_source = 'app'),

    -- === Legacy proxy z push_tokens (přechodné období) ===
    'push_active_devices',  (select count(*) from (
                                select distinct user_id, lower(platform)
                                from push_tokens
                                where active is true and user_id is not null
                             ) d)
  ) into result;

  return result;
end;
$$;


ALTER FUNCTION "public"."get_app_install_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_app_install_timeseries"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_installs jsonb;
  v_regs     jsonb;
  v_since    date;
begin
  if not public.is_admin() then
    raise exception 'admin only';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'd', to_char(d, 'YYYY-MM-DD'),
           'android', android,
           'ios', ios,
           'other', other) order by d), '[]'::jsonb),
         min(d)
    into v_installs, v_since
  from (
    select first_seen_at::date as d,
           count(*) filter (where lower(coalesce(platform,'')) = 'android') as android,
           count(*) filter (where lower(coalesce(platform,'')) = 'ios')     as ios,
           count(*) filter (where lower(coalesce(platform,''))
                            not in ('android','ios'))                        as other
    from public.app_installations
    where first_seen_at is not null
    group by 1
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'd', to_char(d, 'YYYY-MM-DD'),
           'n', n) order by d), '[]'::jsonb)
    into v_regs
  from (
    select created_at::date as d, count(*) as n
    from public.profiles
    where created_at is not null
    group by 1
  ) t;

  return jsonb_build_object(
    'installs', v_installs,
    'registrations', v_regs,
    'tracking_since', coalesce(to_char(v_since, 'YYYY-MM-DD'), null)
  );
end;
$$;


ALTER FUNCTION "public"."get_app_install_timeseries"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_available_motos"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_category" "text" DEFAULT NULL::"text", "p_license" "public"."license_group" DEFAULT NULL::"public"."license_group", "p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS SETOF "public"."motorcycles"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT m.*
    FROM motorcycles m
    WHERE m.status = 'active'
      AND (p_category IS NULL OR m.category = p_category)
      AND (p_license IS NULL OR m.license_required = p_license)
      AND (p_branch_id IS NULL OR m.branch_id = p_branch_id)
      AND NOT EXISTS (
          SELECT 1 FROM bookings b
          WHERE b.moto_id = m.id
            AND b.status IN ('pending', 'active')
            AND b.start_date < p_end
            AND b.end_date > p_start
      );
END;
$$;


ALTER FUNCTION "public"."get_available_motos"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_category" "text", "p_license" "public"."license_group", "p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_booking_loyalty_rate"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b     bookings%ROWTYPE;
  v_level int := 0;
  v_pct   numeric := 0;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('level', 0, 'percent', 0);
  END IF;
  IF NOT (auth.role() = 'service_role' OR is_admin()
          OR auth.uid() IS NOT DISTINCT FROM v_b.user_id) THEN
    RETURN jsonb_build_object('level', 0, 'percent', 0);
  END IF;
  IF COALESCE(v_b.booking_source, 'web') <> 'app' THEN
    RETURN jsonb_build_object('level', 0, 'percent', 0);
  END IF;
  v_level := LEAST(20, CEIL((_loyalty_qualifying_count(v_b.user_id) + 1) / 2.0))::int;
  SELECT COALESCE(discount_percent, 0) INTO v_pct FROM loyalty_levels WHERE level = v_level;
  RETURN jsonb_build_object('level', v_level, 'percent', COALESCE(v_pct, 0));
END;
$$;


ALTER FUNCTION "public"."get_booking_loyalty_rate"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_branch_gear_calendar"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") RETURNS TABLE("shortage_date" "date", "accessory_type" "text", "size" "text", "is_consumable" boolean, "stock" integer, "booked" integer, "free" integer, "deficit" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with days as (select generate_series(p_from,p_to,interval '1 day')::date d),
  types as (
    select at.key type, s.size, coalesce(at.is_consumable,false) is_consumable, coalesce(at.sort_order,0) so
    from accessory_types at
    cross join lateral unnest(coalesce(at.sizes,'{}'::text[])) s(size)
    where at.is_active = true
      and ( at.key in ('helmet','jacket','pants','boots','gloves')   -- fyzické typy z rezervací
            or coalesce(at.is_consumable,false) = true )             -- + spotřební (kukla…)
  ),
  stock as (select type, size, quantity from branch_accessories where branch_id=p_branch_id),
  universe as (
    select type, size, is_consumable, so from types
    union
    select s.type, s.size,
      coalesce((select bool_or(t.is_consumable) from types t where t.type=s.type), false),
      coalesce((select min(t.so) from types t where t.type=s.type), 999)
    from stock s
    where not exists (select 1 from types t where t.type=s.type and t.size=s.size)
  ),
  bk as (
    select b.start_date::date sd, b.end_date::date ed, x.type, x.size
    from bookings b join motorcycles m on m.id=b.moto_id
    cross join lateral (values
      ('helmet',b.helmet_size),('jacket',b.jacket_size),('pants',b.pants_size),
      ('boots',b.boots_size),('gloves',b.gloves_size),
      ('helmet',b.passenger_helmet_size),('jacket',b.passenger_jacket_size),
      ('pants',b.passenger_pants_size),('boots',b.passenger_boots_size),('gloves',b.passenger_gloves_size)
    ) x(type,size)
    where m.branch_id=p_branch_id and b.status in ('pending','reserved','active')
      and coalesce(b.pickup_method,'')<>'delivery' and x.size is not null and x.size<>''
  ),
  booked as (select d.d, bk.type, bk.size, count(*)::int n from days d join bk on d.d between bk.sd and bk.ed group by 1,2,3)
  select d.d, u.type, u.size, u.is_consumable,
    coalesce(s.quantity,0)::int, coalesce(bo.n,0)::int,
    greatest(coalesce(s.quantity,0)-coalesce(bo.n,0),0)::int,
    greatest(coalesce(bo.n,0)-coalesce(s.quantity,0),0)::int
  from days d cross join universe u
  left join stock s on s.type=u.type and s.size=u.size
  left join booked bo on bo.d=d.d and bo.type=u.type and bo.size=u.size
  order by u.is_consumable, u.so, u.type, u.size, d.d
$$;


ALTER FUNCTION "public"."get_branch_gear_calendar"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_branch_routes"("p_branch_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(t order by t.sort_order, t.distance_km nulls last), '[]'::jsonb)
  from (
    select r.*,
      (select round(avg(rating)::numeric,1) from public.route_reviews rr
         where rr.route_id = r.id and rr.status='approved') as review_avg,
      (select count(*) from public.route_reviews rr
         where rr.route_id = r.id and rr.status='approved') as review_count,
      coalesce(
        (select jsonb_agg(
           to_jsonb(p) || jsonb_build_object(
             'avg_rating',   (select round(avg(rating)::numeric,1) from public.poi_ratings pr where pr.route_poi_id = p.id),
             'rating_count', (select count(*) from public.poi_ratings pr where pr.route_poi_id = p.id)
           ) order by p.sort_order)
         from public.route_pois p where p.route_id = r.id),
        '[]'::jsonb
      ) as pois
    from public.routes r
    where r.is_active = true and r.status = 'approved'
      and (p_branch_id is null or r.branch_id = p_branch_id)
  ) t;
$$;


ALTER FUNCTION "public"."get_branch_routes"("p_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_branch_routes_lite"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(t.j order by t.sort_order, t.distance_km nulls last),
                  '[]'::jsonb)
  from (
    select r.sort_order, r.distance_km,
      jsonb_build_object(
        'id', r.id,
        'branch_id', r.branch_id,
        'name', r.name,
        'route_type', r.route_type,
        'distance_km', r.distance_km,
        'duration_min', r.duration_min,
        'difficulty', r.difficulty,
        'waypoints', r.waypoints,
        'mapy_url', r.mapy_url,
        'cover_image', coalesce(r.cover_image, r.images[1]),
        'countries', to_jsonb(r.countries),
        'translations', public.jsonb_name_translations(r.translations),
        'review_avg', rv.avg_rating,
        'review_count', coalesce(rv.review_count, 0),
        'pois', coalesce(ps.pois, '[]'::jsonb)
      ) as j
    from public.routes r
    left join (
      select route_id,
             round(avg(rating)::numeric, 1) as avg_rating,
             count(*)                        as review_count
      from public.route_reviews
      where status = 'approved'
      group by route_id
    ) rv on rv.route_id = r.id
    left join (
      select p.route_id,
             jsonb_agg(jsonb_build_object(
               'id', p.id,
               'name', p.name,
               'lat', p.lat, 'lng', p.lng,
               'image_url', coalesce(p.image_url, p.images[1]),
               'translations', public.jsonb_name_translations(p.translations),
               'avg_rating', pr.avg_rating,
               'rating_count', coalesce(pr.rating_count, 0)
             ) order by p.sort_order) as pois
      from public.route_pois p
      left join (
        select route_poi_id,
               round(avg(rating)::numeric, 1) as avg_rating,
               count(*)                        as rating_count
        from public.poi_ratings
        where route_poi_id is not null
        group by route_poi_id
      ) pr on pr.route_poi_id = p.id
      group by p.route_id
    ) ps on ps.route_id = r.id
    where r.is_active = true and r.status = 'approved'
  ) t;
$$;


ALTER FUNCTION "public"."get_branch_routes_lite"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_document_translation"("p_template_slug" "text", "p_language" "text" DEFAULT 'cs'::"text") RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
  v_html text;
BEGIN
  IF p_language = 'cs' OR p_language IS NULL THEN
    SELECT content_html INTO v_html FROM document_templates
     WHERE type = p_template_slug AND active = true LIMIT 1;
    RETURN v_html;
  END IF;

  SELECT content_translations->>p_language INTO v_html
    FROM document_templates
   WHERE type = p_template_slug AND active = true LIMIT 1;

  RETURN v_html;  -- NULL pokud překlad neexistuje
END;
$$;


ALTER FUNCTION "public"."get_document_translation"("p_template_slug" "text", "p_language" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_handover_protocol_state"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
  v_self boolean;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_b.user_id <> v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  v_self := _is_self_service_booking(p_booking_id);

  RETURN jsonb_build_object(
    'is_self_service', v_self,
    'started_at',  v_b.handover_protocol_started_at,
    'deadline',    CASE WHEN v_b.handover_protocol_started_at IS NOT NULL
                        THEN v_b.handover_protocol_started_at + interval '1 hour' END,
    'filled_at',   v_b.handover_protocol_filled_at,
    'autofilled',  v_b.handover_protocol_autofilled,
    'locked',      (v_b.handover_protocol_filled_at IS NOT NULL),
    'can_fill',    (v_self
                    AND v_b.status IN ('reserved','active')
                    AND v_b.handover_protocol_started_at IS NOT NULL
                    AND v_b.handover_protocol_filled_at IS NULL)
  );
END;
$$;


ALTER FUNCTION "public"."get_handover_protocol_state"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_loyalty_celebration_motos"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with personal as (
    select mc.id, mc.brand, mc.model, mc.color,
      coalesce(nullif(mc.image_url,''), nullif((mc.images)[1],'')) as image_url,
      coalesce(mc.videos, '{}') as videos,
      count(*) filter (where b.status='completed') as rentals,
      max(coalesce(b.returned_at, b.actual_return_date, b.end_date)) as last_rented
    from bookings b join motorcycles mc on mc.id = b.moto_id
    where b.user_id = auth.uid() and b.status='completed'
      and coalesce(b.is_test,false)=false and coalesce(mc.is_trailer,false)=false
    group by mc.id, mc.brand, mc.model, mc.color, mc.image_url, mc.images, mc.videos
  ),
  personal_good as (
    select * from personal
    where image_url is not null or array_length(videos,1) > 0
    order by last_rented desc nulls last limit 3
  ),
  fallback as (
    select mc.id, mc.brand, mc.model, mc.color,
      coalesce(nullif(mc.image_url,''), nullif((mc.images)[1],'')) as image_url,
      coalesce(mc.videos,'{}') as videos, 0::bigint as rentals, null::timestamptz as last_rented
    from motorcycles mc
    where mc.status='active' and coalesce(mc.is_trailer,false)=false
      and (mc.image_url is not null or array_length(mc.videos,1)>0 or array_length(mc.images,1)>0)
    order by (array_length(mc.videos,1)>0) desc nulls last, mc.sort_order asc nulls last, mc.model asc
    limit 3
  )
  select case when exists (select 1 from personal_good) then jsonb_build_object(
    'is_personalized', true,
    'motos', (select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'brand',brand,'model',model,'color',color,'image_url',image_url,
      'video_url',nullif(videos[1],''),'videos',to_jsonb(videos),
      'rentals',rentals,'last_rented',last_rented) order by last_rented desc nulls last),'[]'::jsonb) from personal_good))
  else jsonb_build_object(
    'is_personalized', false,
    'motos', (select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'brand',brand,'model',model,'color',color,'image_url',image_url,
      'video_url',nullif(videos[1],''),'videos',to_jsonb(videos),'rentals',rentals)),'[]'::jsonb) from fallback)) end;
$$;


ALTER FUNCTION "public"."get_loyalty_celebration_motos"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_loyalty_leaderboard"("p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ms date := date_trunc('month', CURRENT_DATE)::date;
  v_me date := (date_trunc('month', CURRENT_DATE) + interval '1 month')::date;
  v_rows jsonb; v_win jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','unauthenticated'); END IF;

  WITH month_days AS (
    SELECT b.user_id, SUM(GREATEST(1, (b.end_date - b.start_date)))::int AS days
    FROM bookings b
    WHERE b.booking_source = 'app' AND b.status IN ('active','completed')
      AND b.start_date >= v_ms AND b.start_date < v_me
    GROUP BY b.user_id
  ),
  ranked AS (
    SELECT p.id, btrim(p.loyalty_nickname) AS nick, md.days,
           LEAST(20, CEIL((_loyalty_effective_count(p.id) + 1)/2.0))::int AS lvl
    FROM profiles p
    JOIN month_days md ON md.user_id = p.id
    WHERE p.loyalty_leaderboard_opt_in = true
      AND NULLIF(btrim(p.loyalty_nickname), '') IS NOT NULL
  ),
  numbered AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY days DESC, lvl DESC, nick ASC) AS rn
    FROM ranked
  )
  SELECT jsonb_agg(jsonb_build_object(
    'rank_pos', n.rn, 'nickname', n.nick, 'days', n.days,
    'level', n.lvl, 'percent', n.lvl,
    'rank_name', ll.name, 'color_hex', ll.color_hex,
    'is_me', (n.id = v_uid)
  ) ORDER BY n.rn)
  INTO v_rows
  FROM numbered n LEFT JOIN loyalty_levels ll ON ll.level = n.lvl
  WHERE n.rn <= p_limit;

  SELECT jsonb_build_object('nickname', w.nickname, 'days', w.days,
                            'month', to_char(w.month,'YYYY-MM'))
    INTO v_win
  FROM loyalty_monthly_winners w
  WHERE w.user_id IS NOT NULL
  ORDER BY w.month DESC LIMIT 1;

  RETURN jsonb_build_object(
    'month', to_char(v_ms,'YYYY-MM'),
    'entries', COALESCE(v_rows, '[]'::jsonb),
    'last_winner', v_win
  );
END; $$;


ALTER FUNCTION "public"."get_loyalty_leaderboard"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_loyalty_status"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cnt int; v_pct int; v_bonus int; v_optin boolean; v_nick text;
  v_cur loyalty_levels%ROWTYPE; v_next loyalty_levels%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'unauthenticated'); END IF;
  SELECT COALESCE(loyalty_bonus_points,0), COALESCE(loyalty_leaderboard_opt_in,true),
         loyalty_nickname
    INTO v_bonus, v_optin, v_nick
  FROM profiles WHERE id = v_uid;
  v_cnt := _loyalty_effective_count(v_uid);
  v_pct := LEAST(20, CEIL((v_cnt + 1) / 2.0))::int;
  SELECT * INTO v_cur  FROM loyalty_levels WHERE level = v_pct;
  SELECT * INTO v_next FROM loyalty_levels WHERE level = v_pct + 1;
  RETURN jsonb_build_object(
    'level', v_pct,
    'percent', COALESCE(v_cur.discount_percent, v_pct),
    'rank_name', COALESCE(v_cur.name, 'Startér'),
    'color_hex', COALESCE(v_cur.color_hex, '#9CA3AF'),
    'qualifying_count', v_cnt,
    'max_level', 20,
    'next_rank_name', v_next.name,
    'next_percent', v_next.discount_percent,
    'next_color_hex', v_next.color_hex,
    'bookings_to_next', CASE WHEN v_pct >= 20 THEN NULL ELSE 2 * v_pct - v_cnt END,
    'leaderboard_opt_in', v_optin,
    'nickname', v_nick,
    'bonus_points', v_bonus
  );
END; $$;


ALTER FUNCTION "public"."get_loyalty_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_moto_booked_dates"("p_moto_id" "uuid") RETURNS TABLE("start_date" "date", "end_date" "date", "status" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  -- Přímé rezervace (kus jako motorka i jako samostatně půjčený vozík)
  SELECT b.start_date::date, b.end_date::date, b.status::text, b.created_at
  FROM bookings b
  WHERE b.moto_id = p_moto_id
    AND b.status IN ('pending','reserved','active')

  UNION ALL

  -- Gear add-on: tento vozík je přiřazený jako příslušenství k rezervaci motorky
  SELECT b.start_date::date, b.end_date::date, b.status::text, b.created_at
  FROM bookings b
  WHERE b.trailer_moto_id = p_moto_id
    AND b.status IN ('pending','reserved','active')

  UNION ALL

  -- Servis blokuje POUZE rozsah service_date → scheduled_date.
  SELECT
    m.service_date::date,
    COALESCE(m.scheduled_date, m.service_date)::date,
    'service'::text,
    m.created_at
  FROM maintenance_log m
  WHERE m.moto_id = p_moto_id
    AND m.service_date IS NOT NULL
    AND m.completed_date IS NULL
    AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
    AND COALESCE(m.scheduled_date, m.service_date) >= CURRENT_DATE;
$$;


ALTER FUNCTION "public"."get_moto_booked_dates"("p_moto_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_motos_availability_status"() RETURNS TABLE("moto_id" "uuid", "next_available_date" "date")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  m RECORD;
  bk RECORD;
  d DATE;
BEGIN
  FOR m IN
    SELECT id FROM motorcycles WHERE status = 'active'
  LOOP
    d := CURRENT_DATE;
    FOR bk IN
      SELECT b.start_date::date AS s, b.end_date::date AS e
      FROM bookings b
      WHERE b.moto_id = m.id
        AND b.status IN ('pending','reserved','active')
        AND b.end_date::date >= CURRENT_DATE
      ORDER BY b.start_date ASC
    LOOP
      IF bk.s <= d AND bk.e >= d THEN
        d := bk.e + INTERVAL '1 day';
      ELSIF bk.s > d THEN
        EXIT;
      END IF;
    END LOOP;
    moto_id := m.id;
    next_available_date := d;
    RETURN NEXT;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."get_motos_availability_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_places"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v.id,
    'route_poi_id', v.route_poi_id, 'user_poi_id', v.user_poi_id, 'poi_id', v.poi_id,
    'name', coalesce(rp.name, up.name, cp.name, v.name),
    'lat', coalesce(rp.lat, up.lat, cp.lat, v.lat),
    'lng', coalesce(rp.lng, up.lng, cp.lng, v.lng),
    'image_url', coalesce(rp.image_url, up.image_url, cp.image_url),
    'route_id', v.route_id, 'route_name', r.name,
    'first_visited_at', v.first_visited_at, 'last_visited_at', v.last_visited_at,
    'visit_count', v.visit_count
  ) order by v.last_visited_at desc), '[]'::jsonb)
  from public.user_visited_places v
  left join public.route_pois rp on rp.id = v.route_poi_id
  left join public.user_pois up on up.id = v.user_poi_id
  left join public.points_of_interest cp on cp.id = v.poi_id
  left join public.routes r on r.id = v.route_id
  where v.user_id = auth.uid();
$$;


ALTER FUNCTION "public"."get_my_places"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_saved_routes"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'name', s.name, 'description', s.description,
    'source_route_id', s.source_route_id,
    'waypoints', s.waypoints, 'poi_refs', s.poi_refs,
    'profile', s.profile, 'distance_km', s.distance_km,
    'duration_min', s.duration_min, 'created_at', s.created_at
  ) order by s.created_at desc), '[]'::jsonb)
  from public.user_saved_routes s
  where s.user_id = auth.uid();
$$;


ALTER FUNCTION "public"."get_my_saved_routes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_page_ai_traffic"("p_path" "text", "p_from" timestamp with time zone DEFAULT ("now"() - '30 days'::interval), "p_to" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM ai_traffic_log WHERE path = p_path AND ts BETWEEN p_from AND p_to),
    'by_bot', (
      SELECT jsonb_object_agg(coalesce(bot_name,'unknown'), c)
      FROM (SELECT bot_name, count(*) c FROM ai_traffic_log WHERE path = p_path AND ts BETWEEN p_from AND p_to GROUP BY bot_name) s
    ),
    'daily', (
      SELECT jsonb_agg(jsonb_build_object('date', d, 'count', c) ORDER BY d)
      FROM (
        SELECT date_trunc('day', ts)::date d, count(*) c
        FROM ai_traffic_log WHERE path = p_path AND ts BETWEEN p_from AND p_to
        GROUP BY 1
      ) s
    ),
    'led_to_bookings', (
      SELECT count(*) FROM ai_traffic_log
      WHERE path = p_path AND outcome = 'booking_created' AND ts BETWEEN p_from AND p_to
    )
  ) INTO result;

  RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_page_ai_traffic"("p_path" "text", "p_from" timestamp with time zone, "p_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_poi_detail"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    (select jsonb_build_object(
      'id', p.id, 'name', p.name, 'description', p.description,
      'surroundings', p.surroundings,
      'lat', p.lat, 'lng', p.lng,
      'image_url', p.image_url, 'images', to_jsonb(p.images),
      'translations', p.translations, 'category', p.category,
      'country', p.country, 'is_catalog', true,
      'avg_rating',   (select round(avg(rating)::numeric, 1) from poi_ratings r where r.poi_id = p.id),
      'rating_count', (select count(*) from poi_ratings r where r.poi_id = p.id)
    )
    from public.points_of_interest p
    where p.id = p_id and p.is_active = true),
    'null'::jsonb
  );
$$;


ALTER FUNCTION "public"."get_poi_detail"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_poi_reviews"("p_route_poi_id" "uuid" DEFAULT NULL::"uuid", "p_user_poi_id" "uuid" DEFAULT NULL::"uuid", "p_poi_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with vis as (
    select r.* from poi_ratings r
    where r.route_poi_id is not distinct from p_route_poi_id
      and r.user_poi_id  is not distinct from p_user_poi_id
      and r.poi_id       is not distinct from p_poi_id
      and (r.status = 'approved' or r.user_id = auth.uid() or is_admin())
  )
  select jsonb_build_object(
    'avg',   (select round(avg(rating)::numeric,1) from vis where status='approved'),
    'count', (select count(*) from vis where status='approved'),
    'my', (
      select to_jsonb(m) from (
        select rating, review_text, photos from vis where user_id = auth.uid() limit 1
      ) m
    ),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'rating', v.rating, 'review_text', v.review_text, 'photos', v.photos,
        'status', v.status, 'is_mine', (v.user_id = auth.uid()),
        'author', coalesce(nullif(btrim(p.loyalty_nickname),''),
                           nullif(btrim(p.full_name),''), 'Motorkář'),
        'created_at', v.created_at
      ) order by (v.user_id = auth.uid()) desc, v.created_at desc)
      from vis v left join profiles p on p.id = v.user_id
      where v.review_text is not null or coalesce(array_length(v.photos,1),0) > 0
    ), '[]'::jsonb)
  );
$$;


ALTER FUNCTION "public"."get_poi_reviews"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_pois_catalog"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'translations', coalesce(p.translations_names, '{}'::jsonb),
    'lat', p.lat, 'lng', p.lng,
    'image_url', coalesce(p.image_url, p.images[1]),
    'category', p.category,
    'country', p.country,
    'is_catalog', true,
    'avg_rating', r.avg_rating,
    'rating_count', coalesce(r.rating_count, 0)
  )), '[]'::jsonb)
  from public.points_of_interest p
  left join (
    select poi_id,
           round(avg(rating)::numeric, 1) as avg_rating,
           count(*)                        as rating_count
    from public.poi_ratings
    where poi_id is not null
    group by poi_id
  ) r on r.poi_id = p.id
  where p.is_active = true;
$$;


ALTER FUNCTION "public"."get_pois_catalog"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_promo_code_type"("p_code" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT type FROM public.promo_codes WHERE code = upper(p_code) LIMIT 1;
$$;


ALTER FUNCTION "public"."get_promo_code_type"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_route_detail"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce((
    select to_jsonb(r) || jsonb_build_object(
      'review_avg',   (select round(avg(rating)::numeric, 1)
                         from public.route_reviews rr
                        where rr.route_id = r.id and rr.status = 'approved'),
      'review_count', (select count(*)
                         from public.route_reviews rr
                        where rr.route_id = r.id and rr.status = 'approved'),
      'pois', coalesce((
        select jsonb_agg(to_jsonb(p) || jsonb_build_object(
                 'avg_rating',   (select round(avg(rating)::numeric, 1)
                                    from public.poi_ratings pr
                                   where pr.route_poi_id = p.id),
                 'rating_count', (select count(*)
                                    from public.poi_ratings pr
                                   where pr.route_poi_id = p.id)
               ) order by p.sort_order)
        from public.route_pois p where p.route_id = r.id), '[]'::jsonb)
    )
    from public.routes r
    where r.id = p_id and r.is_active = true and r.status = 'approved'
  ), 'null'::jsonb);
$$;


ALTER FUNCTION "public"."get_route_detail"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_route_poi_detail"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce((
    select to_jsonb(p) || jsonb_build_object(
      'avg_rating',   (select round(avg(rating)::numeric, 1)
                         from public.poi_ratings pr where pr.route_poi_id = p.id),
      'rating_count', (select count(*)
                         from public.poi_ratings pr where pr.route_poi_id = p.id)
    )
    from public.route_pois p
    join public.routes r on r.id = p.route_id
    where p.id = p_id and r.is_active = true
  ), 'null'::jsonb);
$$;


ALTER FUNCTION "public"."get_route_poi_detail"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_route_reviews"("p_route_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  with vis as (
    select r.* from route_reviews r
    where r.route_id = p_route_id
      and (r.status = 'approved' or r.user_id = auth.uid() or is_admin())
  )
  select jsonb_build_object(
    'avg',   (select round(avg(rating)::numeric,1) from vis where status='approved'),
    'count', (select count(*) from vis where status='approved'),
    'my', (
      select to_jsonb(m) from (
        select rating, review_text, photos from vis where user_id = auth.uid() limit 1
      ) m
    ),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id,
        'rating', v.rating,
        'review_text', v.review_text,
        'photos', v.photos,
        'status', v.status,
        'is_mine', (v.user_id = auth.uid()),
        'author', coalesce(nullif(btrim(p.loyalty_nickname),''),
                           nullif(btrim(p.full_name),''), 'Motorkář'),
        'created_at', v.created_at
      ) order by (v.user_id = auth.uid()) desc, v.created_at desc)
      from vis v left join profiles p on p.id = v.user_id
    ), '[]'::jsonb)
  );
$$;


ALTER FUNCTION "public"."get_route_reviews"("p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_trailer_availability"("p_start" "date", "p_end" "date", "p_exclude_booking" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  WITH free AS (
    SELECT m.id, m.created_at
    FROM motorcycles m
    WHERE m.is_trailer = true
      AND m.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM bookings b
        WHERE (b.moto_id = m.id OR b.trailer_moto_id = m.id)
          AND b.status IN ('pending','reserved','active')
          AND (p_exclude_booking IS NULL OR b.id <> p_exclude_booking)
          AND b.start_date::date <= p_end
          AND b.end_date::date   >= p_start)
      AND NOT EXISTS (
        SELECT 1 FROM maintenance_log ml
        WHERE ml.moto_id = m.id
          AND ml.service_date IS NOT NULL
          AND ml.completed_date IS NULL
          AND COALESCE(ml.status,'') NOT IN ('completed','cancelled')
          AND ml.service_date <= p_end
          AND COALESCE(ml.scheduled_date, ml.service_date) >= p_start)
  )
  SELECT jsonb_build_object(
    'available_count', (SELECT count(*) FROM free),
    'trailer_id', (SELECT id FROM free ORDER BY created_at LIMIT 1));
$$;


ALTER FUNCTION "public"."get_trailer_availability"("p_start" "date", "p_end" "date", "p_exclude_booking" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unread_thread_message_count"("p_customer_id" "uuid") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT COALESCE(COUNT(*)::integer, 0)
  FROM messages m
  JOIN message_threads t ON t.id = m.thread_id
  WHERE t.customer_id = p_customer_id
    AND m.direction = 'admin'
    AND m.read_at IS NULL;
$$;


ALTER FUNCTION "public"."get_unread_thread_message_count"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_visitor_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_host" "text" DEFAULT NULL::"text", "p_granularity" "text" DEFAULT 'day'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "statement_timeout" TO '20s'
    AS $$
declare
  v_result jsonb;
  v_trunc  text;
  v_tz     constant text := 'Europe/Prague';
begin
  if not is_admin() then
    raise exception 'Access denied';
  end if;

  v_trunc := case lower(coalesce(p_granularity, 'day'))
    when 'week'  then 'week'
    when 'month' then 'month'
    when 'year'  then 'year'
    else 'day'
  end;

  with base as (
    -- jen sloupce, které agregace níže reálně potřebují (ne select *)
    select ts, host, visitor_hash, referrer_type, referrer_domain,
           path, referrer, device, country,
           -- lokální (Europe/Prague) hodina 0–23 a den v týdnu 1=Po … 7=Ne
           extract(hour  from ts at time zone v_tz)::int  as loc_hour,
           extract(isodow from ts at time zone v_tz)::int as loc_dow
    from visitor_log
    where ts >= p_from and ts < p_to
      and (p_host is null or host = p_host)
  )
  select jsonb_build_object(
    'total_views',     (select count(*) from base),
    'unique_visitors', (select count(distinct visitor_hash) from base),

    'by_host', (select coalesce(jsonb_object_agg(h, c), '{}'::jsonb) from (
        select coalesce(nullif(host, ''), '(neznámá)') h, count(*) c
        from base group by 1 order by c desc limit 50) t),

    'by_referrer_type', (select coalesce(jsonb_object_agg(rt, c), '{}'::jsonb) from (
        select coalesce(nullif(referrer_type, ''), 'direct') rt, count(*) c
        from base group by 1) t),

    'by_referrer_domain', (select coalesce(jsonb_agg(jsonb_build_object('name', d, 'count', c) order by c desc), '[]'::jsonb) from (
        select coalesce(nullif(referrer_domain, ''), '(přímý vstup)') d, count(*) c
        from base
        where coalesce(referrer_type, 'direct') <> 'internal'
        group by 1 order by c desc limit 30) t),

    'top_paths', (select coalesce(jsonb_agg(jsonb_build_object('path', p, 'count', c) order by c desc), '[]'::jsonb) from (
        select coalesce(path, '/') p, count(*) c
        from base group by 1 order by c desc limit 30) t),

    'top_referrers', (select coalesce(jsonb_agg(jsonb_build_object('referrer', r, 'count', c) order by c desc), '[]'::jsonb) from (
        select referrer r, count(*) c
        from base where referrer is not null and referrer <> ''
        group by 1 order by c desc limit 30) t),

    'by_device', (select coalesce(jsonb_object_agg(dev, c), '{}'::jsonb) from (
        select coalesce(nullif(device, ''), 'unknown') dev, count(*) c
        from base group by 1) t),

    'by_country', (select coalesce(jsonb_agg(jsonb_build_object('name', co, 'count', c) order by c desc), '[]'::jsonb) from (
        select country co, count(*) c
        from base where country is not null and country <> ''
        group by 1 order by c desc limit 30) t),

    'timeline', (select coalesce(jsonb_agg(jsonb_build_object('bucket', b, 'views', v, 'visitors', uv) order by b), '[]'::jsonb) from (
        select date_trunc(v_trunc, ts) b, count(*) v, count(distinct visitor_hash) uv
        from base group by 1 order by 1) t),

    -- NOVÉ: vytíženost po hodinách (napříč všemi dny rozsahu), lokální čas
    'by_hour', (select coalesce(jsonb_agg(jsonb_build_object('hour', h, 'views', v, 'visitors', uv) order by h), '[]'::jsonb) from (
        select loc_hour h, count(*) v, count(distinct visitor_hash) uv
        from base group by 1 order by 1) t),

    -- NOVÉ: vytíženost po dnech v týdnu (1=Po … 7=Ne)
    'by_dow', (select coalesce(jsonb_agg(jsonb_build_object('dow', d, 'views', v, 'visitors', uv) order by d), '[]'::jsonb) from (
        select loc_dow d, count(*) v, count(distinct visitor_hash) uv
        from base group by 1 order by 1) t),

    -- NOVÉ: heatmapa den × hodina (jen buňky s daty; nuly dopočte frontend)
    'by_dow_hour', (select coalesce(jsonb_agg(jsonb_build_object('dow', d, 'hour', h, 'views', v) order by d, h), '[]'::jsonb) from (
        select loc_dow d, loc_hour h, count(*) v
        from base group by 1, 2 order by 1, 2) t)
  ) into v_result;

  return v_result;
end;
$$;


ALTER FUNCTION "public"."get_visitor_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_host" "text", "p_granularity" "text") OWNER TO "postgres";


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
    p.full_name AS customer_name, p.email AS customer_email,
    m.license_required
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p     ON p.id = b.user_id
  LEFT JOIN motorcycles m  ON m.id = b.moto_id
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
    'docs_status',    v_docs_status
  );
END;
$$;


ALTER FUNCTION "public"."get_web_booking_confirmation"("p_session_id" "text", "p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_web_booking_resume"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_result jsonb;
  v_uid    uuid;
  v_end    date;
  v_moto   uuid;
  v_docs   text;
BEGIN
  -- Nejprve ověř, že rezervace odpovídá povoleným stavům (jinak = not found).
  SELECT b.user_id, b.end_date::date, b.moto_id
    INTO v_uid, v_end, v_moto
    FROM bookings b
   WHERE b.id = p_booking_id
     AND b.booking_source = 'web'
     AND (
       (b.status = 'pending' AND b.payment_status = 'unpaid')
       OR (b.status IN ('reserved','active') AND b.payment_status IN ('paid','partial_refund','refund_pending'))
     );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  -- docs_status v izolovaném bloku — případná výjimka NESMÍ shodit celý resume
  -- (jinak by se návrat z platební brány jevil jako „Rezervace nenalezena").
  BEGIN
    v_docs := check_booking_docs_status(v_uid, v_end, v_moto);
  EXCEPTION WHEN OTHERS THEN
    v_docs := NULL;
  END;

  SELECT jsonb_build_object(
    'booking_id',           b.id,
    'user_id',              b.user_id,
    'moto_id',              b.moto_id,
    'moto_model',           m.model,
    'start_date',           b.start_date,
    'end_date',             b.end_date,
    'total_price',          b.total_price,
    'extras_price',         b.extras_price,
    'discount_amount',      b.discount_amount,
    'discount_code',        b.discount_code,
    'promo_code',           pc.code,
    'voucher_id',           b.voucher_id,
    'voucher_code',         vc.code,
    'voucher_amount',       vc.amount,
    'pickup_time',          b.pickup_time,
    'return_time',          b.return_time,
    'delivery_address',     b.pickup_address,
    'return_address',       b.return_address,
    'notes',                b.notes,
    'helmet_size',          b.helmet_size,
    'jacket_size',          b.jacket_size,
    'pants_size',           b.pants_size,
    'boots_size',           b.boots_size,
    'gloves_size',          b.gloves_size,
    'passenger_helmet_size', b.passenger_helmet_size,
    'passenger_jacket_size', b.passenger_jacket_size,
    'passenger_gloves_size', b.passenger_gloves_size,
    'passenger_boots_size',  b.passenger_boots_size,
    'customer_name',        p.full_name,
    'customer_email',       p.email,
    'customer_phone',       p.phone,
    'customer_street',      p.street,
    'customer_city',        p.city,
    'customer_zip',         p.zip,
    'customer_country',     p.country,
    'license_group',        p.license_group,
    'license_expiry',       p.license_expiry,
    'date_of_birth',        p.date_of_birth,
    'id_number',            p.id_number,
    'license_number',       p.license_number,
    'has_id_number',        (p.id_number IS NOT NULL AND p.id_number <> ''),
    'has_license_number',   (p.license_number IS NOT NULL AND p.license_number <> ''),
    'has_password',         (p.password_last4_bcrypt IS NOT NULL),
    'payment_status',       b.payment_status,
    'booking_status',       b.status,
    'pay_channel',          b.pay_channel,
    'docs_status',          v_docs,
    'extras',               COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'name',       be.name,
          'unit_price', be.unit_price,
          'quantity',   be.quantity
        )
        ORDER BY be.id
      )
      FROM booking_extras be
      WHERE be.booking_id = b.id
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM bookings b
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  LEFT JOIN profiles    p ON p.id = b.user_id
  LEFT JOIN promo_codes pc ON pc.id = b.promo_code_id
  LEFT JOIN vouchers    vc ON vc.id = b.voucher_id
  WHERE b.id = p_booking_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."get_web_booking_resume"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_web_shop_order_confirmation"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_order record;
  v_vouchers jsonb;
begin
  if p_order_id is null then
    return jsonb_build_object('error', 'missing_identifier');
  end if;

  select id, order_number, customer_name, customer_email,
         total, subtotal, shipping_cost, discount,
         payment_status, status, shipping_method,
         created_at, confirmed_at, notes
    into v_order
    from public.shop_orders
   where id = p_order_id
   limit 1;

  if v_order.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  -- Načti případné vouchery vytvořené pro tuto objednávku
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', code,
           'amount', amount,
           'valid_until', valid_until
         ) order by created_at), '[]'::jsonb)
    into v_vouchers
    from public.vouchers
   where order_id = p_order_id;

  return jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'customer_name', v_order.customer_name,
    'customer_email', v_order.customer_email,
    'total', v_order.total,
    'subtotal', v_order.subtotal,
    'shipping_cost', v_order.shipping_cost,
    'discount', v_order.discount,
    'payment_status', v_order.payment_status,
    'status', v_order.status,
    'shipping_method', v_order.shipping_method,
    'created_at', v_order.created_at,
    'confirmed_at', v_order.confirmed_at,
    'notes', v_order.notes,
    'vouchers', v_vouchers
  );
end;
$$;


ALTER FUNCTION "public"."get_web_shop_order_confirmation"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone, registration_source)
  VALUES (
    NEW.id,
    lower(NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    COALESCE(NEW.raw_user_meta_data->>'registration_source', 'auth_trigger')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE id = auth.uid() AND active = true
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM admin_users WHERE id = p_user_id);
END;
$$;


ALTER FUNCTION "public"."is_admin"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_superadmin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE id = auth.uid() AND role = 'superadmin' AND active = true
  );
$$;


ALTER FUNCTION "public"."is_superadmin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jsonb_name_translations"("t" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select coalesce(
           jsonb_object_agg(e.k, jsonb_build_object('name', e.v->'name')),
           '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(t) = 'object'
                       then t else '{}'::jsonb end) as e(k, v)
  where jsonb_typeof(e.v) = 'object' and e.v ? 'name';
$$;


ALTER FUNCTION "public"."jsonb_name_translations"("t" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_command_broadcast"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  BEGIN
    PERFORM realtime.send(jsonb_build_object('id', NEW.id), 'cmd', 'kiosk:' || NEW.device_id::text, false);
  EXCEPTION WHEN undefined_function THEN NULL; WHEN undefined_table THEN NULL; WHEN others THEN NULL;
  END;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."kiosk_command_broadcast"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_complete_command"("p_device_id" "uuid", "p_device_token" "uuid", "p_command_id" "uuid", "p_success" boolean, "p_result" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  UPDATE public.kiosk_commands
     SET status = CASE WHEN p_success THEN 'done' ELSE 'failed' END,
         result = coalesce(p_result,'{}'::jsonb), executed_at = now()
   WHERE id = p_command_id AND device_id = p_device_id;
END; $$;


ALTER FUNCTION "public"."kiosk_complete_command"("p_device_id" "uuid", "p_device_token" "uuid", "p_command_id" "uuid", "p_success" boolean, "p_result" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_device_branch"("p_device_id" "uuid", "p_device_token" "uuid", "p_touch" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_branch uuid;
BEGIN
  SELECT branch_id INTO v_branch FROM public.kiosk_devices
   WHERE id = p_device_id AND device_token = p_device_token AND is_active = true;
  IF v_branch IS NULL THEN RETURN NULL; END IF;
  IF p_touch THEN
    UPDATE public.kiosk_devices SET last_seen_at = now() WHERE id = p_device_id;
  END IF;
  RETURN v_branch;
END; $$;


ALTER FUNCTION "public"."kiosk_device_branch"("p_device_id" "uuid", "p_device_token" "uuid", "p_touch" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_fetch_commands"("p_device_id" "uuid", "p_device_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_bid uuid; v_rows jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'command', command, 'params', params) ORDER BY created_at), '[]'::jsonb)
    INTO v_rows
    FROM public.kiosk_commands
   WHERE device_id = p_device_id AND status = 'pending';
  RETURN jsonb_build_object('ok', true, 'commands', v_rows);
END; $$;


ALTER FUNCTION "public"."kiosk_fetch_commands"("p_device_id" "uuid", "p_device_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_heartbeat"("p_device_id" "uuid", "p_device_token" "uuid", "p_app_version" "text" DEFAULT NULL::"text", "p_platform" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE; v_bid uuid; v_app jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  UPDATE public.kiosk_devices
     SET last_seen_at = now(),
         app_version = COALESCE(p_app_version, app_version),
         platform    = COALESCE(p_platform, platform)
   WHERE id = p_device_id;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;
  SELECT value INTO v_app FROM public.app_settings WHERE key = 'kiosk_app';
  RETURN jsonb_build_object(
    'ok', true, 'branch_id', v_bid, 'branch_name', v_branch.name,
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'music_seconds', COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds', COALESCE(v_cfg.door_open_seconds,8),
    'light_seconds', COALESCE(v_cfg.light_seconds,120),
    'power_status_url', v_cfg.power_status_url,
    'power_poll_seconds', COALESCE(v_cfg.power_poll_seconds,60),
    'update', v_app
  );
END; $$;


ALTER FUNCTION "public"."kiosk_heartbeat"("p_device_id" "uuid", "p_device_token" "uuid", "p_app_version" "text", "p_platform" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_jbool"("p" "jsonb", VARIADIC "keys" "text"[]) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE k text; v text;
BEGIN
  FOREACH k IN ARRAY keys LOOP
    IF p ? k AND (p->>k) IS NOT NULL THEN
      v := lower(p->>k);
      IF v IN ('true','1','on','yes') THEN RETURN true; END IF;
      IF v IN ('false','0','off','no') THEN RETURN false; END IF;
    END IF;
  END LOOP;
  RETURN NULL;
END; $$;


ALTER FUNCTION "public"."kiosk_jbool"("p" "jsonb", VARIADIC "keys" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_jnum"("p" "jsonb", VARIADIC "keys" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE k text;
BEGIN
  FOREACH k IN ARRAY keys LOOP
    IF p ? k AND (p->>k) IS NOT NULL THEN
      BEGIN RETURN (p->>k)::numeric; EXCEPTION WHEN others THEN NULL; END;
    END IF;
  END LOOP;
  RETURN NULL;
END; $$;


ALTER FUNCTION "public"."kiosk_jnum"("p" "jsonb", VARIADIC "keys" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_log_event"("p_device_id" "uuid", "p_device_token" "uuid", "p_level" "text", "p_source" "text", "p_message" "text", "p_detail" "jsonb" DEFAULT '{}'::"jsonb", "p_app_version" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN; END IF;
  INSERT INTO public.kiosk_logs(device_id, branch_id, level, source, message, detail, app_version)
  VALUES (p_device_id, v_bid,
          COALESCE(NULLIF(p_level,''),'info'), p_source, left(coalesce(p_message,''), 4000),
          coalesce(p_detail,'{}'::jsonb), p_app_version);
END; $$;


ALTER FUNCTION "public"."kiosk_log_event"("p_device_id" "uuid", "p_device_token" "uuid", "p_level" "text", "p_source" "text", "p_message" "text", "p_detail" "jsonb", "p_app_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_log_open"("p_device_id" "uuid", "p_device_token" "uuid", "p_door_id" "uuid", "p_kind" "text", "p_booking_id" "uuid", "p_success" boolean, "p_detail" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  INSERT INTO public.branch_door_events(branch_id, device_id, door_id, kind, booking_id, success, detail)
  VALUES (v_bid, p_device_id, p_door_id, p_kind, p_booking_id, coalesce(p_success,true), coalesce(p_detail,'{}'::jsonb));
END; $$;


ALTER FUNCTION "public"."kiosk_log_open"("p_device_id" "uuid", "p_device_token" "uuid", "p_door_id" "uuid", "p_kind" "text", "p_booking_id" "uuid", "p_success" boolean, "p_detail" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_report_power"("p_device_id" "uuid", "p_device_token" "uuid", "p_payload" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  INSERT INTO public.branch_power_status AS bps
    (branch_id, source, battery_soc, battery_voltage, battery_power_w, pv_power_w, load_power_w,
     grid_present, generator_on, raw, updated_at)
  VALUES (
    v_bid, 'tablet',
    public.kiosk_jnum(p_payload, 'battery_soc','soc','SOC','stateOfCharge'),
    public.kiosk_jnum(p_payload, 'battery_voltage','batteryVoltage','vBat','battery_v'),
    public.kiosk_jnum(p_payload, 'battery_power_w','batteryPower','pBat','battery_w'),
    public.kiosk_jnum(p_payload, 'pv_power_w','pvPower','pv_w','solar_w','pPv'),
    public.kiosk_jnum(p_payload, 'load_power_w','loadPower','load_w','consumption_w','pLoad'),
    public.kiosk_jbool(p_payload, 'grid_present','gridPresent','grid','mains'),
    public.kiosk_jbool(p_payload, 'generator_on','generatorOn','generator','genset'),
    coalesce(p_payload, '{}'::jsonb), now()
  )
  ON CONFLICT (branch_id) DO UPDATE SET
    source = 'tablet',
    battery_soc = EXCLUDED.battery_soc, battery_voltage = EXCLUDED.battery_voltage,
    battery_power_w = EXCLUDED.battery_power_w, pv_power_w = EXCLUDED.pv_power_w,
    load_power_w = EXCLUDED.load_power_w, grid_present = EXCLUDED.grid_present,
    generator_on = EXCLUDED.generator_on, raw = EXCLUDED.raw, updated_at = now();
END; $$;


ALTER FUNCTION "public"."kiosk_report_power"("p_device_id" "uuid", "p_device_token" "uuid", "p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
BEGIN
  IF v_code = '' THEN RETURN jsonb_build_object('ok',false,'error','missing_inputs'); END IF;
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;

  -- 1) servisní heslo → seznam všech aktivních dveří (app se zeptá které)
  IF EXISTS (SELECT 1 FROM public.branch_service_codes s WHERE s.branch_id=v_bid AND s.is_active AND s.code=v_code) THEN
    SELECT coalesce(jsonb_agg(d ORDER BY d.ord),'[]'::jsonb) INTO v_doors FROM (
      SELECT bd.id,bd.door_kind,bd.box_number,bd.label,bd.relay_url,bd.light_url,coalesce(bd.box_number,9999) AS ord
        FROM public.branch_doors bd WHERE bd.branch_id=v_bid AND bd.is_active) d;
    RETURN jsonb_build_object('ok',true,'kind','service','branch_id',v_bid,'branch_name',v_branch.name,
      'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
      'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),'doors',v_doors);
  END IF;

  -- 2) zákaznický kód (branch_door_codes) — aktivní, vydaný, v platnosti, této pobočky
  SELECT * INTO v_dc FROM public.branch_door_codes bdc
   WHERE bdc.branch_id=v_bid AND bdc.door_code=v_code AND bdc.is_active=true AND bdc.sent_to_customer=true
     AND (bdc.valid_from IS NULL OR bdc.valid_from<=now()) AND (bdc.valid_until IS NULL OR bdc.valid_until>=now())
   ORDER BY bdc.updated_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','invalid_code'); END IF;

  IF v_dc.code_type='accessories' THEN
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='accessories' AND is_active LIMIT 1;
  ELSE
    SELECT box_number INTO v_box FROM public.motorcycles WHERE id=v_dc.moto_id;
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='motorcycle' AND box_number=v_box AND is_active LIMIT 1;
  END IF;

  RETURN jsonb_build_object('ok',true,'kind',v_dc.code_type,'branch_id',v_bid,'branch_name',v_branch.name,
    'booking_id',v_dc.booking_id,'box_number',coalesce(v_door.box_number,v_box),
    'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),
    'door',CASE WHEN v_door.id IS NULL THEN NULL ELSE jsonb_build_object('id',v_door.id,'door_kind',v_door.door_kind,
      'box_number',v_door.box_number,'label',v_door.label,'relay_url',v_door.relay_url,'light_url',v_door.light_url) END,
    'door_configured',(v_door.id IS NOT NULL));
END; $$;


ALTER FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kiosk_sync_codes"("p_device_id" "uuid", "p_device_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_bid uuid; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_doors jsonb; v_services jsonb; v_codes jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'door_kind', door_kind, 'box_number', box_number,
    'label', label, 'relay_url', relay_url, 'light_url', light_url)), '[]'::jsonb)
  INTO v_doors FROM public.branch_doors WHERE branch_id = v_bid AND is_active;

  SELECT coalesce(jsonb_agg(code), '[]'::jsonb) INTO v_services
  FROM public.branch_service_codes WHERE branch_id = v_bid AND is_active;

  -- Aktivní zákaznické kódy + ke kterým dveřím patří (relay/light pro offline otevření)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'code', bdc.door_code, 'kind', bdc.code_type, 'booking_id', bdc.booking_id,
    'valid_from', bdc.valid_from, 'valid_until', bdc.valid_until,
    'door_id', d.id, 'box_number', d.box_number, 'label', d.label,
    'relay_url', d.relay_url, 'light_url', d.light_url)), '[]'::jsonb)
  INTO v_codes
  FROM public.branch_door_codes bdc
  LEFT JOIN public.motorcycles m ON m.id = bdc.moto_id
  LEFT JOIN public.branch_doors d ON d.branch_id = v_bid AND d.is_active AND (
        (bdc.code_type = 'accessories' AND d.door_kind = 'accessories')
     OR (bdc.code_type = 'motorcycle'  AND d.door_kind = 'motorcycle' AND d.box_number = m.box_number))
  WHERE bdc.branch_id = v_bid AND bdc.is_active = true AND bdc.sent_to_customer = true
    AND (bdc.valid_until IS NULL OR bdc.valid_until >= now() - interval '1 day');

  RETURN jsonb_build_object(
    'ok', true, 'synced_at', now(),
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'music_seconds', COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds', COALESCE(v_cfg.door_open_seconds,8),
    'light_seconds', COALESCE(v_cfg.light_seconds,120),
    'doors', v_doors, 'service_codes', v_services, 'codes', v_codes
  );
END; $$;


ALTER FUNCTION "public"."kiosk_sync_codes"("p_device_id" "uuid", "p_device_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."learn_sku"("p_sku" "text", "p_name" "text", "p_category" "text", "p_type" "text", "p_size" "text", "p_alias" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not is_admin() then return; end if;
  insert into sku_catalog(sku, name, category, type, size, aliases)
    values(p_sku, coalesce(nullif(p_name,''), p_sku), coalesce(nullif(p_category,''),'zbozi'),
           nullif(p_type,''), nullif(p_size,''),
           case when nullif(p_alias,'') is not null then array[lower(p_alias)] else '{}'::text[] end)
  on conflict (sku) do update set
    name    = coalesce(nullif(excluded.name,''), sku_catalog.name),
    type    = coalesce(sku_catalog.type, excluded.type),
    size    = coalesce(sku_catalog.size, excluded.size),
    aliases = case when nullif(p_alias,'') is not null and not (lower(p_alias) = any(sku_catalog.aliases))
                   then array_append(sku_catalog.aliases, lower(p_alias)) else sku_catalog.aliases end,
    updated_at = now();
end $$;


ALTER FUNCTION "public"."learn_sku"("p_sku" "text", "p_name" "text", "p_category" "text", "p_type" "text", "p_size" "text", "p_alias" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_pending_ai_suggestions"("p_limit" integer DEFAULT 50) RETURNS TABLE("message_id" "uuid", "thread_id" "uuid", "channel" "text", "customer_id" "uuid", "inbound_content" "text", "ai_suggested_reply" "text", "ai_confidence" "text", "ai_admin_note" "text", "ai_suggested_at" timestamp with time zone, "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    m.id, m.thread_id, t.channel, t.customer_id,
    m.content, m.ai_suggested_reply, m.ai_confidence, m.ai_admin_note,
    m.ai_suggested_at, m.created_at
  FROM messages m
  JOIN message_threads t ON t.id = m.thread_id
  WHERE m.ai_suggestion_status = 'pending'
    AND m.direction = 'inbound'
  ORDER BY m.created_at DESC
  LIMIT p_limit;
$$;


ALTER FUNCTION "public"."list_pending_ai_suggestions"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_stock_movement"("p_item" "uuid", "p_type" "text", "p_qty" integer, "p_note" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare v_fk text; v_note text; v_user uuid := auth.uid();
begin
  select column_name into v_fk from information_schema.columns
    where table_schema='public' and table_name='inventory_movements'
      and column_name in ('item_id','inventory_id','inventory_item_id') limit 1;
  if v_fk is null then return; end if;
  select column_name into v_note from information_schema.columns
    where table_schema='public' and table_name='inventory_movements'
      and column_name in ('note','notes') limit 1;
  begin
    if v_note is not null then
      execute format('insert into inventory_movements(%I, type, quantity, performed_by, %I) values($1,$2,$3,$4,$5)', v_fk, v_note)
        using p_item, p_type, p_qty, v_user, p_note;
    else
      execute format('insert into inventory_movements(%I, type, quantity, performed_by) values($1,$2,$3,$4)', v_fk)
        using p_item, p_type, p_qty, v_user;
    end if;
  exception when others then
    begin
      execute format('insert into inventory_movements(%I, type, quantity) values($1,$2,$3)', v_fk) using p_item, p_type, p_qty;
    exception when others then null; end;
  end;
end $_$;


ALTER FUNCTION "public"."log_stock_movement"("p_item" "uuid", "p_type" "text", "p_qty" integer, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."loyalty_advance_celebrated"("p_level" integer) RETURNS integer
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  UPDATE profiles
     SET loyalty_celebrated_level = GREATEST(COALESCE(loyalty_celebrated_level, 0), p_level)
   WHERE id = auth.uid()
  RETURNING loyalty_celebrated_level;
$$;


ALTER FUNCTION "public"."loyalty_advance_celebrated"("p_level" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."loyalty_award_monthly_winner"("p_month" "date" DEFAULT ("date_trunc"('month'::"text", (CURRENT_DATE - '1 day'::interval)))::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end   date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_winner uuid; v_nick text; v_days int; v_lvl int;
BEGIN
  IF EXISTS (SELECT 1 FROM loyalty_monthly_winners WHERE month = v_start) THEN
    RETURN jsonb_build_object('status','already_awarded','month',to_char(v_start,'YYYY-MM'));
  END IF;

  SELECT p.id, btrim(p.loyalty_nickname),
         SUM(GREATEST(1, (b.end_date - b.start_date)))::int
    INTO v_winner, v_nick, v_days
  FROM bookings b JOIN profiles p ON p.id = b.user_id
  WHERE b.booking_source='app' AND b.status IN ('active','completed')
    AND b.start_date >= v_start AND b.start_date < v_end
    AND p.loyalty_leaderboard_opt_in = true
    AND NULLIF(btrim(p.loyalty_nickname), '') IS NOT NULL
  GROUP BY p.id, p.loyalty_nickname
  ORDER BY SUM(GREATEST(1, (b.end_date - b.start_date))) DESC, p.id ASC
  LIMIT 1;

  IF v_winner IS NULL THEN
    INSERT INTO loyalty_monthly_winners(month, days) VALUES (v_start, 0);
    RETURN jsonb_build_object('status','no_participants','month',to_char(v_start,'YYYY-MM'));
  END IF;

  v_lvl := LEAST(20, CEIL((_loyalty_effective_count(v_winner)+1)/2.0))::int;
  UPDATE profiles SET loyalty_bonus_points = COALESCE(loyalty_bonus_points,0) + 4
  WHERE id = v_winner;
  INSERT INTO loyalty_monthly_winners(month, user_id, nickname, days, awarded_level_before)
  VALUES (v_start, v_winner, v_nick, v_days, v_lvl);

  RETURN jsonb_build_object('status','awarded','month',to_char(v_start,'YYYY-MM'),
    'winner', v_nick, 'days', v_days, 'bonus_points', 4);
END; $$;


ALTER FUNCTION "public"."loyalty_award_monthly_winner"("p_month" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."loyalty_get_celebrated"() RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(loyalty_celebrated_level, 0)
  FROM profiles WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."loyalty_get_celebrated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_place_visited"("p_route_poi_id" "uuid" DEFAULT NULL::"uuid", "p_user_poi_id" "uuid" DEFAULT NULL::"uuid", "p_poi_id" "uuid" DEFAULT NULL::"uuid", "p_route_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_name text; v_lat double precision; v_lng double precision;
  v_first boolean := false; v_count int; v_total int;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id, p_poi_id) <> 1 then
    return jsonb_build_object('success', false, 'error', 'one_target_required');
  end if;

  if p_route_poi_id is not null then
    select p.name, p.lat, p.lng into v_name, v_lat, v_lng
      from route_pois p where p.id = p_route_poi_id;
  elsif p_user_poi_id is not null then
    select p.name, p.lat, p.lng into v_name, v_lat, v_lng
      from user_pois p where p.id = p_user_poi_id;
  else
    select p.name, p.lat, p.lng into v_name, v_lat, v_lng
      from points_of_interest p where p.id = p_poi_id;
  end if;
  if v_name is null then return jsonb_build_object('success', false, 'error', 'place_not_found'); end if;

  if p_route_poi_id is not null then
    insert into user_visited_places (user_id, route_poi_id, name, lat, lng, route_id)
    values (auth.uid(), p_route_poi_id, v_name, v_lat, v_lng, p_route_id)
    on conflict (user_id, route_poi_id) do update
      set last_visited_at = now(), visit_count = user_visited_places.visit_count + 1
    returning (visit_count = 1), visit_count into v_first, v_count;
  elsif p_user_poi_id is not null then
    insert into user_visited_places (user_id, user_poi_id, name, lat, lng, route_id)
    values (auth.uid(), p_user_poi_id, v_name, v_lat, v_lng, p_route_id)
    on conflict (user_id, user_poi_id) do update
      set last_visited_at = now(), visit_count = user_visited_places.visit_count + 1
    returning (visit_count = 1), visit_count into v_first, v_count;
  else
    insert into user_visited_places (user_id, poi_id, name, lat, lng, route_id)
    values (auth.uid(), p_poi_id, v_name, v_lat, v_lng, p_route_id)
    on conflict (user_id, poi_id) do update
      set last_visited_at = now(), visit_count = user_visited_places.visit_count + 1
    returning (visit_count = 1), visit_count into v_first, v_count;
  end if;

  select count(*) into v_total from user_visited_places where user_id = auth.uid();
  return jsonb_build_object('success', true, 'first_visit', v_first,
                            'visit_count', v_count, 'total_places', v_total);
end;
$$;


ALTER FUNCTION "public"."mark_place_visited"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_route_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_license_group"("p_existing" "public"."license_group"[], "p_new" "text") RETURNS "public"."license_group"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  v_new    license_group;
  v_has_b  boolean := false;
  v_rank   int := 0;
  v_g      license_group;
  v_result license_group[] := '{}';
BEGIN
  IF p_new IS NOT NULL AND btrim(p_new) <> '' THEN
    BEGIN
      v_new := upper(btrim(p_new))::license_group;   -- T/C/D/BE… spadnou sem a ignorují se
    EXCEPTION WHEN OTHERS THEN
      v_new := NULL;
    END;
  END IF;

  IF v_new IS NULL THEN
    RETURN p_existing;
  END IF;

  IF p_existing IS NOT NULL THEN
    FOREACH v_g IN ARRAY p_existing LOOP
      IF v_g = 'B' THEN v_has_b := true; END IF;
      v_rank := GREATEST(v_rank, public._license_moto_rank(v_g));
    END LOOP;
  END IF;

  IF v_new = 'B' THEN v_has_b := true; END IF;
  v_rank := GREATEST(v_rank, public._license_moto_rank(v_new));

  IF    v_rank = 4 THEN v_result := array_append(v_result, 'A'::license_group);
  ELSIF v_rank = 3 THEN v_result := array_append(v_result, 'A2'::license_group);
  ELSIF v_rank = 2 THEN v_result := array_append(v_result, 'A1'::license_group);
  ELSIF v_rank = 1 THEN v_result := array_append(v_result, 'AM'::license_group);
  END IF;
  IF v_has_b THEN v_result := array_append(v_result, 'B'::license_group); END IF;

  IF array_length(v_result, 1) IS NULL THEN RETURN p_existing; END IF;
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."merge_license_group"("p_existing" "public"."license_group"[], "p_new" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_license_group_multi"("p_existing" "public"."license_group"[], "p_raw" "text") RETURNS "public"."license_group"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
  v_result license_group[] := p_existing;
  v_tok    text;
BEGIN
  IF p_raw IS NULL OR btrim(p_raw) = '' THEN RETURN p_existing; END IF;
  FOREACH v_tok IN ARRAY regexp_split_to_array(upper(p_raw), '[^A-Z0-9]+') LOOP
    IF v_tok <> '' THEN
      v_result := public.merge_license_group(v_result, v_tok);
    END IF;
  END LOOP;
  RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."merge_license_group_multi"("p_existing" "public"."license_group"[], "p_raw" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mirror_route_images_tick"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_key text;
  v_url text;
begin
  select value #>> '{}' into v_key from app_settings where key = 'service_role_key';
  select value #>> '{}' into v_url from app_settings where key = 'supabase_url';
  if v_key is null then return; end if;
  perform net.http_post(
    url := coalesce(v_url, 'https://vnwnqteskbykeucanlhk.supabase.co') || '/functions/v1/mirror-route-images',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
end;
$$;


ALTER FUNCTION "public"."mirror_route_images_tick"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."next_document_number"("p_prefix" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_seq int;
  v_live_max int;
BEGIN
  INSERT INTO document_number_counters (prefix, year, last_seq)
  VALUES (p_prefix, v_year, 0)
  ON CONFLICT (prefix, year) DO NOTHING;

  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0)
    INTO v_live_max
    FROM invoices
   WHERE number LIKE p_prefix||'-'||v_year||'-%'
     AND CAST(SUBSTRING(number FROM '-(\d+)$') AS int) < 5000;

  UPDATE document_number_counters                 -- row-lock serializuje souběh
     SET last_seq = GREATEST(last_seq, v_live_max) + 1
   WHERE prefix = p_prefix AND year = v_year
  RETURNING last_seq INTO v_seq;

  RETURN p_prefix||'-'||v_year||'-'||LPAD(v_seq::text, 4, '0');
END; $_$;


ALTER FUNCTION "public"."next_document_number"("p_prefix" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_registration_source"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.registration_source = 'auth_trigger' THEN
    NEW.registration_source := NULL;
  END IF;
  RETURN NEW;
END
$$;


ALTER FUNCTION "public"."normalize_registration_source"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_supplier_name"("input" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT lower(
    translate(input,
      'áäčďéěíľňóöřšťúůüýžÁÄČĎÉĚÍĽŇÓÖŘŠŤÚŮÜÝŽ',
      'aacdeeillnoorstuuuyzAACDEEILNOORSTUUUYZ'
    )
  )
$$;


ALTER FUNCTION "public"."normalize_supplier_name"("input" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_booking_activated_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_email text; v_name text; v_moto text; v_url text; v_key text;
BEGIN
  IF OLD.status != 'reserved' OR NEW.status != 'active' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM message_log WHERE booking_id = NEW.id AND template_slug LIKE 'booking_reserved%' AND channel = 'email' AND content_preview LIKE '%aktivována%' AND status = 'sent') THEN RETURN NEW; END IF;
  SELECT email, full_name INTO v_email, v_name FROM profiles WHERE id = NEW.user_id;
  IF v_email IS NULL THEN RETURN NEW; END IF;
  SELECT model INTO v_moto FROM motorcycles WHERE id = NEW.moto_id;
  v_url := current_setting('supabase.url', true); v_key := current_setting('supabase.service_role_key', true);
  PERFORM net.http_post(url := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    body := jsonb_build_object('type','booking_reserved','booking_id',NEW.id,'customer_email',v_email,'customer_name',COALESCE(v_name,''),'motorcycle',COALESCE(v_moto,''),'start_date',NEW.start_date,'end_date',NEW.end_date,'total_price',NEW.total_price,'source',COALESCE(NEW.booking_source,'app')));
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_booking_activated_email failed: %', SQLERRM; RETURN NEW;
END; $$;


ALTER FUNCTION "public"."notify_booking_activated_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_booking_cancelled_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_url text; v_key text;
BEGIN
  IF EXISTS (SELECT 1 FROM message_log WHERE booking_id = NEW.id AND template_slug = 'booking_cancelled' AND channel = 'email' AND status = 'sent' LIMIT 1) THEN RETURN NEW; END IF;
  v_url := current_setting('supabase.url', true); v_key := current_setting('supabase.service_role_key', true);
  PERFORM net.http_post(url := v_url || '/functions/v1/send-cancellation-email',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    body := jsonb_build_object('booking_id',NEW.id,'cancellation_reason',COALESCE(NEW.cancellation_reason,''),'cancelled_by_source',COALESCE(NEW.cancelled_by_source,''),'source',COALESCE(NEW.booking_source,'app')));
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_booking_cancelled_email failed: %', SQLERRM; RETURN NEW;
END; $$;


ALTER FUNCTION "public"."notify_booking_cancelled_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_booking_completed_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_email text; v_name text; v_moto text; v_url text; v_key text; v_google text;
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF NEW.payment_status != 'paid' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM message_log WHERE booking_id = NEW.id AND template_slug = 'booking_completed' AND channel = 'email' AND status = 'sent') THEN RETURN NEW; END IF;
  SELECT email, full_name INTO v_email, v_name FROM profiles WHERE id = NEW.user_id;
  IF v_email IS NULL THEN RETURN NEW; END IF;
  SELECT model INTO v_moto FROM motorcycles WHERE id = NEW.moto_id;
  SELECT value::text INTO v_google FROM app_settings WHERE key = 'google_review_url';
  v_url := current_setting('supabase.url', true); v_key := current_setting('supabase.service_role_key', true);
  PERFORM net.http_post(url := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    body := jsonb_build_object('type','booking_completed','booking_id',NEW.id,'customer_email',v_email,'customer_name',COALESCE(v_name,''),'motorcycle',COALESCE(v_moto,''),'start_date',NEW.start_date,'end_date',NEW.end_date,'total_price',NEW.total_price,'source',COALESCE(NEW.booking_source,'app'),'google_review_url',COALESCE(v_google,''),'facebook_review_url','https://facebook.com/MotoGo24/reviews'));
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_booking_completed_email failed: %', SQLERRM; RETURN NEW;
END; $$;


ALTER FUNCTION "public"."notify_booking_completed_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_sos_incident_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_email text; v_name text; v_url text; v_key text;
BEGIN
  SELECT email, full_name INTO v_email, v_name FROM profiles WHERE id = NEW.user_id;
  IF v_email IS NULL THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM message_log WHERE booking_id = NEW.booking_id AND template_slug = 'sos_incident' AND channel = 'email' AND status = 'sent') THEN RETURN NEW; END IF;
  v_url := current_setting('supabase.url', true); v_key := current_setting('supabase.service_role_key', true);
  PERFORM net.http_post(url := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key,'apikey',v_key),
    body := jsonb_build_object('type','sos_incident','booking_id',NEW.booking_id,'customer_email',v_email,'customer_name',COALESCE(v_name,''),'source','app'));
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_sos_incident_email failed: %', SQLERRM; RETURN NEW;
END; $$;


ALTER FUNCTION "public"."notify_sos_incident_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_web_booking_abandoned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_profile RECORD;
  v_moto RECORD;
  v_booking_number TEXT;
  v_resume_link TEXT;
BEGIN
  -- Only for web bookings that were pending and got cancelled
  IF NEW.status = 'cancelled' AND OLD.status = 'pending'
     AND NEW.booking_source = 'web'
     AND NEW.payment_status = 'unpaid' THEN

    -- Get customer info
    SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;
    SELECT model INTO v_moto FROM motorcycles WHERE id = NEW.moto_id;

    IF v_profile.email IS NOT NULL THEN
      v_booking_number := upper(left(NEW.id::text, 8));
      v_resume_link := 'https://motogo24.cz/#/rezervace?resume=' || NEW.id::text;

      -- Send abandoned email via edge function
      PERFORM net.http_post(
        url := current_setting('app.settings.supabase_url', true) || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
          'type', 'booking_abandoned',
          'booking_id', NEW.id,
          'customer_email', v_profile.email,
          'customer_name', v_profile.full_name,
          'motorcycle', v_moto.model,
          'source', 'web',
          'resume_link', v_resume_link
        )
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'notify_web_booking_abandoned error: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_web_booking_abandoned"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."poi_rating_summary"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("avg_rating" numeric, "rating_count" integer, "my_rating" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select round(avg(r.rating)::numeric, 1),
         count(*)::int,
         max(case when r.user_id = auth.uid() then r.rating end)::int
  from poi_ratings r
  where r.route_poi_id is not distinct from p_route_poi_id
    and r.user_poi_id  is not distinct from p_user_poi_id
    and r.poi_id       is not distinct from p_poi_id;
$$;


ALTER FUNCTION "public"."poi_rating_summary"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."point_country"("p_lat" double precision, "p_lng" double precision) RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select code from (values
    ('CZ', 49.80, 15.50),
    ('DE', 51.10, 10.40),
    ('AT', 47.60, 14.10),
    ('PL', 52.00, 19.10),
    ('SK', 48.70, 19.70)
  ) as c(code, clat, clng)
  where p_lat is not null and p_lng is not null
  order by (p_lat-clat)*(p_lat-clat) + (p_lng-clng)*(p_lng-clng)
  limit 1;
$$;


ALTER FUNCTION "public"."point_country"("p_lat" double precision, "p_lng" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."post_invoice_to_financial_event"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_cust text;
  v_has_stripe boolean;
BEGIN
  -- 1) co se nepropisuje
  IF COALESCE(NEW.status,'') = 'cancelled' THEN RETURN NEW; END IF;
  IF NEW.type = 'received' THEN RETURN NEW; END IF;          -- přijaté řeší vlastní tok
  IF COALESCE(NEW.total,0) = 0 THEN RETURN NEW; END IF;      -- nulová KF apod.

  -- 2) idempotence — událost pro tuto fakturu už existuje
  IF EXISTS (SELECT 1 FROM financial_events
             WHERE linked_entity_type = 'invoice' AND linked_entity_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- 3) dedup proti Stripe: stejná rezervace/objednávka + stejná částka + stejné znaménko
  SELECT EXISTS (
    SELECT 1 FROM financial_events fe
    WHERE fe.source = 'stripe'
      AND (
        (NEW.booking_id IS NOT NULL AND fe.linked_entity_id = NEW.booking_id) OR
        (NEW.order_id   IS NOT NULL AND fe.linked_entity_id = NEW.order_id)
      )
      AND round(abs(fe.amount_czk)) = round(abs(NEW.total))
      AND sign(fe.amount_czk) = sign(NEW.total)
  ) INTO v_has_stripe;
  IF v_has_stripe THEN RETURN NEW; END IF;

  SELECT full_name INTO v_cust FROM profiles WHERE id = NEW.customer_id;

  INSERT INTO financial_events (
    event_type, source, amount_czk, vat_rate, duzp,
    linked_entity_type, linked_entity_id, confidence_score, status, metadata
  ) VALUES (
    'revenue', 'manual', NEW.total, 0, COALESCE(NEW.issue_date, CURRENT_DATE),
    'invoice', NEW.id, 1.0, 'enriched',
    jsonb_build_object(
      'invoice_number', NEW.number,
      'invoice_type',   NEW.type,
      'invoice_source', NEW.source,
      'customer_name',  COALESCE(v_cust, NEW.customer_snapshot->>'name'),
      'variable_symbol', NEW.variable_symbol,
      'due_date',       NEW.due_date,
      'payment_method', NEW.payment_method,
      'booking_id',     NEW.booking_id,
      'order_id',       NEW.order_id,
      'ai_classification', jsonb_build_object('category',
        CASE WHEN NEW.type = 'credit_note'  THEN 'vraceni'
             WHEN NEW.order_id  IS NOT NULL THEN 'prodej_zbozi'
             WHEN NEW.booking_id IS NOT NULL THEN 'pronajem_motorek'
             ELSE 'ostatni' END)
    )
  );
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- nikdy neshodit vznik faktury kvůli účetní události
  BEGIN
    INSERT INTO debug_log(source, action, component, status, error_message)
    VALUES ('post_invoice_to_financial_event','insert_failed','db-trigger','error', SQLERRM);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."post_invoice_to_financial_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rate_poi"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_rating" integer, "p_poi_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id, p_poi_id) <> 1 then
    raise exception 'exactly one poi target required';
  end if;
  if p_rating < 1 or p_rating > 5 then
    delete from poi_ratings where user_id = auth.uid()
      and route_poi_id is not distinct from p_route_poi_id
      and user_poi_id  is not distinct from p_user_poi_id
      and poi_id       is not distinct from p_poi_id;
    return;
  end if;
  if p_route_poi_id is not null then
    insert into poi_ratings(user_id, route_poi_id, rating)
    values (auth.uid(), p_route_poi_id, p_rating)
    on conflict (user_id, route_poi_id) do update set rating = excluded.rating, updated_at = now();
  elsif p_user_poi_id is not null then
    insert into poi_ratings(user_id, user_poi_id, rating)
    values (auth.uid(), p_user_poi_id, p_rating)
    on conflict (user_id, user_poi_id) do update set rating = excluded.rating, updated_at = now();
  else
    insert into poi_ratings(user_id, poi_id, rating)
    values (auth.uid(), p_poi_id, p_rating)
    on conflict (user_id, poi_id) do update set rating = excluded.rating, updated_at = now();
  end if;
end;
$$;


ALTER FUNCTION "public"."rate_poi"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_rating" integer, "p_poi_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."receive_stock_from_document"("p_lines" "jsonb", "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare ln jsonb; v_inv record; v_qty int; v_sku text; v_name text; v_price numeric; v_cat text;
  v_stocked int:=0; v_item_id uuid;
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then return jsonb_build_object('success',false,'error','bad_input'); end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    v_sku := nullif(trim(ln->>'sku'),''); v_qty := coalesce((ln->>'qty')::int,0);
    if v_sku is null or v_qty<=0 then continue; end if;
    v_name := coalesce(nullif(trim(ln->>'name'),''), v_sku);
    v_price := coalesce((ln->>'unit_price')::numeric,0);
    v_cat := coalesce(nullif(trim(ln->>'category'),''), case when v_sku like 'prislusenstvi-%' then 'prislusenstvi' else 'inventory' end);
    select * into v_inv from inventory where sku=v_sku limit 1;
    if found then
      update inventory set stock=coalesce(stock,0)+v_qty,
        unit_price=case when coalesce(unit_price,0)=0 and v_price>0 then v_price else unit_price end where id=v_inv.id;
      v_item_id := v_inv.id;
    else
      insert into inventory(sku,name,category,stock,min_stock,unit_price) values(v_sku,v_name,v_cat,v_qty,0,v_price) returning id into v_item_id;
    end if;
    perform public.log_stock_movement(v_item_id, 'receipt', v_qty, coalesce(p_note,'Naskladnění z dokladu'));
    v_stocked := v_stocked+1;
  end loop;
  return jsonb_build_object('success',true,'stocked',v_stocked);
end $$;


ALTER FUNCTION "public"."receive_stock_from_document"("p_lines" "jsonb", "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_stock_receipt"("p_doc_type" "text", "p_doc_number" "text" DEFAULT NULL::"text", "p_doc_date" "date" DEFAULT NULL::"date", "p_variable_symbol" "text" DEFAULT NULL::"text", "p_supplier_ico" "text" DEFAULT NULL::"text", "p_supplier_name" "text" DEFAULT NULL::"text", "p_amount" numeric DEFAULT 0, "p_financial_event_id" "uuid" DEFAULT NULL::"uuid", "p_will_stock" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_norm text := public._norm_supplier(p_supplier_name);
  v_tol numeric := greatest(coalesce(p_amount, 0) * 0.02, 1);   -- tolerance 2 %, min 1 Kč
  v_cp public.stock_receipts;
  v_duplicate boolean := false;
  v_effective_stock boolean;
  v_needs_dl boolean := false;
  v_id uuid;
begin
  -- Najdi nespárovaný protějšek OPAČNÉHO typu od stejného dodavatele s podobnou částkou (posl. 120 dní)
  select * into v_cp from public.stock_receipts r
  where r.doc_type <> p_doc_type
    and r.matched_receipt_id is null
    and abs(coalesce(r.amount_czk, 0) - coalesce(p_amount, 0)) <= v_tol
    and (
      (p_supplier_ico is not null and r.supplier_ico is not null and r.supplier_ico = p_supplier_ico)
      or (coalesce(p_supplier_ico, '') = '' and v_norm <> '' and public._norm_supplier(r.supplier_name) = v_norm)
    )
    and r.created_at > now() - interval '120 days'
  order by r.created_at desc
  limit 1;

  -- Pokud protějšek už zboží naskladnil → tenhle doklad NEnaskladňuje (duplicita)
  if v_cp.id is not null and v_cp.stocked then
    v_duplicate := true;
  end if;

  v_effective_stock := coalesce(p_will_stock, true) and not v_duplicate;

  -- Faktura, ke které se nenašel DL → "chybí DL"
  if p_doc_type = 'invoice' and v_cp.id is null then
    v_needs_dl := true;
  end if;

  insert into public.stock_receipts(
    doc_type, doc_number, doc_date, variable_symbol, supplier_ico, supplier_name,
    amount_czk, financial_event_id, stocked, matched_receipt_id, needs_dl)
  values (
    p_doc_type, p_doc_number, p_doc_date, p_variable_symbol, p_supplier_ico, p_supplier_name,
    p_amount, p_financial_event_id, v_effective_stock, v_cp.id, v_needs_dl)
  returning id into v_id;

  -- Spáruj protějšek zpět; pokud nově přišel DL k faktuře, zruš protějšku "chybí DL"
  if v_cp.id is not null then
    update public.stock_receipts
      set matched_receipt_id = v_id,
          needs_dl = case when p_doc_type = 'delivery_note' then false else needs_dl end
      where id = v_cp.id;
  end if;

  return jsonb_build_object(
    'receipt_id', v_id,
    'duplicate', v_duplicate,
    'will_stock', v_effective_stock,
    'matched_receipt_id', v_cp.id,
    'needs_dl', v_needs_dl
  );
end $$;


ALTER FUNCTION "public"."record_stock_receipt"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric, "p_financial_event_id" "uuid", "p_will_stock" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."redeem_booking_discounts_on_paid"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE r record; v_src text; v_url text; v_key text;
BEGIN
  IF NOT (NEW.payment_status = 'paid' AND OLD.payment_status IS DISTINCT FROM 'paid') THEN RETURN NEW; END IF;
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key='supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key='service_role_key';
  FOR r IN SELECT * FROM booking_discounts WHERE booking_id = NEW.id LOOP
    IF r.kind = 'voucher' AND r.voucher_id IS NOT NULL THEN
      v_src := NULL;
      UPDATE vouchers SET status='redeemed', redeemed_at=now(), redeemed_by=NEW.user_id, booking_id=NEW.id, updated_at=now()
        WHERE id = r.voucher_id AND status='active' RETURNING source INTO v_src;
      IF v_src = 'slevomat' AND v_url IS NOT NULL AND v_key IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(url := v_url || '/functions/v1/slevomat-voucher',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
            body := jsonb_build_object('action','apply','code', r.code));
        EXCEPTION WHEN OTHERS THEN
          INSERT INTO debug_log(source,action,status,error_message,request_data)
          VALUES('redeem_booking_discounts_on_paid','slevomat_apply_failed','error',SQLERRM,
                 jsonb_build_object('booking_id',NEW.id,'code',r.code));
        END;
      END IF;
    ELSIF r.kind = 'promo_code' AND r.promo_code_id IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM promo_code_usage WHERE promo_code_id=r.promo_code_id AND booking_id=NEW.id) THEN
        INSERT INTO promo_code_usage (promo_code_id, booking_id, customer_id, discount_applied, used_at)
        VALUES (r.promo_code_id, NEW.id, NEW.user_id, r.amount, now());
        UPDATE promo_codes SET used_count = COALESCE(used_count,0) + 1 WHERE id = r.promo_code_id;
      END IF;
    END IF;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'redeem_booking_discounts_on_paid failed for %: %', NEW.id, SQLERRM; RETURN NEW;
END; $$;


ALTER FUNCTION "public"."redeem_booking_discounts_on_paid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."regen_door_codes_on_moto_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_branch_id uuid;
  v_withheld text;
  v_has_docs boolean;
  v_code1 text;
  v_code2 text;
  v_phone text;
BEGIN
  IF OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('active','reserved') THEN RETURN NEW; END IF;

  UPDATE branch_door_codes SET is_active = false
   WHERE booking_id = NEW.id AND is_active = true;

  SELECT branch_id INTO v_branch_id FROM motorcycles WHERE id = NEW.moto_id;
  IF v_branch_id IS NULL THEN RETURN NEW; END IF;

  v_withheld := check_booking_docs_status(NEW.user_id, NEW.end_date::date);
  v_has_docs := v_withheld IS NULL;

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
        'Nové přístupové kódy',
        'Změnili jste motorku – nové kódy:' || E'\n' ||
        'Kód k motorce: ' || v_code1 || E'\n' ||
        'Kód k příslušenství: ' || v_code2 || E'\n' ||
        'Kódy jsou platné (' ||
        TO_CHAR(NEW.start_date::date, 'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(NEW.end_date::date, 'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone, 'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(NEW.id::text,8)),
            'door_code_moto', v_code1,
            'door_code_gear', v_code2
          ), NEW.user_id, NEW.id);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      DELETE FROM message_log
      WHERE booking_id = NEW.id
        AND template_slug IN ('door_codes','web_door_codes')
        AND channel = 'email';
    EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM send_door_codes_email(NEW.id, NEW.user_id);
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'regen_door_codes_on_moto_change failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."regen_door_codes_on_moto_change"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."regen_door_codes_on_moto_change"() IS 'Při změně motorky na bookingu: deaktivuj staré kódy, vygeneruj nové, notifikuj zákazníka.';



CREATE OR REPLACE FUNCTION "public"."regen_voucher_for_order"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order shop_orders%ROWTYPE;
  v_item RECORD;
  v_all_items_count INT;
  v_voucher_items_count INT;
  v_is_all_vouchers BOOL;
  v_has_physical_voucher BOOL := false;
  v_code TEXT;
  v_valid_until DATE := CURRENT_DATE + INTERVAL '3 years';
  v_codes TEXT[] := '{}';
  v_i INT;
BEGIN
  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

  -- Idempotence: pokud vouchery už existují, nedělej nic
  IF EXISTS (SELECT 1 FROM vouchers WHERE order_id = p_order_id) THEN
    RETURN jsonb_build_object('success', true, 'skipped', 'vouchers_exist');
  END IF;

  SELECT COUNT(*) INTO v_all_items_count FROM shop_order_items WHERE order_id = p_order_id;
  SELECT COUNT(*) INTO v_voucher_items_count
  FROM shop_order_items WHERE order_id = p_order_id
    AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%');

  IF v_voucher_items_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'skipped', 'no_voucher_items');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM shop_order_items WHERE order_id = p_order_id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
      AND (LOWER(product_name) LIKE '%tišt%' OR LOWER(product_name) LIKE '%fyzick%' OR LOWER(product_name) LIKE '%printed%')
  ) INTO v_has_physical_voucher;
  IF NOT v_has_physical_voucher AND COALESCE(v_order.notes, '') ILIKE '%fyzick%' THEN
    v_has_physical_voucher := true;
  END IF;
  v_is_all_vouchers := (v_voucher_items_count = v_all_items_count);

  FOR v_item IN
    SELECT * FROM shop_order_items WHERE order_id = p_order_id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
  LOOP
    FOR v_i IN 1..GREATEST(v_item.quantity, 1) LOOP
      v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text || v_i::text) FROM 1 FOR 6));
      WHILE EXISTS (SELECT 1 FROM vouchers WHERE code = v_code) LOOP
        v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));
      END LOOP;
      v_codes := array_append(v_codes, v_code);

      INSERT INTO vouchers (
        code, amount, currency, status,
        buyer_id, buyer_name, buyer_email,
        valid_from, valid_until,
        source, order_id, category
      ) VALUES (
        v_code,
        COALESCE(v_item.unit_price, v_item.total_price, 0),
        'CZK', 'active',
        v_order.customer_id,
        COALESCE(NULLIF(v_order.customer_name, ''), 'Web zákazník'),
        COALESCE(NULLIF(v_order.customer_email, ''), ''),
        CURRENT_DATE, v_valid_until,
        'eshop', p_order_id, 'gift'
      );
    END LOOP;
  END LOOP;

  -- Aktualizuj status
  UPDATE shop_orders SET
    status = CASE
      WHEN v_is_all_vouchers AND NOT v_has_physical_voucher THEN 'delivered'
      ELSE 'confirmed'
    END,
    confirmed_at = COALESCE(confirmed_at, NOW()),
    delivered_at = CASE
      WHEN v_is_all_vouchers AND NOT v_has_physical_voucher THEN NOW()
      ELSE delivered_at
    END
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'codes_generated', array_length(v_codes, 1),
    'is_digital', v_is_all_vouchers AND NOT v_has_physical_voucher
  );
END;
$$;


ALTER FUNCTION "public"."regen_voucher_for_order"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_codes_on_profile_verify"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.id_verified_at      IS DISTINCT FROM OLD.id_verified_at
  OR NEW.passport_verified_at IS DISTINCT FROM OLD.passport_verified_at
  OR NEW.license_verified_at IS DISTINCT FROM OLD.license_verified_at
  OR NEW.id_number           IS DISTINCT FROM OLD.id_number
  OR NEW.license_number      IS DISTINCT FROM OLD.license_number
  THEN
    PERFORM release_withheld_door_codes_for_user(NEW.id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN RETURN NEW;
END; $$;


ALTER FUNCTION "public"."release_codes_on_profile_verify"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."release_codes_on_profile_verify"() IS 'Při update Mindee ověřovacích sloupců v profilu uvolní zadržené door codes (pojistka když insert do documents selže).';



CREATE OR REPLACE FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_uid uuid;
  v_booking record;
  v_reason text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
  v_released int := 0;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT id, user_id, start_date, end_date, status, moto_id
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
    RETURN jsonb_build_object('success', true, 'released', 0, 'message', 'No withheld codes');
  END IF;

  -- KANONICKÁ kontrola dokladů: fotka NEBO OCR verified_at + expirace ŘP + child-bike skip
  v_reason := check_booking_docs_status(v_uid, v_booking.end_date::date, v_booking.moto_id);
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Documents missing', 'withheld_reason', v_reason);
  END IF;

  -- Uvolni kódy
  UPDATE branch_door_codes
  SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
  WHERE booking_id = p_booking_id AND is_active = true AND sent_to_customer = false;
  GET DIAGNOSTICS v_released = ROW_COUNT;

  SELECT door_code INTO v_code_moto FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
  SELECT door_code INTO v_code_gear FROM branch_door_codes
   WHERE booking_id = p_booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

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

  BEGIN
    SELECT phone INTO v_phone FROM profiles WHERE id = v_uid;
    IF v_phone IS NOT NULL AND v_phone <> '' THEN
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

  PERFORM send_door_codes_email(p_booking_id, v_uid);

  RETURN jsonb_build_object('success', true, 'released', v_released);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") IS 'RPC: zákazník zavolá po platbě — ověří doklady a uvolní zadržené přístupové kódy.';



CREATE OR REPLACE FUNCTION "public"."release_swap_next_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."release_swap_next_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_withheld_door_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.user_id IS NOT NULL THEN
    PERFORM release_withheld_door_codes_for_user(NEW.user_id);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."release_withheld_door_codes"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."release_withheld_door_codes"() IS 'Při nahrání dokladů uvolní zadržené přístupové kódy a pošle notifikaci zákazníkovi.';



CREATE OR REPLACE FUNCTION "public"."release_withheld_door_codes_for_user"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_booking record;
  v_withheld text;
  v_code_moto text;
  v_code_gear text;
  v_phone text;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;

  FOR v_booking IN
    SELECT DISTINCT b.id AS booking_id, b.user_id, b.start_date, b.end_date
    FROM bookings b
    JOIN branch_door_codes bdc ON bdc.booking_id = b.id
    WHERE b.user_id = p_user_id
      AND b.status IN ('reserved','active')   -- ⬅ POJISTKA: jen aktivní/nadcházející rezervace (ne zrušené/dokončené)
      AND bdc.is_active = true
      AND bdc.sent_to_customer = false
  LOOP
    v_withheld := check_booking_docs_status(v_booking.user_id, v_booking.end_date::date);
    IF v_withheld IS NOT NULL THEN
      -- Aktualizuj jen důvod (třeba z "Chybí doklady" na "ŘP propadlý")
      UPDATE branch_door_codes
      SET withheld_reason = v_withheld
      WHERE booking_id = v_booking.booking_id
        AND is_active = true
        AND sent_to_customer = false
        AND withheld_reason IS DISTINCT FROM v_withheld;
      CONTINUE; -- neuvolňujeme
    END IF;

    -- Uvolni
    UPDATE branch_door_codes
    SET sent_to_customer = true, sent_at = NOW(), withheld_reason = NULL
    WHERE booking_id = v_booking.booking_id
      AND is_active = true
      AND sent_to_customer = false;

    SELECT door_code INTO v_code_moto FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'motorcycle' AND is_active = true LIMIT 1;
    SELECT door_code INTO v_code_gear FROM branch_door_codes
     WHERE booking_id = v_booking.booking_id AND code_type = 'accessories' AND is_active = true LIMIT 1;

    BEGIN
      INSERT INTO admin_messages (user_id, title, message, type)
      VALUES (
        v_booking.user_id,
        'Přístupové kódy k pobočce',
        'Kód k motorce: ' || COALESCE(v_code_moto,'–') || E'\n' ||
        'Kód k příslušenství: ' || COALESCE(v_code_gear,'–') || E'\n' ||
        'Kódy jsou platné po dobu trvání pronájmu (' ||
        TO_CHAR(v_booking.start_date::date,'DD.MM.YYYY') || ' – ' ||
        TO_CHAR(v_booking.end_date::date,'DD.MM.YYYY') || ').',
        'door_codes'
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
      SELECT phone INTO v_phone FROM profiles WHERE id = v_booking.user_id;
      IF v_phone IS NOT NULL AND v_phone <> '' THEN
        PERFORM send_sms_and_wa(v_phone, 'door_codes',
          jsonb_build_object(
            'booking_number', upper(left(v_booking.booking_id::text,8)),
            'door_code_moto', COALESCE(v_code_moto,'–'),
            'door_code_gear', COALESCE(v_code_gear,'–')
          ), v_booking.user_id, v_booking.booking_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM send_door_codes_email(v_booking.booking_id, v_booking.user_id);
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'release_withheld_door_codes_for_user failed: %', SQLERRM;
END;
$$;


ALTER FUNCTION "public"."release_withheld_door_codes_for_user"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reschedule_booking_free"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_source" "text" DEFAULT 'web_customer'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_bk      bookings%ROWTYPE;
  v_today   date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_hist    jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_bk.user_id <> v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  IF v_bk.status <> 'reserved' THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF v_bk.payment_status <> 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
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
       AND m.license_required IS DISTINCT FROM 'N'   -- <<< OPRAVA: žádný COALESCE('') na enum
       AND b.start_date::date <= p_new_end
       AND b.end_date::date   >= p_new_start
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'customer_overlap');
  END IF;

  v_hist := COALESCE(v_bk.modification_history, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'at', now(),
      'from_start', v_bk.start_date::date, 'from_end', v_bk.end_date::date,
      'to_start', p_new_start, 'to_end', p_new_end,
      'source', COALESCE(p_source,'web_customer'), 'free_move', true
    )
  );

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


ALTER FUNCTION "public"."reschedule_booking_free"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_source" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_booking_ref"("p_ref" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE v_clean text; v_id uuid; v_cnt int;
BEGIN
  IF p_ref IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'bad_ref'); END IF;
  v_clean := lower(regexp_replace(p_ref, '[^0-9a-fA-F-]', '', 'g'));
  -- plné UUID (s pomlčkami)
  IF v_clean ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN jsonb_build_object('success', true, 'booking_id', v_clean);
  END IF;
  -- UUID bez pomlček (32 hex)
  IF v_clean ~ '^[0-9a-f]{32}$' THEN
    RETURN jsonb_build_object('success', true, 'booking_id',
      substr(v_clean,1,8)||'-'||substr(v_clean,9,4)||'-'||substr(v_clean,13,4)||'-'||substr(v_clean,17,4)||'-'||substr(v_clean,21,12));
  END IF;
  -- krátká reference = posledních 8 hex znaků (to, co zákazník vidí jako "#XXXXXXXX")
  IF v_clean ~ '^[0-9a-f]{8}$' THEN
    SELECT count(*) INTO v_cnt FROM bookings WHERE right(replace(id::text,'-',''),8) = v_clean;
    IF v_cnt = 0 THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
    IF v_cnt > 1 THEN RETURN jsonb_build_object('success', false, 'error', 'ambiguous'); END IF;
    SELECT id INTO v_id FROM bookings WHERE right(replace(id::text,'-',''),8) = v_clean;
    RETURN jsonb_build_object('success', true, 'booking_id', v_id);
  END IF;
  RETURN jsonb_build_object('success', false, 'error', 'bad_ref');
END; $_$;


ALTER FUNCTION "public"."resolve_booking_ref"("p_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."restore_vouchers_on_cancel"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_code text; v_codes text[];
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
    UPDATE vouchers v SET status='active', redeemed_at=NULL, redeemed_by=NULL, booking_id=NULL, updated_at=now()
      FROM booking_discounts bd
      WHERE bd.booking_id = NEW.id AND bd.kind='voucher' AND bd.voucher_id = v.id
        AND v.status='redeemed' AND v.source IS DISTINCT FROM 'slevomat';
    IF NEW.discount_code IS NOT NULL AND NEW.discount_code <> '' THEN
      v_codes := string_to_array(NEW.discount_code, ',');
      FOREACH v_code IN ARRAY v_codes LOOP
        v_code := trim(v_code);
        IF v_code <> '' THEN
          UPDATE vouchers SET status='active', redeemed_at=NULL, redeemed_by=NULL, booking_id=NULL, updated_at=now()
            WHERE code = v_code AND status='redeemed' AND source IS DISTINCT FROM 'slevomat';
        END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."restore_vouchers_on_cancel"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_api_key"("p_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  UPDATE api_keys SET is_active = false, revoked_at = now(), revoked_reason = p_reason WHERE id = p_id;
END;
$$;


ALTER FUNCTION "public"."revoke_api_key"("p_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."route_detect_countries"("p_waypoints" "jsonb", "p_geometry" "jsonb") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE
    AS $$
  with pts as (
    select (e->>'lat')::double precision as lat, (e->>'lng')::double precision as lng
      from jsonb_array_elements(
        case when jsonb_typeof(p_waypoints)='array' then p_waypoints else '[]'::jsonb end) e
    union all
    select (c->>1)::double precision as lat, (c->>0)::double precision as lng
      from jsonb_array_elements(
        case when jsonb_typeof(p_geometry->'coordinates')='array'
             then p_geometry->'coordinates' else '[]'::jsonb end) c
  )
  select coalesce(
    array(
      select distinct public.point_country(lat, lng)
      from pts
      where lat is not null and lng is not null
      order by 1
    ),
    array['CZ']
  );
$$;


ALTER FUNCTION "public"."route_detect_countries"("p_waypoints" "jsonb", "p_geometry" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."routes_set_countries"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.countries is null or array_length(new.countries, 1) is null then
    new.countries := public.route_detect_countries(new.waypoints, new.geometry);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."routes_set_countries"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_user_route"("p_name" "text", "p_description" "text" DEFAULT NULL::"text", "p_source_route_id" "uuid" DEFAULT NULL::"uuid", "p_waypoints" "jsonb" DEFAULT '[]'::"jsonb", "p_poi_refs" "jsonb" DEFAULT '[]'::"jsonb", "p_profile" "text" DEFAULT 'recommended'::"text", "p_distance_km" numeric DEFAULT NULL::numeric, "p_duration_min" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('success', false, 'error', 'name_required'); end if;
  if jsonb_typeof(p_waypoints) is distinct from 'array'
     or jsonb_array_length(p_waypoints) < 1 then
    return jsonb_build_object('success', false, 'error', 'waypoints_required');
  end if;
  -- pojistka proti zahlcení (běžný jezdec jich má jednotky)
  if (select count(*) from user_saved_routes where user_id = auth.uid()) >= 200 then
    return jsonb_build_object('success', false, 'error', 'limit_reached');
  end if;
  insert into user_saved_routes
    (user_id, name, description, source_route_id, waypoints, poi_refs,
     profile, distance_km, duration_min)
  values
    (auth.uid(), left(trim(p_name), 120), nullif(trim(coalesce(p_description,'')), ''),
     p_source_route_id, p_waypoints, coalesce(p_poi_refs, '[]'::jsonb),
     case when p_profile in ('recommended','fastest','shortest') then p_profile else 'recommended' end,
     p_distance_km, p_duration_min)
  returning id into v_id;
  return jsonb_build_object('success', true, 'id', v_id);
end;
$$;


ALTER FUNCTION "public"."save_user_route"("p_name" "text", "p_description" "text", "p_source_route_id" "uuid", "p_waypoints" "jsonb", "p_poi_refs" "jsonb", "p_profile" "text", "p_distance_km" numeric, "p_duration_min" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_abandoned_booking_emails"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url         text;
  v_key         text;
  v_row         record;
  v_sent_ab     int := 0;
  v_sent_docs   int := 0;
  v_pay_url     text;
  v_docs_url    text;
  v_site_url    text := 'https://www.motogo24.cz';
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_abandoned_booking_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  -- PATH AB: pending + unpaid (web) — 15 min od created_at. Obnovené rezervace
  -- (restored_at) se přeskakují — obnovil je admin, „nedokončená" nejsou.
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.stripe_checkout_url, b.checkout_started_at, b.created_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.booking_source        = 'web'
       AND b.status                = 'pending'
       AND b.payment_status        = 'unpaid'
       AND b.restored_at           IS NULL
       AND b.abandoned_email_sent_at IS NULL
       AND b.created_at < now() - interval '15 minutes'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_pay_url := COALESCE(NULLIF(v_row.stripe_checkout_url, ''), v_site_url || '/rezervace?resume=' || v_row.id::text);

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_abandoned','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'total_price',v_row.total_price,
          'pay_url',v_pay_url,'resume_link',v_pay_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET abandoned_email_sent_at = now() WHERE id = v_row.id;
      v_sent_ab := v_sent_ab + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails AB: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- PATH C: paid + reserved/active + NEDOKONČIL krok dokladů (docs_completed_at IS NULL),
  -- 30 min od confirmed_at. Jen samoobslužné vyzvednutí (obslužná/delivery = doklady
  -- nepovinné, ověří obsluha → žádná připomínka). Dětská motorka: docs_completed_at
  -- se stejně nastaví při „Hotovo", takže nezacyklí.
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.confirmed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p  ON p.id  = b.user_id
      LEFT JOIN motorcycles m  ON m.id  = b.moto_id
      LEFT JOIN branches    br ON br.id = m.branch_id
     WHERE b.booking_source             = 'web'
       AND b.status                     IN ('reserved','active')
       AND b.payment_status             = 'paid'
       AND b.docs_completed_at          IS NULL
       AND b.docs_reminder_sent_at      IS NULL
       AND b.confirmed_at < now() - interval '30 minutes'
       AND COALESCE(br.type, '')         <> 'obslužná'
       AND COALESCE(b.pickup_method, '') <> 'delivery'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_url := v_site_url || '/rezervace?resume=' || v_row.id::text;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_missing_docs','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'docs_url',v_docs_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET docs_reminder_sent_at = now() WHERE id = v_row.id;
      v_sent_docs := v_sent_docs + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_abandoned', v_sent_ab, 'sent_missing_docs', v_sent_docs);
END;
$$;


ALTER FUNCTION "public"."send_abandoned_booking_emails"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_admin_message"("p_user_id" "uuid", "p_title" "text", "p_message" "text", "p_type" "text" DEFAULT 'info'::"text", "p_incident_id" "uuid" DEFAULT NULL::"uuid", "p_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_msg_id UUID;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
        RAISE EXCEPTION 'Přístup odepřen – pouze admin';
    END IF;

    INSERT INTO admin_messages (user_id, title, message, type, incident_id, booking_id, sent_by)
    VALUES (p_user_id, p_title, p_message, p_type, p_incident_id, p_booking_id, auth.uid())
    RETURNING id INTO v_msg_id;

    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(),
        'send_admin_message',
        'admin_messages',
        v_msg_id,
        jsonb_build_object(
            'user_id', p_user_id,
            'title', p_title,
            'type', p_type,
            'incident_id', p_incident_id
        )
    );

    RETURN v_msg_id;
END;
$$;


ALTER FUNCTION "public"."send_admin_message"("p_user_id" "uuid", "p_title" "text", "p_message" "text", "p_type" "text", "p_incident_id" "uuid", "p_booking_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."send_admin_message"("p_user_id" "uuid", "p_title" "text", "p_message" "text", "p_type" "text", "p_incident_id" "uuid", "p_booking_id" "uuid") IS 'RPC: Admin odešle zprávu zákazníkovi (loguje se do audit logu)';



CREATE OR REPLACE FUNCTION "public"."send_door_codes_email"("p_booking_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_already_sent boolean;
  v_supabase_url text;
  v_service_key text;
  v_email text;
  v_name text;
  v_moto_model text;
  v_start date;
  v_end date;
  v_source text;
  v_language text;
begin
  -- Per-booking dedup: max 1 door_codes mail per booking (libovolný slug)
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = p_booking_id
      AND template_slug IN ('door_codes', 'web_door_codes')
      AND channel = 'email'
      AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN; END IF;

  -- Booking + customer
  SELECT p.email, p.full_name, m.model,
         b.start_date::date, b.end_date::date,
         COALESCE(b.booking_source, 'app'),
         COALESCE(b.language, p.language, 'cs')
    INTO v_email, v_name, v_moto_model, v_start, v_end, v_source, v_language
  FROM bookings b
  LEFT JOIN profiles p ON p.id = b.user_id
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  WHERE b.id = p_booking_id;
  IF v_email IS NULL OR v_email = '' THEN
    RAISE WARNING 'send_door_codes_email: no email for booking %', p_booking_id;
    RETURN;
  END IF;

  -- Supabase URL + service role key z app_settings (stejný pattern jako trg_send_booking_completed_email)
  SELECT value #>> '{}' INTO v_supabase_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_service_key  FROM app_settings WHERE key = 'service_role_key';
  IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
    RAISE WARNING 'send_door_codes_email: supabase_url or service_role_key missing in app_settings';
    RETURN;
  END IF;

  -- Zavolej edge fn send-booking-email s type='door_codes'.
  -- Edge fn si sám načte door codes z branch_door_codes, vyrenderuje template,
  -- pošle přes Resend a zaloguje do message_log.
  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'apikey',        v_service_key,
      'Content-Type',  'application/json'
    ),
    body := jsonb_build_object(
      'type',            'door_codes',
      'booking_id',      p_booking_id::text,
      'customer_email',  v_email,
      'customer_name',   COALESCE(v_name, ''),
      'motorcycle',      COALESCE(v_moto_model, ''),
      'start_date',      v_start::text,
      'end_date',        v_end::text,
      'source',          v_source,
      'language',        v_language
    )
  );

  -- Log marker do message_log (dedup pro budoucí volání) — sluga rozlišíme podle source
  INSERT INTO message_log (channel, direction, recipient_email, booking_id,
                           template_slug, content_preview, status)
  VALUES ('email', 'outbound', v_email, p_booking_id,
          CASE WHEN v_source = 'web' THEN 'web_door_codes' ELSE 'door_codes' END,
          'Přístupové kódy — ' || COALESCE(v_moto_model,'') || ' ' || to_char(v_start,'DD.MM.') || '–' || to_char(v_end,'DD.MM.YYYY'),
          'sent');

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_door_codes_email failed for booking %: %', p_booking_id, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."send_door_codes_email"("p_booking_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."send_door_codes_email"("p_booking_id" "uuid", "p_user_id" "uuid") IS 'Pošle samostatný door codes email zákazníkovi přes Resend. Šablonu čte z email_templates podle booking.booking_source: web → web_door_codes, app → door_codes (fallback na door_codes). Strict per-booking dedup: max 1 mail per booking.';



CREATE OR REPLACE FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid" DEFAULT NULL::"uuid", "p_booking_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- Načti z app_settings
  SELECT value#>>'{}'  INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value#>>'{}'  INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_message_via_edge: app_settings supabase_url/service_role_key not configured, skipping';
    RETURN;
  END IF;

  IF p_to IS NULL OR p_to = '' THEN
    RAISE WARNING 'send_message_via_edge: empty phone, skipping (slug=%)', p_template_slug;
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-message',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'channel', p_channel,
      'to', p_to,
      'template_slug', p_template_slug,
      'template_vars', p_template_vars,
      'customer_id', p_customer_id,
      'booking_id', p_booking_id
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_message_via_edge failed (slug=%, channel=%): %', p_template_slug, p_channel, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid" DEFAULT NULL::"uuid", "p_booking_id" "uuid" DEFAULT NULL::"uuid", "p_language" "text" DEFAULT 'cs'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- ZMĚNA: čteme z app_settings tabulky (Supabase managed neumí ALTER DATABASE)
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_message_via_edge: app_settings(supabase_url|service_role_key) chybí';
    RETURN;
  END IF;

  IF p_to IS NULL OR p_to = '' THEN
    RAISE WARNING 'send_message_via_edge: empty phone, skipping (slug=%)', p_template_slug;
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-message',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type',  'application/json'
    ),
    body := jsonb_build_object(
      'channel',       p_channel,
      'to',            p_to,
      'template_slug', p_template_slug,
      'template_vars', p_template_vars,
      'customer_id',   p_customer_id,
      'booking_id',    p_booking_id,
      'language',      COALESCE(p_language, 'cs')   -- ⚠️ i18n
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_message_via_edge failed (slug=%, channel=%): %', p_template_slug, p_channel, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_missing_booking_reserved_emails"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url   text;
  v_key   text;
  v_row   record;
  v_docs  text;
  v_sent  int := 0;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_missing_booking_reserved_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.booking_source, b.docs_completed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model, m.manual_url AS manual_url
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.status                 IN ('reserved','active')
       AND b.payment_status         = 'paid'
       AND b.confirmed_at IS NOT NULL
       AND b.confirmed_at           < now() - interval '3 minutes'
       AND b.reserved_email_sent_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM message_log ml
          WHERE ml.booking_id    = b.id
            AND ml.channel       = 'email'
            AND ml.template_slug IN ('web_booking_reserved','booking_reserved')
       )
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    -- WEB: reserved až když dokončený krok dokladů (čísla) NEBO doklady už ověřené.
    IF COALESCE(v_row.booking_source, 'web') = 'web' AND v_row.docs_completed_at IS NULL THEN
      v_docs := NULL;
      BEGIN
        v_docs := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'send_missing_booking_reserved_emails: docs check failed for %: %', v_row.id, SQLERRM;
        CONTINUE;
      END;
      IF v_docs IS NOT NULL THEN CONTINUE; END IF;  -- ani nedokončené, ani ověřené → ještě ne
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_reserved','source',COALESCE(v_row.booking_source,'web'),
          'booking_id',v_row.id,'customer_email',v_row.customer_email,
          'customer_name',COALESCE(v_row.customer_name,''),'motorcycle',COALESCE(v_row.motorcycle_model,''),
          'start_date',v_row.start_date,'end_date',v_row.end_date,'total_price',v_row.total_price,
          'manual_url',COALESCE(v_row.manual_url,''),'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET reserved_email_sent_at = now() WHERE id = v_row.id;
      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_missing_booking_reserved_emails: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_reserved', v_sent);
END;
$$;


ALTER FUNCTION "public"."send_missing_booking_reserved_emails"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_push_via_edge"("p_user_id" "uuid", "p_title" "text", "p_body" "text", "p_data" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_url text; v_key text;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_push_via_edge: app_settings missing';
    RETURN;
  END IF;
  IF p_user_id IS NULL OR p_title IS NULL THEN RETURN; END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'user_id', p_user_id,
      'title',   p_title,
      'body',    COALESCE(p_body, ''),
      'data',    COALESCE(p_data, '{}'::jsonb)
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_push_via_edge failed (user=%, title=%): %', p_user_id, p_title, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."send_push_via_edge"("p_user_id" "uuid", "p_title" "text", "p_body" "text", "p_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_sms_and_wa"("p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid" DEFAULT NULL::"uuid", "p_booking_id" "uuid" DEFAULT NULL::"uuid", "p_language" "text" DEFAULT 'cs'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  PERFORM send_message_via_edge('sms',      p_to, p_template_slug, p_template_vars, p_customer_id, p_booking_id, p_language);
  PERFORM send_message_via_edge('whatsapp', p_to, p_template_slug, p_template_vars, p_customer_id, p_booking_id, p_language);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_sms_and_wa failed (slug=%): %', p_template_slug, SQLERRM;
END;
$$;


ALTER FUNCTION "public"."send_sms_and_wa"("p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_booking_form_seconds"("p_booking_id" "uuid", "p_started_at" timestamp with time zone) RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  UPDATE public.bookings
     SET form_started_at   = p_started_at,
         form_fill_seconds = GREATEST(0, LEAST(86400, EXTRACT(EPOCH FROM (now() - p_started_at))::int))
   WHERE id = p_booking_id AND booking_source = 'web' AND form_started_at IS NULL
     AND p_started_at IS NOT NULL AND p_started_at <= now() AND p_started_at >= now() - interval '24 hours';
$$;


ALTER FUNCTION "public"."set_booking_form_seconds"("p_booking_id" "uuid", "p_started_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_booking_mod_surcharge"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b  bookings%ROWTYPE;
  v_vs text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF COALESCE(v_b.mod_surcharge_due, 0) <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_surcharge_pending');
  END IF;

  IF v_b.mod_surcharge_vs IS NULL THEN           -- VS přidělit jen jednou
    v_vs := nextval('booking_vs_seq')::text;
    UPDATE bookings SET mod_surcharge_vs = v_vs, updated_at = now()
     WHERE id = p_booking_id;
  ELSE
    v_vs := v_b.mod_surcharge_vs;
  END IF;

  RETURN jsonb_build_object(
    'success',    true,
    'booking_id', p_booking_id,
    'vs',         v_vs,
    'amount',     v_b.mod_surcharge_due
  );
END;
$$;


ALTER FUNCTION "public"."set_booking_mod_surcharge"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_booking_qr_payment"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b  bookings%ROWTYPE;
  v_vs text;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF COALESCE(v_b.booking_source, '') <> 'web' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_web_booking');
  END IF;
  IF v_b.payment_status = 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_paid');
  END IF;

  IF v_b.payment_vs IS NULL THEN                 -- VS přidělit jen jednou
    v_vs := nextval('booking_vs_seq')::text;
    UPDATE bookings
       SET payment_vs             = v_vs,
           pay_channel            = 'qr',
           payment_method         = 'bank_transfer',
           abandoned_email_sent_at = COALESCE(abandoned_email_sent_at, now()), -- potlač abandoned mail
           updated_at             = now()
     WHERE id = p_booking_id;
  ELSE
    v_vs := v_b.payment_vs;
    UPDATE bookings
       SET pay_channel            = 'qr',
           abandoned_email_sent_at = COALESCE(abandoned_email_sent_at, now())
     WHERE id = p_booking_id;
  END IF;

  RETURN jsonb_build_object(
    'success',   true,
    'booking_id', p_booking_id,
    'vs',        v_vs,
    'amount',    v_b.total_price,
    'due_hours', 4
  );
END;
$$;


ALTER FUNCTION "public"."set_booking_qr_payment"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_loyalty_leaderboard_optin"("p_opt_in" boolean) RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  UPDATE profiles SET loyalty_leaderboard_opt_in = p_opt_in WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."set_loyalty_leaderboard_optin"("p_opt_in" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_loyalty_nickname"("p_nickname" "text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  UPDATE profiles SET loyalty_nickname = NULLIF(btrim(p_nickname), '') WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."set_loyalty_nickname"("p_nickname" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_my_license_group"("p_groups" "text"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_groups license_group[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT array_agg(DISTINCT upper(g)::license_group)
    INTO v_groups
    FROM unnest(p_groups) AS g
   WHERE upper(g) IN ('AM','A1','A2','A','B','N');

  UPDATE public.profiles
     SET license_group = v_groups
   WHERE id = v_uid;

  RETURN jsonb_build_object('success', true,
                            'count', COALESCE(array_length(v_groups, 1), 0));
END;
$$;


ALTER FUNCTION "public"."set_my_license_group"("p_groups" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_promo_code_source"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.source IS NULL AND NEW.code ILIKE 'VRACENI-%' THEN
    NEW.source := 'vraceni';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_promo_code_source"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin new.updated_at = now(); return new; end; $$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at_now"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;


ALTER FUNCTION "public"."set_updated_at_now"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_web_booking_chosen_method"("p_booking_id" "uuid", "p_method" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE bookings
     SET chosen_payment_method = LEFT(COALESCE(p_method, ''), 20),
         pay_channel = CASE WHEN p_method = 'card' THEN NULL ELSE pay_channel END
   WHERE id = p_booking_id
     AND booking_source = 'web'
     AND payment_status <> 'paid';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."set_web_booking_chosen_method"("p_booking_id" "uuid", "p_method" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_web_booking_company"("p_booking_id" "uuid", "p_company_name" "text" DEFAULT NULL::"text", "p_ico" "text" DEFAULT NULL::"text", "p_dic" "text" DEFAULT NULL::"text", "p_company_address" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Klíčováno přes booking_id, jen web rezervace (vzor set_web_booking_docs)
  SELECT user_id INTO v_user_id
    FROM bookings
   WHERE id = p_booking_id
     AND booking_source = 'web';

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'booking_not_found');
  END IF;

  -- COALESCE(NULLIF(trim(...))) — prázdné hodnoty nepřepíší existující
  UPDATE profiles SET
    company_name    = COALESCE(NULLIF(trim(p_company_name), ''), company_name),
    ico             = COALESCE(NULLIF(trim(p_ico), ''), ico),
    dic             = COALESCE(NULLIF(trim(p_dic), ''), dic),
    company_address = COALESCE(NULLIF(trim(p_company_address), ''), company_address)
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."set_web_booking_company"("p_booking_id" "uuid", "p_company_name" "text", "p_ico" "text", "p_dic" "text", "p_company_address" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_web_booking_device"("p_booking_id" "uuid", "p_device" "text", "p_phase" "text" DEFAULT 'created'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_source text;
  v_device text;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;

  v_device := CASE lower(COALESCE(p_device, ''))
    WHEN 'pc' THEN 'pc'
    WHEN 'desktop' THEN 'pc'
    WHEN 'mobile' THEN 'mobile'
    WHEN 'phone' THEN 'mobile'
    WHEN 'tablet' THEN 'tablet'
    ELSE NULL
  END;
  IF v_device IS NULL THEN
    RETURN jsonb_build_object('error', 'Neznámé zařízení');
  END IF;

  SELECT booking_source INTO v_source FROM bookings WHERE id = p_booking_id;
  IF v_source IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  IF p_phase = 'completed' THEN
    UPDATE bookings SET completed_device = v_device WHERE id = p_booking_id;
  ELSE
    UPDATE bookings SET created_device = v_device
      WHERE id = p_booking_id AND created_device IS NULL;
  END IF;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."set_web_booking_device"("p_booking_id" "uuid", "p_device" "text", "p_phase" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_web_booking_docs"("p_booking_id" "uuid", "p_id_number" "text" DEFAULT NULL::"text", "p_license_number" "text" DEFAULT NULL::"text", "p_license_expiry" "text" DEFAULT NULL::"text", "p_license_group" "text" DEFAULT NULL::"text", "p_date_of_birth" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_user_id uuid;
  v_source text;
  v_lic_group license_group[];
  v_lic_expiry date;
  v_dob date;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;

  SELECT user_id, booking_source INTO v_user_id, v_source
    FROM bookings WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  -- ŘP skupina → enum array. Podporuje VÍCE skupin oddělených čárkou ("A,B").
  -- Neplatné/prázdné tokeny ignorujeme; když nic platného nezbyde → NULL (nepřepíše).
  IF p_license_group IS NOT NULL AND p_license_group <> '' THEN
    BEGIN
      SELECT array_agg(DISTINCT g)
        INTO v_lic_group
        FROM (
          SELECT upper(trim(tok))::license_group AS g
          FROM unnest(string_to_array(p_license_group, ',')) AS tok
          WHERE trim(tok) <> ''
            AND upper(trim(tok)) IN ('AM','A1','A2','A','B','N')
        ) s;
    EXCEPTION WHEN OTHERS THEN
      v_lic_group := NULL;
    END;
  END IF;

  -- platnost ŘP → date (neplatný formát ignorujeme)
  IF p_license_expiry IS NOT NULL AND p_license_expiry <> '' THEN
    BEGIN
      v_lic_expiry := p_license_expiry::date;
    EXCEPTION WHEN OTHERS THEN
      v_lic_expiry := NULL;
    END;
  END IF;

  -- datum narození → date (neplatný formát ignorujeme)
  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN
      v_dob := p_date_of_birth::date;
    EXCEPTION WHEN OTHERS THEN
      v_dob := NULL;
    END;
  END IF;

  UPDATE profiles SET
    id_number      = COALESCE(NULLIF(p_id_number, ''), id_number),
    license_number = COALESCE(NULLIF(p_license_number, ''), license_number),
    license_group  = COALESCE(v_lic_group, license_group),
    license_expiry = COALESCE(v_lic_expiry::text, license_expiry),
    date_of_birth  = COALESCE(v_dob, date_of_birth),
    updated_at     = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."set_web_booking_docs"("p_booking_id" "uuid", "p_id_number" "text", "p_license_number" "text", "p_license_expiry" "text", "p_license_group" "text", "p_date_of_birth" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_web_booking_docs_completed"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE bookings
     SET docs_completed_at = COALESCE(docs_completed_at, now()),
         docs_fill_seconds = COALESCE(
           docs_fill_seconds,
           GREATEST(0, LEAST(604800, EXTRACT(EPOCH FROM (now() - COALESCE(confirmed_at, created_at)))::int))
         )
   WHERE id = p_booking_id
     AND booking_source = 'web';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."set_web_booking_docs_completed"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_web_booking_password"("p_booking_id" "uuid", "p_password" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id uuid;
  v_source text;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RETURN jsonb_build_object('error', 'Heslo musí mít alespoň 8 znaků');
  END IF;

  SELECT user_id, booking_source INTO v_user_id, v_source
    FROM bookings WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source <> 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  -- Hlavní heslo do auth.users
  UPDATE auth.users SET
    encrypted_password = crypt(p_password, gen_salt('bf')),
    updated_at = now()
  WHERE id = v_user_id;

  -- Hash posledních 4 znaků pro AI ověření
  UPDATE profiles
     SET password_last4_bcrypt = crypt(right(p_password, 4), gen_salt('bf'))
   WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;


ALTER FUNCTION "public"."set_web_booking_password"("p_booking_id" "uuid", "p_password" "text") OWNER TO "postgres";


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


ALTER FUNCTION "public"."shorten_booking_with_refund"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."slevomat_auto_apply_on_redeem"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_url text; v_key text;
BEGIN
  IF NEW.source <> 'slevomat' OR NEW.status <> 'redeemed'
     OR NEW.slevomat_applied_at IS NOT NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'redeemed' THEN RETURN NEW; END IF; -- jen přechod

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key='supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key='service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN RETURN NEW; END IF;

  BEGIN
    PERFORM net.http_post(
      url := v_url || '/functions/v1/slevomat-voucher',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
      body := jsonb_build_object('action','apply','code', NEW.code));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source,action,status,error_message,request_data)
    VALUES('slevomat_auto_apply_on_redeem','slevomat_apply_failed','error',SQLERRM,
           jsonb_build_object('code',NEW.code));
  END;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."slevomat_auto_apply_on_redeem"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."snapshot_daily_stats"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    yesterday DATE := CURRENT_DATE - 1;
    branch RECORD;
BEGIN
    FOR branch IN SELECT id FROM branches LOOP
        INSERT INTO daily_stats (date, branch_id, total_bookings, revenue, active_motos, utilization_pct, new_customers, sos_incidents)
        VALUES (
            yesterday,
            branch.id,
            (SELECT COUNT(*) FROM bookings WHERE branch_id = branch.id AND start_date::DATE <= yesterday AND end_date::DATE >= yesterday AND status IN ('active', 'completed')),
            (SELECT COALESCE(SUM(total_price), 0) FROM bookings WHERE branch_id = branch.id AND start_date::DATE = yesterday AND payment_status = 'paid'),
            (SELECT COUNT(*) FROM motorcycles WHERE branch_id = branch.id AND status = 'active'),
            (SELECT ROUND(
                COUNT(DISTINCT b.moto_id)::NUMERIC /
                NULLIF((SELECT COUNT(*) FROM motorcycles WHERE branch_id = branch.id AND status = 'active'), 0) * 100, 2
            ) FROM bookings b WHERE b.branch_id = branch.id AND b.start_date::DATE <= yesterday AND b.end_date::DATE >= yesterday AND b.status IN ('active', 'completed')),
            (SELECT COUNT(*) FROM profiles WHERE created_at::DATE = yesterday AND preferred_branch = branch.id),
            (SELECT COUNT(*) FROM sos_incidents si JOIN bookings bk ON si.booking_id = bk.id WHERE bk.branch_id = branch.id AND si.created_at::DATE = yesterday)
        )
        ON CONFLICT (date, branch_id) DO UPDATE SET
            total_bookings = EXCLUDED.total_bookings,
            revenue = EXCLUDED.revenue,
            active_motos = EXCLUDED.active_motos,
            utilization_pct = EXCLUDED.utilization_pct,
            new_customers = EXCLUDED.new_customers,
            sos_incidents = EXCLUDED.sos_incidents;
    END LOOP;
END;
$$;


ALTER FUNCTION "public"."snapshot_daily_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sos_auto_severity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.severity IS NULL OR NEW.severity::text = 'medium' THEN
    CASE NEW.type::text
      WHEN 'theft' THEN NEW.severity := 'critical';
      WHEN 'accident_major' THEN NEW.severity := 'high';
      WHEN 'breakdown_major' THEN NEW.severity := 'high';
      WHEN 'accident_minor' THEN NEW.severity := 'medium';
      WHEN 'breakdown_minor' THEN NEW.severity := 'low';
      WHEN 'defect_question' THEN NEW.severity := 'low';
      ELSE NEW.severity := 'medium';
    END CASE;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[sos_auto_severity] error: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sos_auto_severity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sos_auto_timeline"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO sos_timeline (incident_id, action, performed_by)
  VALUES (NEW.id, 'Incident nahlasen zakaznikem (' || COALESCE(NEW.type::text, 'other') || ')', 'System');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[sos_auto_timeline] error: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sos_auto_timeline"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sos_notify_user_on_create"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_type_label text;
  v_message text;
  v_title text;
  v_is_light boolean;
  v_exists boolean;
BEGIN
  -- Dedup: neposílej pokud už existuje zpráva v posledních 2 minutách
  SELECT EXISTS(
    SELECT 1 FROM admin_messages
    WHERE user_id = NEW.user_id
      AND type IN ('sos_response', 'sos_auto')
      AND created_at > now() - interval '2 minutes'
  ) INTO v_exists;

  IF v_exists THEN
    RETURN NEW;
  END IF;

  CASE NEW.type::text
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  v_is_light := NEW.type::text IN ('accident_minor', 'breakdown_minor', 'defect_question', 'location_share', 'other');

  IF v_is_light THEN
    v_title := 'Děkujeme za nahlášení';
    v_message := 'Děkujeme za nahlášení incidentu (' || v_type_label || '). Šťastnou cestu!';
  ELSE
    v_title := 'SOS přijato: ' || v_type_label;
    v_message := 'Vaše hlášení bylo přijato centrálou MotoGo24. ' ||
      COALESCE(NEW.description, '') ||
      ' Asistent vás bude kontaktovat.';
  END IF;

  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    v_title,
    v_message,
    CASE WHEN v_is_light THEN 'sos_auto' ELSE 'sos_response' END
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '[sos_notify_user_on_create] error: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sos_notify_user_on_create"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sos_share_location"("p_incident_id" "uuid", "p_lat" numeric, "p_lng" numeric) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    UPDATE sos_incidents SET latitude = p_lat, longitude = p_lng, updated_at = NOW()
    WHERE id = p_incident_id AND user_id = auth.uid();

    INSERT INTO sos_timeline (incident_id, action, performed_by, data)
    VALUES (p_incident_id, 'gps_shared', auth.uid(), jsonb_build_object('lat', p_lat, 'lng', p_lng));

    RETURN FOUND;
END;
$$;


ALTER FUNCTION "public"."sos_share_location"("p_incident_id" "uuid", "p_lat" numeric, "p_lng" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sos_swap_bookings"("p_incident_id" "uuid", "p_replacement_moto_id" "uuid", "p_replacement_model" "text" DEFAULT NULL::"text", "p_delivery_fee" numeric DEFAULT 0, "p_daily_price" numeric DEFAULT 0, "p_is_free" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_incident record;
  v_booking record;
  v_original_end date;
  v_new_booking_id uuid;
  v_remaining_days int;
  v_total_price numeric;
  v_today date := CURRENT_DATE;
  v_already_ended boolean := false;
  v_debug text := '';
  v_payment payment_status;
  v_status booking_status := 'active';
BEGIN
  SELECT * INTO v_incident FROM sos_incidents WHERE id = p_incident_id;
  IF v_incident IS NULL THEN
    RETURN jsonb_build_object('error', 'Incident not found', 'step', 'find_incident');
  END IF;

  -- 1. Active paid booking for today
  SELECT * INTO v_booking FROM bookings
    WHERE user_id = v_incident.user_id
      AND status IN ('active'::booking_status, 'pending'::booking_status, 'reserved'::booking_status)
      AND payment_status = 'paid'::payment_status
      AND start_date::date <= v_today
      AND end_date::date >= v_today
    ORDER BY start_date DESC LIMIT 1;
  IF v_booking IS NOT NULL THEN v_debug := 'found_via_active_paid'; END IF;

  -- 2. Any non-cancelled/completed booking
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND status NOT IN ('cancelled'::booking_status, 'completed'::booking_status)
        AND start_date::date <= v_today
        AND end_date::date >= v_today
      ORDER BY start_date DESC LIMIT 1;
    IF v_booking IS NOT NULL THEN v_debug := 'found_via_any_active'; END IF;
  END IF;

  -- 3. By incident booking_id
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id
        AND status NOT IN ('cancelled'::booking_status, 'completed'::booking_status);
    IF v_booking IS NOT NULL THEN v_debug := 'found_via_incident_booking_id'; END IF;
  END IF;

  -- 4. Already ended by SOS
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND ended_by_sos = true
        AND status = 'completed'::booking_status
        AND end_date::date >= v_today - 1
      ORDER BY end_date DESC, created_at DESC LIMIT 1;
    IF v_booking IS NOT NULL THEN
      v_already_ended := true;
      v_debug := 'found_via_ended_by_sos';
    END IF;
  END IF;

  -- 5. By incident booking_id (any non-cancelled)
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id AND status != 'cancelled'::booking_status;
    IF v_booking IS NOT NULL THEN
      IF v_booking.status = 'completed'::booking_status AND v_booking.ended_by_sos = true THEN
        v_already_ended := true;
      END IF;
      v_debug := 'found_via_incident_booking_id_any';
    END IF;
  END IF;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'No booking found for user',
      'step', 'find_booking',
      'user_id', v_incident.user_id,
      'incident_booking_id', v_incident.booking_id
    );
  END IF;

  -- Double-swap protection
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE replacement_for_booking_id = v_booking.id
      AND sos_replacement = true
      AND status != 'cancelled'::booking_status
  ) THEN
    SELECT id INTO v_new_booking_id FROM bookings
      WHERE replacement_for_booking_id = v_booking.id
        AND sos_replacement = true
        AND status != 'cancelled'::booking_status
      LIMIT 1;
    RETURN jsonb_build_object(
      'success', true,
      'original_booking_id', v_booking.id,
      'replacement_booking_id', v_new_booking_id,
      'remaining_days', 1,
      'total_price', 0,
      'already_existed', true,
      'debug', 'double_swap_protection'
    );
  END IF;

  -- Calculate dates
  v_original_end := COALESCE(v_booking.original_end_date, v_booking.end_date)::date;
  IF v_original_end < v_today THEN
    v_original_end := v_today;
  END IF;
  v_remaining_days := GREATEST(1, (v_original_end - v_today) + 1);
  v_total_price := CASE WHEN p_is_free THEN 0 ELSE (p_daily_price * v_remaining_days + p_delivery_fee) END;

  -- Payment status as proper ENUM
  v_payment := CASE WHEN p_is_free THEN 'paid'::payment_status ELSE 'unpaid'::payment_status END;

  -- Step 1: End original booking
  IF NOT v_already_ended THEN
    BEGIN
      UPDATE bookings SET
        original_end_date = CASE WHEN original_end_date IS NULL THEN end_date ELSE original_end_date END,
        end_date = v_today,
        status = 'completed'::booking_status,
        ended_by_sos = true,
        sos_incident_id = p_incident_id
      WHERE id = v_booking.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'sos_swap: original booking update failed: %', SQLERRM;
      BEGIN
        UPDATE bookings SET
          status = 'completed'::booking_status,
          ended_by_sos = true
        WHERE id = v_booking.id;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'sos_swap: even minimal update failed: %', SQLERRM;
      END;
    END;
  END IF;

  -- Step 2: Create replacement booking
  BEGIN
    INSERT INTO bookings (
      user_id, moto_id, start_date, end_date, pickup_time,
      status, payment_status, total_price, delivery_fee,
      sos_replacement, replacement_for_booking_id, sos_incident_id,
      notes, booking_source, picked_up_at
    ) VALUES (
      v_incident.user_id,
      p_replacement_moto_id,
      v_today,
      v_original_end,
      '09:00',
      v_status,
      v_payment,
      v_total_price,
      CASE WHEN p_is_free THEN 0 ELSE p_delivery_fee END,
      true,
      v_booking.id,
      p_incident_id,
      '[SOS] Náhradní motorka. Incident: ' || p_incident_id::text,
      'app',
      NOW()
    )
    RETURNING id INTO v_new_booking_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'error', 'Replacement booking INSERT failed: ' || SQLERRM,
      'step', 'insert_replacement',
      'original_booking_id', v_booking.id,
      'replacement_moto_id', p_replacement_moto_id,
      'dates', v_today::text || ' → ' || v_original_end::text,
      'debug', v_debug,
      'partial', true
    );
  END;

  -- Step 3: Update incident
  UPDATE sos_incidents SET
    original_booking_id = v_booking.id,
    replacement_booking_id = v_new_booking_id,
    original_moto_id = v_booking.moto_id,
    replacement_moto_id = p_replacement_moto_id
  WHERE id = p_incident_id;

  -- Step 4: Original moto to maintenance
  UPDATE motorcycles SET status = 'maintenance'::moto_status
  WHERE id = v_booking.moto_id;

  RETURN jsonb_build_object(
    'success', true,
    'original_booking_id', v_booking.id,
    'replacement_booking_id', v_new_booking_id,
    'remaining_days', v_remaining_days,
    'total_price', v_total_price,
    'original_end_date', v_original_end,
    'debug', v_debug
  );
END;
$$;


ALTER FUNCTION "public"."sos_swap_bookings"("p_incident_id" "uuid", "p_replacement_moto_id" "uuid", "p_replacement_model" "text", "p_delivery_fee" numeric, "p_daily_price" numeric, "p_is_free" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."split_booking_moto_swap"("p_booking_id" "uuid", "p_new_moto_id" "uuid", "p_swap_date" "date", "p_swap_time" "text" DEFAULT NULL::"text", "p_dry_run" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."split_booking_moto_swap"("p_booking_id" "uuid", "p_new_moto_id" "uuid", "p_swap_date" "date", "p_swap_time" "text", "p_dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_handover_protocol_window"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF v_b.user_id <> v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF v_b.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF NOT _is_self_service_booking(p_booking_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_self_service');
  END IF;

  IF v_b.handover_protocol_started_at IS NULL AND v_b.handover_protocol_filled_at IS NULL THEN
    UPDATE bookings SET handover_protocol_started_at = now() WHERE id = p_booking_id;
    v_b.handover_protocol_started_at := now();
    IF v_b.user_id IS NOT NULL THEN
      PERFORM send_push_via_edge(
        v_b.user_id,
        'Předávací protokol',
        'Vyplňte prosím předávací protokol — máte na to 60 minut. Po hodině ho vyplníme automaticky.',
        jsonb_build_object('type', 'handover_protocol', 'id', p_booking_id::text)
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'started_at', v_b.handover_protocol_started_at,
    'deadline',   v_b.handover_protocol_started_at + interval '1 hour',
    'filled_at',  v_b.handover_protocol_filled_at,
    'autofilled', v_b.handover_protocol_autofilled
  );
END;
$$;


ALTER FUNCTION "public"."start_handover_protocol_window"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_poi_review"("p_route_poi_id" "uuid" DEFAULT NULL::"uuid", "p_user_poi_id" "uuid" DEFAULT NULL::"uuid", "p_poi_id" "uuid" DEFAULT NULL::"uuid", "p_rating" integer DEFAULT NULL::integer, "p_review_text" "text" DEFAULT NULL::"text", "p_photos" "text"[] DEFAULT '{}'::"text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_id uuid; v_text text; v_photos text[];
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id, p_poi_id) <> 1 then
    raise exception 'exactly one poi target required';
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'rating must be 1..5';
  end if;
  v_text   := nullif(btrim(coalesce(p_review_text,'')),'');
  v_photos := coalesce(p_photos, '{}');
  if p_route_poi_id is not null then
    insert into poi_ratings(user_id, route_poi_id, rating, review_text, photos)
    values (auth.uid(), p_route_poi_id, p_rating, v_text, v_photos)
    on conflict (user_id, route_poi_id) do update
      set rating=excluded.rating, review_text=excluded.review_text,
          photos=excluded.photos, status='approved', updated_at=now()
    returning id into v_id;
  elsif p_user_poi_id is not null then
    insert into poi_ratings(user_id, user_poi_id, rating, review_text, photos)
    values (auth.uid(), p_user_poi_id, p_rating, v_text, v_photos)
    on conflict (user_id, user_poi_id) do update
      set rating=excluded.rating, review_text=excluded.review_text,
          photos=excluded.photos, status='approved', updated_at=now()
    returning id into v_id;
  else
    insert into poi_ratings(user_id, poi_id, rating, review_text, photos)
    values (auth.uid(), p_poi_id, p_rating, v_text, v_photos)
    on conflict (user_id, poi_id) do update
      set rating=excluded.rating, review_text=excluded.review_text,
          photos=excluded.photos, status='approved', updated_at=now()
    returning id into v_id;
  end if;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."submit_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_route_review"("p_route_id" "uuid", "p_rating" integer, "p_review_text" "text" DEFAULT NULL::"text", "p_photos" "text"[] DEFAULT '{}'::"text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if p_rating < 1 or p_rating > 5 then raise exception 'rating must be 1..5'; end if;
  insert into route_reviews(user_id, route_id, rating, review_text, photos)
  values (auth.uid(), p_route_id, p_rating,
          nullif(btrim(coalesce(p_review_text,'')),''),
          coalesce(p_photos, '{}'))
  on conflict (user_id, route_id) do update
    set rating = excluded.rating,
        review_text = excluded.review_text,
        photos = excluded.photos,
        status = 'approved',
        updated_at = now()
  returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."submit_route_review"("p_route_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."swap_handoff_bookings"("p_prev" "uuid", "p_next" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  a bookings;
  b bookings;
  v_prev_status text;
  v_next_status text;
BEGIN
  IF NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO a FROM bookings WHERE id = p_prev;
  SELECT * INTO b FROM bookings WHERE id = p_next;
  IF a.id IS NULL OR b.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF a.user_id IS DISTINCT FROM b.user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'different_customer');
  END IF;
  IF b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'next_not_paid');
  END IF;

  -- Uvolni STAROU (idempotentně): completed + returned_at.
  UPDATE bookings
     SET status = 'completed',
         returned_at = COALESCE(returned_at, now()),
         actual_return_date = COALESCE(actual_return_date, CURRENT_DATE)
   WHERE id = p_prev
     AND status IN ('active', 'reserved');

  -- Aktivuj NOVOU + nastav protokol PŘÍMO + vazbu řetězu. Přijmi i 'active'
  -- (novou mohl doc-trigger aktivovat už při podpisu protokolu PŘED RPC) →
  -- i tak dopíšeme continues_booking_id.
  UPDATE bookings
     SET status = 'active',
         picked_up_at = COALESCE(picked_up_at, now()),
         handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now()),
         continues_booking_id = p_prev
   WHERE id = p_next
     AND status IN ('reserved', 'pending', 'active');

  SELECT status::text INTO v_prev_status FROM bookings WHERE id = p_prev;
  SELECT status::text INTO v_next_status FROM bookings WHERE id = p_next;

  RETURN jsonb_build_object(
    'success', true, 'prev', p_prev, 'next', p_next,
    'prev_status', v_prev_status, 'next_status', v_next_status,
    'prev_completed', (v_prev_status = 'completed'),
    'next_active', (v_next_status = 'active')
  );
END;
$$;


ALTER FUNCTION "public"."swap_handoff_bookings"("p_prev" "uuid", "p_next" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_cms_flat_to_nested"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
declare
  raw text;
  m text[];
  step_num int;
  idx int;
  ben_idx int;
begin
  -- Půjčovna H1
  if new.key = 'web.pujcovna.h1' then
    insert into cms_variables (key, value, category)
    values ('web.pujcovna.intro.h1', new.value, new.category)
    on conflict (key) do update
      set value = excluded.value, updated_at = now();

  -- Půjčovna intro
  elsif new.key = 'web.pujcovna.intro' then
    insert into cms_variables (key, value, category)
    values ('web.pujcovna.intro.body', new.value, new.category)
    on conflict (key) do update
      set value = excluded.value, updated_at = now();

  -- Půjčovna benefits closing
  elsif new.key = 'web.pujcovna.ben.bottom' then
    insert into cms_variables (key, value, category)
    values ('web.pujcovna.benefits.closing', new.value, new.category)
    on conflict (key) do update
      set value = excluded.value, updated_at = now();

  -- Půjčovna benefits.items.{2,3,5} (ben.{3,4,6} → split)
  elsif new.key in ('web.pujcovna.ben.3','web.pujcovna.ben.4','web.pujcovna.ben.6') then
    ben_idx := case new.key
      when 'web.pujcovna.ben.3' then 2
      when 'web.pujcovna.ben.4' then 3
      when 'web.pujcovna.ben.6' then 5
    end;
    raw := new.value #>> '{}';
    m := regexp_match(raw, '^(.*?)\s[-–]\s(.*)$');
    if m is not null then
      insert into cms_variables (key, value, category)
      values ('web.pujcovna.benefits.items.' || ben_idx || '.title', to_jsonb(m[1]), new.category)
      on conflict (key) do update set value = excluded.value, updated_at = now();
      insert into cms_variables (key, value, category)
      values ('web.pujcovna.benefits.items.' || ben_idx || '.text', to_jsonb(m[2]), new.category)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    else
      insert into cms_variables (key, value, category)
      values ('web.pujcovna.benefits.items.' || ben_idx || '.title', to_jsonb(raw), new.category)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    end if;

  -- Půjčovna process.steps.{0..7} (step.{1..8} → split)
  elsif new.key like 'web.pujcovna.step.%' then
    step_num := substring(new.key from 'step\.(\d+)$')::int;
    if step_num between 1 and 8 then
      idx := step_num - 1;
      raw := new.value #>> '{}';
      m := regexp_match(raw, '^(.*?)\s[-–]\s(.*)$');
      if m is not null then
        insert into cms_variables (key, value, category)
        values ('web.pujcovna.process.steps.' || idx || '.title', to_jsonb(m[1]), new.category)
        on conflict (key) do update set value = excluded.value, updated_at = now();
        insert into cms_variables (key, value, category)
        values ('web.pujcovna.process.steps.' || idx || '.text', to_jsonb(m[2]), new.category)
        on conflict (key) do update set value = excluded.value, updated_at = now();
      else
        insert into cms_variables (key, value, category)
        values ('web.pujcovna.process.steps.' || idx || '.title', to_jsonb(raw), new.category)
        on conflict (key) do update set value = excluded.value, updated_at = now();
      end if;
    end if;

  -- Kontakt
  elsif new.key = 'web.kontakt.hours' then
    insert into cms_variables (key, value, category)
    values ('web.kontakt.place.hours', new.value, new.category)
    on conflict (key) do update set value = excluded.value, updated_at = now();

  elsif new.key = 'web.kontakt.seo' then
    insert into cms_variables (key, value, category)
    values ('web.kontakt.seo.description', new.value, new.category)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;

  return new;
end;
$_$;


ALTER FUNCTION "public"."sync_cms_flat_to_nested"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_generated_doc_to_documents"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid;
  v_template_type text;
  v_doc_type text;
  v_file_name text;
BEGIN
  SELECT user_id INTO v_user_id
  FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN
    v_user_id := NEW.customer_id;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.template_id IS NOT NULL THEN
    SELECT type INTO v_template_type
    FROM document_templates WHERE id = NEW.template_id;
  ELSE
    -- El. protokol (bez šablony) → typ z filled_data._doc_type
    v_template_type := NEW.filled_data->>'_doc_type';
  END IF;

  IF v_template_type = 'damage_protocol' THEN
    v_doc_type := 'protocol_damage';
    v_file_name := 'Protokol o poškození.pdf';
  ELSIF v_template_type = 'rental_contract' OR v_template_type ILIKE '%contract%' THEN
    v_doc_type := 'contract';
    v_file_name := 'Smlouva o pronájmu.pdf';
  ELSIF v_template_type = 'handover_protocol' OR v_template_type ILIKE '%protocol%' THEN
    v_doc_type := 'protocol';
    v_file_name := 'Předávací protokol.pdf';
  ELSE
    v_doc_type := 'contract';
    v_file_name := 'Dokument.pdf';
  END IF;

  INSERT INTO documents (booking_id, user_id, type, file_name, file_path)
  SELECT NEW.booking_id, v_user_id, v_doc_type, v_file_name,
    COALESCE(NEW.pdf_path, 'generated/' || NEW.id || '.html')
  WHERE NOT EXISTS (
    SELECT 1 FROM documents
    WHERE booking_id = NEW.booking_id
      AND user_id = v_user_id
      AND type = v_doc_type
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_generated_doc_to_documents"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_invoice_pdf_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.pdf_path IS DISTINCT FROM OLD.pdf_path AND NEW.pdf_path IS NOT NULL THEN
    UPDATE documents
    SET file_path = NEW.pdf_path
    WHERE booking_id = NEW.booking_id
      AND type IN ('invoice_advance', 'invoice_final')
      AND file_path LIKE 'invoices/%';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_invoice_pdf_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_invoice_to_documents"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid;
  v_doc_type text;
BEGIN
  -- Pro shop objednávky: customer_id přímo z invoices
  -- Pro booking: z bookings tabulky
  IF NEW.booking_id IS NOT NULL THEN
    SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  END IF;
  IF v_user_id IS NULL THEN
    v_user_id := NEW.customer_id;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.type IN ('proforma', 'advance', 'shop_proforma') THEN
    v_doc_type := 'invoice_advance';
  ELSIF NEW.type = 'payment_receipt' THEN
    v_doc_type := 'payment_receipt';
  ELSIF NEW.type = 'shop_final' THEN
    v_doc_type := 'invoice_shop';
  ELSE
    v_doc_type := 'invoice_final';
  END IF;

  -- Pro shop: booking_id je NULL, použij order_id pro deduplikaci
  INSERT INTO documents (booking_id, user_id, type, file_name, file_path)
  SELECT NEW.booking_id, v_user_id, v_doc_type,
    CASE
      WHEN NEW.type = 'payment_receipt' THEN 'DP ' || NEW.number || '.html'
      WHEN NEW.type = 'shop_proforma' THEN 'ZF ' || NEW.number || '.html'
      WHEN NEW.type = 'shop_final' THEN 'FV ' || NEW.number || '.html'
      ELSE 'Faktura ' || NEW.number || '.html'
    END,
    COALESCE(NEW.pdf_path, 'invoices/' || NEW.id || '.html')
  WHERE NOT EXISTS (
    SELECT 1 FROM documents
    WHERE user_id = v_user_id
      AND type = v_doc_type
      AND file_path = COALESCE(NEW.pdf_path, 'invoices/' || NEW.id || '.html')
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_invoice_to_documents"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_moto_day_prices_to_motorcycles"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE motorcycles SET
    price_mon = NEW.price_monday,
    price_tue = NEW.price_tuesday,
    price_wed = NEW.price_wednesday,
    price_thu = NEW.price_thursday,
    price_fri = NEW.price_friday,
    price_sat = NEW.price_saturday,
    price_sun = NEW.price_sunday,
    price_weekday = ROUND((NEW.price_monday + NEW.price_tuesday + NEW.price_wednesday + NEW.price_thursday + NEW.price_friday) / 5),
    price_weekend = ROUND((NEW.price_saturday + NEW.price_sunday) / 2)
  WHERE id = NEW.moto_id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_moto_day_prices_to_motorcycles"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_motorcycle_to_assets"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO acc_long_term_assets (
      name, category, purchase_price, current_value, acquired_date,
      depreciation_group, depreciation_method, description, status
    ) VALUES (
      NEW.brand || ' ' || NEW.model || ' (' || COALESCE(NEW.year::text, '?') || ')',
      'vehicles',
      COALESCE(NEW.purchase_price, 0),
      COALESCE(NEW.purchase_price, 0),
      COALESCE(NEW.acquired_date, CURRENT_DATE),
      2, 'linear',
      'Motorka MotoGo24 - ID: ' || NEW.id::text,
      'active'
    ) ON CONFLICT DO NOTHING;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    UPDATE acc_long_term_assets
    SET name = NEW.brand || ' ' || NEW.model || ' (' || COALESCE(NEW.year::text, '?') || ')',
        status = CASE WHEN NEW.status = 'retired' THEN 'disposed' ELSE 'active' END,
        updated_at = now()
    WHERE description LIKE '%' || NEW.id::text || '%';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_motorcycle_to_assets"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."track_booking_content_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_entry  jsonb;
  v_gear   jsonb := '{}'::jsonb;
  v_uid    uuid;
  v_source text;
  v_from_moto text;
  v_to_moto   text;
  v_changed boolean;
BEGIN
  -- Volající už zapsal vlastní záznam v tomto UPDATE → nic nepřidávat
  IF NEW.modification_history IS DISTINCT FROM OLD.modification_history THEN
    RETURN NEW;
  END IF;

  BEGIN
    -- Výbava (jen změněná pole)
    IF NEW.helmet_size IS DISTINCT FROM OLD.helmet_size THEN
      v_gear := v_gear || jsonb_build_object('helmet', jsonb_build_object('from', OLD.helmet_size, 'to', NEW.helmet_size));
    END IF;
    IF NEW.jacket_size IS DISTINCT FROM OLD.jacket_size THEN
      v_gear := v_gear || jsonb_build_object('jacket', jsonb_build_object('from', OLD.jacket_size, 'to', NEW.jacket_size));
    END IF;
    IF NEW.pants_size IS DISTINCT FROM OLD.pants_size THEN
      v_gear := v_gear || jsonb_build_object('pants', jsonb_build_object('from', OLD.pants_size, 'to', NEW.pants_size));
    END IF;
    IF NEW.boots_size IS DISTINCT FROM OLD.boots_size THEN
      v_gear := v_gear || jsonb_build_object('boots', jsonb_build_object('from', OLD.boots_size, 'to', NEW.boots_size));
    END IF;
    IF NEW.gloves_size IS DISTINCT FROM OLD.gloves_size THEN
      v_gear := v_gear || jsonb_build_object('gloves', jsonb_build_object('from', OLD.gloves_size, 'to', NEW.gloves_size));
    END IF;
    IF NEW.passenger_helmet_size IS DISTINCT FROM OLD.passenger_helmet_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_helmet', jsonb_build_object('from', OLD.passenger_helmet_size, 'to', NEW.passenger_helmet_size));
    END IF;
    IF NEW.passenger_jacket_size IS DISTINCT FROM OLD.passenger_jacket_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_jacket', jsonb_build_object('from', OLD.passenger_jacket_size, 'to', NEW.passenger_jacket_size));
    END IF;
    IF NEW.passenger_pants_size IS DISTINCT FROM OLD.passenger_pants_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_pants', jsonb_build_object('from', OLD.passenger_pants_size, 'to', NEW.passenger_pants_size));
    END IF;
    IF NEW.passenger_boots_size IS DISTINCT FROM OLD.passenger_boots_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_boots', jsonb_build_object('from', OLD.passenger_boots_size, 'to', NEW.passenger_boots_size));
    END IF;
    IF NEW.passenger_gloves_size IS DISTINCT FROM OLD.passenger_gloves_size THEN
      v_gear := v_gear || jsonb_build_object('passenger_gloves', jsonb_build_object('from', OLD.passenger_gloves_size, 'to', NEW.passenger_gloves_size));
    END IF;

    v_changed := (
      NEW.start_date      IS DISTINCT FROM OLD.start_date
      OR NEW.end_date     IS DISTINCT FROM OLD.end_date
      OR NEW.pickup_time  IS DISTINCT FROM OLD.pickup_time
      OR NEW.return_time  IS DISTINCT FROM OLD.return_time
      OR NEW.moto_id      IS DISTINCT FROM OLD.moto_id
      OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
      OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
      OR NEW.return_method  IS DISTINCT FROM OLD.return_method
      OR NEW.return_address IS DISTINCT FROM OLD.return_address
      OR v_gear <> '{}'::jsonb
    );
    IF NOT v_changed THEN
      RETURN NEW;
    END IF;

    v_uid := auth.uid();
    IF v_uid IS NULL THEN
      v_source := 'system';
    ELSIF v_uid = COALESCE(NEW.user_id, OLD.user_id) THEN
      v_source := 'customer';
    ELSIF public.is_admin() THEN
      v_source := 'admin';
    ELSE
      v_source := 'system';
    END IF;

    v_entry := jsonb_build_object(
      'at', now(), 'auto', true, 'source', v_source,
      'from_start', OLD.start_date, 'from_end', OLD.end_date,
      'to_start',   NEW.start_date, 'to_end',   NEW.end_date
    );

    IF NEW.pickup_time IS DISTINCT FROM OLD.pickup_time THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_time', OLD.pickup_time::text, 'to_pickup_time', NEW.pickup_time::text);
    END IF;
    IF NEW.return_time IS DISTINCT FROM OLD.return_time THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_time', OLD.return_time::text, 'to_return_time', NEW.return_time::text);
    END IF;

    IF NEW.moto_id IS DISTINCT FROM OLD.moto_id THEN
      SELECT model INTO v_from_moto FROM motorcycles WHERE id = OLD.moto_id;
      SELECT model INTO v_to_moto   FROM motorcycles WHERE id = NEW.moto_id;
      v_entry := v_entry || jsonb_build_object(
        'from_moto', COALESCE(v_from_moto, OLD.moto_id::text),
        'to_moto',   COALESCE(v_to_moto,   NEW.moto_id::text));
    END IF;

    IF NEW.pickup_method IS DISTINCT FROM OLD.pickup_method THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_method', OLD.pickup_method, 'to_pickup_method', NEW.pickup_method);
    END IF;
    IF NEW.pickup_address IS DISTINCT FROM OLD.pickup_address THEN
      v_entry := v_entry || jsonb_build_object(
        'from_pickup_address', OLD.pickup_address, 'to_pickup_address', NEW.pickup_address);
    END IF;
    IF NEW.return_method IS DISTINCT FROM OLD.return_method THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_method', OLD.return_method, 'to_return_method', NEW.return_method);
    END IF;
    IF NEW.return_address IS DISTINCT FROM OLD.return_address THEN
      v_entry := v_entry || jsonb_build_object(
        'from_return_address', OLD.return_address, 'to_return_address', NEW.return_address);
    END IF;

    IF v_gear <> '{}'::jsonb THEN
      v_entry := v_entry || jsonb_build_object('gear_changes', v_gear);
    END IF;

    NEW.modification_history := COALESCE(OLD.modification_history, '[]'::jsonb) || v_entry;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO debug_log(source, action, status, error_message)
      VALUES ('track_booking_content_changes', 'append_history', 'error', SQLERRM);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."track_booking_content_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."transfer_branch_gear"("p_from_branch" "uuid", "p_to_branch" "uuid", "p_type" "text", "p_size" "text", "p_qty" integer, "p_shortage_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_src record;
begin
  if not is_admin() then return jsonb_build_object('success',false,'error','not_authorized'); end if;
  if p_qty is null or p_qty<=0 then return jsonb_build_object('success',false,'error','bad_qty'); end if;
  select id, quantity into v_src from branch_accessories
    where branch_id=p_from_branch and type=p_type and size=p_size for update;
  if not found or v_src.quantity < p_qty then
    return jsonb_build_object('success',false,'error','insufficient_source'); end if;

  update branch_accessories set quantity=quantity-p_qty, updated_at=now() where id=v_src.id;
  insert into branch_accessories(branch_id,type,size,quantity) values(p_to_branch,p_type,p_size,p_qty)
    on conflict (branch_id,type,size) do update set quantity=branch_accessories.quantity+excluded.quantity, updated_at=now();

  if p_shortage_id is not null then
    update gear_shortages set status='transfer_requested', transfer_from_branch_id=p_from_branch, updated_at=now()
      where id=p_shortage_id; end if;

  perform detect_gear_shortages_for_window(p_to_branch, current_date, current_date+120);
  perform detect_gear_shortages_for_window(p_from_branch, current_date, current_date+120);
  return jsonb_build_object('success',true);
end $$;


ALTER FUNCTION "public"."transfer_branch_gear"("p_from_branch" "uuid", "p_to_branch" "uuid", "p_type" "text", "p_size" "text", "p_qty" integer, "p_shortage_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_booking_mileage_to_moto"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.mileage_start IS NULL OR NEW.mileage_start <= 0 THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.mileage_start IS NOT DISTINCT FROM OLD.mileage_start THEN
    RETURN NEW;
  END IF;
  IF NEW.moto_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Nikdy nesnižovat odometr (GREATEST chrání před chybným/staršího pořadí čtením).
  UPDATE motorcycles
     SET mileage = GREATEST(COALESCE(mileage, 0), NEW.mileage_start)
   WHERE id = NEW.moto_id
     AND COALESCE(mileage, 0) < NEW.mileage_start;  -- no-op když neroste

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_mileage_to_moto','bump_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id,'moto_id',NEW.moto_id,'mileage_start',NEW.mileage_start));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;  -- nikdy neshodit UPDATE rezervace
END;
$$;


ALTER FUNCTION "public"."trg_booking_mileage_to_moto"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_booking_payment_fill_seconds"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.form_started_at IS NOT NULL AND NEW.payment_fill_seconds IS NULL
     AND NEW.payment_status = 'paid'
     AND (TG_OP = 'INSERT' OR OLD.payment_status IS DISTINCT FROM 'paid') THEN
    NEW.payment_fill_seconds := GREATEST(0, LEAST(604800,
      EXTRACT(EPOCH FROM (COALESCE(NEW.confirmed_at, now()) - NEW.form_started_at))::int));
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_booking_payment_fill_seconds"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_email_on_door_codes_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_booking_id uuid;
BEGIN
  IF NEW.type IS DISTINCT FROM 'door_codes' THEN
    RETURN NEW;
  END IF;

  -- Najdi nejnovější aktivní booking s uvolněnými kódy
  SELECT b.id INTO v_booking_id
  FROM bookings b
  WHERE b.user_id = NEW.user_id
    AND b.status IN ('active', 'reserved')
    AND EXISTS (
      SELECT 1 FROM branch_door_codes bdc
      WHERE bdc.booking_id = b.id
        AND bdc.is_active = true
        AND bdc.sent_to_customer = true
    )
  ORDER BY b.created_at DESC
  LIMIT 1;

  IF v_booking_id IS NOT NULL THEN
    PERFORM send_door_codes_email(v_booking_id, NEW.user_id);
  END IF;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_email_on_door_codes_message failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_email_on_door_codes_message"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."trg_email_on_door_codes_message"() IS 'Při insertu door_codes admin_message pošle email s kódy (idempotentní přes message_log dedup).';



CREATE OR REPLACE FUNCTION "public"."trg_gear_shortage_on_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare v_branch uuid;
begin
  begin
    select m.branch_id into v_branch from motorcycles m where m.id = new.moto_id;
    if v_branch is not null then
      perform public.detect_gear_shortages_for_window(v_branch, new.start_date::date, new.end_date::date);
    end if;
  exception when others then
    null;  -- NIKDY neblokovat rezervaci
  end;
  return new;
end $$;


ALTER FUNCTION "public"."trg_gear_shortage_on_booking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_moto_purchase_mileage_floor"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.purchase_mileage IS NOT NULL
     AND NEW.purchase_mileage > COALESCE(NEW.mileage, 0) THEN
    NEW.mileage := NEW.purchase_mileage;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_moto_purchase_mileage_floor"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_notify_booking_cancelled"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_phone text;
  v_lang text;
  v_already_sent boolean;
BEGIN
  IF NEW.status != 'cancelled' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'cancelled' THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'booking_cancelled' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  v_lang := detect_customer_language(NEW.user_id, NEW.id, NULL);

  PERFORM send_sms_and_wa(
    v_phone,
    'booking_cancelled',
    jsonb_build_object(
      'booking_number', upper(left(NEW.id::text, 8))
    ),
    NEW.user_id,
    NEW.id,
    v_lang
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_booking_cancelled failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_notify_booking_cancelled"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_notify_booking_confirmed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_phone text;
  v_moto_model text;
  v_lang text;
  v_already_sent boolean;
BEGIN
  IF NEW.status != 'reserved' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'reserved' THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'booking_confirmed' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = NEW.moto_id;
  v_lang := detect_customer_language(NEW.user_id, NEW.id, NULL);

  PERFORM send_sms_and_wa(
    v_phone,
    'booking_confirmed',
    jsonb_build_object(
      'booking_number', upper(left(NEW.id::text, 8)),
      'motorcycle', coalesce(v_moto_model, ''),
      'start_date', coalesce(to_char(NEW.start_date, 'DD.MM.YYYY'), ''),
      'end_date',   coalesce(to_char(NEW.end_date,   'DD.MM.YYYY'), '')
    ),
    NEW.user_id,
    NEW.id,
    v_lang
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_booking_confirmed failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_notify_booking_confirmed"() OWNER TO "postgres";


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
BEGIN
  IF NEW.code_type != 'motorcycle' THEN RETURN NEW; END IF;

  -- Najdi user_id přes booking_id
  SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;
  v_booking_id := NEW.booking_id;

  -- Dedup
  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id AND template_slug = 'door_codes' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = v_user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  -- Načti oba kódy
  SELECT door_code INTO v_code_moto
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'motorcycle' AND is_active = true
   ORDER BY created_at DESC LIMIT 1;
  SELECT door_code INTO v_code_gear
    FROM branch_door_codes
   WHERE booking_id = NEW.booking_id AND code_type = 'accessories' AND is_active = true
   ORDER BY created_at DESC LIMIT 1;

  v_lang := detect_customer_language(v_user_id, v_booking_id, NULL);

  PERFORM send_sms_and_wa(
    v_phone,
    'door_codes',
    jsonb_build_object(
      'booking_number',  upper(left(v_booking_id::text, 8)),
      'door_code_moto',  coalesce(v_code_moto, ''),
      'door_code_gear',  coalesce(v_code_gear, '')
    ),
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


ALTER FUNCTION "public"."trg_notify_door_codes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_notify_ride_completed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_phone text;
  v_moto_model text;
  v_lang text;
  v_already_sent boolean;
  v_review_link text;
BEGIN
  IF NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.id AND template_slug = 'ride_completed' AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT phone INTO v_phone FROM profiles WHERE id = NEW.user_id;
  IF v_phone IS NULL OR v_phone = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = NEW.moto_id;
  v_lang := detect_customer_language(NEW.user_id, NEW.id, NULL);

  -- Review link z app_settings (volitelný — když chybí, šablona to ošetří)
  SELECT value #>> '{}' INTO v_review_link FROM app_settings WHERE key = 'google_review_url';

  PERFORM send_sms_and_wa(
    v_phone,
    'ride_completed',
    jsonb_build_object(
      'motorcycle',   coalesce(v_moto_model, ''),
      'review_link',  coalesce(v_review_link, 'https://motogo24.cz')
    ),
    NEW.user_id,
    NEW.id,
    v_lang
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_notify_ride_completed failed: %', SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_notify_ride_completed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_push_on_admin_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_data jsonb;
BEGIN
  v_data := jsonb_build_object(
    'type', CASE
      WHEN NEW.type = 'door_codes' THEN 'door_codes'
      ELSE 'message'
    END,
    'id', NEW.id
  );

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


ALTER FUNCTION "public"."trg_push_on_admin_message"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."trg_push_on_admin_message"() IS 'Při nové admin_messages pošle FCM push přes send-push edge function.';



CREATE OR REPLACE FUNCTION "public"."trg_realloc_booking_discounts"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.discount_amount IS DISTINCT FROM OLD.discount_amount THEN
    PERFORM public._reallocate_booking_discounts(NEW.id, NEW.discount_amount);
  END IF;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."trg_realloc_booking_discounts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_send_booking_completed_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_booking bookings%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_moto_model text;
  v_source text;
  v_google_url text;
  v_facebook_url text;
  v_already_sent boolean;
  v_booking_short text;
  v_promo_code text;
  v_payload jsonb;
BEGIN
  IF NEW.type != 'final' OR NEW.booking_id IS NULL THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
    WHERE booking_id = NEW.booking_id
      AND template_slug IN ('booking_completed', 'web_booking_completed')
      AND status = 'sent'
    LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'trg_send_booking_completed_email: app_settings missing';
    RETURN NEW;
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND OR v_booking.user_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_booking.user_id;
  IF NOT FOUND OR v_profile.email IS NULL OR v_profile.email = '' THEN RETURN NEW; END IF;

  SELECT model INTO v_moto_model FROM motorcycles WHERE id = v_booking.moto_id;
  v_source := COALESCE(v_booking.booking_source, 'app');

  SELECT value #>> '{}' INTO v_google_url   FROM app_settings WHERE key = 'google_review_url';
  SELECT value #>> '{}' INTO v_facebook_url FROM app_settings WHERE key = 'facebook_review_url';

  v_booking_short := UPPER(RIGHT(REPLACE(v_booking.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;
  IF NOT EXISTS (SELECT 1 FROM promo_codes WHERE code = v_promo_code) THEN
    v_promo_code := '';
  END IF;

  -- Sdílený payload pro hardcoded volání i dispatch_email_event
  v_payload := jsonb_build_object(
    'booking_id',           v_booking.id,
    'customer_email',       v_profile.email,
    'customer_name',        COALESCE(v_profile.full_name, ''),
    'motorcycle',           COALESCE(v_moto_model, ''),
    'start_date',           v_booking.start_date,
    'end_date',             v_booking.end_date,
    'total_price',          v_booking.total_price,
    'source',               v_source,
    'google_review_url',    COALESCE(v_google_url, ''),
    'facebook_review_url',  COALESCE(v_facebook_url, ''),
    'discount_code',        v_promo_code
  );

  -- HARDCODED legacy volání — beze změny chování
  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                   'Authorization', 'Bearer ' || v_key),
    body    := v_payload || jsonb_build_object('type', 'booking_completed')
  );

  -- ⚠️ NOVÉ: dispatch custom šablon které admin přiřadil k těmto eventům
  PERFORM dispatch_email_event('kf_invoice_created', v_payload);
  PERFORM dispatch_email_event('booking_status_changed_to_completed', v_payload);
  PERFORM dispatch_email_event('auto_after_kf_created', v_payload);

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_booking_completed_email failed for invoice %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_send_booking_completed_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_send_booking_modified_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_profile profiles%ROWTYPE;
  v_moto_old text;
  v_moto_new text;
  v_already_sent boolean;
  v_changed boolean;
  v_payload jsonb;
  v_price_diff numeric;
  v_app_msg text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_status_change','info',
            jsonb_build_object('booking_id',NEW.id,'old_status',OLD.status,'new_status',NEW.status));
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('reserved','active') THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_status_not_eligible','info',
            jsonb_build_object('booking_id',NEW.id,'status',NEW.status));
    RETURN NEW;
  END IF;

  v_changed :=
       NEW.moto_id        IS DISTINCT FROM OLD.moto_id
    OR NEW.start_date     IS DISTINCT FROM OLD.start_date
    OR NEW.end_date       IS DISTINCT FROM OLD.end_date
    OR NEW.total_price    IS DISTINCT FROM OLD.total_price
    OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
    OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
    OR NEW.pickup_time    IS DISTINCT FROM OLD.pickup_time
    OR NEW.return_method  IS DISTINCT FROM OLD.return_method
    OR NEW.return_address IS DISTINCT FROM OLD.return_address
    OR NEW.return_time    IS DISTINCT FROM OLD.return_time;

  IF NOT v_changed THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_field_change','info',
            jsonb_build_object(
              'booking_id',NEW.id,
              'old',jsonb_build_object('moto',OLD.moto_id,'start',OLD.start_date,'end',OLD.end_date,'total',OLD.total_price,'pickup_method',OLD.pickup_method,'pickup_time',OLD.pickup_time,'return_method',OLD.return_method,'return_time',OLD.return_time),
              'new',jsonb_build_object('moto',NEW.moto_id,'start',NEW.start_date,'end',NEW.end_date,'total',NEW.total_price,'pickup_method',NEW.pickup_method,'pickup_time',NEW.pickup_time,'return_method',NEW.return_method,'return_time',NEW.return_time)
            ));
    RETURN NEW;
  END IF;

  SELECT model INTO v_moto_old FROM motorcycles WHERE id = OLD.moto_id;
  SELECT model INTO v_moto_new FROM motorcycles WHERE id = NEW.moto_id;

  SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;

  v_payload := jsonb_build_object(
    'booking_id', NEW.id,
    'customer_email', COALESCE(v_profile.email,''),
    'customer_name', COALESCE(v_profile.full_name,''),
    'source', COALESCE(NEW.booking_source,'app'),
    'motorcycle', COALESCE(v_moto_new,''),
    'start_date', NEW.start_date,
    'end_date', NEW.end_date,
    'total_price', NEW.total_price,
    'price_difference', COALESCE(NEW.total_price,0) - COALESCE(OLD.total_price,0),
    'pickup_method', COALESCE(NEW.pickup_method,''),
    'pickup_address', COALESCE(NEW.pickup_address,''),
    'pickup_time', COALESCE(NEW.pickup_time::text,''),
    'return_method', COALESCE(NEW.return_method,''),
    'return_address', COALESCE(NEW.return_address,''),
    'return_time', COALESCE(NEW.return_time::text,''),
    'original_motorcycle', COALESCE(v_moto_old,''),
    'original_start_date', OLD.start_date,
    'original_end_date', OLD.end_date,
    'original_total_price', OLD.total_price,
    'original_pickup_method', COALESCE(OLD.pickup_method,''),
    'original_pickup_address', COALESCE(OLD.pickup_address,''),
    'original_pickup_time', COALESCE(OLD.pickup_time::text,''),
    'original_return_method', COALESCE(OLD.return_method,''),
    'original_return_address', COALESCE(OLD.return_address,''),
    'original_return_time', COALESCE(OLD.return_time::text,'')
  );

  -- NOVÉ (2026-07-27): úprava s nezaplaceným doplatkem → mail ODLOŽIT.
  -- Payload se uschová a odešle ho confirm_booking_surcharge po potvrzení platby
  -- (zákazník mezitím dostane výzvu k platbě ze šablony booking_qr_payment přes
  -- edge fn qr-payment v režimu surcharge). Interní UPDATE nemění žádné sledované
  -- pole → rekurze se zastaví na skipped_no_field_change.
  IF COALESCE(NEW.mod_surcharge_due, 0) > 0 THEN
    BEGIN
      UPDATE bookings SET mod_email_payload = v_payload WHERE id = NEW.id;
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('trg_booking_modified_email','deferred_surcharge_pending','info',
              jsonb_build_object('booking_id',NEW.id,'surcharge_due',NEW.mod_surcharge_due));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('trg_booking_modified_email','deferred_payload_store_failed','error',SQLERRM,
              jsonb_build_object('booking_id',NEW.id));
    END;
    RETURN NEW;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE booking_id = NEW.id AND template_slug LIKE 'booking_modified%'
       AND status = 'sent' AND created_at > now() - interval '5 minutes' LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_dedup_5min','info',
            jsonb_build_object('booking_id',NEW.id));
    RETURN NEW;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','app_settings_missing','error','supabase_url or service_role_key empty',
            jsonb_build_object('booking_id',NEW.id,'has_url',v_url IS NOT NULL,'has_key',v_key IS NOT NULL));
    RETURN NEW;
  END IF;

  IF v_profile.id IS NULL OR v_profile.email IS NULL OR v_profile.email = '' THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_email','info',
            jsonb_build_object('booking_id',NEW.id,'user_id',NEW.user_id));
    RETURN NEW;
  END IF;

  -- KROK 1: hardcoded mail — isolated tak, aby selhání KROKU 2 NEROLLBACKLO http_post
  BEGIN
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/send-booking-email',
      headers := jsonb_build_object('Content-Type','application/json',
                                     'Authorization','Bearer '||v_key),
      body    := v_payload || jsonb_build_object('type','booking_modified')
    );
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','http_post_queued','info',
            jsonb_build_object('booking_id',NEW.id,'recipient',v_profile.email));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','http_post_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  -- KROK 2: dispatch custom šablon — isolated v vlastním BEGIN/EXCEPTION
  BEGIN
    PERFORM dispatch_email_event('booking_updated', v_payload);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','dispatch_event_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  -- KROK 3 (2026-06-11): in-app zpráva → appka Zprávy + FCM push
  BEGIN
    v_price_diff := COALESCE(NEW.total_price,0) - COALESCE(OLD.total_price,0);
    v_app_msg := 'Vaše rezervace č. ' || UPPER(RIGHT(NEW.id::text, 8)) || ' byla upravena.'
      || CASE WHEN NEW.start_date::date <> OLD.start_date::date OR NEW.end_date::date <> OLD.end_date::date
           THEN ' Nový termín: ' || TO_CHAR(NEW.start_date,'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date,'DD.MM.YYYY') || '.'
           ELSE '' END
      || CASE WHEN NEW.moto_id IS DISTINCT FROM OLD.moto_id
           THEN ' Nová motorka: ' || COALESCE(v_moto_new,'') || '.'
           ELSE '' END
      || CASE WHEN v_price_diff > 0
           THEN ' Doplatek ' || ROUND(v_price_diff)::text || ' Kč — doklad o platbě najdete v e-mailu.'
           WHEN v_price_diff < 0
           THEN ' Vracíme ' || ROUND(ABS(v_price_diff))::text || ' Kč zpět na kartu — dobropis najdete v e-mailu.'
           ELSE '' END
      || ' Detaily a aktualizovanou smlouvu jsme poslali e-mailem.';
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (NEW.user_id, 'Rezervace upravena', v_app_msg, 'info');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','app_message_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','trigger_outer_exception','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_send_booking_modified_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_send_shop_order_confirmed_email"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_payload jsonb;
  v_already_sent boolean := false;
  v_source text;
  v_has_voucher_item boolean := false;
BEGIN
  -- Trigger fire: jen při přechodu pending → paid
  IF NEW.payment_status != 'paid' OR OLD.payment_status = 'paid' THEN
    RETURN NEW;
  END IF;

  -- Voucher delivered (čistě digitální poukaz) → mail si zařídí webhook-receiver
  IF NEW.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  -- Smíšená objednávka s voucher itemem → taky webhook-receiver
  SELECT EXISTS(
    SELECT 1 FROM shop_order_items
    WHERE order_id = NEW.id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
  ) INTO v_has_voucher_item;

  IF v_has_voucher_item THEN
    RETURN NEW;
  END IF;

  IF NEW.customer_email IS NULL OR NEW.customer_email = '' THEN
    RETURN NEW;
  END IF;

  -- Dedup
  SELECT EXISTS(
    SELECT 1 FROM message_log
     WHERE template_slug IN ('shop_order_confirmed', 'web_shop_order_confirmed')
       AND recipient_email = NEW.customer_email
       AND content_preview LIKE '%' || NEW.order_number || '%'
       AND status = 'sent' LIMIT 1
  ) INTO v_already_sent;
  IF v_already_sent THEN RETURN NEW; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN RETURN NEW; END IF;

  v_source := CASE WHEN NEW.customer_id IS NULL THEN 'web' ELSE 'app' END;

  v_payload := jsonb_build_object(
    'order_id',       NEW.id,
    'order_number',   NEW.order_number,
    'customer_email', NEW.customer_email,
    'customer_name',  COALESCE(NEW.customer_name, ''),
    'total_price',    NEW.total,
    'shipping_cost',  NEW.shipping_cost,
    'source',         v_source
  );

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-booking-email',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                   'Authorization', 'Bearer ' || v_key),
    body    := v_payload || jsonb_build_object('type', 'shop_order_confirmed')
  );

  -- Custom šablonové eventy přes dispatcher (pokud admin přidá custom šablony)
  BEGIN
    PERFORM dispatch_email_event('stripe_payment_confirmed_shop', v_payload);
    PERFORM dispatch_email_event('shop_order_status_confirmed', v_payload);
  EXCEPTION WHEN OTHERS THEN
    -- dispatch_email_event nemusí existovat — neblokuje
    NULL;
  END;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'trg_send_shop_order_confirmed_email: pg_net failed for %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trg_send_shop_order_confirmed_email"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_poi_photo_backfill"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_url text;
  v_key text;
  v_missing int;
begin
  -- Práce = aktivní body BEZ fotky, u kterých se fotka JEŠTĚ nezkoušela.
  select count(*) into v_missing
  from public.points_of_interest
  where image_url is null and photo_checked_at is null and is_active;

  -- Hotovo → odplánuj sebe sama a skonči.
  if coalesce(v_missing, 0) = 0 then
    begin
      perform cron.unschedule('backfill-poi-photos');
    exception when others then null;
    end;
    return;
  end if;

  select value #>> '{}' into v_url from public.app_settings where key = 'supabase_url';
  select value #>> '{}' into v_key from public.app_settings where key = 'service_role_key';
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    raise warning 'trigger_poi_photo_backfill: app_settings supabase_url/service_role_key chybí';
    return;
  end if;

  perform net.http_post(
    url := v_url || '/functions/v1/backfill-poi-photos?limit=150',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := '{}'::jsonb
  );
end $$;


ALTER FUNCTION "public"."trigger_poi_photo_backfill"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_poi_surroundings_backfill"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin return; end $$;


ALTER FUNCTION "public"."trigger_poi_surroundings_backfill"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_route_translation_backfill"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin return; end $$;


ALTER FUNCTION "public"."trigger_route_translation_backfill"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  b record;
  v_pp int; v_pbr int; v_pbp int;
  v_new_pass boolean; v_new_br boolean; v_new_bp boolean;
  v_old_paid int := 0; v_new_paid int := 0; v_diff int;
  s_h text; s_j text; s_p text; s_b text; s_g text;
  s_ph text; s_pj text; s_pp_ text; s_pb text; s_pg text;
  v_dtype text;
  v_calc jsonb;
  v_net_diff numeric;
  v_new_total numeric;
  v_new_discount numeric;
  v_loy_level int := 0;
  v_loy_pct numeric := 0;
  v_loy_disc numeric := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','unauthenticated'); END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','not_found'); END IF;
  IF b.user_id <> v_uid AND NOT is_admin() THEN RETURN jsonb_build_object('success',false,'error','not_owner'); END IF;
  IF b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success',false,'error','wrong_status'); END IF;
  IF b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success',false,'error','not_paid'); END IF;

  SELECT COALESCE(MAX(CASE WHEN key='passenger_gear'  AND pricing_unit<>'free' THEN price_czk END),690),
         COALESCE(MAX(CASE WHEN key='boots_rider'     AND pricing_unit<>'free' THEN price_czk END),290),
         COALESCE(MAX(CASE WHEN key='boots_passenger' AND pricing_unit<>'free' THEN price_czk END),290)
    INTO v_pp, v_pbr, v_pbp
    FROM accessory_types WHERE key IN ('passenger_gear','boots_rider','boots_passenger');

  s_h  := NULLIF(p_sizes->>'helmet','');  s_j := NULLIF(p_sizes->>'jacket','');
  s_p  := NULLIF(p_sizes->>'pants','');   s_b := NULLIF(p_sizes->>'boots','');
  s_g  := NULLIF(p_sizes->>'gloves','');
  s_ph := NULLIF(p_sizes->>'passenger_helmet','');  s_pj := NULLIF(p_sizes->>'passenger_jacket','');
  s_pp_:= NULLIF(p_sizes->>'passenger_pants','');   s_pb := NULLIF(p_sizes->>'passenger_boots','');
  s_pg := NULLIF(p_sizes->>'passenger_gloves','');

  v_new_pass := (s_ph IS NOT NULL OR s_pj IS NOT NULL OR s_pp_ IS NOT NULL OR s_pg IS NOT NULL);
  v_new_br   := (s_b  IS NOT NULL);
  v_new_bp   := (s_pb IS NOT NULL);
  IF v_new_pass THEN v_new_paid := v_new_paid + v_pp;  END IF;
  IF v_new_br   THEN v_new_paid := v_new_paid + v_pbr; END IF;
  IF v_new_bp   THEN v_new_paid := v_new_paid + v_pbp; END IF;

  SELECT COALESCE(SUM(
    CASE
      WHEN (lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%')
       AND (lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%') THEN v_pbp
      WHEN (lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%')           THEN v_pbr
      WHEN (lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%')  THEN v_pp
      ELSE 0 END),0)
  INTO v_old_paid FROM booking_extras WHERE booking_id = p_booking_id;

  v_diff := v_new_paid - v_old_paid;

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — app rezervace, kladný rozdíl výbavy ──
  -- Výbava je součást loyalty base i při vzniku rezervace; doplatek za
  -- přidanou výbavu se sníží o pct dle aktuálního ranku.
  IF COALESCE(b.booking_source, 'web') = 'app' AND v_diff > 0 THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND(v_diff * v_loy_pct / 100.0);
  END IF;

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  -- v_diff je HRUBÝ rozdíl výbavy; net_diff (po slevě) je to, co se účtuje /
  -- vrací zákazníkovi. Loyalty sleva se odečítá už z gross rozdílu.
  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(b.id, b.total_price, b.discount_amount, v_diff - v_loy_disc, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  IF p_dry_run THEN
    RETURN jsonb_build_object('success',true,'payment_required', v_net_diff>0,'net_diff',v_net_diff,
      'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
      'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
  END IF;

  UPDATE bookings SET
    helmet_size=s_h, jacket_size=s_j, pants_size=s_p, boots_size=s_b, gloves_size=s_g,
    passenger_helmet_size = CASE WHEN v_new_pass THEN s_ph  ELSE NULL END,
    passenger_jacket_size = CASE WHEN v_new_pass THEN s_pj  ELSE NULL END,
    passenger_pants_size  = CASE WHEN v_new_pass THEN s_pp_ ELSE NULL END,
    passenger_gloves_size = CASE WHEN v_new_pass THEN s_pg  ELSE NULL END,
    passenger_boots_size  = CASE WHEN v_new_bp   THEN s_pb  ELSE NULL END,
    extras_price = GREATEST(0, COALESCE(extras_price,0) + v_diff),
    total_price  = v_new_total,
    discount_amount = v_new_discount,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level   = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END
  WHERE id = p_booking_id;

  DELETE FROM booking_extras WHERE booking_id = p_booking_id
    AND ( lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%'
       OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );
  IF v_new_pass THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Výbava spolujezdce',v_pp,1); END IF;
  IF v_new_br   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty řidič',v_pbr,1); END IF;
  IF v_new_bp   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty spolujezdce',v_pbp,1); END IF;

  RETURN jsonb_build_object('success',true,'payment_required',false,'net_diff',v_net_diff,
    'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
    'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
END;
$$;


ALTER FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_moto_after_service"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF NEW.moto_id IS NULL THEN RETURN NEW; END IF;

  -- Bump odometru ze servisního čtení (nikdy nesnižovat).
  IF NEW.km_at_service IS NOT NULL AND NEW.km_at_service > 0 THEN
    UPDATE motorcycles
       SET mileage = GREATEST(COALESCE(mileage, 0), NEW.km_at_service)
     WHERE id = NEW.moto_id
       AND COALESCE(mileage, 0) < NEW.km_at_service;
  END IF;

  -- Při dokončení servisu srovnat baseline plánů.
  IF COALESCE(NEW.status,'') = 'completed' THEN
    UPDATE motorcycles
       SET last_service_date = COALESCE(NEW.completed_date::date, CURRENT_DATE)
     WHERE id = NEW.moto_id;
    UPDATE maintenance_schedules
       SET last_service_km   = GREATEST(COALESCE(last_service_km,0), COALESCE(NEW.km_at_service,0)),
           last_service_date = COALESCE(NEW.completed_date::date, CURRENT_DATE)
     WHERE moto_id = NEW.moto_id AND active = true;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('update_moto_after_service','failed','error',SQLERRM,
            jsonb_build_object('log_id',NEW.id,'moto_id',NEW.moto_id));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_moto_after_service"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_test_booking_fields"("p_booking_id" "uuid", "p_fields" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE bookings SET
    end_date = COALESCE((p_fields->>'end_date')::timestamptz, end_date),
    picked_up_at = COALESCE((p_fields->>'picked_up_at')::timestamptz, picked_up_at),
    mileage_start = COALESCE((p_fields->>'mileage_start')::int, mileage_start),
    mileage_end = COALESCE((p_fields->>'mileage_end')::int, mileage_end),
    returned_at = COALESCE((p_fields->>'returned_at')::timestamptz, returned_at),
    rating = COALESCE((p_fields->>'rating')::smallint, rating),
    rated_at = COALESCE((p_fields->>'rated_at')::timestamptz, rated_at),
    pickup_method = COALESCE(p_fields->>'pickup_method', pickup_method),
    pickup_address = COALESCE(p_fields->>'pickup_address', pickup_address),
    pickup_lat = COALESCE((p_fields->>'pickup_lat')::double precision, pickup_lat),
    pickup_lng = COALESCE((p_fields->>'pickup_lng')::double precision, pickup_lng),
    return_method = COALESCE(p_fields->>'return_method', return_method),
    return_address = COALESCE(p_fields->>'return_address', return_address),
    return_lat = COALESCE((p_fields->>'return_lat')::double precision, return_lat),
    return_lng = COALESCE((p_fields->>'return_lng')::double precision, return_lng)
  WHERE id = p_booking_id;
END;
$$;


ALTER FUNCTION "public"."update_test_booking_fields"("p_booking_id" "uuid", "p_fields" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_test_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status", "p_payment_status" "public"."payment_status" DEFAULT NULL::"public"."payment_status") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF p_payment_status IS NOT NULL THEN
    UPDATE bookings SET status = p_status, payment_status = p_payment_status WHERE id = p_booking_id AND is_test = true;
  ELSE
    UPDATE bookings SET status = p_status WHERE id = p_booking_id AND is_test = true;
  END IF;
END;
$$;


ALTER FUNCTION "public"."update_test_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status", "p_payment_status" "public"."payment_status") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_test_profile"("p_user_id" "uuid", "p_data" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_license text[];
BEGIN
  -- Basic fields
  UPDATE profiles SET
    full_name = COALESCE(p_data->>'full_name', full_name),
    phone = COALESCE(p_data->>'phone', phone),
    city = COALESCE(p_data->>'city', city),
    is_test_account = COALESCE((p_data->>'is_test_account')::boolean, is_test_account)
  WHERE id = p_user_id;

  -- License group (array)
  IF p_data ? 'license_group' THEN
    IF p_data->'license_group' IS NULL OR p_data->>'license_group' = 'null' THEN
      UPDATE profiles SET license_group = NULL WHERE id = p_user_id;
    ELSE
      SELECT array_agg(val) INTO v_license FROM jsonb_array_elements_text(p_data->'license_group') AS val;
      UPDATE profiles SET license_group = v_license WHERE id = p_user_id;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION "public"."update_test_profile"("p_user_id" "uuid", "p_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_test_sos_status"("p_incident_id" "uuid", "p_status" "public"."sos_status", "p_notes" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE sos_incidents SET 
    status = p_status, 
    admin_notes = p_notes,
    resolved_at = CASE WHEN p_status IN ('resolved', 'closed') THEN NOW() ELSE resolved_at END
  WHERE id = p_incident_id;
END;
$$;


ALTER FUNCTION "public"."update_test_sos_status"("p_incident_id" "uuid", "p_status" "public"."sos_status", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."use_promo_code"("p_code" "text", "p_booking_id" "uuid" DEFAULT NULL::"uuid", "p_base_amount" numeric DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_promo promo_codes%ROWTYPE;
  v_uid uuid;
  v_discount numeric;
  v_actual_uses integer;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_promo FROM promo_codes
    WHERE code = upper(p_code) AND active = true
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód neexistuje nebo není aktivní');
  END IF;

  IF v_promo.valid_from IS NOT NULL AND v_promo.valid_from > CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód ještě není platný');
  END IF;

  IF v_promo.valid_to IS NOT NULL AND v_promo.valid_to < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód vypršel');
  END IF;

  -- Počítej skutečné použití
  SELECT count(*) INTO v_actual_uses
    FROM promo_code_usage WHERE promo_code_id = v_promo.id;

  IF v_promo.max_uses IS NOT NULL AND v_promo.max_uses > 0 AND v_actual_uses >= v_promo.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód byl vyčerpán');
  END IF;

  IF v_promo.min_order_amount IS NOT NULL AND p_base_amount < v_promo.min_order_amount THEN
    RETURN jsonb_build_object('valid', false, 'error',
      'Minimální hodnota objednávky je ' || v_promo.min_order_amount || ' Kč');
  END IF;

  -- Vypočítej slevu
  IF v_promo.type = 'percent' THEN
    v_discount := ROUND(p_base_amount * v_promo.value / 100);
  ELSE
    v_discount := v_promo.value;
  END IF;

  -- Aktualizuj used_count na skutečný počet + 1
  UPDATE promo_codes SET used_count = v_actual_uses + 1
    WHERE id = v_promo.id;

  -- Zaloguj použití
  INSERT INTO promo_code_usage (promo_code_id, booking_id, customer_id, discount_applied, used_at)
    VALUES (v_promo.id, p_booking_id, v_uid, v_discount, now());

  RETURN jsonb_build_object(
    'valid', true,
    'id', v_promo.id,
    'type', v_promo.type,
    'value', v_promo.value,
    'discount', v_discount
  );
END;
$$;


ALTER FUNCTION "public"."use_promo_code"("p_code" "text", "p_booking_id" "uuid", "p_base_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_app_loyalty_discount"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_cnt int; v_pct int; v_base numeric; v_max numeric;
BEGIN
  IF COALESCE(NEW.booking_source, 'app') <> 'app' THEN
    IF COALESCE(NEW.loyalty_discount_amount, 0) > 0 THEN
      NEW.total_price := COALESCE(NEW.total_price, 0) + NEW.loyalty_discount_amount;
    END IF;
    NEW.loyalty_level := NULL; NEW.loyalty_percent := NULL; NEW.loyalty_discount_amount := 0;
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.loyalty_discount_amount, 0) <= 0 THEN RETURN NEW; END IF;

  v_cnt := _loyalty_effective_count(NEW.user_id);          -- ZMĚNA: efektivní
  v_pct := LEAST(20, CEIL((v_cnt + 1) / 2.0))::int;
  v_base := COALESCE(NEW.total_price,0) + COALESCE(NEW.discount_amount,0)
          + COALESCE(NEW.loyalty_discount_amount,0) - COALESCE(NEW.delivery_fee,0);
  v_max  := ROUND(v_base * v_pct / 100.0);
  IF NEW.loyalty_discount_amount > v_max + 1 OR COALESCE(NEW.loyalty_percent, 0) > v_pct THEN
    NEW.total_price := COALESCE(NEW.total_price,0) + (NEW.loyalty_discount_amount - v_max);
    NEW.loyalty_discount_amount := v_max;
    NEW.loyalty_percent := v_pct;
    NEW.loyalty_level := v_pct;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'validate_app_loyalty_discount failed: %', SQLERRM;
  RETURN NEW;
END; $$;


ALTER FUNCTION "public"."validate_app_loyalty_discount"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_late_pickup_discount"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_max numeric; v_sent numeric;
BEGIN
  BEGIN
    v_sent := COALESCE(NEW.late_pickup_discount_amount, 0);
    IF v_sent > 0 THEN
      v_max := public._late_pickup_discount(NEW.moto_id, NEW.start_date, NEW.end_date, NEW.pickup_time);
      IF v_sent > v_max THEN
        NEW.total_price := COALESCE(NEW.total_price, 0) + (v_sent - v_max);
        NEW.late_pickup_discount_amount := v_max;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_late_pickup_discount"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_promo_code"("p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_promo promo_codes%ROWTYPE;
  v_actual_uses integer;
BEGIN
  SELECT * INTO v_promo FROM promo_codes
    WHERE code = upper(p_code) AND active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód neexistuje nebo není aktivní');
  END IF;

  IF v_promo.valid_from IS NOT NULL AND v_promo.valid_from > CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód ještě není platný');
  END IF;

  IF v_promo.valid_to IS NOT NULL AND v_promo.valid_to < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód vypršel');
  END IF;

  -- Počítej skutečné použití z promo_code_usage (ne z used_count sloupce)
  SELECT count(*) INTO v_actual_uses
    FROM promo_code_usage WHERE promo_code_id = v_promo.id;

  -- Synchronizuj used_count pokud se liší
  IF v_promo.used_count IS DISTINCT FROM v_actual_uses THEN
    UPDATE promo_codes SET used_count = v_actual_uses WHERE id = v_promo.id;
  END IF;

  IF v_promo.max_uses IS NOT NULL AND v_promo.max_uses > 0 AND v_actual_uses >= v_promo.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód byl vyčerpán');
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'id', v_promo.id,
    'type', v_promo.type,
    'value', v_promo.value,
    'min_order_amount', v_promo.min_order_amount
  );
END;
$$;


ALTER FUNCTION "public"."validate_promo_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_voucher_code"("p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_voucher vouchers%ROWTYPE;
BEGIN
  SELECT * INTO v_voucher FROM vouchers
    WHERE code = upper(p_code) AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Poukaz neexistuje nebo není aktivní');
  END IF;

  IF v_voucher.valid_from IS NOT NULL AND v_voucher.valid_from > CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Poukaz ještě není platný');
  END IF;

  IF v_voucher.valid_until IS NOT NULL AND v_voucher.valid_until < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Poukaz vypršel');
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'id', v_voucher.id,
    'type', 'fixed',
    'value', v_voucher.amount,
    'code', v_voucher.code
  );
END;
$$;


ALTER FUNCTION "public"."validate_voucher_code"("p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verify_customer_docs"("p_ocr_name" "text" DEFAULT NULL::"text", "p_ocr_dob" "text" DEFAULT NULL::"text", "p_ocr_id_number" "text" DEFAULT NULL::"text", "p_ocr_license_number" "text" DEFAULT NULL::"text", "p_ocr_license_category" "text" DEFAULT NULL::"text", "p_ocr_license_expiry" "text" DEFAULT NULL::"text", "p_rental_end" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
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
          'type', 'license_expired',
          'label', 'Řidičský průkaz je neplatný (expiroval ' || p_ocr_license_expiry || ')'
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
    EXCEPTION WHEN OTHERS THEN NULL;
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


ALTER FUNCTION "public"."verify_customer_docs"("p_ocr_name" "text", "p_ocr_dob" "text", "p_ocr_id_number" "text", "p_ocr_license_number" "text", "p_ocr_license_category" "text", "p_ocr_license_expiry" "text", "p_rental_end" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."verify_customer_docs"("p_ocr_name" "text", "p_ocr_dob" "text", "p_ocr_id_number" "text", "p_ocr_license_number" "text", "p_ocr_license_category" "text", "p_ocr_license_expiry" "text", "p_rental_end" "text") IS 'Verifikace naskenovaných dokladů proti profilu. Kontroluje jméno, DOB, číslo ŘP, platnost ŘP, skupiny ŘP.';



CREATE OR REPLACE FUNCTION "public"."withhold_swap_next_codes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."withhold_swap_next_codes"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."_git_migrations" (
    "filename" "text" NOT NULL,
    "applied_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "baseline" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."_git_migrations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_depreciation_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "year_number" integer NOT NULL,
    "annual_amount" numeric DEFAULT 0,
    "cumulative_amount" numeric DEFAULT 0,
    "remaining_value" numeric DEFAULT 0,
    "method" "text",
    "depreciation_group" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."acc_depreciation_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_employees" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "contract_type" "text" NOT NULL,
    "gross_salary" numeric DEFAULT 0,
    "start_date" "date",
    "end_date" "date",
    "personal_id" "text",
    "bank_account" "text",
    "tax_discount" numeric DEFAULT 2570,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "phone" "text",
    "email" "text",
    "position" "text",
    "vacation_days_total" integer DEFAULT 20,
    "vacation_days_used" integer DEFAULT 0,
    "hourly_rate" numeric DEFAULT 500,
    CONSTRAINT "acc_employees_contract_type_check" CHECK (("contract_type" = ANY (ARRAY['hpp'::"text", 'dpp'::"text", 'dpc'::"text", 'ico'::"text"])))
);


ALTER TABLE "public"."acc_employees" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_liabilities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "counterparty" "text",
    "type" "text" NOT NULL,
    "amount" numeric DEFAULT 0,
    "paid_amount" numeric DEFAULT 0,
    "due_date" "date",
    "paid_date" "date",
    "description" "text",
    "variable_symbol" "text",
    "invoice_number" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "financial_event_id" "uuid",
    CONSTRAINT "acc_liabilities_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'partial'::"text", 'paid'::"text", 'overdue'::"text"]))),
    CONSTRAINT "acc_liabilities_type_check" CHECK (("type" = ANY (ARRAY['supplier'::"text", 'tax'::"text", 'social'::"text", 'health'::"text", 'salary'::"text", 'loan'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."acc_liabilities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_long_term_assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "purchase_price" numeric DEFAULT 0,
    "current_value" numeric DEFAULT 0,
    "total_depreciated" numeric DEFAULT 0,
    "acquired_date" "date",
    "disposed_date" "date",
    "depreciation_group" integer,
    "depreciation_method" "text" DEFAULT 'linear'::"text",
    "description" "text",
    "invoice_number" "text",
    "supplier" "text",
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "motorcycle_id" "uuid",
    "missing_purchase_doc" boolean DEFAULT false,
    CONSTRAINT "acc_long_term_assets_category_check" CHECK (("category" = ANY (ARRAY['vehicles'::"text", 'machinery'::"text", 'buildings'::"text", 'land'::"text", 'equipment'::"text", 'intangible'::"text"]))),
    CONSTRAINT "acc_long_term_assets_depreciation_group_check" CHECK ((("depreciation_group" >= 1) AND ("depreciation_group" <= 6))),
    CONSTRAINT "acc_long_term_assets_depreciation_method_check" CHECK (("depreciation_method" = ANY (ARRAY['linear'::"text", 'accelerated'::"text"]))),
    CONSTRAINT "acc_long_term_assets_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'fully_depreciated'::"text", 'disposed'::"text"])))
);


ALTER TABLE "public"."acc_long_term_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_payrolls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "year" integer NOT NULL,
    "month" integer NOT NULL,
    "contract_type" "text",
    "gross_salary" numeric DEFAULT 0,
    "social_employee" numeric DEFAULT 0,
    "health_employee" numeric DEFAULT 0,
    "tax_advance" numeric DEFAULT 0,
    "net_salary" numeric DEFAULT 0,
    "social_employer" numeric DEFAULT 0,
    "health_employer" numeric DEFAULT 0,
    "total_employer_cost" numeric DEFAULT 0,
    "status" "text" DEFAULT 'prepared'::"text",
    "paid_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "acc_payrolls_month_check" CHECK ((("month" >= 1) AND ("month" <= 12))),
    CONSTRAINT "acc_payrolls_status_check" CHECK (("status" = ANY (ARRAY['prepared'::"text", 'paid'::"text"])))
);


ALTER TABLE "public"."acc_payrolls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_short_term_assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "purchase_price" numeric DEFAULT 0,
    "current_value" numeric DEFAULT 0,
    "acquired_date" "date",
    "disposed_date" "date",
    "description" "text",
    "invoice_number" "text",
    "supplier" "text",
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "acc_short_term_assets_category_check" CHECK (("category" = ANY (ARRAY['material'::"text", 'inventory'::"text", 'supplies'::"text", 'receivables'::"text", 'cash'::"text", 'bank'::"text", 'prepaid'::"text"]))),
    CONSTRAINT "acc_short_term_assets_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'disposed'::"text"])))
);


ALTER TABLE "public"."acc_short_term_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_tax_returns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "year" integer NOT NULL,
    "total_revenue" numeric DEFAULT 0,
    "total_expenses" numeric DEFAULT 0,
    "payroll_costs" numeric DEFAULT 0,
    "depreciation" numeric DEFAULT 0,
    "gross_income" numeric DEFAULT 0,
    "deductible_expenses" numeric DEFAULT 0,
    "tax_base" numeric DEFAULT 0,
    "rounded_tax_base" numeric DEFAULT 0,
    "income_tax_15" numeric DEFAULT 0,
    "income_tax_23" numeric DEFAULT 0,
    "total_income_tax" numeric DEFAULT 0,
    "tax_discount" numeric DEFAULT 30840,
    "tax_after_discount" numeric DEFAULT 0,
    "paid_advances" numeric DEFAULT 0,
    "tax_to_pay" numeric DEFAULT 0,
    "tax_to_refund" numeric DEFAULT 0,
    "status" "text" DEFAULT 'prepared'::"text",
    "submitted_at" timestamp with time zone,
    "details" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "acc_tax_returns_status_check" CHECK (("status" = ANY (ARRAY['prepared'::"text", 'submitted'::"text"])))
);


ALTER TABLE "public"."acc_tax_returns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."acc_vat_returns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "year" integer NOT NULL,
    "quarter" integer NOT NULL,
    "period_from" "date" NOT NULL,
    "period_to" "date" NOT NULL,
    "taxable_outputs" numeric DEFAULT 0,
    "output_vat" numeric DEFAULT 0,
    "taxable_inputs" numeric DEFAULT 0,
    "input_vat" numeric DEFAULT 0,
    "vat_difference" numeric DEFAULT 0,
    "vat_to_pay" numeric DEFAULT 0,
    "vat_to_refund" numeric DEFAULT 0,
    "total_invoices_issued" integer DEFAULT 0,
    "total_invoices_received" integer DEFAULT 0,
    "status" "text" DEFAULT 'prepared'::"text",
    "submitted_at" timestamp with time zone,
    "details" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "acc_vat_returns_quarter_check" CHECK ((("quarter" >= 1) AND ("quarter" <= 4))),
    CONSTRAINT "acc_vat_returns_status_check" CHECK (("status" = ANY (ARRAY['prepared'::"text", 'submitted'::"text"])))
);


ALTER TABLE "public"."acc_vat_returns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."accessory_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sizes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "is_consumable" boolean DEFAULT false,
    "sort_order" integer DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "price_czk" integer DEFAULT 0 NOT NULL,
    "pricing_unit" "text" DEFAULT 'per_booking'::"text" NOT NULL,
    "audience" "text" DEFAULT 'adult'::"text" NOT NULL,
    CONSTRAINT "accessory_types_audience_check" CHECK (("audience" = ANY (ARRAY['adult'::"text", 'child'::"text", 'both'::"text"]))),
    CONSTRAINT "accessory_types_pricing_unit_check" CHECK (("pricing_unit" = ANY (ARRAY['per_booking'::"text", 'per_day'::"text", 'free'::"text"])))
);


ALTER TABLE "public"."accessory_types" OWNER TO "postgres";


COMMENT ON COLUMN "public"."accessory_types"."price_czk" IS 'Cena za zapůjčení v Kč. 0 = zdarma. Frontend i process-payment to čte z DB; faktury/refundy derivují z bookings.extras_price.';



COMMENT ON COLUMN "public"."accessory_types"."pricing_unit" IS 'per_booking = jednorázově za rezervaci, per_day = × počet dní, free = nic neúčtovat (informativní).';



COMMENT ON COLUMN "public"."accessory_types"."audience" IS 'Pro koho jsou velikosti určené: adult / child / both. Web /rezervace filtruje podle motorcycles.license_required (N=dětská) až s flagem inventory_v2.';



CREATE TABLE IF NOT EXISTS "public"."accounting_entries" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "type" "public"."entry_type" NOT NULL,
    "category" "text" NOT NULL,
    "amount" numeric(12,2) NOT NULL,
    "tax_rate" numeric(4,2) DEFAULT 21,
    "tax_amount" numeric(12,2),
    "description" "text",
    "reference_type" "text",
    "reference_id" "uuid",
    "branch_id" "uuid",
    "invoice_id" "uuid",
    "date" "date" DEFAULT CURRENT_DATE,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "booking_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."accounting_entries" OWNER TO "postgres";


COMMENT ON TABLE "public"."accounting_entries" IS 'Účetní záznamy — příjmy a výdaje';



CREATE TABLE IF NOT EXISTS "public"."accounting_exceptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "financial_event_id" "uuid",
    "reason" "text" NOT NULL,
    "suggested_fix" "jsonb",
    "assigned_to" "text" DEFAULT 'admin'::"text",
    "resolved_at" timestamp with time zone,
    "resolution_note" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."accounting_exceptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_audit_log" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "admin_id" "uuid",
    "action" "text" NOT NULL,
    "entity_type" "text",
    "entity_id" "uuid",
    "old_data" "jsonb",
    "new_data" "jsonb",
    "ip_address" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."admin_audit_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."admin_audit_log" IS 'Audit log adminských akcí — kdo, co, kdy, odkud';



CREATE TABLE IF NOT EXISTS "public"."admin_messages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "incident_id" "uuid",
    "booking_id" "uuid",
    "type" "text" DEFAULT 'info'::"text" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "read" boolean DEFAULT false,
    "sent_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."admin_messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."admin_messages" IS 'Zprávy z centrály pro zákazníky – reakce na SOS, informace, oznámení';



CREATE TABLE IF NOT EXISTS "public"."admin_users" (
    "id" "uuid" NOT NULL,
    "role" "public"."admin_role" DEFAULT 'viewer'::"public"."admin_role",
    "branch_access" "uuid"[] DEFAULT '{}'::"uuid"[],
    "permissions" "jsonb" DEFAULT '{}'::"jsonb",
    "last_login_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "name" "text" DEFAULT ''::"text" NOT NULL,
    "email" "text" DEFAULT ''::"text" NOT NULL,
    "phone" "text",
    "active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."admin_users" OWNER TO "postgres";


COMMENT ON TABLE "public"."admin_users" IS 'Admin uživatelé — role, oprávnění, přístup k pobočkám';



CREATE TABLE IF NOT EXISTS "public"."ai_actions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "conversation_id" "uuid",
    "action_type" "text" NOT NULL,
    "action_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "approved_by" "uuid",
    "executed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "admin_id" "uuid",
    "tool" "text",
    "input" "jsonb" DEFAULT '{}'::"jsonb",
    "result" "jsonb" DEFAULT '{}'::"jsonb",
    "success" boolean DEFAULT true,
    CONSTRAINT "ai_actions_action_type_check" CHECK (("action_type" = ANY (ARRAY['create_booking'::"text", 'update_price'::"text", 'schedule_service'::"text", 'send_message'::"text", 'generate_report'::"text", 'block_moto'::"text", 'approve_order'::"text"]))),
    CONSTRAINT "ai_actions_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'executed'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."ai_actions" OWNER TO "postgres";


COMMENT ON TABLE "public"."ai_actions" IS 'Akce navržené AI — booking, cena, servis, zpráva, report';



CREATE TABLE IF NOT EXISTS "public"."ai_citations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "observed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ai_platform" "text" NOT NULL,
    "query" "text" NOT NULL,
    "response_excerpt" "text",
    "cited_url" "text",
    "screenshot_url" "text",
    "rank" integer,
    "notes" "text",
    "recorded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ai_citations_ai_platform_check" CHECK (("ai_platform" = ANY (ARRAY['chatgpt'::"text", 'claude'::"text", 'perplexity'::"text", 'gemini'::"text", 'copilot'::"text", 'grok'::"text", 'duckassist'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."ai_citations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_conversations" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "admin_id" "uuid",
    "messages" "jsonb" DEFAULT '[]'::"jsonb",
    "context_page" "text",
    "model" "text" DEFAULT 'claude-sonnet-4-5-20250929'::"text",
    "total_tokens" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "title" "text" DEFAULT 'Nová konverzace'::"text" NOT NULL
);


ALTER TABLE "public"."ai_conversations" OWNER TO "postgres";


COMMENT ON TABLE "public"."ai_conversations" IS 'Konverzace s AI asistentem v admin panelu';



CREATE TABLE IF NOT EXISTS "public"."ai_customer_conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" DEFAULT 'Nová konverzace'::"text",
    "messages" "jsonb" DEFAULT '[]'::"jsonb",
    "booking_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ai_customer_conversations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "admin_id" "uuid",
    "prompt" "text" NOT NULL,
    "response" "text",
    "tokens_used" integer DEFAULT 0,
    "model" "text",
    "latency_ms" integer,
    "action_taken" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "agent_id" "text",
    "action" "text",
    "details" "jsonb" DEFAULT '{}'::"jsonb"
);


ALTER TABLE "public"."ai_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."ai_logs" IS 'Logy AI volání — prompt, response, tokeny, latence';



CREATE TABLE IF NOT EXISTS "public"."ai_public_conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_id" "text" NOT NULL,
    "lang" "text",
    "page_context" "jsonb",
    "messages" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "message_count" integer DEFAULT 0 NOT NULL,
    "ip_hash" "text",
    "user_agent" "text",
    "outcome" "text",
    "booking_id" "uuid",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_activity_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ai_public_conversations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_traffic_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ts" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" NOT NULL,
    "bot_name" "text",
    "user_agent" "text",
    "path" "text",
    "endpoint" "text",
    "method" "text",
    "lang" "text",
    "ip_hash" "text",
    "country" "text",
    "partner_id" "uuid",
    "status_code" integer,
    "latency_ms" integer,
    "outcome" "text",
    "booking_id" "uuid",
    "details" "jsonb" DEFAULT '{}'::"jsonb",
    CONSTRAINT "ai_traffic_log_outcome_check" CHECK (("outcome" = ANY (ARRAY['view'::"text", 'quote'::"text", 'booking_created'::"text", 'error'::"text", 'rate_limited'::"text"]))),
    CONSTRAINT "ai_traffic_log_source_check" CHECK (("source" = ANY (ARRAY['crawler'::"text", 'mcp'::"text", 'rest_api'::"text", 'widget'::"text", 'unknown'::"text"])))
);


ALTER TABLE "public"."ai_traffic_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."api_keys" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key_hash" "text" NOT NULL,
    "key_prefix" "text" NOT NULL,
    "partner_name" "text" NOT NULL,
    "partner_email" "text" NOT NULL,
    "partner_url" "text",
    "rate_limit_rpm" integer DEFAULT 1000 NOT NULL,
    "scopes" "text"[] DEFAULT ARRAY['read'::"text"] NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "last_used_at" timestamp with time zone,
    "request_count" bigint DEFAULT 0 NOT NULL,
    "revoked_at" timestamp with time zone,
    "revoked_reason" "text"
);


ALTER TABLE "public"."api_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_crash_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "app_version" "text",
    "platform" "text",
    "screen" "text",
    "action" "text",
    "error_type" "text" NOT NULL,
    "error_message" "text" NOT NULL,
    "stack_trace" "text",
    "severity" "text" DEFAULT 'error'::"text",
    "extra_data" "jsonb"
);


ALTER TABLE "public"."app_crash_reports" OWNER TO "postgres";


COMMENT ON TABLE "public"."app_crash_reports" IS 'Flutter app crash reports — automatically pushed from the mobile app. Read by Velín admin dashboard for monitoring and debugging.';



CREATE TABLE IF NOT EXISTS "public"."app_debug_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "app_version" "text",
    "platform" "text",
    "category" "text" NOT NULL,
    "action" "text" NOT NULL,
    "detail" "text",
    "data" "jsonb",
    "duration_ms" integer
);


ALTER TABLE "public"."app_debug_logs" OWNER TO "postgres";


COMMENT ON TABLE "public"."app_debug_logs" IS 'High-volume debug logs from Flutter app. Every screen, API call, button tap, payment step, auth event, etc. Auto-cleanup after 30 days recommended.';



CREATE TABLE IF NOT EXISTS "public"."app_installations" (
    "device_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "platform" "text",
    "app_version" "text",
    "push_enabled" boolean DEFAULT false NOT NULL,
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."app_installations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_settings" (
    "key" "text" NOT NULL,
    "value" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."app_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."approval_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "financial_event_id" "uuid",
    "approval_type" "text" NOT NULL,
    "submitted_by" "text" DEFAULT 'system'::"text",
    "approved_by" "text",
    "approved_at" timestamp with time zone,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "approval_queue_approval_type_check" CHECK (("approval_type" = ANY (ARRAY['invoice_export'::"text", 'expense_export'::"text", 'asset_registration'::"text", 'payroll'::"text", 'bank_reconciliation'::"text"]))),
    CONSTRAINT "approval_queue_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."approval_queue" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."auto_order_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "inventory_item_id" "uuid",
    "trigger_type" "text" NOT NULL,
    "threshold_quantity" integer,
    "interval_days" integer,
    "order_quantity" integer DEFAULT 10 NOT NULL,
    "notes" "text",
    "email_override" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "last_triggered_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "auto_order_rules_trigger_type_check" CHECK (("trigger_type" = ANY (ARRAY['stock_low'::"text", 'interval'::"text", 'manual'::"text"])))
);


ALTER TABLE "public"."auto_order_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."automation_rules" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "event" "text" NOT NULL,
    "conditions" "jsonb" DEFAULT '{}'::"jsonb",
    "actions" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "automation_rules_event_check" CHECK (("event" = ANY (ARRAY['booking_created'::"text", 'booking_paid'::"text", 'booking_cancelled'::"text", 'sos_reported'::"text", 'stock_low'::"text", 'service_due'::"text"])))
);


ALTER TABLE "public"."automation_rules" OWNER TO "postgres";


COMMENT ON TABLE "public"."automation_rules" IS 'Automatizační pravidla — akce na události v systému';



CREATE TABLE IF NOT EXISTS "public"."booking_cancellations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid",
    "cancelled_by" "uuid",
    "reason" "text",
    "refund_amount" numeric(10,2) DEFAULT 0,
    "refund_percent" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."booking_cancellations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_complaints" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid",
    "customer_id" "uuid",
    "subject" "text" NOT NULL,
    "description" "text",
    "status" "text" DEFAULT 'open'::"text",
    "resolution" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "resolved_at" timestamp with time zone,
    "resolved_by" "uuid",
    CONSTRAINT "booking_complaints_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'resolved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."booking_complaints" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_discounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "code" "text" NOT NULL,
    "promo_code_id" "uuid",
    "voucher_id" "uuid",
    "discount_type" "text" NOT NULL,
    "value" numeric DEFAULT 0 NOT NULL,
    "amount" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "booking_discounts_discount_type_check" CHECK (("discount_type" = ANY (ARRAY['percent'::"text", 'fixed'::"text"]))),
    CONSTRAINT "booking_discounts_kind_check" CHECK (("kind" = ANY (ARRAY['promo_code'::"text", 'voucher'::"text"])))
);


ALTER TABLE "public"."booking_discounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_extras" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "booking_id" "uuid",
    "extra_id" "uuid",
    "name" "text" NOT NULL,
    "quantity" integer DEFAULT 1,
    "unit_price" numeric(10,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."booking_extras" OWNER TO "postgres";


COMMENT ON TABLE "public"."booking_extras" IS 'Extras přiřazené ke konkrétní rezervaci';



CREATE SEQUENCE IF NOT EXISTS "public"."booking_vs_seq"
    START WITH 10000001
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."booking_vs_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "moto_id" "uuid",
    "branch_id" "uuid",
    "start_date" timestamp with time zone NOT NULL,
    "end_date" timestamp with time zone NOT NULL,
    "actual_return_date" timestamp with time zone,
    "pickup_time" time without time zone DEFAULT '09:00:00'::time without time zone,
    "pickup_method" "text" DEFAULT 'store'::"text",
    "pickup_address" "text",
    "return_method" "text" DEFAULT 'store'::"text",
    "return_address" "text",
    "total_price" numeric(10,2) DEFAULT 0,
    "extras_price" numeric(10,2) DEFAULT 0,
    "delivery_fee" numeric(10,2) DEFAULT 0,
    "discount_amount" numeric(10,2) DEFAULT 0,
    "discount_code" "text",
    "status" "public"."booking_status" DEFAULT 'pending'::"public"."booking_status",
    "payment_status" "public"."payment_status" DEFAULT 'unpaid'::"public"."payment_status",
    "payment_method" "text",
    "contract_url" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "insurance_type" "text" DEFAULT 'basic'::"text",
    "signed_contract" boolean DEFAULT false,
    "mileage_start" integer,
    "mileage_end" integer,
    "damage_report" "text",
    "promo_code" "text",
    "cancelled_by" "uuid",
    "cancelled_by_source" "text",
    "cancellation_reason" "text",
    "cancelled_at" timestamp with time zone,
    "cancellation_notified" boolean DEFAULT false,
    "confirmed_at" timestamp with time zone,
    "picked_up_at" timestamp with time zone,
    "returned_at" timestamp with time zone,
    "sos_replacement" boolean DEFAULT false,
    "rating" smallint,
    "rated_at" timestamp with time zone,
    "boots_size" "text",
    "helmet_size" "text",
    "jacket_size" "text",
    "replacement_for_booking_id" "uuid",
    "sos_incident_id" "uuid",
    "ended_by_sos" boolean DEFAULT false,
    "original_start_date" "date",
    "original_end_date" "date",
    "complaint_status" "text",
    "modification_history" "jsonb" DEFAULT '[]'::"jsonb",
    "booking_source" "text" DEFAULT 'app'::"text",
    "stripe_payment_intent_id" "text",
    "stripe_session_id" "text",
    "pickup_lat" double precision,
    "pickup_lng" double precision,
    "return_lat" double precision,
    "return_lng" double precision,
    "is_test" boolean DEFAULT false,
    "source" "text" DEFAULT 'app'::"text",
    "promo_code_id" "uuid",
    "voucher_id" "uuid",
    "pants_size" "text",
    "gloves_size" "text",
    "passenger_helmet_size" "text",
    "passenger_jacket_size" "text",
    "passenger_pants_size" "text",
    "passenger_boots_size" "text",
    "passenger_gloves_size" "text",
    "return_time" "text",
    "checkout_started_at" timestamp with time zone,
    "stripe_checkout_url" "text",
    "abandoned_email_sent_at" timestamp with time zone,
    "created_via_ai" boolean DEFAULT false NOT NULL,
    "docs_reminder_sent_at" timestamp with time zone,
    "language" "text" DEFAULT 'cs'::"text" NOT NULL,
    "stripe_refund_id" "text",
    "card_brand" "text",
    "card_last4" "text",
    "form_fill_seconds" integer,
    "form_started_at" timestamp with time zone,
    "payment_fill_seconds" integer,
    "created_device" "text",
    "completed_device" "text",
    "payment_reference" "text",
    "loyalty_level" integer,
    "loyalty_percent" integer,
    "loyalty_discount_amount" numeric DEFAULT 0,
    "trailer_moto_id" "uuid",
    "reserved_email_sent_at" timestamp with time zone,
    "late_pickup_discount_amount" numeric DEFAULT 0 NOT NULL,
    "handover_protocol_started_at" timestamp with time zone,
    "handover_protocol_filled_at" timestamp with time zone,
    "handover_protocol_autofilled" boolean DEFAULT false NOT NULL,
    "handover_protocol_reminder_sent_at" timestamp with time zone,
    "pay_channel" "text",
    "payment_vs" "text",
    "docs_completed_at" timestamp with time zone,
    "docs_fill_seconds" integer,
    "chosen_payment_method" "text",
    "continues_booking_id" "uuid",
    "mod_surcharge_due" numeric,
    "mod_surcharge_vs" "text",
    "mod_surcharge_requested_at" timestamp with time zone,
    "mod_surcharge_paid_at" timestamp with time zone,
    "mod_email_payload" "jsonb",
    "restored_at" timestamp with time zone,
    "extends_booking_id" "uuid",
    CONSTRAINT "bookings_language_check" CHECK (("language" = ANY (ARRAY['cs'::"text", 'en'::"text", 'de'::"text", 'nl'::"text", 'es'::"text", 'fr'::"text", 'pl'::"text"]))),
    CONSTRAINT "bookings_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5))),
    CONSTRAINT "valid_dates" CHECK (("end_date" >= "start_date"))
);


ALTER TABLE "public"."bookings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."bookings"."pickup_address" IS 'Adresa vyzvednutí (doručení zákazníkovi)';



COMMENT ON COLUMN "public"."bookings"."return_address" IS 'Adresa vrácení (svoz od zákazníka)';



COMMENT ON COLUMN "public"."bookings"."sos_replacement" IS 'True pokud byla motorka vyměněna přes SOS flow (náhradní motorka)';



COMMENT ON COLUMN "public"."bookings"."rating" IS 'Hodnocení jízdy 1-5 hvězdiček';



COMMENT ON COLUMN "public"."bookings"."source" IS 'Zdroj rezervace: app | web | admin';



COMMENT ON COLUMN "public"."bookings"."return_time" IS 'Čas vrácení motorky (HH:MM). Default UI 19:00.';



COMMENT ON COLUMN "public"."bookings"."created_via_ai" IS 'TRUE pokud rezervaci vytvořil ai-public-agent edge fn (zákazník přes AI asistenta v widgetu na webu). FALSE = klasický webový formulář / appka / admin / SOS. Velín to zobrazuje jako 🤖 AI badge vedle WEB.';



COMMENT ON COLUMN "public"."bookings"."docs_reminder_sent_at" IS 'Kdy byl odeslán email „nahrajte doklady" (state C: paid+reserved+chybí doklady, 5 min od confirmed_at). NULL = ještě neposlán.';



COMMENT ON COLUMN "public"."bookings"."stripe_refund_id" IS 'Stripe Refund ID (poslední refund k rezervaci). Plní process-refund po úspěšném Stripe refundu.';



COMMENT ON COLUMN "public"."bookings"."card_brand" IS 'Brand platební karty (visa/mastercard/amex/...). Plní webhook-receiver po payment_intent.succeeded.';



COMMENT ON COLUMN "public"."bookings"."card_last4" IS 'Posledních 4 číslic karty (např. ''4242''). Plní webhook-receiver po payment_intent.succeeded.';



COMMENT ON COLUMN "public"."bookings"."late_pickup_discount_amount" IS 'Sleva 50 % na 1. den při pozdním vyzvednutí (>=12:00) a rezervaci >=2 dny. Oddělená od discount_amount a loyalty_discount_amount.';



COMMENT ON COLUMN "public"."bookings"."handover_protocol_started_at" IS 'Start 1h okna pro samovyplnění protokolu (zadání kódu ke dveřím na tabletu v appce).';



COMMENT ON COLUMN "public"."bookings"."handover_protocol_filled_at" IS 'Kdy byl předávací protokol vyplněn (zákazníkem nebo auto-fillem). NULL = ještě nevyplněn.';



COMMENT ON COLUMN "public"."bookings"."handover_protocol_autofilled" IS 'TRUE = protokol vyplnil systém automaticky (zákazník nestihl do 1h).';



COMMENT ON COLUMN "public"."bookings"."continues_booking_id" IS 'Výměna motorky bez přerušení: tato rezervace navazuje na rezervaci continues_booking_id (jiná motorka téhož zákazníka, obslužná pobočka). Plní swap_handoff_bookings při switchi.';



COMMENT ON COLUMN "public"."bookings"."restored_at" IS 'Okamžik posledního obnovení zrušené rezervace ve Velíně (tlačítko Obnovit → pending/unpaid). Non-NULL = auto_cancel_expired_pending() ani abandoned mail (Path AB) na rezervaci nesahají — řeší ji admin ručně.';



CREATE TABLE IF NOT EXISTS "public"."branch_accessories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "size" "text" NOT NULL,
    "quantity" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."branch_accessories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_cameras" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "name" "text",
    "kind" "text" DEFAULT 'snapshot'::"text" NOT NULL,
    "stream_url" "text",
    "snapshot_url" "text",
    "control_url" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "branch_cameras_kind_check" CHECK (("kind" = ANY (ARRAY['snapshot'::"text", 'mjpeg'::"text", 'hls'::"text", 'iframe'::"text"])))
);


ALTER TABLE "public"."branch_cameras" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_door_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "moto_id" "uuid",
    "code_type" "text" NOT NULL,
    "door_code" "text" NOT NULL,
    "is_active" boolean DEFAULT false,
    "valid_from" timestamp with time zone,
    "valid_until" timestamp with time zone,
    "sent_to_customer" boolean DEFAULT false,
    "sent_at" timestamp with time zone,
    "withheld_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "branch_door_codes_code_type_check" CHECK (("code_type" = ANY (ARRAY['motorcycle'::"text", 'accessories'::"text"])))
);


ALTER TABLE "public"."branch_door_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_door_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid",
    "device_id" "uuid",
    "door_id" "uuid",
    "kind" "text",
    "booking_id" "uuid",
    "code_masked" "text",
    "success" boolean DEFAULT true NOT NULL,
    "detail" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."branch_door_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_doors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "door_kind" "text" NOT NULL,
    "box_number" integer,
    "label" "text",
    "relay_url" "text",
    "light_url" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "branch_doors_door_kind_check" CHECK (("door_kind" = ANY (ARRAY['motorcycle'::"text", 'accessories'::"text"])))
);


ALTER TABLE "public"."branch_doors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_kiosk_config" (
    "branch_id" "uuid" NOT NULL,
    "music_on_url" "text",
    "music_off_url" "text",
    "relay_base_url" "text",
    "door_open_seconds" integer DEFAULT 8 NOT NULL,
    "light_seconds" integer DEFAULT 120 NOT NULL,
    "music_seconds" integer DEFAULT 90 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "power_status_url" "text",
    "power_poll_seconds" integer DEFAULT 60 NOT NULL
);


ALTER TABLE "public"."branch_kiosk_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_performance" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "branch_id" "uuid",
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "revenue" numeric(12,2) DEFAULT 0,
    "costs" numeric(12,2) DEFAULT 0,
    "profit" numeric(12,2) DEFAULT 0,
    "avg_utilization" numeric(5,2) DEFAULT 0,
    "customer_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."branch_performance" OWNER TO "postgres";


COMMENT ON TABLE "public"."branch_performance" IS 'Výkonnostní metriky poboček za období';



CREATE TABLE IF NOT EXISTS "public"."branch_power_status" (
    "branch_id" "uuid" NOT NULL,
    "source" "text",
    "battery_soc" numeric(5,1),
    "battery_voltage" numeric(6,2),
    "battery_power_w" numeric(10,1),
    "pv_power_w" numeric(10,1),
    "load_power_w" numeric(10,1),
    "grid_present" boolean,
    "generator_on" boolean,
    "raw" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."branch_power_status" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branch_service_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "label" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."branch_service_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branches" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "address" "text" NOT NULL,
    "city" "text" NOT NULL,
    "zip" "text",
    "coordinates" "point",
    "phone" "text",
    "email" "text",
    "opening_hours" "jsonb" DEFAULT '{"fr": "08:00-18:00", "mo": "08:00-18:00", "sa": "09:00-14:00", "su": "closed", "th": "08:00-18:00", "tu": "08:00-18:00", "we": "08:00-18:00"}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "gps_lat" numeric(10,7),
    "gps_lng" numeric(10,7),
    "notes" "text",
    "active" boolean DEFAULT true NOT NULL,
    "branch_code" "text",
    "is_open" boolean DEFAULT false,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "location" "text",
    "type" "text" DEFAULT 'samoobslužná'::"text",
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "branches_type_check" CHECK (("type" = ANY (ARRAY['samoobslužná'::"text", 'obslužná'::"text"])))
);


ALTER TABLE "public"."branches" OWNER TO "postgres";


COMMENT ON COLUMN "public"."branches"."location" IS 'Typ pobočky: turistická, městská, horská, rekreační voda, metropolitní centrum, městská tranzitní';



CREATE TABLE IF NOT EXISTS "public"."broadcast_campaigns" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "channel" "text" DEFAULT 'sms'::"text" NOT NULL,
    "template_id" "uuid",
    "segment" "text" DEFAULT 'all'::"text",
    "segment_filter" "jsonb" DEFAULT '{}'::"jsonb",
    "template_vars" "jsonb" DEFAULT '{}'::"jsonb",
    "scheduled_at" timestamp with time zone,
    "status" "text" DEFAULT 'draft'::"text",
    "total_recipients" integer DEFAULT 0,
    "sent_count" integer DEFAULT 0,
    "failed_count" integer DEFAULT 0,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    CONSTRAINT "broadcast_campaigns_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'scheduled'::"text", 'sending'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."broadcast_campaigns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cash_register" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "text" NOT NULL,
    "amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "description" "text",
    "date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "balance" numeric(12,2) DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "cash_register_type_check" CHECK (("type" = ANY (ARRAY['income'::"text", 'expense'::"text"])))
);


ALTER TABLE "public"."cash_register" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cms_pages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "slug" "text" NOT NULL,
    "title" "text" NOT NULL,
    "content" "text",
    "meta_description" "text",
    "og_image" "text",
    "published" boolean DEFAULT false,
    "sort_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "excerpt" "text",
    "description" "text",
    "image_url" "text",
    "images" "text"[] DEFAULT '{}'::"text"[],
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "image_alts" "text"[] DEFAULT '{}'::"text"[]
);


ALTER TABLE "public"."cms_pages" OWNER TO "postgres";


COMMENT ON TABLE "public"."cms_pages" IS 'CMS stránky — statický obsah webu';



COMMENT ON COLUMN "public"."cms_pages"."image_alts" IS 'Per-fotka SEO popisek (paralelní index s images[]). Admin vyplňuje jen krátký popisek, PHP složí finální alt jako "{title} – {popisek}".';



CREATE TABLE IF NOT EXISTS "public"."cms_variables" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "key" "text" NOT NULL,
    "value" "jsonb" NOT NULL,
    "category" "text" NOT NULL,
    "description" "text",
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "cms_variables_category_check" CHECK (("category" = ANY (ARRAY['general'::"text", 'web'::"text", 'pricing'::"text", 'contact'::"text", 'content'::"text", 'legal'::"text"])))
);


ALTER TABLE "public"."cms_variables" OWNER TO "postgres";


COMMENT ON TABLE "public"."cms_variables" IS 'CMS proměnné — ceny, obsah, featury, SEO, promo nastavení';



CREATE TABLE IF NOT EXISTS "public"."contracts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contract_number" "text",
    "contract_type" "text" DEFAULT 'other'::"text" NOT NULL,
    "title" "text",
    "counterparty" "text",
    "counterparty_ico" "text",
    "amount" numeric,
    "payment_frequency" "text",
    "valid_from" "date",
    "valid_until" "date",
    "status" "text" DEFAULT 'pending'::"text",
    "notes" "text",
    "storage_path" "text",
    "photo_url" "text",
    "extracted_data" "jsonb",
    "source" "text" DEFAULT 'manual'::"text",
    "financial_event_id" "uuid",
    "employee_id" "uuid",
    "employee_name" "text",
    "approved_at" timestamp with time zone,
    "terminated_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."contracts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "description" "text",
    "kind" "text" DEFAULT 'html'::"text" NOT NULL,
    "content_html" "text",
    "pdf_path" "text",
    "show_on_web" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 100 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "custom_documents_kind_check" CHECK (("kind" = ANY (ARRAY['html'::"text", 'pdf'::"text"])))
);


ALTER TABLE "public"."custom_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_stats" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "date" "date" NOT NULL,
    "branch_id" "uuid",
    "total_bookings" integer DEFAULT 0,
    "revenue" numeric(12,2) DEFAULT 0,
    "active_motos" integer DEFAULT 0,
    "utilization_pct" numeric(5,2) DEFAULT 0,
    "new_customers" integer DEFAULT 0,
    "sos_incidents" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."daily_stats" OWNER TO "postgres";


COMMENT ON TABLE "public"."daily_stats" IS 'Denní statistiky — bookings, revenue, utilizace per pobočka';



CREATE TABLE IF NOT EXISTS "public"."debug_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "admin_id" "uuid",
    "source" "text" NOT NULL,
    "action" "text" NOT NULL,
    "component" "text",
    "status" "text" DEFAULT 'info'::"text" NOT NULL,
    "request_data" "jsonb",
    "response_data" "jsonb",
    "error_message" "text",
    "error_stack" "text",
    "duration_ms" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."debug_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."delivery_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "dl_number" "text",
    "supplier_name" "text",
    "supplier_ico" "text",
    "total_amount" numeric DEFAULT 0,
    "delivery_date" "date",
    "variable_symbol" "text",
    "items" "jsonb",
    "notes" "text",
    "photo_url" "text",
    "storage_path" "text",
    "extracted_data" "jsonb",
    "source" "text" DEFAULT 'manual'::"text",
    "financial_event_id" "uuid",
    "matched_invoice_id" "uuid",
    "match_method" "text",
    "match_confidence" numeric,
    "matched_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."delivery_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."document_number_counters" (
    "prefix" "text" NOT NULL,
    "year" integer NOT NULL,
    "last_seq" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."document_number_counters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."document_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "text" NOT NULL,
    "name" "text" NOT NULL,
    "content_html" "text" NOT NULL,
    "active" boolean DEFAULT true,
    "version" integer DEFAULT 1,
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "content_translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "name_translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."document_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."documents" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "booking_id" "uuid",
    "user_id" "uuid",
    "type" "text" NOT NULL,
    "file_path" "text" NOT NULL,
    "file_name" "text",
    "file_size" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "name" "text"
);


ALTER TABLE "public"."documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."email_send_locks" (
    "booking_id" "uuid" NOT NULL,
    "template_slug" "text" NOT NULL,
    "locked_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."email_send_locks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."email_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "subject" "text" DEFAULT ''::"text" NOT NULL,
    "body_html" "text" DEFAULT ''::"text" NOT NULL,
    "body_text" "text",
    "variables" "text"[] DEFAULT '{}'::"text"[],
    "description" "text",
    "active" boolean DEFAULT true NOT NULL,
    "updated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "subject_translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "body_translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "triggers" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL
);


ALTER TABLE "public"."email_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emp_attendance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "check_in" timestamp with time zone,
    "check_out" timestamp with time zone,
    "break_minutes" integer DEFAULT 0,
    "hours_worked" numeric(5,2) DEFAULT 0,
    "status" "text" DEFAULT 'present'::"text" NOT NULL,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "emp_attendance_status_check" CHECK (("status" = ANY (ARRAY['present'::"text", 'absent'::"text", 'sick'::"text", 'vacation'::"text", 'home_office'::"text", 'half_day'::"text"])))
);


ALTER TABLE "public"."emp_attendance" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emp_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "file_url" "text",
    "valid_from" "date",
    "valid_until" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "emp_documents_type_check" CHECK (("type" = ANY (ARRAY['contract'::"text", 'amendment'::"text", 'termination'::"text", 'agreement'::"text", 'certificate'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."emp_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emp_shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "shift_type" "text" DEFAULT 'morning'::"text" NOT NULL,
    "start_time" time without time zone,
    "end_time" time without time zone,
    "branch_id" "uuid",
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "emp_shifts_shift_type_check" CHECK (("shift_type" = ANY (ARRAY['morning'::"text", 'afternoon'::"text", 'night'::"text", 'full_day'::"text", 'free'::"text"])))
);


ALTER TABLE "public"."emp_shifts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emp_vacations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "days" integer NOT NULL,
    "type" "text" DEFAULT 'vacation'::"text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "note" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "emp_vacations_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "emp_vacations_type_check" CHECK (("type" = ANY (ARRAY['vacation'::"text", 'sick'::"text", 'personal'::"text", 'unpaid'::"text", 'maternity'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."emp_vacations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."extras_catalog" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "price_per_day" numeric(10,2) NOT NULL,
    "branch_id" "uuid",
    "available" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "extras_catalog_category_check" CHECK (("category" = ANY (ARRAY['ochranné'::"text", 'zavazadla'::"text", 'navigace'::"text"])))
);


ALTER TABLE "public"."extras_catalog" OWNER TO "postgres";


COMMENT ON TABLE "public"."extras_catalog" IS 'Katalog příslušenství k pronájmu (helmy, kufry, navigace)';



CREATE TABLE IF NOT EXISTS "public"."faq_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category_key" "text" NOT NULL,
    "category_label" "text" NOT NULL,
    "question" "text" NOT NULL,
    "answer" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "featured_home" boolean DEFAULT false NOT NULL,
    "published" boolean DEFAULT true NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."faq_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feature_flags" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "key" "text" NOT NULL,
    "enabled" boolean DEFAULT false,
    "description" "text",
    "conditions" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."feature_flags" OWNER TO "postgres";


COMMENT ON TABLE "public"."feature_flags" IS 'Feature flags — zapínání/vypínání funkcí v aplikaci';



CREATE TABLE IF NOT EXISTS "public"."financial_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_type" "text" NOT NULL,
    "source" "text" NOT NULL,
    "amount_czk" numeric(12,2) NOT NULL,
    "vat_rate" numeric(5,2) DEFAULT 0 NOT NULL,
    "duzp" "date" NOT NULL,
    "linked_entity_type" "text",
    "linked_entity_id" "uuid",
    "confidence_score" numeric(3,2) DEFAULT 1.0,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "flexi_id" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "document_type" "text",
    CONSTRAINT "financial_events_confidence_score_check" CHECK ((("confidence_score" >= (0)::numeric) AND ("confidence_score" <= (1)::numeric))),
    CONSTRAINT "financial_events_event_type_check" CHECK (("event_type" = ANY (ARRAY['revenue'::"text", 'expense'::"text", 'asset'::"text", 'payroll'::"text"]))),
    CONSTRAINT "financial_events_source_check" CHECK (("source" = ANY (ARRAY['stripe'::"text", 'ocr'::"text", 'system'::"text", 'manual'::"text"]))),
    CONSTRAINT "financial_events_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'enriched'::"text", 'validated'::"text", 'exported'::"text", 'approved'::"text", 'submitted'::"text", 'error'::"text"])))
);


ALTER TABLE "public"."financial_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."flexi_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_type" "text" NOT NULL,
    "period_from" "date",
    "period_to" "date",
    "year" integer,
    "quarter" integer,
    "raw_data" "jsonb" NOT NULL,
    "rendered_html" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "approved_by" "text",
    "approved_at" timestamp with time zone,
    "submitted_at" timestamp with time zone,
    "datova_schranka_message_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "flexi_reports_report_type_check" CHECK (("report_type" = ANY (ARRAY['vat_return'::"text", 'income_tax'::"text", 'balance_sheet'::"text", 'profit_loss'::"text", 'ossz'::"text", 'vzp'::"text", 'cash_flow'::"text", 'accounting_closing'::"text"]))),
    CONSTRAINT "flexi_reports_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'approved'::"text", 'submitted'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."flexi_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."flexi_sync_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "financial_event_id" "uuid",
    "direction" "text" NOT NULL,
    "flexi_entity_type" "text",
    "payload" "jsonb",
    "response_code" integer,
    "response_body" "jsonb",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "flexi_sync_log_direction_check" CHECK (("direction" = ANY (ARRAY['push'::"text", 'pull'::"text"]))),
    CONSTRAINT "flexi_sync_log_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'success'::"text", 'error'::"text", 'retry'::"text"])))
);


ALTER TABLE "public"."flexi_sync_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gear_shortages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "accessory_type" "text" NOT NULL,
    "size" "text" NOT NULL,
    "audience" "text" DEFAULT 'adult'::"text" NOT NULL,
    "shortage_date" "date" NOT NULL,
    "needed_qty" integer DEFAULT 0 NOT NULL,
    "stock_qty" integer DEFAULT 0 NOT NULL,
    "deficit_qty" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "resolution" "text",
    "purchase_order_id" "uuid",
    "transfer_from_branch_id" "uuid",
    "booking_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "assigned_to" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone
);


ALTER TABLE "public"."gear_shortages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."generated_documents" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "template_id" "uuid",
    "booking_id" "uuid",
    "customer_id" "uuid",
    "filled_data" "jsonb",
    "pdf_path" "text",
    "generated_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."generated_documents" OWNER TO "postgres";


COMMENT ON TABLE "public"."generated_documents" IS 'Vygenerované dokumenty z šablon pro konkrétní rezervace';



CREATE TABLE IF NOT EXISTS "public"."inventory" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "branch_id" "uuid",
    "sku" "text" NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "unit" "text" DEFAULT 'ks'::"text",
    "stock" integer DEFAULT 0,
    "min_stock" integer,
    "max_stock" integer,
    "unit_price" numeric(10,2),
    "supplier_id" "uuid",
    "location" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "inventory_category_check" CHECK (("category" = ANY (ARRAY['material'::"text", 'inventory'::"text", 'supplies'::"text", 'prislusenstvi'::"text"])))
);


ALTER TABLE "public"."inventory" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory" IS 'Skladové zásoby — ochranné pomůcky, spotřební, náhradní díly';



CREATE TABLE IF NOT EXISTS "public"."inventory_movements" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "inventory_id" "uuid",
    "type" "text" NOT NULL,
    "quantity" integer NOT NULL,
    "reason" "text",
    "reference_type" "text",
    "reference_id" "uuid",
    "from_branch" "uuid",
    "to_branch" "uuid",
    "performed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "inventory_movements_type_check" CHECK (("type" = ANY (ARRAY['in'::"text", 'out'::"text", 'adjustment'::"text", 'transfer'::"text"])))
);


ALTER TABLE "public"."inventory_movements" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_movements" IS 'Pohyby na skladě — příjem, výdej, přesun, korekce';



CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "number" "text" NOT NULL,
    "type" "text" NOT NULL,
    "customer_id" "uuid",
    "supplier_id" "uuid",
    "booking_id" "uuid",
    "issue_date" "date" NOT NULL,
    "due_date" "date" NOT NULL,
    "paid_date" "date",
    "subtotal" numeric(12,2) NOT NULL,
    "tax_amount" numeric(12,2) NOT NULL,
    "total" numeric(12,2) NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "pdf_path" "text",
    "items" "jsonb" DEFAULT '[]'::"jsonb",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "variable_symbol" "text",
    "source" "text",
    "order_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "matched_delivery_note_id" "uuid",
    "original_invoice_id" "uuid",
    "stripe_refund_id" "text",
    "customer_snapshot" "jsonb",
    "payment_method" "text",
    "transaction_ref" "text",
    CONSTRAINT "invoices_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'issued'::"text", 'paid'::"text", 'overdue'::"text", 'cancelled'::"text", 'sent'::"text", 'refunded'::"text"]))),
    CONSTRAINT "invoices_type_check" CHECK (("type" = ANY (ARRAY['issued'::"text", 'received'::"text", 'final'::"text", 'proforma'::"text", 'shop_proforma'::"text", 'shop_final'::"text", 'advance'::"text", 'payment_receipt'::"text", 'credit_note'::"text"])))
);


ALTER TABLE "public"."invoices" OWNER TO "postgres";


COMMENT ON TABLE "public"."invoices" IS 'Faktury vydané a přijaté';



COMMENT ON COLUMN "public"."invoices"."source" IS 'Zdroj faktury: booking, edit, sos, shop, restore, final_summary';



CREATE TABLE IF NOT EXISTS "public"."kiosk_commands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_id" "uuid" NOT NULL,
    "branch_id" "uuid",
    "command" "text" NOT NULL,
    "params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "result" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "executed_at" timestamp with time zone,
    CONSTRAINT "kiosk_commands_command_check" CHECK (("command" = ANY (ARRAY['open_door'::"text", 'music_on'::"text", 'music_off'::"text", 'identify'::"text", 'reload'::"text", 'camera_control'::"text", 'http_get'::"text", 'restart'::"text"]))),
    CONSTRAINT "kiosk_commands_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'done'::"text", 'failed'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."kiosk_commands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kiosk_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid" NOT NULL,
    "name" "text",
    "device_token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "platform" "text",
    "app_version" "text",
    "last_seen_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."kiosk_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kiosk_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_id" "uuid",
    "branch_id" "uuid",
    "level" "text" DEFAULT 'info'::"text" NOT NULL,
    "source" "text",
    "message" "text",
    "detail" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "app_version" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "kiosk_logs_level_check" CHECK (("level" = ANY (ARRAY['info'::"text", 'warn'::"text", 'error'::"text", 'crash'::"text"])))
);


ALTER TABLE "public"."kiosk_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."loyalty_levels" (
    "level" integer NOT NULL,
    "discount_percent" integer NOT NULL,
    "min_booking_order" integer NOT NULL,
    "name" "text" NOT NULL,
    "color_hex" "text" NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "loyalty_levels_level_check" CHECK ((("level" >= 1) AND ("level" <= 20)))
);


ALTER TABLE "public"."loyalty_levels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."loyalty_monthly_winners" (
    "month" "date" NOT NULL,
    "user_id" "uuid",
    "nickname" "text",
    "days" integer,
    "awarded_level_before" integer,
    "awarded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."loyalty_monthly_winners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."maintenance_log" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "moto_id" "uuid",
    "service_date" "date" NOT NULL,
    "mileage_at_service" integer,
    "service_type" "text" NOT NULL,
    "description" "text",
    "parts_used" "jsonb" DEFAULT '[]'::"jsonb",
    "labor_cost" numeric(10,2),
    "parts_cost" numeric(10,2),
    "total_cost" numeric(10,2) GENERATED ALWAYS AS ((COALESCE("labor_cost", (0)::numeric) + COALESCE("parts_cost", (0)::numeric))) STORED,
    "mechanic" "text",
    "photos" "text"[] DEFAULT '{}'::"text"[],
    "next_service_date" "date",
    "next_service_mileage" integer,
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "km_at_service" integer,
    "completed_date" "date",
    "scheduled_date" "date",
    "sos_incident_id" "uuid",
    "status" "text" DEFAULT 'pending'::"text",
    "performed_by" "text",
    "cost" numeric,
    "type" "text",
    "items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "is_urgent" boolean DEFAULT false,
    "expected_return_date" "date",
    "defects" "text",
    "replacement_moto_id" "uuid",
    "retirement_type" "text",
    "technician_id" "uuid",
    "labor_hours" numeric DEFAULT 0,
    "extra_cost" numeric DEFAULT 0,
    "is_test" boolean DEFAULT false,
    CONSTRAINT "maintenance_log_retirement_type_check" CHECK (("retirement_type" = ANY (ARRAY['disassembly'::"text", 'scrap'::"text", NULL::"text"]))),
    CONSTRAINT "maintenance_log_service_type_check" CHECK (("service_type" = ANY (ARRAY['regular'::"text", 'extraordinary'::"text", 'repair'::"text"]))),
    CONSTRAINT "maintenance_log_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_service'::"text", 'completed'::"text"])))
);


ALTER TABLE "public"."maintenance_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."maintenance_log" IS 'Evidence servisních zásahů na motorkách';



CREATE TABLE IF NOT EXISTS "public"."maintenance_schedules" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "moto_id" "uuid",
    "schedule_type" "text" NOT NULL,
    "interval_km" integer,
    "interval_days" integer,
    "last_performed" "date",
    "next_due" "date",
    "description" "text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_service_km" integer DEFAULT 0,
    "last_service_date" "date",
    "first_service_km" integer,
    "first_service_desc" "text",
    CONSTRAINT "maintenance_schedules_schedule_type_check" CHECK (("schedule_type" = ANY (ARRAY['mileage'::"text", 'time'::"text", 'both'::"text"])))
);


ALTER TABLE "public"."maintenance_schedules" OWNER TO "postgres";


COMMENT ON TABLE "public"."maintenance_schedules" IS 'Plány pravidelné údržby — dle km nebo času';



CREATE TABLE IF NOT EXISTS "public"."message_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "channel" "text" DEFAULT 'sms'::"text" NOT NULL,
    "direction" "text" DEFAULT 'outbound'::"text" NOT NULL,
    "recipient_phone" "text",
    "recipient_email" "text",
    "customer_id" "uuid",
    "booking_id" "uuid",
    "template_slug" "text",
    "content_preview" "text",
    "body" "text",
    "external_id" "text",
    "status" "text" DEFAULT 'queued'::"text" NOT NULL,
    "error_message" "text",
    "cost_amount" numeric(8,4),
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "is_marketing" boolean DEFAULT false,
    "template_vars" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "message_log_direction_check" CHECK (("direction" = ANY (ARRAY['outbound'::"text", 'inbound'::"text"]))),
    CONSTRAINT "message_log_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'sent'::"text", 'delivered'::"text", 'failed'::"text", 'bounced'::"text"])))
);


ALTER TABLE "public"."message_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."message_templates" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "content" "text" NOT NULL,
    "category" "text",
    "variables" "text"[] DEFAULT '{}'::"text"[],
    "language" "text" DEFAULT 'cs'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "slug" "text",
    "channel" "text" DEFAULT 'sms'::"text",
    "subject" "text",
    "subject_template" "text",
    "body_template" "text",
    "wa_template_id" "text",
    "is_marketing" boolean DEFAULT false,
    "is_active" boolean DEFAULT true,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."message_templates" OWNER TO "postgres";


COMMENT ON TABLE "public"."message_templates" IS 'Šablony odpovědí pro rychlou komunikaci';



CREATE TABLE IF NOT EXISTS "public"."message_threads" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "customer_id" "uuid",
    "channel" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "assigned_admin" "uuid",
    "subject" "text",
    "last_message_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "message_threads_channel_check" CHECK (("channel" = ANY (ARRAY['app'::"text", 'web'::"text", 'email'::"text", 'sms'::"text"]))),
    CONSTRAINT "message_threads_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'waiting'::"text", 'resolved'::"text", 'closed'::"text"])))
);


ALTER TABLE "public"."message_threads" OWNER TO "postgres";


COMMENT ON TABLE "public"."message_threads" IS 'Vlákna konverzací se zákazníky — omnichannel (web, email, WhatsApp, IG, FB, SMS)';



CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "thread_id" "uuid",
    "direction" "text" NOT NULL,
    "sender_name" "text",
    "content" "text" NOT NULL,
    "attachments" "text"[] DEFAULT '{}'::"text"[],
    "read_at" timestamp with time zone,
    "ai_suggested_reply" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "ai_suggested_at" timestamp with time zone,
    "ai_suggestion_status" "public"."ai_suggestion_status",
    "ai_suggested_by_model" "text",
    "ai_confidence" "text",
    "ai_admin_note" "text",
    "ai_final_reply" "text",
    "ai_approved_by" "uuid",
    "ai_approved_at" timestamp with time zone,
    "ai_sent_message_id" "uuid",
    "ai_error" "text",
    CONSTRAINT "messages_ai_confidence_check" CHECK (("ai_confidence" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text"]))),
    CONSTRAINT "messages_direction_check" CHECK (("direction" = ANY (ARRAY['inbound'::"text", 'outbound'::"text", 'admin'::"text", 'customer'::"text", 'system'::"text"])))
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."messages" IS 'Jednotlivé zprávy v konverzačním vláknu';



CREATE TABLE IF NOT EXISTS "public"."moto_day_prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "moto_id" "uuid" NOT NULL,
    "price_monday" numeric(10,2) DEFAULT 0 NOT NULL,
    "price_tuesday" numeric(10,2) DEFAULT 0 NOT NULL,
    "price_wednesday" numeric(10,2) DEFAULT 0 NOT NULL,
    "price_thursday" numeric(10,2) DEFAULT 0 NOT NULL,
    "price_friday" numeric(10,2) DEFAULT 0 NOT NULL,
    "price_saturday" numeric(10,2) DEFAULT 0 NOT NULL,
    "price_sunday" numeric(10,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."moto_day_prices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."moto_locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "moto_id" "uuid" NOT NULL,
    "lat" double precision,
    "lng" double precision,
    "address" "text",
    "speed" numeric(5,1),
    "heading" numeric(5,1),
    "accuracy" numeric(6,1),
    "source" "text" DEFAULT 'gps'::"text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."moto_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."moto_performance" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "moto_id" "uuid",
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "revenue" numeric(12,2) DEFAULT 0,
    "bookings_count" integer DEFAULT 0,
    "utilization_pct" numeric(5,2) DEFAULT 0,
    "avg_daily_price" numeric(10,2) DEFAULT 0,
    "maintenance_cost" numeric(10,2) DEFAULT 0,
    "profit" numeric(12,2) DEFAULT 0,
    "roi" numeric(5,2) DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."moto_performance" OWNER TO "postgres";


COMMENT ON TABLE "public"."moto_performance" IS 'Výkonnostní metriky motorek za období';



CREATE TABLE IF NOT EXISTS "public"."notification_log" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "rule_id" "uuid",
    "recipient_type" "text" NOT NULL,
    "recipient_id" "uuid",
    "channel" "text" NOT NULL,
    "content" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "notification_log_channel_check" CHECK (("channel" = ANY (ARRAY['email'::"text", 'sms'::"text", 'push'::"text", 'webhook'::"text"]))),
    CONSTRAINT "notification_log_recipient_type_check" CHECK (("recipient_type" = ANY (ARRAY['admin'::"text", 'customer'::"text"]))),
    CONSTRAINT "notification_log_status_check" CHECK (("status" = ANY (ARRAY['sent'::"text", 'failed'::"text", 'pending'::"text"])))
);


ALTER TABLE "public"."notification_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_log" IS 'Log odeslaných notifikací — email, SMS, push, webhook';



CREATE TABLE IF NOT EXISTS "public"."notification_rules" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "trigger_type" "text" NOT NULL,
    "conditions" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "actions" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "notification_rules_trigger_type_check" CHECK (("trigger_type" = ANY (ARRAY['mileage'::"text", 'date'::"text", 'booking_status'::"text", 'stock_level'::"text", 'sos'::"text"])))
);


ALTER TABLE "public"."notification_rules" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_rules" IS 'Pravidla pro automatické notifikace — servis, stock, SOS';



CREATE TABLE IF NOT EXISTS "public"."payment_methods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "type" "text" NOT NULL,
    "stripe_payment_method_id" "text",
    "brand" "text",
    "last4" "text",
    "exp_month" integer,
    "exp_year" integer,
    "holder_name" "text",
    "is_default" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."payment_methods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."poi_ratings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "route_poi_id" "uuid",
    "user_poi_id" "uuid",
    "rating" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "poi_id" "uuid",
    "review_text" "text",
    "photos" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "status" "text" DEFAULT 'approved'::"text" NOT NULL,
    CONSTRAINT "poi_ratings_one_target" CHECK (("num_nonnulls"("route_poi_id", "user_poi_id", "poi_id") = 1)),
    CONSTRAINT "poi_ratings_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5))),
    CONSTRAINT "poi_ratings_status_check" CHECK (("status" = ANY (ARRAY['approved'::"text", 'hidden'::"text"])))
);


ALTER TABLE "public"."poi_ratings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."points_of_interest" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "lat" double precision NOT NULL,
    "lng" double precision NOT NULL,
    "country" "text",
    "region" "text",
    "image_url" "text",
    "images" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "image_alts" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "translations" "jsonb",
    "source" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "surroundings" "text",
    "photo_checked_at" timestamp with time zone,
    "translations_names" "jsonb" GENERATED ALWAYS AS ("public"."jsonb_name_translations"("translations")) STORED,
    CONSTRAINT "points_of_interest_category_check" CHECK (("category" = ANY (ARRAY['food'::"text", 'castle'::"text", 'lookout'::"text", 'water'::"text", 'sights'::"text", 'nature'::"text", 'other'::"text", 'military'::"text", 'aviation'::"text", 'tech'::"text", 'moto'::"text"])))
);


ALTER TABLE "public"."points_of_interest" OWNER TO "postgres";


COMMENT ON COLUMN "public"."points_of_interest"."category" IS 'food/castle/lookout/water/sights/nature/other + cílovka: military/aviation/tech/moto';



CREATE TABLE IF NOT EXISTS "public"."predictions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "type" "text" NOT NULL,
    "target_period_start" "date" NOT NULL,
    "target_period_end" "date" NOT NULL,
    "data" "jsonb" NOT NULL,
    "confidence_pct" numeric(5,2),
    "model_version" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "predictions_type_check" CHECK (("type" = ANY (ARRAY['demand'::"text", 'revenue'::"text", 'maintenance'::"text", 'stock'::"text"])))
);


ALTER TABLE "public"."predictions" OWNER TO "postgres";


COMMENT ON TABLE "public"."predictions" IS 'AI predikce — poptávka, revenue, údržba, stock';



CREATE TABLE IF NOT EXISTS "public"."pricing_rules" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "moto_id" "uuid",
    "type" "text" NOT NULL,
    "name" "text" NOT NULL,
    "modifier" numeric(5,2) NOT NULL,
    "valid_from" "date",
    "valid_to" "date",
    "min_days" integer,
    "promo_code" "text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "pricing_rules_type_check" CHECK (("type" = ANY (ARRAY['seasonal'::"text", 'promo'::"text", 'long_term'::"text", 'early_bird'::"text"])))
);


ALTER TABLE "public"."pricing_rules" OWNER TO "postgres";


COMMENT ON TABLE "public"."pricing_rules" IS 'Cenová pravidla — sezónní, promo, long-term, early-bird modifikátory';



CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric DEFAULT 0 NOT NULL,
    "images" "text"[] DEFAULT '{}'::"text"[],
    "sizes" "text"[] DEFAULT '{}'::"text"[],
    "sku" "text",
    "stock_quantity" integer DEFAULT 0 NOT NULL,
    "category" "text" DEFAULT 'merch'::"text",
    "color" "text",
    "material" "text",
    "is_active" boolean DEFAULT true,
    "sort_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "size_stock" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "image_alts" "text"[] DEFAULT '{}'::"text"[]
);


ALTER TABLE "public"."products" OWNER TO "postgres";


COMMENT ON COLUMN "public"."products"."size_stock" IS 'Počet kusů na skladě per velikost: {"M":5,"L":10,"XL":3}. Plní Velín ProductsTab modal pro produkty se sizes[]. stock_quantity = SUM hodnot, drženo v sync při ukládání. Produkty bez sizes[] mají {} a používají stock_quantity přímo.';



COMMENT ON COLUMN "public"."products"."image_alts" IS 'Per-fotka SEO popisek (paralelní index s images[]). Admin vyplňuje jen krátký popisek, PHP složí finální alt jako "{name} – {popisek}".';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "full_name" "text",
    "phone" "text",
    "license_group" "public"."license_group"[],
    "date_of_birth" "date",
    "street" "text",
    "city" "text",
    "zip" "text",
    "country" "text" DEFAULT 'CZ'::"text",
    "gear_sizes" "jsonb" DEFAULT '{}'::"jsonb",
    "reliability_score" "jsonb" DEFAULT '{"notes": "", "accidents": 0, "late_returns": 0}'::"jsonb",
    "avatar_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "emergency_contact" "text",
    "emergency_phone" "text",
    "riding_experience" "text",
    "preferred_branch" "uuid",
    "marketing_consent" boolean DEFAULT false,
    "language" "text" DEFAULT 'cs'::"text",
    "ico" "text",
    "dic" "text",
    "license_number" "text",
    "license_expiry" "text",
    "id_number" "text",
    "docs_verified_at" timestamp with time zone,
    "docs_verification_status" "text",
    "marketing_consent_at" timestamp with time zone,
    "preferred_channel" "text" DEFAULT 'sms'::"text",
    "phone_e164" "text",
    "is_blocked" boolean DEFAULT false,
    "blocked_at" timestamp with time zone,
    "blocked_reason" "text",
    "consent_gdpr" boolean DEFAULT true,
    "consent_vop" boolean DEFAULT true,
    "consent_email" boolean DEFAULT true,
    "consent_sms" boolean DEFAULT true,
    "consent_push" boolean DEFAULT true,
    "consent_data_processing" boolean DEFAULT true,
    "consent_photo" boolean DEFAULT true,
    "stripe_customer_id" "text",
    "is_test_account" boolean DEFAULT false,
    "id_verified_at" timestamp with time zone,
    "id_verified_until" "date",
    "license_verified_at" timestamp with time zone,
    "license_verified_until" "date",
    "passport_verified_at" timestamp with time zone,
    "passport_verified_until" "date",
    "consent_whatsapp" boolean DEFAULT true,
    "consent_contract" boolean DEFAULT true,
    "registration_source" "text",
    "password_last4_bcrypt" "text",
    "app_permissions" "jsonb",
    "loyalty_nickname" "text",
    "loyalty_leaderboard_opt_in" boolean DEFAULT true NOT NULL,
    "loyalty_bonus_points" integer DEFAULT 0 NOT NULL,
    "loyalty_celebrated_level" integer DEFAULT 0 NOT NULL,
    "company_name" "text",
    "company_address" "text",
    CONSTRAINT "profiles_language_check" CHECK (("language" = ANY (ARRAY['cs'::"text", 'en'::"text", 'de'::"text", 'nl'::"text", 'es'::"text", 'fr'::"text", 'pl'::"text"]))),
    CONSTRAINT "profiles_riding_experience_check" CHECK (("riding_experience" = ANY (ARRAY['beginner'::"text", 'intermediate'::"text", 'advanced'::"text", 'expert'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."id_number" IS 'Číslo dokladu totožnosti (OP nebo pas) — z Mindee OCR';



COMMENT ON COLUMN "public"."profiles"."registration_source" IS 'Zdroj registrace: app nebo web';



COMMENT ON COLUMN "public"."profiles"."password_last4_bcrypt" IS 'bcrypt hash posledních 4 znaků hesla — používá AI agent pro ověření identity při úpravě rezervace.';



COMMENT ON COLUMN "public"."profiles"."app_permissions" IS 'Poslední snapshot OS oprávnění z appky (location/camera/notification/photos bool + platform + reported_at). Plní appka PermissionService.reportToProfile, čte Velín detail zákazníka. Informativní, device-level.';



CREATE TABLE IF NOT EXISTS "public"."promo_code_usage" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "promo_code_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "customer_id" "uuid",
    "discount_applied" numeric(10,2) DEFAULT 0 NOT NULL,
    "used_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."promo_code_usage" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promo_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "type" "text" DEFAULT 'percent'::"text" NOT NULL,
    "value" numeric(10,2) DEFAULT 0 NOT NULL,
    "valid_from" "date",
    "valid_to" "date",
    "max_uses" integer,
    "used_count" integer DEFAULT 0 NOT NULL,
    "min_order_amount" numeric(10,2),
    "applicable_motos" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_test" boolean DEFAULT false,
    "source" "text",
    CONSTRAINT "promo_codes_type_check" CHECK (("type" = ANY (ARRAY['percent'::"text", 'fixed'::"text"])))
);


ALTER TABLE "public"."promo_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_order_items" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "order_id" "uuid",
    "inventory_id" "uuid",
    "quantity" integer NOT NULL,
    "unit_price" numeric(10,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."purchase_order_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."purchase_order_items" IS 'Položky nákupní objednávky';



CREATE TABLE IF NOT EXISTS "public"."purchase_orders" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "supplier_id" "uuid",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "total_amount" numeric(12,2),
    "approved_by" "uuid",
    "notes" "text",
    "ordered_at" timestamp with time zone,
    "received_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "sent_at" timestamp with time zone,
    CONSTRAINT "purchase_orders_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'pending_approval'::"text", 'approved'::"text", 'ordered'::"text", 'received'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."purchase_orders" OWNER TO "postgres";


COMMENT ON TABLE "public"."purchase_orders" IS 'Nákupní objednávky na dodavatele';



CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "push_tokens_platform_check" CHECK (("platform" = ANY (ARRAY['ios'::"text", 'android'::"text", 'web'::"text"])))
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


COMMENT ON TABLE "public"."push_tokens" IS 'Push notification tokeny pro mobilní a webové klienty';



CREATE TABLE IF NOT EXISTS "public"."reviews" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "booking_id" "uuid",
    "user_id" "uuid",
    "moto_id" "uuid",
    "rating" integer,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "admin_reply" "text",
    "visible" boolean DEFAULT true NOT NULL,
    "author_name" "text",
    CONSTRAINT "reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."reviews" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_pois" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "route_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "lat" double precision,
    "lng" double precision,
    "image_url" "text",
    "images" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "surroundings" "text"
);


ALTER TABLE "public"."route_pois" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "route_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "rating" integer NOT NULL,
    "review_text" "text",
    "photos" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "status" "text" DEFAULT 'approved'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "route_reviews_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5))),
    CONSTRAINT "route_reviews_status_check" CHECK (("status" = ANY (ARRAY['approved'::"text", 'hidden'::"text"])))
);


ALTER TABLE "public"."route_reviews" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "route_type" "text" DEFAULT 'loop'::"text" NOT NULL,
    "distance_km" numeric(6,1),
    "duration_min" integer,
    "difficulty" "text",
    "waypoints" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "geometry" "jsonb",
    "mapy_url" "text",
    "cover_image" "text",
    "images" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "image_alts" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "translations" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "status" "text" DEFAULT 'approved'::"text" NOT NULL,
    "submitted_note" "text",
    "countries" "text"[],
    CONSTRAINT "routes_difficulty_check" CHECK (("difficulty" = ANY (ARRAY['easy'::"text", 'medium'::"text", 'hard'::"text"]))),
    CONSTRAINT "routes_route_type_check" CHECK (("route_type" = ANY (ARRAY['loop'::"text", 'poi'::"text"]))),
    CONSTRAINT "routes_status_check" CHECK (("status" = ANY (ARRAY['approved'::"text", 'pending'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."routes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sent_emails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "template_slug" "text",
    "recipient_email" "text" NOT NULL,
    "recipient_id" "uuid",
    "booking_id" "uuid",
    "subject" "text" NOT NULL,
    "body_html" "text",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'sent'::"text" NOT NULL,
    "error_message" "text",
    "provider_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "attachments_meta" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    CONSTRAINT "sent_emails_status_check" CHECK (("status" = ANY (ARRAY['queued'::"text", 'sent'::"text", 'failed'::"text", 'bounced'::"text"])))
);


ALTER TABLE "public"."sent_emails" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "moto_id" "uuid" NOT NULL,
    "maintenance_log_id" "uuid",
    "type" "text" NOT NULL,
    "items" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "km" integer,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "assigned_to" "text",
    "notes" "text",
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_test" boolean DEFAULT false,
    CONSTRAINT "service_orders_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_service'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."service_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "schedule_id" "uuid" NOT NULL,
    "inventory_item_id" "uuid" NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."service_parts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "product_name" "text" NOT NULL,
    "product_sku" "text",
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(10,2) DEFAULT 0 NOT NULL,
    "total_price" numeric(10,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "size" "text",
    "product_id" "uuid"
);


ALTER TABLE "public"."shop_order_items" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."shop_order_seq"
    START WITH 1001
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."shop_order_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shop_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_number" "text" NOT NULL,
    "customer_id" "uuid",
    "customer_name" "text",
    "customer_email" "text",
    "customer_phone" "text",
    "shipping_address" "text",
    "billing_address" "text",
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "payment_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "payment_method" "text",
    "subtotal" numeric(10,2) DEFAULT 0 NOT NULL,
    "shipping_cost" numeric(10,2) DEFAULT 0 NOT NULL,
    "discount" numeric(10,2) DEFAULT 0 NOT NULL,
    "total" numeric(10,2) DEFAULT 0 NOT NULL,
    "promo_code_id" "uuid",
    "notes" "text",
    "tracking_number" "text",
    "shipped_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "confirmed_at" timestamp with time zone,
    "stripe_payment_intent_id" "text",
    "stripe_session_id" "text",
    "language" "text" DEFAULT 'cs'::"text" NOT NULL,
    "shipping_method" "text",
    "customer_company" "text",
    "customer_ico" "text",
    "customer_dic" "text",
    CONSTRAINT "shop_orders_language_check" CHECK (("language" = ANY (ARRAY['cs'::"text", 'en'::"text", 'de'::"text", 'nl'::"text", 'es'::"text", 'fr'::"text", 'pl'::"text"]))),
    CONSTRAINT "shop_orders_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['pending'::"text", 'paid'::"text", 'refunded'::"text", 'failed'::"text"]))),
    CONSTRAINT "shop_orders_shipping_method_check" CHECK ((("shipping_method" IS NULL) OR ("shipping_method" = ANY (ARRAY['pickup'::"text", 'post'::"text", 'zasilkovna'::"text"])))),
    CONSTRAINT "shop_orders_status_check" CHECK (("status" = ANY (ARRAY['new'::"text", 'confirmed'::"text", 'processing'::"text", 'shipped'::"text", 'delivered'::"text", 'cancelled'::"text", 'returned'::"text", 'refunded'::"text"])))
);


ALTER TABLE "public"."shop_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sku_catalog" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sku" "text" NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "type" "text",
    "size" "text",
    "aliases" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "is_consumable" boolean DEFAULT false NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."sku_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sos_incidents" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "booking_id" "uuid",
    "moto_id" "uuid",
    "type" "public"."sos_type" NOT NULL,
    "status" "public"."sos_status" DEFAULT 'reported'::"public"."sos_status",
    "latitude" numeric(10,7),
    "longitude" numeric(10,7),
    "description" "text",
    "is_customer_fault" boolean,
    "photos" "text"[] DEFAULT '{}'::"text"[],
    "police_report_number" "text",
    "admin_notes" "text",
    "replacement_moto_id" "uuid",
    "tow_requested" boolean DEFAULT false,
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "title" "text",
    "severity" "text" DEFAULT 'medium'::"text",
    "moto_rideable" boolean,
    "customer_decision" "text",
    "customer_fault" boolean,
    "damage_description" "text",
    "damage_severity" "text",
    "nearest_service_name" "text",
    "nearest_service_address" "text",
    "nearest_service_phone" "text",
    "address" "text",
    "assigned_to" "uuid",
    "contact_phone" "text",
    "resolution" "text",
    "resolved_by" "uuid",
    "replacement_data" "jsonb",
    "replacement_status" "text",
    "original_booking_id" "uuid",
    "replacement_booking_id" "uuid",
    "original_moto_id" "uuid",
    "is_test" boolean DEFAULT false,
    CONSTRAINT "sos_incidents_customer_decision_check" CHECK ((("customer_decision" IS NULL) OR ("customer_decision" = ANY (ARRAY['replacement_moto'::"text", 'end_ride'::"text", 'continue'::"text", 'waiting'::"text"])))),
    CONSTRAINT "sos_incidents_damage_severity_check" CHECK ((("damage_severity" IS NULL) OR ("damage_severity" = ANY (ARRAY['none'::"text", 'cosmetic'::"text", 'functional'::"text", 'totaled'::"text"])))),
    CONSTRAINT "sos_incidents_replacement_status_check" CHECK ((("replacement_status" IS NULL) OR ("replacement_status" = ANY (ARRAY['selecting'::"text", 'pending_payment'::"text", 'paid'::"text", 'admin_review'::"text", 'approved'::"text", 'dispatched'::"text", 'delivered'::"text", 'rejected'::"text"])))),
    CONSTRAINT "sos_incidents_severity_check" CHECK (("severity" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text", 'critical'::"text"]))),
    CONSTRAINT "sos_incidents_status_check" CHECK ((("status")::"text" = ANY (ARRAY['reported'::"text", 'acknowledged'::"text", 'in_progress'::"text", 'resolved'::"text", 'closed'::"text"]))),
    CONSTRAINT "sos_incidents_type_check" CHECK ((("type")::"text" = ANY (ARRAY['theft'::"text", 'accident_minor'::"text", 'accident_major'::"text", 'breakdown_minor'::"text", 'breakdown_major'::"text", 'defect_question'::"text", 'location_share'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."sos_incidents" OWNER TO "postgres";


COMMENT ON TABLE "public"."sos_incidents" IS 'SOS hlášení z mobilní app — nehody, krádeže, poruchy';



COMMENT ON COLUMN "public"."sos_incidents"."replacement_data" IS 'Structured replacement order: {replacement_moto_id, replacement_model, delivery_address, delivery_city, delivery_note, payment_status (pending/paid/failed), payment_amount, approved_by_admin (bool), approved_at, customer_confirmed_at}';



COMMENT ON COLUMN "public"."sos_incidents"."replacement_status" IS 'Status of replacement motorcycle order flow';



CREATE TABLE IF NOT EXISTS "public"."sos_timeline" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "incident_id" "uuid",
    "action" "text" NOT NULL,
    "performed_by" "uuid",
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "description" "text",
    "admin_id" "uuid"
);


ALTER TABLE "public"."sos_timeline" OWNER TO "postgres";


COMMENT ON TABLE "public"."sos_timeline" IS 'Chronologický log událostí na SOS incidentu';



CREATE TABLE IF NOT EXISTS "public"."stock_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "doc_type" "text" NOT NULL,
    "doc_number" "text",
    "variable_symbol" "text",
    "supplier_ico" "text",
    "supplier_name" "text",
    "amount_czk" numeric DEFAULT 0,
    "financial_event_id" "uuid",
    "stocked" boolean DEFAULT false,
    "matched_receipt_id" "uuid",
    "needs_dl" boolean DEFAULT false,
    "note" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "doc_date" "date",
    CONSTRAINT "stock_receipts_doc_type_check" CHECK (("doc_type" = ANY (ARRAY['invoice'::"text", 'delivery_note'::"text"])))
);


ALTER TABLE "public"."stock_receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "contact_person" "text",
    "email" "text",
    "phone" "text",
    "address" "text",
    "ico" "text",
    "dic" "text",
    "payment_terms" integer DEFAULT 14,
    "bank_account" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "normalized_name" "text",
    "default_category" "text",
    "default_account" "text",
    "contact_email" "text",
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


COMMENT ON TABLE "public"."suppliers" IS 'Dodavatelé náhradních dílů a spotřebního materiálu';



CREATE TABLE IF NOT EXISTS "public"."tax_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "text" DEFAULT 'income_tax'::"text",
    "period_from" "date",
    "period_to" "date",
    "total" numeric(12,2) DEFAULT 0,
    "tax_base" numeric(12,2) DEFAULT 0,
    "tax_amount" numeric(12,2) DEFAULT 0,
    "status" "text" DEFAULT 'prepared'::"text",
    "notes" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "tax_records_status_check" CHECK (("status" = ANY (ARRAY['prepared'::"text", 'submitted'::"text", 'paid'::"text"])))
);


ALTER TABLE "public"."tax_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_pois" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "lat" double precision NOT NULL,
    "lng" double precision NOT NULL,
    "image_url" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_pois_status_check" CHECK (("status" = ANY (ARRAY['approved'::"text", 'pending'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."user_pois" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_saved_routes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "source_route_id" "uuid",
    "waypoints" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "poi_refs" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "profile" "text" DEFAULT 'recommended'::"text" NOT NULL,
    "distance_km" numeric(6,1),
    "duration_min" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_saved_routes_profile_check" CHECK (("profile" = ANY (ARRAY['recommended'::"text", 'fastest'::"text", 'shortest'::"text"])))
);


ALTER TABLE "public"."user_saved_routes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_visited_places" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "route_poi_id" "uuid",
    "user_poi_id" "uuid",
    "poi_id" "uuid",
    "name" "text" NOT NULL,
    "lat" double precision,
    "lng" double precision,
    "route_id" "uuid",
    "first_visited_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_visited_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "visit_count" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "user_visited_one_target" CHECK (("num_nonnulls"("route_poi_id", "user_poi_id", "poi_id") = 1))
);


ALTER TABLE "public"."user_visited_places" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_api_performance" AS
 SELECT "action",
    "count"(*) AS "call_count",
    ("avg"("duration_ms"))::integer AS "avg_ms",
    "max"("duration_ms") AS "max_ms",
    "count"(*) FILTER (WHERE ("detail" ~~ 'error%'::"text")) AS "error_count"
   FROM "public"."app_debug_logs"
  WHERE (("category" = 'api'::"text") AND ("created_at" > ("now"() - '24:00:00'::interval)))
  GROUP BY "action"
  ORDER BY ("count"(*) FILTER (WHERE ("detail" ~~ 'error%'::"text"))) DESC, (("avg"("duration_ms"))::integer) DESC;


ALTER VIEW "public"."v_api_performance" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_recent_crashes" AS
 SELECT "cr"."id",
    "cr"."created_at",
    "cr"."severity",
    "cr"."error_type",
    "cr"."error_message",
    "cr"."screen",
    "cr"."action",
    "cr"."platform",
    "cr"."app_version",
    "p"."full_name" AS "user_name",
    "p"."email" AS "user_email"
   FROM ("public"."app_crash_reports" "cr"
     LEFT JOIN "public"."profiles" "p" ON (("p"."id" = "cr"."user_id")))
  WHERE ("cr"."created_at" > ("now"() - '24:00:00'::interval))
  ORDER BY "cr"."created_at" DESC;


ALTER VIEW "public"."v_recent_crashes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_screen_error_rate" AS
 SELECT "screen",
    "count"(*) AS "total_crashes",
    "count"(DISTINCT "user_id") AS "affected_users",
    "max"("created_at") AS "last_crash"
   FROM "public"."app_crash_reports"
  WHERE ("created_at" > ("now"() - '24:00:00'::interval))
  GROUP BY "screen"
  ORDER BY ("count"(*)) DESC;


ALTER VIEW "public"."v_screen_error_rate" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_debug_timeline" AS
 SELECT "id",
    "created_at",
    "category",
    "action",
    "detail",
    "data",
    "duration_ms",
    "platform",
    "app_version",
    "user_id"
   FROM "public"."app_debug_logs" "dl"
  WHERE ("created_at" > ("now"() - '7 days'::interval))
  ORDER BY "created_at" DESC;


ALTER VIEW "public"."v_user_debug_timeline" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."visitor_log" (
    "id" bigint NOT NULL,
    "ts" timestamp with time zone DEFAULT "now"() NOT NULL,
    "host" "text",
    "path" "text",
    "referrer" "text",
    "referrer_domain" "text",
    "referrer_type" "text",
    "lang" "text",
    "device" "text",
    "country" "text",
    "ip_hash" "text",
    "visitor_hash" "text",
    "user_agent" "text",
    "utm_source" "text",
    "utm_medium" "text",
    "utm_campaign" "text"
);


ALTER TABLE "public"."visitor_log" OWNER TO "postgres";


ALTER TABLE "public"."visitor_log" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."visitor_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."vouchers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "amount" numeric(10,2) DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'CZK'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "buyer_id" "uuid",
    "buyer_name" "text",
    "buyer_email" "text",
    "valid_from" "date" DEFAULT CURRENT_DATE NOT NULL,
    "valid_until" "date" DEFAULT (CURRENT_DATE + '1 year'::interval) NOT NULL,
    "redeemed_at" timestamp with time zone,
    "redeemed_by" "uuid",
    "redeemed_for" "text",
    "booking_id" "uuid",
    "description" "text",
    "category" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "order_id" "uuid",
    "source" "text" DEFAULT 'admin'::"text",
    "slevomat_applied_at" timestamp with time zone,
    "slevomat_apply_status" "text",
    "slevomat_apply_error" "text",
    "slevomat_apply_attempts" integer DEFAULT 0 NOT NULL,
    "slevomat_apply_last_at" timestamp with time zone,
    CONSTRAINT "vouchers_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'redeemed'::"text", 'expired'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."vouchers" OWNER TO "postgres";


ALTER TABLE ONLY "public"."_git_migrations"
    ADD CONSTRAINT "_git_migrations_pkey" PRIMARY KEY ("filename");



ALTER TABLE ONLY "public"."acc_depreciation_entries"
    ADD CONSTRAINT "acc_depreciation_entries_asset_id_year_key" UNIQUE ("asset_id", "year");



ALTER TABLE ONLY "public"."acc_depreciation_entries"
    ADD CONSTRAINT "acc_depreciation_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_employees"
    ADD CONSTRAINT "acc_employees_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_liabilities"
    ADD CONSTRAINT "acc_liabilities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_long_term_assets"
    ADD CONSTRAINT "acc_long_term_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_payrolls"
    ADD CONSTRAINT "acc_payrolls_employee_id_year_month_key" UNIQUE ("employee_id", "year", "month");



ALTER TABLE ONLY "public"."acc_payrolls"
    ADD CONSTRAINT "acc_payrolls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_short_term_assets"
    ADD CONSTRAINT "acc_short_term_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_tax_returns"
    ADD CONSTRAINT "acc_tax_returns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_tax_returns"
    ADD CONSTRAINT "acc_tax_returns_year_key" UNIQUE ("year");



ALTER TABLE ONLY "public"."acc_vat_returns"
    ADD CONSTRAINT "acc_vat_returns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."acc_vat_returns"
    ADD CONSTRAINT "acc_vat_returns_year_quarter_key" UNIQUE ("year", "quarter");



ALTER TABLE ONLY "public"."accessory_types"
    ADD CONSTRAINT "accessory_types_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."accessory_types"
    ADD CONSTRAINT "accessory_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."accounting_entries"
    ADD CONSTRAINT "accounting_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."accounting_exceptions"
    ADD CONSTRAINT "accounting_exceptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_audit_log"
    ADD CONSTRAINT "admin_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_messages"
    ADD CONSTRAINT "admin_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_users"
    ADD CONSTRAINT "admin_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_actions"
    ADD CONSTRAINT "ai_actions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_citations"
    ADD CONSTRAINT "ai_citations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_conversations"
    ADD CONSTRAINT "ai_conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_customer_conversations"
    ADD CONSTRAINT "ai_customer_conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_logs"
    ADD CONSTRAINT "ai_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_public_conversations"
    ADD CONSTRAINT "ai_public_conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_public_conversations"
    ADD CONSTRAINT "ai_public_conversations_session_id_key" UNIQUE ("session_id");



ALTER TABLE ONLY "public"."ai_traffic_log"
    ADD CONSTRAINT "ai_traffic_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_key_hash_key" UNIQUE ("key_hash");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_crash_reports"
    ADD CONSTRAINT "app_crash_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_debug_logs"
    ADD CONSTRAINT "app_debug_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_installations"
    ADD CONSTRAINT "app_installations_pkey" PRIMARY KEY ("device_id");



ALTER TABLE ONLY "public"."app_settings"
    ADD CONSTRAINT "app_settings_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."approval_queue"
    ADD CONSTRAINT "approval_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auto_order_rules"
    ADD CONSTRAINT "auto_order_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."automation_rules"
    ADD CONSTRAINT "automation_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_cancellations"
    ADD CONSTRAINT "booking_cancellations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_complaints"
    ADD CONSTRAINT "booking_complaints_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_discounts"
    ADD CONSTRAINT "booking_discounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_extras"
    ADD CONSTRAINT "booking_extras_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_accessories"
    ADD CONSTRAINT "branch_accessories_branch_id_type_size_key" UNIQUE ("branch_id", "type", "size");



ALTER TABLE ONLY "public"."branch_accessories"
    ADD CONSTRAINT "branch_accessories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_cameras"
    ADD CONSTRAINT "branch_cameras_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_door_codes"
    ADD CONSTRAINT "branch_door_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_door_events"
    ADD CONSTRAINT "branch_door_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_doors"
    ADD CONSTRAINT "branch_doors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_kiosk_config"
    ADD CONSTRAINT "branch_kiosk_config_pkey" PRIMARY KEY ("branch_id");



ALTER TABLE ONLY "public"."branch_performance"
    ADD CONSTRAINT "branch_performance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_power_status"
    ADD CONSTRAINT "branch_power_status_pkey" PRIMARY KEY ("branch_id");



ALTER TABLE ONLY "public"."branch_service_codes"
    ADD CONSTRAINT "branch_service_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_branch_code_key" UNIQUE ("branch_code");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."broadcast_campaigns"
    ADD CONSTRAINT "broadcast_campaigns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cash_register"
    ADD CONSTRAINT "cash_register_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cms_pages"
    ADD CONSTRAINT "cms_pages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cms_pages"
    ADD CONSTRAINT "cms_pages_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."cms_variables"
    ADD CONSTRAINT "cms_variables_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."cms_variables"
    ADD CONSTRAINT "cms_variables_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contracts"
    ADD CONSTRAINT "contracts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_documents"
    ADD CONSTRAINT "custom_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_documents"
    ADD CONSTRAINT "custom_documents_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."daily_stats"
    ADD CONSTRAINT "daily_stats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."debug_log"
    ADD CONSTRAINT "debug_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."delivery_notes"
    ADD CONSTRAINT "delivery_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_number_counters"
    ADD CONSTRAINT "document_number_counters_pkey" PRIMARY KEY ("prefix", "year");



ALTER TABLE ONLY "public"."document_templates"
    ADD CONSTRAINT "document_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."document_templates"
    ADD CONSTRAINT "document_templates_type_unique" UNIQUE ("type");



ALTER TABLE ONLY "public"."documents"
    ADD CONSTRAINT "documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_send_locks"
    ADD CONSTRAINT "email_send_locks_pkey" PRIMARY KEY ("booking_id", "template_slug");



ALTER TABLE ONLY "public"."email_templates"
    ADD CONSTRAINT "email_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_templates"
    ADD CONSTRAINT "email_templates_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."emp_attendance"
    ADD CONSTRAINT "emp_attendance_employee_id_date_key" UNIQUE ("employee_id", "date");



ALTER TABLE ONLY "public"."emp_attendance"
    ADD CONSTRAINT "emp_attendance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emp_documents"
    ADD CONSTRAINT "emp_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emp_shifts"
    ADD CONSTRAINT "emp_shifts_employee_id_date_key" UNIQUE ("employee_id", "date");



ALTER TABLE ONLY "public"."emp_shifts"
    ADD CONSTRAINT "emp_shifts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."emp_vacations"
    ADD CONSTRAINT "emp_vacations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."extras_catalog"
    ADD CONSTRAINT "extras_catalog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."faq_items"
    ADD CONSTRAINT "faq_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feature_flags"
    ADD CONSTRAINT "feature_flags_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."feature_flags"
    ADD CONSTRAINT "feature_flags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."financial_events"
    ADD CONSTRAINT "financial_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."flexi_reports"
    ADD CONSTRAINT "flexi_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."flexi_sync_log"
    ADD CONSTRAINT "flexi_sync_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gear_shortages"
    ADD CONSTRAINT "gear_shortages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."generated_documents"
    ADD CONSTRAINT "generated_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_number_key" UNIQUE ("number");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kiosk_commands"
    ADD CONSTRAINT "kiosk_commands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kiosk_devices"
    ADD CONSTRAINT "kiosk_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kiosk_logs"
    ADD CONSTRAINT "kiosk_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."loyalty_levels"
    ADD CONSTRAINT "loyalty_levels_pkey" PRIMARY KEY ("level");



ALTER TABLE ONLY "public"."loyalty_monthly_winners"
    ADD CONSTRAINT "loyalty_monthly_winners_pkey" PRIMARY KEY ("month");



ALTER TABLE ONLY "public"."maintenance_log"
    ADD CONSTRAINT "maintenance_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maintenance_schedules"
    ADD CONSTRAINT "maintenance_schedules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."message_log"
    ADD CONSTRAINT "message_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."message_templates"
    ADD CONSTRAINT "message_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."message_templates"
    ADD CONSTRAINT "message_templates_slug_channel_language_key" UNIQUE ("slug", "channel", "language");



ALTER TABLE ONLY "public"."message_threads"
    ADD CONSTRAINT "message_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."moto_day_prices"
    ADD CONSTRAINT "moto_day_prices_moto_id_key" UNIQUE ("moto_id");



ALTER TABLE ONLY "public"."moto_day_prices"
    ADD CONSTRAINT "moto_day_prices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."moto_locations"
    ADD CONSTRAINT "moto_locations_moto_id_key" UNIQUE ("moto_id");



ALTER TABLE ONLY "public"."moto_locations"
    ADD CONSTRAINT "moto_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."moto_performance"
    ADD CONSTRAINT "moto_performance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."motorcycles"
    ADD CONSTRAINT "motorcycles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."motorcycles"
    ADD CONSTRAINT "motorcycles_vin_key" UNIQUE ("vin");



ALTER TABLE ONLY "public"."notification_log"
    ADD CONSTRAINT "notification_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_rules"
    ADD CONSTRAINT "notification_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payment_methods"
    ADD CONSTRAINT "payment_methods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_uniq_poi" UNIQUE ("user_id", "poi_id");



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_uniq_route" UNIQUE ("user_id", "route_poi_id");



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_uniq_user" UNIQUE ("user_id", "user_poi_id");



ALTER TABLE ONLY "public"."points_of_interest"
    ADD CONSTRAINT "points_of_interest_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."predictions"
    ADD CONSTRAINT "predictions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pricing_rules"
    ADD CONSTRAINT "pricing_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promo_code_usage"
    ADD CONSTRAINT "promo_code_usage_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promo_codes"
    ADD CONSTRAINT "promo_codes_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."promo_codes"
    ADD CONSTRAINT "promo_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_pois"
    ADD CONSTRAINT "route_pois_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_reviews"
    ADD CONSTRAINT "route_reviews_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_reviews"
    ADD CONSTRAINT "route_reviews_uniq" UNIQUE ("user_id", "route_id");



ALTER TABLE ONLY "public"."routes"
    ADD CONSTRAINT "routes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sent_emails"
    ADD CONSTRAINT "sent_emails_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_parts"
    ADD CONSTRAINT "service_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_parts"
    ADD CONSTRAINT "service_parts_schedule_id_inventory_item_id_key" UNIQUE ("schedule_id", "inventory_item_id");



ALTER TABLE ONLY "public"."shop_order_items"
    ADD CONSTRAINT "shop_order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shop_orders"
    ADD CONSTRAINT "shop_orders_order_number_key" UNIQUE ("order_number");



ALTER TABLE ONLY "public"."shop_orders"
    ADD CONSTRAINT "shop_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sku_catalog"
    ADD CONSTRAINT "sku_catalog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sku_catalog"
    ADD CONSTRAINT "sku_catalog_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."sos_incidents"
    ADD CONSTRAINT "sos_incidents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sos_timeline"
    ADD CONSTRAINT "sos_timeline_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_receipts"
    ADD CONSTRAINT "stock_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tax_records"
    ADD CONSTRAINT "tax_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_stats"
    ADD CONSTRAINT "uq_daily_stats_date_branch" UNIQUE ("date", "branch_id");



ALTER TABLE ONLY "public"."gear_shortages"
    ADD CONSTRAINT "uq_gear_shortages_cell" UNIQUE ("branch_id", "accessory_type", "size", "shortage_date");



ALTER TABLE ONLY "public"."user_pois"
    ADD CONSTRAINT "user_pois_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_saved_routes"
    ADD CONSTRAINT "user_saved_routes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "user_visited_places_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "uvp_uniq_poi" UNIQUE ("user_id", "poi_id");



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "uvp_uniq_route_poi" UNIQUE ("user_id", "route_poi_id");



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "uvp_uniq_user_poi" UNIQUE ("user_id", "user_poi_id");



ALTER TABLE ONLY "public"."visitor_log"
    ADD CONSTRAINT "visitor_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_pkey" PRIMARY KEY ("id");



CREATE INDEX "custom_documents_web_idx" ON "public"."custom_documents" USING "btree" ("active", "show_on_web", "sort_order");



CREATE INDEX "financial_events_duzp_idx" ON "public"."financial_events" USING "btree" ("duzp");



CREATE INDEX "financial_events_linked_entity_id_idx" ON "public"."financial_events" USING "btree" ("linked_entity_id");



CREATE INDEX "financial_events_status_idx" ON "public"."financial_events" USING "btree" ("status");



CREATE UNIQUE INDEX "flexi_reports_report_type_year_idx" ON "public"."flexi_reports" USING "btree" ("report_type", "year") WHERE ("quarter" IS NULL);



CREATE INDEX "flexi_reports_report_type_year_quarter_idx" ON "public"."flexi_reports" USING "btree" ("report_type", "year", "quarter");



CREATE UNIQUE INDEX "flexi_reports_report_type_year_quarter_idx1" ON "public"."flexi_reports" USING "btree" ("report_type", "year", "quarter") WHERE ("quarter" IS NOT NULL);



CREATE INDEX "flexi_reports_status_idx" ON "public"."flexi_reports" USING "btree" ("status");



CREATE INDEX "flexi_sync_log_financial_event_id_idx" ON "public"."flexi_sync_log" USING "btree" ("financial_event_id");



CREATE INDEX "idx_acc_liabilities_financial_event_id" ON "public"."acc_liabilities" USING "btree" ("financial_event_id");



CREATE INDEX "idx_acc_long_term_assets_motorcycle_id" ON "public"."acc_long_term_assets" USING "btree" ("motorcycle_id");



CREATE INDEX "idx_accounting_entries_branch" ON "public"."accounting_entries" USING "btree" ("branch_id");



CREATE INDEX "idx_accounting_entries_date" ON "public"."accounting_entries" USING "btree" ("date" DESC);



CREATE INDEX "idx_accounting_entries_reference" ON "public"."accounting_entries" USING "btree" ("reference_type", "reference_id");



CREATE INDEX "idx_accounting_entries_type" ON "public"."accounting_entries" USING "btree" ("type");



CREATE INDEX "idx_admin_audit_log_admin" ON "public"."admin_audit_log" USING "btree" ("admin_id");



CREATE INDEX "idx_admin_audit_log_created" ON "public"."admin_audit_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_admin_audit_log_entity" ON "public"."admin_audit_log" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "idx_admin_messages_created" ON "public"."admin_messages" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_admin_messages_incident" ON "public"."admin_messages" USING "btree" ("incident_id") WHERE ("incident_id" IS NOT NULL);



CREATE INDEX "idx_admin_messages_read" ON "public"."admin_messages" USING "btree" ("user_id", "read");



CREATE INDEX "idx_admin_messages_user" ON "public"."admin_messages" USING "btree" ("user_id");



CREATE INDEX "idx_admin_messages_user_unread" ON "public"."admin_messages" USING "btree" ("user_id", "read") WHERE ("read" = false);



CREATE INDEX "idx_admin_users_email" ON "public"."admin_users" USING "btree" ("email");



CREATE INDEX "idx_admin_users_role" ON "public"."admin_users" USING "btree" ("role");



CREATE INDEX "idx_ai_actions_admin" ON "public"."ai_actions" USING "btree" ("admin_id");



CREATE INDEX "idx_ai_actions_conversation" ON "public"."ai_actions" USING "btree" ("conversation_id");



CREATE INDEX "idx_ai_actions_created" ON "public"."ai_actions" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_ai_actions_status" ON "public"."ai_actions" USING "btree" ("status");



CREATE INDEX "idx_ai_actions_tool" ON "public"."ai_actions" USING "btree" ("tool");



CREATE INDEX "idx_ai_actions_type" ON "public"."ai_actions" USING "btree" ("action_type");



CREATE INDEX "idx_ai_citations_observed" ON "public"."ai_citations" USING "btree" ("observed_at" DESC);



CREATE INDEX "idx_ai_citations_platform" ON "public"."ai_citations" USING "btree" ("ai_platform");



CREATE INDEX "idx_ai_conversations_admin" ON "public"."ai_conversations" USING "btree" ("admin_id");



CREATE INDEX "idx_ai_conversations_created" ON "public"."ai_conversations" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_ai_conversations_updated" ON "public"."ai_conversations" USING "btree" ("updated_at" DESC);



CREATE INDEX "idx_ai_customer_conv_user" ON "public"."ai_customer_conversations" USING "btree" ("user_id");



CREATE INDEX "idx_ai_logs_admin" ON "public"."ai_logs" USING "btree" ("admin_id");



CREATE INDEX "idx_ai_logs_created" ON "public"."ai_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_ai_public_conv_booking" ON "public"."ai_public_conversations" USING "btree" ("booking_id") WHERE ("booking_id" IS NOT NULL);



CREATE INDEX "idx_ai_public_conv_last_activity" ON "public"."ai_public_conversations" USING "btree" ("last_activity_at" DESC);



CREATE INDEX "idx_ai_public_conv_outcome" ON "public"."ai_public_conversations" USING "btree" ("outcome");



CREATE INDEX "idx_ai_public_conv_started" ON "public"."ai_public_conversations" USING "btree" ("started_at" DESC);



CREATE INDEX "idx_ai_traffic_bot" ON "public"."ai_traffic_log" USING "btree" ("bot_name", "ts" DESC) WHERE ("bot_name" IS NOT NULL);



CREATE INDEX "idx_ai_traffic_outcome" ON "public"."ai_traffic_log" USING "btree" ("outcome", "ts" DESC) WHERE ("outcome" IS NOT NULL);



CREATE INDEX "idx_ai_traffic_partner" ON "public"."ai_traffic_log" USING "btree" ("partner_id", "ts" DESC) WHERE ("partner_id" IS NOT NULL);



CREATE INDEX "idx_ai_traffic_path" ON "public"."ai_traffic_log" USING "btree" ("path", "ts" DESC);



CREATE INDEX "idx_ai_traffic_source" ON "public"."ai_traffic_log" USING "btree" ("source", "ts" DESC);



CREATE INDEX "idx_ai_traffic_ts" ON "public"."ai_traffic_log" USING "btree" ("ts" DESC);



CREATE INDEX "idx_api_keys_active" ON "public"."api_keys" USING "btree" ("is_active") WHERE ("is_active" = true);



CREATE INDEX "idx_api_keys_prefix" ON "public"."api_keys" USING "btree" ("key_prefix");



CREATE INDEX "idx_app_installations_last_seen" ON "public"."app_installations" USING "btree" ("last_seen_at" DESC);



CREATE INDEX "idx_app_installations_platform" ON "public"."app_installations" USING "btree" ("lower"("platform"));



CREATE INDEX "idx_app_installations_user" ON "public"."app_installations" USING "btree" ("user_id");



CREATE INDEX "idx_audit_log_action" ON "public"."admin_audit_log" USING "btree" ("action");



CREATE INDEX "idx_audit_log_admin" ON "public"."admin_audit_log" USING "btree" ("admin_id");



CREATE INDEX "idx_audit_log_created" ON "public"."admin_audit_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_automation_rules_enabled" ON "public"."automation_rules" USING "btree" ("enabled") WHERE ("enabled" = true);



CREATE INDEX "idx_automation_rules_event" ON "public"."automation_rules" USING "btree" ("event");



CREATE INDEX "idx_booking_cancellations_booking" ON "public"."booking_cancellations" USING "btree" ("booking_id");



CREATE INDEX "idx_booking_discounts_booking" ON "public"."booking_discounts" USING "btree" ("booking_id");



CREATE INDEX "idx_booking_extras_booking" ON "public"."booking_extras" USING "btree" ("booking_id");



CREATE INDEX "idx_bookings_cancelled_at" ON "public"."bookings" USING "btree" ("cancelled_at");



CREATE INDEX "idx_bookings_continues" ON "public"."bookings" USING "btree" ("continues_booking_id");



CREATE INDEX "idx_bookings_dates" ON "public"."bookings" USING "btree" ("start_date", "end_date");



CREATE INDEX "idx_bookings_extends_booking_id" ON "public"."bookings" USING "btree" ("extends_booking_id") WHERE ("extends_booking_id" IS NOT NULL);



CREATE INDEX "idx_bookings_is_test" ON "public"."bookings" USING "btree" ("is_test") WHERE ("is_test" = true);



CREATE INDEX "idx_bookings_moto" ON "public"."bookings" USING "btree" ("moto_id");



CREATE INDEX "idx_bookings_status" ON "public"."bookings" USING "btree" ("status");



CREATE INDEX "idx_bookings_trailer_moto_id" ON "public"."bookings" USING "btree" ("trailer_moto_id") WHERE ("trailer_moto_id" IS NOT NULL);



CREATE INDEX "idx_bookings_user" ON "public"."bookings" USING "btree" ("user_id");



CREATE INDEX "idx_bookings_user_dates_overlap" ON "public"."bookings" USING "btree" ("user_id", "start_date", "end_date") WHERE ("status" <> 'cancelled'::"public"."booking_status");



CREATE INDEX "idx_branch_accessories_branch_type_size" ON "public"."branch_accessories" USING "btree" ("branch_id", "type", "size");



CREATE INDEX "idx_branch_cameras_branch" ON "public"."branch_cameras" USING "btree" ("branch_id");



CREATE INDEX "idx_branch_door_events_branch" ON "public"."branch_door_events" USING "btree" ("branch_id", "created_at" DESC);



CREATE INDEX "idx_branch_doors_branch" ON "public"."branch_doors" USING "btree" ("branch_id");



CREATE INDEX "idx_branch_performance_branch" ON "public"."branch_performance" USING "btree" ("branch_id");



CREATE INDEX "idx_branch_performance_period" ON "public"."branch_performance" USING "btree" ("period_start", "period_end");



CREATE INDEX "idx_branch_service_codes_branch" ON "public"."branch_service_codes" USING "btree" ("branch_id");



CREATE INDEX "idx_broadcast_campaigns_channel" ON "public"."broadcast_campaigns" USING "btree" ("channel");



CREATE INDEX "idx_broadcast_campaigns_created_at" ON "public"."broadcast_campaigns" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_broadcast_campaigns_status" ON "public"."broadcast_campaigns" USING "btree" ("status");



CREATE INDEX "idx_cms_pages_published" ON "public"."cms_pages" USING "btree" ("published") WHERE ("published" = true);



CREATE INDEX "idx_cms_pages_slug" ON "public"."cms_pages" USING "btree" ("slug");



CREATE INDEX "idx_cms_pages_tags" ON "public"."cms_pages" USING "gin" ("tags");



CREATE INDEX "idx_cms_pages_translations" ON "public"."cms_pages" USING "gin" ("translations");



CREATE INDEX "idx_cms_variables_category" ON "public"."cms_variables" USING "btree" ("category");



CREATE INDEX "idx_cms_variables_key" ON "public"."cms_variables" USING "btree" ("key");



CREATE INDEX "idx_crash_reports_created" ON "public"."app_crash_reports" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_crash_reports_screen" ON "public"."app_crash_reports" USING "btree" ("screen", "created_at" DESC);



CREATE INDEX "idx_crash_reports_severity" ON "public"."app_crash_reports" USING "btree" ("severity", "created_at" DESC);



CREATE INDEX "idx_crash_reports_user" ON "public"."app_crash_reports" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_daily_stats_branch" ON "public"."daily_stats" USING "btree" ("branch_id");



CREATE INDEX "idx_daily_stats_date" ON "public"."daily_stats" USING "btree" ("date" DESC);



CREATE INDEX "idx_debug_log_action" ON "public"."debug_log" USING "btree" ("action");



CREATE INDEX "idx_debug_log_created" ON "public"."debug_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_debug_log_status" ON "public"."debug_log" USING "btree" ("status");



CREATE INDEX "idx_debug_logs_category" ON "public"."app_debug_logs" USING "btree" ("category", "created_at" DESC);



CREATE INDEX "idx_debug_logs_created" ON "public"."app_debug_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_debug_logs_user" ON "public"."app_debug_logs" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_debug_logs_user_category" ON "public"."app_debug_logs" USING "btree" ("user_id", "category", "created_at" DESC);



CREATE INDEX "idx_doc_templates_type_active" ON "public"."document_templates" USING "btree" ("type") WHERE ("active" = true);



CREATE INDEX "idx_documents_booking" ON "public"."documents" USING "btree" ("booking_id");



CREATE INDEX "idx_documents_metadata_mindee" ON "public"."documents" USING "btree" ((("metadata" ->> 'mindee_status'::"text")));



CREATE INDEX "idx_documents_user" ON "public"."documents" USING "btree" ("user_id");



CREATE INDEX "idx_documents_user_type" ON "public"."documents" USING "btree" ("user_id", "type");



CREATE INDEX "idx_email_templates_slug" ON "public"."email_templates" USING "btree" ("slug");



CREATE INDEX "idx_email_templates_triggers_gin" ON "public"."email_templates" USING "gin" ("triggers" "jsonb_path_ops");



CREATE INDEX "idx_extras_catalog_branch" ON "public"."extras_catalog" USING "btree" ("branch_id");



CREATE INDEX "idx_extras_catalog_category" ON "public"."extras_catalog" USING "btree" ("category");



CREATE INDEX "idx_faq_items_category" ON "public"."faq_items" USING "btree" ("category_key", "sort_order");



CREATE INDEX "idx_faq_items_featured" ON "public"."faq_items" USING "btree" ("featured_home", "sort_order") WHERE ("featured_home" = true);



CREATE INDEX "idx_faq_items_published" ON "public"."faq_items" USING "btree" ("published", "sort_order") WHERE ("published" = true);



CREATE INDEX "idx_feature_flags_key" ON "public"."feature_flags" USING "btree" ("key");



CREATE INDEX "idx_gear_shortages_open" ON "public"."gear_shortages" USING "btree" ("status", "shortage_date") WHERE ("status" = 'open'::"text");



CREATE INDEX "idx_generated_documents_booking" ON "public"."generated_documents" USING "btree" ("booking_id");



CREATE INDEX "idx_generated_documents_created" ON "public"."generated_documents" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_generated_documents_customer" ON "public"."generated_documents" USING "btree" ("customer_id");



CREATE INDEX "idx_generated_documents_template" ON "public"."generated_documents" USING "btree" ("template_id");



CREATE INDEX "idx_inventory_branch" ON "public"."inventory" USING "btree" ("branch_id");



CREATE INDEX "idx_inventory_category" ON "public"."inventory" USING "btree" ("category");



CREATE INDEX "idx_inventory_movements_created" ON "public"."inventory_movements" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_inventory_movements_inventory" ON "public"."inventory_movements" USING "btree" ("inventory_id");



CREATE INDEX "idx_inventory_movements_type" ON "public"."inventory_movements" USING "btree" ("type");



CREATE INDEX "idx_inventory_sku" ON "public"."inventory" USING "btree" ("sku");



CREATE INDEX "idx_inventory_supplier" ON "public"."inventory" USING "btree" ("supplier_id");



CREATE INDEX "idx_invoices_booking" ON "public"."invoices" USING "btree" ("booking_id");



CREATE INDEX "idx_invoices_booking_type" ON "public"."invoices" USING "btree" ("booking_id", "type", "status");



CREATE INDEX "idx_invoices_customer" ON "public"."invoices" USING "btree" ("customer_id");



CREATE INDEX "idx_invoices_due_date" ON "public"."invoices" USING "btree" ("due_date");



CREATE INDEX "idx_invoices_number" ON "public"."invoices" USING "btree" ("number");



CREATE INDEX "idx_invoices_original_invoice" ON "public"."invoices" USING "btree" ("original_invoice_id") WHERE ("original_invoice_id" IS NOT NULL);



CREATE INDEX "idx_invoices_status" ON "public"."invoices" USING "btree" ("status");



CREATE INDEX "idx_invoices_type" ON "public"."invoices" USING "btree" ("type");



CREATE INDEX "idx_invoices_type_credit_note" ON "public"."invoices" USING "btree" ("type") WHERE ("type" = 'credit_note'::"text");



CREATE INDEX "idx_invoices_variable_symbol" ON "public"."invoices" USING "btree" ("variable_symbol");



CREATE INDEX "idx_kiosk_commands_device" ON "public"."kiosk_commands" USING "btree" ("device_id", "status", "created_at" DESC);



CREATE INDEX "idx_kiosk_devices_branch" ON "public"."kiosk_devices" USING "btree" ("branch_id");



CREATE INDEX "idx_kiosk_logs_branch" ON "public"."kiosk_logs" USING "btree" ("branch_id", "created_at" DESC);



CREATE INDEX "idx_kiosk_logs_level" ON "public"."kiosk_logs" USING "btree" ("level", "created_at" DESC);



CREATE INDEX "idx_maintenance_log_date" ON "public"."maintenance_log" USING "btree" ("service_date" DESC);



CREATE INDEX "idx_maintenance_log_is_test" ON "public"."maintenance_log" USING "btree" ("is_test") WHERE ("is_test" = true);



CREATE INDEX "idx_maintenance_log_moto" ON "public"."maintenance_log" USING "btree" ("moto_id");



CREATE INDEX "idx_maintenance_log_sos" ON "public"."maintenance_log" USING "btree" ("sos_incident_id") WHERE ("sos_incident_id" IS NOT NULL);



CREATE INDEX "idx_maintenance_log_type" ON "public"."maintenance_log" USING "btree" ("service_type");



CREATE INDEX "idx_maintenance_schedules_active" ON "public"."maintenance_schedules" USING "btree" ("active") WHERE ("active" = true);



CREATE INDEX "idx_maintenance_schedules_moto" ON "public"."maintenance_schedules" USING "btree" ("moto_id");



CREATE INDEX "idx_maintenance_schedules_next_due" ON "public"."maintenance_schedules" USING "btree" ("next_due");



CREATE INDEX "idx_message_log_booking_id" ON "public"."message_log" USING "btree" ("booking_id");



CREATE INDEX "idx_message_log_channel_status" ON "public"."message_log" USING "btree" ("channel", "status");



CREATE INDEX "idx_message_log_created_at" ON "public"."message_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_message_log_customer_id" ON "public"."message_log" USING "btree" ("customer_id");



CREATE INDEX "idx_message_log_template_slug" ON "public"."message_log" USING "btree" ("template_slug");



CREATE INDEX "idx_message_threads_assigned" ON "public"."message_threads" USING "btree" ("assigned_admin");



CREATE INDEX "idx_message_threads_channel" ON "public"."message_threads" USING "btree" ("channel");



CREATE INDEX "idx_message_threads_customer" ON "public"."message_threads" USING "btree" ("customer_id");



CREATE INDEX "idx_message_threads_last_msg" ON "public"."message_threads" USING "btree" ("last_message_at" DESC);



CREATE INDEX "idx_message_threads_status" ON "public"."message_threads" USING "btree" ("status");



CREATE INDEX "idx_messages_ai_suggestion_pending" ON "public"."messages" USING "btree" ("created_at" DESC) WHERE ("ai_suggestion_status" = 'pending'::"public"."ai_suggestion_status");



CREATE INDEX "idx_messages_ai_suggestion_status" ON "public"."messages" USING "btree" ("ai_suggestion_status", "created_at" DESC) WHERE ("ai_suggestion_status" IS NOT NULL);



CREATE INDEX "idx_messages_created" ON "public"."messages" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_messages_thread" ON "public"."messages" USING "btree" ("thread_id");



CREATE INDEX "idx_messages_unread" ON "public"."messages" USING "btree" ("read_at") WHERE ("read_at" IS NULL);



CREATE INDEX "idx_moto_day_prices_moto" ON "public"."moto_day_prices" USING "btree" ("moto_id");



CREATE INDEX "idx_moto_locations_moto" ON "public"."moto_locations" USING "btree" ("moto_id");



CREATE INDEX "idx_moto_performance_moto" ON "public"."moto_performance" USING "btree" ("moto_id");



CREATE INDEX "idx_moto_performance_period" ON "public"."moto_performance" USING "btree" ("period_start", "period_end");



CREATE INDEX "idx_motorcycles_branch" ON "public"."motorcycles" USING "btree" ("branch_id");



CREATE INDEX "idx_motorcycles_sort_order" ON "public"."motorcycles" USING "btree" ("sort_order");



CREATE INDEX "idx_motorcycles_status" ON "public"."motorcycles" USING "btree" ("status");



CREATE INDEX "idx_motorcycles_translations" ON "public"."motorcycles" USING "gin" ("translations");



CREATE INDEX "idx_notification_log_created" ON "public"."notification_log" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_notification_log_recipient" ON "public"."notification_log" USING "btree" ("recipient_id");



CREATE INDEX "idx_notification_log_rule" ON "public"."notification_log" USING "btree" ("rule_id");



CREATE INDEX "idx_notification_log_status" ON "public"."notification_log" USING "btree" ("status");



CREATE INDEX "idx_notification_rules_enabled" ON "public"."notification_rules" USING "btree" ("enabled") WHERE ("enabled" = true);



CREATE INDEX "idx_notification_rules_trigger" ON "public"."notification_rules" USING "btree" ("trigger_type");



CREATE INDEX "idx_payment_methods_user_id" ON "public"."payment_methods" USING "btree" ("user_id");



CREATE INDEX "idx_poi_catalog_active" ON "public"."points_of_interest" USING "btree" ("is_active");



CREATE INDEX "idx_poi_catalog_cat" ON "public"."points_of_interest" USING "btree" ("category");



CREATE INDEX "idx_poi_catalog_country" ON "public"."points_of_interest" USING "btree" ("country");



CREATE INDEX "idx_poi_ratings_poi" ON "public"."poi_ratings" USING "btree" ("poi_id");



CREATE INDEX "idx_poi_ratings_route" ON "public"."poi_ratings" USING "btree" ("route_poi_id");



CREATE INDEX "idx_poi_ratings_route_poi" ON "public"."poi_ratings" USING "btree" ("route_poi_id");



CREATE INDEX "idx_poi_ratings_status" ON "public"."poi_ratings" USING "btree" ("status");



CREATE INDEX "idx_poi_ratings_user_poi" ON "public"."poi_ratings" USING "btree" ("user_poi_id");



CREATE INDEX "idx_predictions_period" ON "public"."predictions" USING "btree" ("target_period_start", "target_period_end");



CREATE INDEX "idx_predictions_type" ON "public"."predictions" USING "btree" ("type");



CREATE INDEX "idx_pricing_rules_active" ON "public"."pricing_rules" USING "btree" ("active") WHERE ("active" = true);



CREATE INDEX "idx_pricing_rules_moto" ON "public"."pricing_rules" USING "btree" ("moto_id");



CREATE INDEX "idx_pricing_rules_type" ON "public"."pricing_rules" USING "btree" ("type");



CREATE INDEX "idx_products_translations" ON "public"."products" USING "gin" ("translations");



CREATE INDEX "idx_profiles_is_test" ON "public"."profiles" USING "btree" ("is_test_account") WHERE ("is_test_account" = true);



CREATE INDEX "idx_promo_codes_active" ON "public"."promo_codes" USING "btree" ("active");



CREATE INDEX "idx_promo_codes_code" ON "public"."promo_codes" USING "btree" ("code");



CREATE INDEX "idx_promo_codes_is_test" ON "public"."promo_codes" USING "btree" ("is_test") WHERE ("is_test" = true);



CREATE INDEX "idx_promo_codes_valid" ON "public"."promo_codes" USING "btree" ("valid_from", "valid_to");



CREATE INDEX "idx_promo_usage_booking" ON "public"."promo_code_usage" USING "btree" ("booking_id");



CREATE INDEX "idx_promo_usage_code" ON "public"."promo_code_usage" USING "btree" ("promo_code_id");



CREATE INDEX "idx_purchase_order_items_order" ON "public"."purchase_order_items" USING "btree" ("order_id");



CREATE INDEX "idx_purchase_orders_status" ON "public"."purchase_orders" USING "btree" ("status");



CREATE INDEX "idx_purchase_orders_supplier" ON "public"."purchase_orders" USING "btree" ("supplier_id");



CREATE INDEX "idx_push_tokens_active" ON "public"."push_tokens" USING "btree" ("active") WHERE ("active" = true);



CREATE INDEX "idx_push_tokens_user" ON "public"."push_tokens" USING "btree" ("user_id");



CREATE INDEX "idx_reviews_moto" ON "public"."reviews" USING "btree" ("moto_id");



CREATE INDEX "idx_reviews_user" ON "public"."reviews" USING "btree" ("user_id");



CREATE INDEX "idx_route_pois_route" ON "public"."route_pois" USING "btree" ("route_id");



CREATE INDEX "idx_route_pois_sort" ON "public"."route_pois" USING "btree" ("sort_order");



CREATE INDEX "idx_route_reviews_route" ON "public"."route_reviews" USING "btree" ("route_id");



CREATE INDEX "idx_route_reviews_status" ON "public"."route_reviews" USING "btree" ("status");



CREATE INDEX "idx_routes_active" ON "public"."routes" USING "btree" ("is_active");



CREATE INDEX "idx_routes_branch" ON "public"."routes" USING "btree" ("branch_id");



CREATE INDEX "idx_routes_sort" ON "public"."routes" USING "btree" ("sort_order");



CREATE INDEX "idx_routes_status" ON "public"."routes" USING "btree" ("status");



CREATE INDEX "idx_sent_emails_booking" ON "public"."sent_emails" USING "btree" ("booking_id");



CREATE INDEX "idx_sent_emails_created" ON "public"."sent_emails" USING "btree" ("created_at");



CREATE INDEX "idx_sent_emails_recipient" ON "public"."sent_emails" USING "btree" ("recipient_id");



CREATE INDEX "idx_sent_emails_template" ON "public"."sent_emails" USING "btree" ("template_slug");



CREATE INDEX "idx_service_orders_is_test" ON "public"."service_orders" USING "btree" ("is_test") WHERE ("is_test" = true);



CREATE INDEX "idx_service_orders_moto" ON "public"."service_orders" USING "btree" ("moto_id");



CREATE INDEX "idx_service_orders_status" ON "public"."service_orders" USING "btree" ("status");



CREATE INDEX "idx_shop_order_items_order" ON "public"."shop_order_items" USING "btree" ("order_id");



CREATE INDEX "idx_shop_order_items_product_id" ON "public"."shop_order_items" USING "btree" ("product_id");



CREATE INDEX "idx_shop_orders_created" ON "public"."shop_orders" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_shop_orders_customer" ON "public"."shop_orders" USING "btree" ("customer_id");



CREATE INDEX "idx_shop_orders_number" ON "public"."shop_orders" USING "btree" ("order_number");



CREATE INDEX "idx_shop_orders_status" ON "public"."shop_orders" USING "btree" ("status");



CREATE INDEX "idx_sos_created" ON "public"."sos_incidents" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_sos_incidents_booking" ON "public"."sos_incidents" USING "btree" ("booking_id");



CREATE INDEX "idx_sos_incidents_created" ON "public"."sos_incidents" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_sos_incidents_is_test" ON "public"."sos_incidents" USING "btree" ("is_test") WHERE ("is_test" = true);



CREATE INDEX "idx_sos_incidents_moto" ON "public"."sos_incidents" USING "btree" ("moto_id");



CREATE INDEX "idx_sos_incidents_severity" ON "public"."sos_incidents" USING "btree" ("severity");



CREATE INDEX "idx_sos_incidents_status" ON "public"."sos_incidents" USING "btree" ("status");



CREATE INDEX "idx_sos_incidents_user" ON "public"."sos_incidents" USING "btree" ("user_id");



CREATE INDEX "idx_sos_status" ON "public"."sos_incidents" USING "btree" ("status");



CREATE INDEX "idx_sos_timeline_created" ON "public"."sos_timeline" USING "btree" ("created_at");



CREATE INDEX "idx_sos_timeline_incident" ON "public"."sos_timeline" USING "btree" ("incident_id");



CREATE INDEX "idx_sos_user" ON "public"."sos_incidents" USING "btree" ("user_id");



CREATE INDEX "idx_stock_receipts_docnum" ON "public"."stock_receipts" USING "btree" ("lower"("doc_number"), "doc_date");



CREATE INDEX "idx_stock_receipts_needs_dl" ON "public"."stock_receipts" USING "btree" ("needs_dl") WHERE ("needs_dl" = true);



CREATE INDEX "idx_stock_receipts_supplier" ON "public"."stock_receipts" USING "btree" ("supplier_ico", "supplier_name");



CREATE INDEX "idx_suppliers_ico" ON "public"."suppliers" USING "btree" ("ico");



CREATE INDEX "idx_suppliers_normalized_name" ON "public"."suppliers" USING "btree" ("normalized_name");



CREATE INDEX "idx_user_pois_status" ON "public"."user_pois" USING "btree" ("status");



CREATE INDEX "idx_user_saved_routes_user" ON "public"."user_saved_routes" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_user_visited_places_user" ON "public"."user_visited_places" USING "btree" ("user_id", "last_visited_at" DESC);



CREATE INDEX "idx_visitor_log_host" ON "public"."visitor_log" USING "btree" ("host");



CREATE INDEX "idx_visitor_log_host_ts" ON "public"."visitor_log" USING "btree" ("host", "ts" DESC);



CREATE INDEX "idx_visitor_log_path" ON "public"."visitor_log" USING "btree" ("path");



CREATE INDEX "idx_visitor_log_ref_domain" ON "public"."visitor_log" USING "btree" ("referrer_domain");



CREATE INDEX "idx_visitor_log_ts" ON "public"."visitor_log" USING "btree" ("ts" DESC);



CREATE INDEX "idx_visitor_log_visitor" ON "public"."visitor_log" USING "btree" ("visitor_hash");



CREATE INDEX "idx_vouchers_buyer_id" ON "public"."vouchers" USING "btree" ("buyer_id");



CREATE INDEX "idx_vouchers_code" ON "public"."vouchers" USING "btree" ("code");



CREATE INDEX "idx_vouchers_created_at" ON "public"."vouchers" USING "btree" ("created_at");



CREATE INDEX "idx_vouchers_order_id" ON "public"."vouchers" USING "btree" ("order_id");



CREATE INDEX "idx_vouchers_slevomat_pending" ON "public"."vouchers" USING "btree" ("slevomat_apply_attempts") WHERE (("source" = 'slevomat'::"text") AND ("status" = 'redeemed'::"text") AND ("slevomat_applied_at" IS NULL));



CREATE INDEX "idx_vouchers_status" ON "public"."vouchers" USING "btree" ("status");



CREATE INDEX "idx_vouchers_valid_until" ON "public"."vouchers" USING "btree" ("valid_until");



CREATE UNIQUE INDEX "invoices_number_unique" ON "public"."invoices" USING "btree" ("number");



CREATE UNIQUE INDEX "uq_branch_doors_acc" ON "public"."branch_doors" USING "btree" ("branch_id") WHERE ("door_kind" = 'accessories'::"text");



CREATE UNIQUE INDEX "uq_branch_doors_moto" ON "public"."branch_doors" USING "btree" ("branch_id", "box_number") WHERE ("door_kind" = 'motorcycle'::"text");



CREATE UNIQUE INDEX "uq_branch_service_codes" ON "public"."branch_service_codes" USING "btree" ("branch_id", "code") WHERE "is_active";



CREATE UNIQUE INDEX "uq_invoices_active_order_type" ON "public"."invoices" USING "btree" ("order_id", "type") WHERE (("order_id" IS NOT NULL) AND ("status" <> 'cancelled'::"text"));



CREATE OR REPLACE TRIGGER "bookings_auto_accounting" AFTER UPDATE OF "payment_status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."payment_status" = 'paid'::"public"."payment_status") AND ("old"."payment_status" IS DISTINCT FROM 'paid'::"public"."payment_status"))) EXECUTE FUNCTION "public"."auto_accounting_on_booking_paid"();



CREATE OR REPLACE TRIGGER "bookings_updated_at" BEFORE UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "cms_pages_updated_at" BEFORE UPDATE ON "public"."cms_pages" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "faq_items_set_updated_at" BEFORE UPDATE ON "public"."faq_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at_now"();



CREATE OR REPLACE TRIGGER "gear_shortage_on_booking" AFTER INSERT OR UPDATE OF "start_date", "end_date", "moto_id", "status", "helmet_size", "jacket_size", "pants_size", "boots_size", "gloves_size", "passenger_helmet_size", "passenger_jacket_size", "passenger_pants_size", "passenger_boots_size", "passenger_gloves_size" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."trg_gear_shortage_on_booking"();



CREATE OR REPLACE TRIGGER "inventory_updated_at" BEFORE UPDATE ON "public"."inventory" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "maintenance_log_after_insert" AFTER INSERT ON "public"."maintenance_log" FOR EACH ROW EXECUTE FUNCTION "public"."update_moto_after_service"();



CREATE OR REPLACE TRIGGER "maintenance_log_after_update" AFTER UPDATE OF "km_at_service", "status", "completed_date" ON "public"."maintenance_log" FOR EACH ROW EXECUTE FUNCTION "public"."update_moto_after_service"();



CREATE OR REPLACE TRIGGER "moto_day_prices_updated" BEFORE UPDATE ON "public"."moto_day_prices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "motorcycles_updated_at" BEFORE UPDATE ON "public"."motorcycles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "purchase_orders_updated_at" BEFORE UPDATE ON "public"."purchase_orders" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "realloc_booking_discounts" AFTER UPDATE OF "discount_amount", "total_price" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."trg_realloc_booking_discounts"();



CREATE OR REPLACE TRIGGER "redeem_booking_discounts" AFTER UPDATE OF "payment_status" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."redeem_booking_discounts_on_paid"();



CREATE OR REPLACE TRIGGER "trg_acc_employees_updated" BEFORE UPDATE ON "public"."acc_employees" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_acc_liabilities_updated" BEFORE UPDATE ON "public"."acc_liabilities" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_acc_long_term_assets_updated" BEFORE UPDATE ON "public"."acc_long_term_assets" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_acc_payrolls_updated" BEFORE UPDATE ON "public"."acc_payrolls" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_acc_short_term_assets_updated" BEFORE UPDATE ON "public"."acc_short_term_assets" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_acc_tax_returns_updated" BEFORE UPDATE ON "public"."acc_tax_returns" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_acc_vat_returns_updated" BEFORE UPDATE ON "public"."acc_vat_returns" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_accessory_types_updated" BEFORE UPDATE ON "public"."accessory_types" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_activate_on_handover_protocol_doc" AFTER INSERT ON "public"."generated_documents" FOR EACH ROW EXECUTE FUNCTION "public"."_activate_on_handover_protocol_doc"();



CREATE OR REPLACE TRIGGER "trg_admin_users_updated" BEFORE UPDATE ON "public"."admin_users" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_ai_conversations_updated" BEFORE UPDATE ON "public"."ai_conversations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_ai_customer_conversations_updated" BEFORE UPDATE ON "public"."ai_customer_conversations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_app_installations_touch" BEFORE UPDATE ON "public"."app_installations" FOR EACH ROW EXECUTE FUNCTION "public"."app_installations_touch"();



CREATE OR REPLACE TRIGGER "trg_app_settings_updated" BEFORE UPDATE ON "public"."app_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_auto_deactivate_door_codes" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."status" = ANY (ARRAY['completed'::"public"."booking_status", 'cancelled'::"public"."booking_status"])) AND ("old"."status" IS DISTINCT FROM "new"."status"))) EXECUTE FUNCTION "public"."auto_deactivate_door_codes"();



CREATE OR REPLACE TRIGGER "trg_auto_generate_door_codes_insert" AFTER INSERT ON "public"."bookings" FOR EACH ROW WHEN (("new"."status" = ANY (ARRAY['active'::"public"."booking_status", 'reserved'::"public"."booking_status"]))) EXECUTE FUNCTION "public"."auto_generate_door_codes"();



CREATE OR REPLACE TRIGGER "trg_auto_generate_door_codes_update" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."status" = ANY (ARRAY['active'::"public"."booking_status", 'reserved'::"public"."booking_status"])) AND ("old"."status" IS DISTINCT FROM "new"."status"))) EXECUTE FUNCTION "public"."auto_generate_door_codes"();



CREATE OR REPLACE TRIGGER "trg_auto_liabilities_payroll" AFTER INSERT ON "public"."acc_payrolls" FOR EACH ROW EXECUTE FUNCTION "public"."auto_liabilities_from_payroll"();



CREATE OR REPLACE TRIGGER "trg_auto_order_rules_updated" BEFORE UPDATE ON "public"."auto_order_rules" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_auto_process_voucher_order" BEFORE UPDATE OF "payment_status" ON "public"."shop_orders" FOR EACH ROW WHEN ((("new"."payment_status" = 'paid'::"text") AND ("old"."payment_status" IS DISTINCT FROM 'paid'::"text"))) EXECUTE FUNCTION "public"."auto_process_voucher_order"();



CREATE OR REPLACE TRIGGER "trg_booking_mileage_to_moto" AFTER INSERT OR UPDATE OF "mileage_start" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."trg_booking_mileage_to_moto"();



CREATE OR REPLACE TRIGGER "trg_booking_modified_email" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."trg_send_booking_modified_email"();



CREATE OR REPLACE TRIGGER "trg_booking_payment_fill_seconds" BEFORE INSERT OR UPDATE OF "payment_status", "confirmed_at" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."trg_booking_payment_fill_seconds"();



CREATE OR REPLACE TRIGGER "trg_branch_accessories_updated" BEFORE UPDATE ON "public"."branch_accessories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_branch_cameras_touch" BEFORE UPDATE ON "public"."branch_cameras" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_branch_door_codes_updated" BEFORE UPDATE ON "public"."branch_door_codes" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_branch_doors_touch" BEFORE UPDATE ON "public"."branch_doors" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_branch_kiosk_config_touch" BEFORE UPDATE ON "public"."branch_kiosk_config" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_branch_service_codes_touch" BEFORE UPDATE ON "public"."branch_service_codes" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_branches_updated" BEFORE UPDATE ON "public"."branches" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_bridge_admin_message" AFTER INSERT ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."bridge_admin_message_to_app"();



CREATE OR REPLACE TRIGGER "trg_cap_refund_to_paid" BEFORE INSERT ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."_cap_refund_to_paid"();



CREATE OR REPLACE TRIGGER "trg_check_booking_overlap" BEFORE INSERT OR UPDATE OF "start_date", "end_date", "moto_id" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."check_booking_overlap"();



CREATE OR REPLACE TRIGGER "trg_check_trailer_overlap" BEFORE INSERT OR UPDATE OF "moto_id", "trailer_moto_id", "start_date", "end_date", "status" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."check_trailer_overlap"();



CREATE OR REPLACE TRIGGER "trg_check_user_booking_overlap" BEFORE INSERT OR UPDATE OF "start_date", "end_date", "user_id", "status" ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."check_user_booking_overlap"();



CREATE OR REPLACE TRIGGER "trg_contracts_updated" BEFORE UPDATE ON "public"."contracts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_custom_documents_updated_at" BEFORE UPDATE ON "public"."custom_documents" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_delivery_notes_updated" BEFORE UPDATE ON "public"."delivery_notes" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_detect_consecutive_booking" BEFORE INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."detect_consecutive_booking"();



CREATE OR REPLACE TRIGGER "trg_email_on_door_codes_message" AFTER INSERT ON "public"."admin_messages" FOR EACH ROW WHEN (("new"."type" = 'door_codes'::"text")) EXECUTE FUNCTION "public"."trg_email_on_door_codes_message"();



CREATE OR REPLACE TRIGGER "trg_email_templates_updated" BEFORE UPDATE ON "public"."email_templates" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_emp_attendance_updated" BEFORE UPDATE ON "public"."emp_attendance" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_emp_documents_updated" BEFORE UPDATE ON "public"."emp_documents" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_emp_shifts_updated" BEFORE UPDATE ON "public"."emp_shifts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_emp_vacations_updated" BEFORE UPDATE ON "public"."emp_vacations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_fe_updated" BEFORE UPDATE ON "public"."financial_events" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_flexi_reports_updated" BEFORE UPDATE ON "public"."flexi_reports" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_gate_obsluzna_activation" BEFORE UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."status" = 'active'::"public"."booking_status") AND ("old"."status" <> 'active'::"public"."booking_status"))) EXECUTE FUNCTION "public"."_gate_obsluzna_activation"();



CREATE OR REPLACE TRIGGER "trg_generate_final_invoice" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("old"."status" = 'active'::"public"."booking_status") AND ("new"."status" = 'completed'::"public"."booking_status"))) EXECUTE FUNCTION "public"."generate_final_invoice_on_complete"();



CREATE OR REPLACE TRIGGER "trg_generate_shop_final_on_ship" AFTER UPDATE OF "status", "payment_status" ON "public"."shop_orders" FOR EACH ROW WHEN ((("new"."status" = ANY (ARRAY['shipped'::"text", 'delivered'::"text"])) AND ("old"."status" IS DISTINCT FROM "new"."status") AND ("new"."payment_status" = 'paid'::"text"))) EXECUTE FUNCTION "public"."generate_shop_final_on_ship"();



CREATE OR REPLACE TRIGGER "trg_kiosk_command_broadcast" AFTER INSERT ON "public"."kiosk_commands" FOR EACH ROW WHEN (("new"."status" = 'pending'::"text")) EXECUTE FUNCTION "public"."kiosk_command_broadcast"();



CREATE OR REPLACE TRIGGER "trg_kiosk_devices_touch" BEFORE UPDATE ON "public"."kiosk_devices" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_message_templates_updated" BEFORE UPDATE ON "public"."message_templates" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_moto_purchase_mileage_floor" BEFORE INSERT OR UPDATE OF "mileage", "purchase_mileage" ON "public"."motorcycles" FOR EACH ROW EXECUTE FUNCTION "public"."trg_moto_purchase_mileage_floor"();



CREATE OR REPLACE TRIGGER "trg_normalize_registration_source" BEFORE INSERT OR UPDATE OF "registration_source" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."normalize_registration_source"();



CREATE OR REPLACE TRIGGER "trg_notify_booking_activated_email" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."status" = 'active'::"public"."booking_status") AND ("old"."status" = 'reserved'::"public"."booking_status"))) EXECUTE FUNCTION "public"."notify_booking_activated_email"();



CREATE OR REPLACE TRIGGER "trg_notify_booking_cancelled_email" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."status" = 'cancelled'::"public"."booking_status") AND ("old"."status" IS DISTINCT FROM 'cancelled'::"public"."booking_status"))) EXECUTE FUNCTION "public"."notify_booking_cancelled_email"();



CREATE OR REPLACE TRIGGER "trg_notify_booking_completed_email" AFTER UPDATE OF "status" ON "public"."bookings" FOR EACH ROW WHEN ((("new"."status" = 'completed'::"public"."booking_status") AND ("old"."status" = 'active'::"public"."booking_status"))) EXECUTE FUNCTION "public"."notify_booking_completed_email"();



CREATE OR REPLACE TRIGGER "trg_notify_door_codes" AFTER INSERT ON "public"."branch_door_codes" FOR EACH ROW WHEN (("new"."code_type" = 'motorcycle'::"text")) EXECUTE FUNCTION "public"."trg_notify_door_codes"();



CREATE OR REPLACE TRIGGER "trg_notify_sos_incident_email" AFTER INSERT ON "public"."sos_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."notify_sos_incident_email"();



CREATE OR REPLACE TRIGGER "trg_one_active_sos" BEFORE INSERT ON "public"."sos_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."check_one_active_sos"();



CREATE OR REPLACE TRIGGER "trg_payment_methods_updated" BEFORE UPDATE ON "public"."payment_methods" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_poi_catalog_updated" BEFORE UPDATE ON "public"."points_of_interest" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_poi_ratings_updated" BEFORE UPDATE ON "public"."poi_ratings" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_post_invoice_to_financial_event" AFTER INSERT ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."post_invoice_to_financial_event"();



CREATE OR REPLACE TRIGGER "trg_products_updated" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_push_on_admin_message" AFTER INSERT ON "public"."admin_messages" FOR EACH ROW EXECUTE FUNCTION "public"."trg_push_on_admin_message"();



CREATE OR REPLACE TRIGGER "trg_regen_codes_on_moto_change" AFTER UPDATE OF "moto_id" ON "public"."bookings" FOR EACH ROW WHEN ((("old"."moto_id" IS DISTINCT FROM "new"."moto_id") AND ("new"."status" = ANY (ARRAY['active'::"public"."booking_status", 'reserved'::"public"."booking_status"])))) EXECUTE FUNCTION "public"."regen_door_codes_on_moto_change"();



CREATE OR REPLACE TRIGGER "trg_release_codes_on_doc_upload" AFTER INSERT ON "public"."documents" FOR EACH ROW WHEN (("new"."type" = ANY (ARRAY['id_card'::"text", 'passport'::"text", 'drivers_license'::"text", 'id_photo'::"text", 'license_photo'::"text"]))) EXECUTE FUNCTION "public"."release_withheld_door_codes"();



CREATE OR REPLACE TRIGGER "trg_release_codes_on_profile_verify" AFTER UPDATE OF "id_verified_at", "passport_verified_at", "license_verified_at", "id_number", "license_number" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."release_codes_on_profile_verify"();



CREATE OR REPLACE TRIGGER "trg_release_swap_next_codes" AFTER UPDATE OF "status", "returned_at" ON "public"."bookings" FOR EACH ROW WHEN (((("new"."status" = 'completed'::"public"."booking_status") OR ("new"."returned_at" IS NOT NULL)) AND (("old"."status" IS DISTINCT FROM "new"."status") OR ("old"."returned_at" IS DISTINCT FROM "new"."returned_at")))) EXECUTE FUNCTION "public"."release_swap_next_codes"();



CREATE OR REPLACE TRIGGER "trg_restore_vouchers_on_cancel" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."restore_vouchers_on_cancel"();



CREATE OR REPLACE TRIGGER "trg_route_pois_updated" BEFORE UPDATE ON "public"."route_pois" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_route_reviews_updated" BEFORE UPDATE ON "public"."route_reviews" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_routes_set_countries" BEFORE INSERT OR UPDATE OF "waypoints", "geometry", "countries" ON "public"."routes" FOR EACH ROW EXECUTE FUNCTION "public"."routes_set_countries"();



CREATE OR REPLACE TRIGGER "trg_routes_updated" BEFORE UPDATE ON "public"."routes" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_send_booking_completed_email" AFTER INSERT ON "public"."invoices" FOR EACH ROW WHEN (("new"."type" = 'final'::"text")) EXECUTE FUNCTION "public"."trg_send_booking_completed_email"();



CREATE OR REPLACE TRIGGER "trg_service_orders_updated" BEFORE UPDATE ON "public"."service_orders" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_service_parts_updated" BEFORE UPDATE ON "public"."service_parts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_set_promo_code_source" BEFORE INSERT ON "public"."promo_codes" FOR EACH ROW EXECUTE FUNCTION "public"."set_promo_code_source"();



CREATE OR REPLACE TRIGGER "trg_shop_order_confirmed_email" AFTER UPDATE OF "payment_status" ON "public"."shop_orders" FOR EACH ROW EXECUTE FUNCTION "public"."trg_send_shop_order_confirmed_email"();



CREATE OR REPLACE TRIGGER "trg_shop_order_number" BEFORE INSERT ON "public"."shop_orders" FOR EACH ROW EXECUTE FUNCTION "public"."generate_shop_order_number"();



CREATE OR REPLACE TRIGGER "trg_shop_orders_updated" BEFORE UPDATE ON "public"."shop_orders" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_slevomat_auto_apply" AFTER INSERT OR UPDATE OF "status" ON "public"."vouchers" FOR EACH ROW EXECUTE FUNCTION "public"."slevomat_auto_apply_on_redeem"();



CREATE OR REPLACE TRIGGER "trg_sos_auto_severity" BEFORE INSERT ON "public"."sos_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."sos_auto_severity"();



CREATE OR REPLACE TRIGGER "trg_sos_auto_timeline" AFTER INSERT ON "public"."sos_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."sos_auto_timeline"();



CREATE OR REPLACE TRIGGER "trg_sos_incidents_updated" BEFORE UPDATE ON "public"."sos_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_sos_notify_user" AFTER INSERT ON "public"."sos_incidents" FOR EACH ROW EXECUTE FUNCTION "public"."sos_notify_user_on_create"();



CREATE OR REPLACE TRIGGER "trg_suppliers_updated" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_sync_cms_flat_to_nested" AFTER INSERT OR UPDATE ON "public"."cms_variables" FOR EACH ROW WHEN (("new"."key" = ANY (ARRAY['web.pujcovna.h1'::"text", 'web.pujcovna.intro'::"text", 'web.pujcovna.ben.bottom'::"text", 'web.pujcovna.ben.3'::"text", 'web.pujcovna.ben.4'::"text", 'web.pujcovna.ben.6'::"text", 'web.pujcovna.step.1'::"text", 'web.pujcovna.step.2'::"text", 'web.pujcovna.step.3'::"text", 'web.pujcovna.step.4'::"text", 'web.pujcovna.step.5'::"text", 'web.pujcovna.step.6'::"text", 'web.pujcovna.step.7'::"text", 'web.pujcovna.step.8'::"text", 'web.kontakt.hours'::"text", 'web.kontakt.seo'::"text"]))) EXECUTE FUNCTION "public"."sync_cms_flat_to_nested"();



CREATE OR REPLACE TRIGGER "trg_sync_generated_doc_to_documents" AFTER INSERT ON "public"."generated_documents" FOR EACH ROW EXECUTE FUNCTION "public"."sync_generated_doc_to_documents"();



CREATE OR REPLACE TRIGGER "trg_sync_invoice_pdf_update" AFTER UPDATE OF "pdf_path" ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."sync_invoice_pdf_update"();



CREATE OR REPLACE TRIGGER "trg_sync_invoice_to_documents" AFTER INSERT ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."sync_invoice_to_documents"();



CREATE OR REPLACE TRIGGER "trg_sync_moto_day_prices" AFTER INSERT OR UPDATE ON "public"."moto_day_prices" FOR EACH ROW EXECUTE FUNCTION "public"."sync_moto_day_prices_to_motorcycles"();



CREATE OR REPLACE TRIGGER "trg_sync_moto_to_assets" AFTER INSERT OR UPDATE ON "public"."motorcycles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_motorcycle_to_assets"();



CREATE OR REPLACE TRIGGER "trg_track_booking_content_changes" BEFORE UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."track_booking_content_changes"();



CREATE OR REPLACE TRIGGER "trg_user_pois_updated" BEFORE UPDATE ON "public"."user_pois" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_user_saved_routes_updated" BEFORE UPDATE ON "public"."user_saved_routes" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_validate_app_loyalty" BEFORE INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."validate_app_loyalty_discount"();



CREATE OR REPLACE TRIGGER "trg_validate_late_pickup" BEFORE INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."validate_late_pickup_discount"();



CREATE OR REPLACE TRIGGER "trg_vouchers_updated" BEFORE UPDATE ON "public"."vouchers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_withhold_swap_next_codes" BEFORE INSERT ON "public"."branch_door_codes" FOR EACH ROW EXECUTE FUNCTION "public"."withhold_swap_next_codes"();



ALTER TABLE ONLY "public"."acc_depreciation_entries"
    ADD CONSTRAINT "acc_depreciation_entries_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "public"."acc_long_term_assets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."acc_liabilities"
    ADD CONSTRAINT "acc_liabilities_financial_event_id_fkey" FOREIGN KEY ("financial_event_id") REFERENCES "public"."financial_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."acc_long_term_assets"
    ADD CONSTRAINT "acc_long_term_assets_motorcycle_id_fkey" FOREIGN KEY ("motorcycle_id") REFERENCES "public"."motorcycles"("id");



ALTER TABLE ONLY "public"."acc_payrolls"
    ADD CONSTRAINT "acc_payrolls_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."acc_employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."accounting_entries"
    ADD CONSTRAINT "accounting_entries_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."accounting_exceptions"
    ADD CONSTRAINT "accounting_exceptions_financial_event_id_fkey" FOREIGN KEY ("financial_event_id") REFERENCES "public"."financial_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."admin_messages"
    ADD CONSTRAINT "admin_messages_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_messages"
    ADD CONSTRAINT "admin_messages_incident_id_fkey" FOREIGN KEY ("incident_id") REFERENCES "public"."sos_incidents"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_messages"
    ADD CONSTRAINT "admin_messages_sent_by_fkey" FOREIGN KEY ("sent_by") REFERENCES "public"."admin_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."admin_messages"
    ADD CONSTRAINT "admin_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."admin_users"
    ADD CONSTRAINT "admin_users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_actions"
    ADD CONSTRAINT "ai_actions_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ai_actions"
    ADD CONSTRAINT "ai_actions_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."ai_conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_citations"
    ADD CONSTRAINT "ai_citations_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ai_customer_conversations"
    ADD CONSTRAINT "ai_customer_conversations_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ai_customer_conversations"
    ADD CONSTRAINT "ai_customer_conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ai_public_conversations"
    ADD CONSTRAINT "ai_public_conversations_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ai_traffic_log"
    ADD CONSTRAINT "ai_traffic_log_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."ai_traffic_log"
    ADD CONSTRAINT "ai_traffic_log_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."api_keys"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_crash_reports"
    ADD CONSTRAINT "app_crash_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_debug_logs"
    ADD CONSTRAINT "app_debug_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_installations"
    ADD CONSTRAINT "app_installations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."approval_queue"
    ADD CONSTRAINT "approval_queue_financial_event_id_fkey" FOREIGN KEY ("financial_event_id") REFERENCES "public"."financial_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."auto_order_rules"
    ADD CONSTRAINT "auto_order_rules_inventory_item_id_fkey" FOREIGN KEY ("inventory_item_id") REFERENCES "public"."inventory"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."auto_order_rules"
    ADD CONSTRAINT "auto_order_rules_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_cancellations"
    ADD CONSTRAINT "booking_cancellations_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_complaints"
    ADD CONSTRAINT "booking_complaints_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_complaints"
    ADD CONSTRAINT "booking_complaints_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."booking_complaints"
    ADD CONSTRAINT "booking_complaints_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."booking_discounts"
    ADD CONSTRAINT "booking_discounts_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_discounts"
    ADD CONSTRAINT "booking_discounts_promo_code_id_fkey" FOREIGN KEY ("promo_code_id") REFERENCES "public"."promo_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."booking_discounts"
    ADD CONSTRAINT "booking_discounts_voucher_id_fkey" FOREIGN KEY ("voucher_id") REFERENCES "public"."vouchers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."booking_extras"
    ADD CONSTRAINT "booking_extras_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_extras"
    ADD CONSTRAINT "booking_extras_extra_id_fkey" FOREIGN KEY ("extra_id") REFERENCES "public"."extras_catalog"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_continues_booking_id_fkey" FOREIGN KEY ("continues_booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_extends_booking_id_fkey" FOREIGN KEY ("extends_booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_promo_code_id_fkey" FOREIGN KEY ("promo_code_id") REFERENCES "public"."promo_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_trailer_moto_id_fkey" FOREIGN KEY ("trailer_moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_voucher_id_fkey" FOREIGN KEY ("voucher_id") REFERENCES "public"."vouchers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_accessories"
    ADD CONSTRAINT "branch_accessories_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_cameras"
    ADD CONSTRAINT "branch_cameras_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_door_codes"
    ADD CONSTRAINT "branch_door_codes_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_door_codes"
    ADD CONSTRAINT "branch_door_codes_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_door_codes"
    ADD CONSTRAINT "branch_door_codes_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_door_events"
    ADD CONSTRAINT "branch_door_events_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_door_events"
    ADD CONSTRAINT "branch_door_events_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."kiosk_devices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_door_events"
    ADD CONSTRAINT "branch_door_events_door_id_fkey" FOREIGN KEY ("door_id") REFERENCES "public"."branch_doors"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_doors"
    ADD CONSTRAINT "branch_doors_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_kiosk_config"
    ADD CONSTRAINT "branch_kiosk_config_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_performance"
    ADD CONSTRAINT "branch_performance_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_power_status"
    ADD CONSTRAINT "branch_power_status_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."branch_service_codes"
    ADD CONSTRAINT "branch_service_codes_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."broadcast_campaigns"
    ADD CONSTRAINT "broadcast_campaigns_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."message_templates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contracts"
    ADD CONSTRAINT "contracts_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."acc_employees"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contracts"
    ADD CONSTRAINT "contracts_financial_event_id_fkey" FOREIGN KEY ("financial_event_id") REFERENCES "public"."financial_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."custom_documents"
    ADD CONSTRAINT "custom_documents_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."admin_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."daily_stats"
    ADD CONSTRAINT "daily_stats_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."delivery_notes"
    ADD CONSTRAINT "delivery_notes_financial_event_id_fkey" FOREIGN KEY ("financial_event_id") REFERENCES "public"."financial_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."delivery_notes"
    ADD CONSTRAINT "delivery_notes_matched_invoice_id_fkey" FOREIGN KEY ("matched_invoice_id") REFERENCES "public"."invoices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."documents"
    ADD CONSTRAINT "documents_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."documents"
    ADD CONSTRAINT "documents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."email_templates"
    ADD CONSTRAINT "email_templates_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."admin_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."emp_attendance"
    ADD CONSTRAINT "emp_attendance_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."acc_employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emp_documents"
    ADD CONSTRAINT "emp_documents_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."acc_employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emp_shifts"
    ADD CONSTRAINT "emp_shifts_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."emp_shifts"
    ADD CONSTRAINT "emp_shifts_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."acc_employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emp_vacations"
    ADD CONSTRAINT "emp_vacations_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."admin_users"("id");



ALTER TABLE ONLY "public"."emp_vacations"
    ADD CONSTRAINT "emp_vacations_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."acc_employees"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."extras_catalog"
    ADD CONSTRAINT "extras_catalog_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."flexi_sync_log"
    ADD CONSTRAINT "flexi_sync_log_financial_event_id_fkey" FOREIGN KEY ("financial_event_id") REFERENCES "public"."financial_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gear_shortages"
    ADD CONSTRAINT "gear_shortages_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gear_shortages"
    ADD CONSTRAINT "gear_shortages_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."gear_shortages"
    ADD CONSTRAINT "gear_shortages_transfer_from_branch_id_fkey" FOREIGN KEY ("transfer_from_branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."generated_documents"
    ADD CONSTRAINT "generated_documents_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."generated_documents"
    ADD CONSTRAINT "generated_documents_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_from_branch_fkey" FOREIGN KEY ("from_branch") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_inventory_id_fkey" FOREIGN KEY ("inventory_id") REFERENCES "public"."inventory"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_to_branch_fkey" FOREIGN KEY ("to_branch") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_matched_delivery_note_id_fkey" FOREIGN KEY ("matched_delivery_note_id") REFERENCES "public"."delivery_notes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."shop_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_original_invoice_id_fkey" FOREIGN KEY ("original_invoice_id") REFERENCES "public"."invoices"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."kiosk_commands"
    ADD CONSTRAINT "kiosk_commands_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."kiosk_commands"
    ADD CONSTRAINT "kiosk_commands_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."kiosk_devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kiosk_devices"
    ADD CONSTRAINT "kiosk_devices_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."kiosk_logs"
    ADD CONSTRAINT "kiosk_logs_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."kiosk_logs"
    ADD CONSTRAINT "kiosk_logs_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "public"."kiosk_devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."loyalty_monthly_winners"
    ADD CONSTRAINT "loyalty_monthly_winners_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."maintenance_log"
    ADD CONSTRAINT "maintenance_log_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."maintenance_log"
    ADD CONSTRAINT "maintenance_log_replacement_moto_id_fkey" FOREIGN KEY ("replacement_moto_id") REFERENCES "public"."motorcycles"("id");



ALTER TABLE ONLY "public"."maintenance_log"
    ADD CONSTRAINT "maintenance_log_sos_incident_id_fkey" FOREIGN KEY ("sos_incident_id") REFERENCES "public"."sos_incidents"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."maintenance_log"
    ADD CONSTRAINT "maintenance_log_technician_id_fkey" FOREIGN KEY ("technician_id") REFERENCES "public"."acc_employees"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."maintenance_schedules"
    ADD CONSTRAINT "maintenance_schedules_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."message_log"
    ADD CONSTRAINT "message_log_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."message_log"
    ADD CONSTRAINT "message_log_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."message_threads"
    ADD CONSTRAINT "message_threads_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_ai_approved_by_fkey" FOREIGN KEY ("ai_approved_by") REFERENCES "public"."admin_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_ai_sent_message_id_fkey" FOREIGN KEY ("ai_sent_message_id") REFERENCES "public"."messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."message_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moto_day_prices"
    ADD CONSTRAINT "moto_day_prices_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moto_locations"
    ADD CONSTRAINT "moto_locations_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moto_performance"
    ADD CONSTRAINT "moto_performance_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."motorcycles"
    ADD CONSTRAINT "motorcycles_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notification_log"
    ADD CONSTRAINT "notification_log_rule_id_fkey" FOREIGN KEY ("rule_id") REFERENCES "public"."notification_rules"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payment_methods"
    ADD CONSTRAINT "payment_methods_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_poi_id_fkey" FOREIGN KEY ("poi_id") REFERENCES "public"."points_of_interest"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_route_poi_id_fkey" FOREIGN KEY ("route_poi_id") REFERENCES "public"."route_pois"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."poi_ratings"
    ADD CONSTRAINT "poi_ratings_user_poi_id_fkey" FOREIGN KEY ("user_poi_id") REFERENCES "public"."user_pois"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pricing_rules"
    ADD CONSTRAINT "pricing_rules_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_preferred_branch_fkey" FOREIGN KEY ("preferred_branch") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."promo_code_usage"
    ADD CONSTRAINT "promo_code_usage_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."promo_code_usage"
    ADD CONSTRAINT "promo_code_usage_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."promo_code_usage"
    ADD CONSTRAINT "promo_code_usage_promo_code_id_fkey" FOREIGN KEY ("promo_code_id") REFERENCES "public"."promo_codes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_inventory_id_fkey" FOREIGN KEY ("inventory_id") REFERENCES "public"."inventory"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reviews"
    ADD CONSTRAINT "reviews_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_pois"
    ADD CONSTRAINT "route_pois_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_reviews"
    ADD CONSTRAINT "route_reviews_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."routes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_reviews"
    ADD CONSTRAINT "route_reviews_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."routes"
    ADD CONSTRAINT "routes_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."routes"
    ADD CONSTRAINT "routes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sent_emails"
    ADD CONSTRAINT "sent_emails_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sent_emails"
    ADD CONSTRAINT "sent_emails_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_maintenance_log_id_fkey" FOREIGN KEY ("maintenance_log_id") REFERENCES "public"."maintenance_log"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_orders"
    ADD CONSTRAINT "service_orders_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."service_parts"
    ADD CONSTRAINT "service_parts_inventory_item_id_fkey" FOREIGN KEY ("inventory_item_id") REFERENCES "public"."inventory"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."service_parts"
    ADD CONSTRAINT "service_parts_schedule_id_fkey" FOREIGN KEY ("schedule_id") REFERENCES "public"."maintenance_schedules"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_order_items"
    ADD CONSTRAINT "shop_order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."shop_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shop_order_items"
    ADD CONSTRAINT "shop_order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."shop_orders"
    ADD CONSTRAINT "shop_orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."shop_orders"
    ADD CONSTRAINT "shop_orders_promo_code_id_fkey" FOREIGN KEY ("promo_code_id") REFERENCES "public"."promo_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sos_incidents"
    ADD CONSTRAINT "sos_incidents_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sos_incidents"
    ADD CONSTRAINT "sos_incidents_moto_id_fkey" FOREIGN KEY ("moto_id") REFERENCES "public"."motorcycles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sos_incidents"
    ADD CONSTRAINT "sos_incidents_replacement_moto_id_fkey" FOREIGN KEY ("replacement_moto_id") REFERENCES "public"."motorcycles"("id");



ALTER TABLE ONLY "public"."sos_incidents"
    ADD CONSTRAINT "sos_incidents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sos_timeline"
    ADD CONSTRAINT "sos_timeline_incident_id_fkey" FOREIGN KEY ("incident_id") REFERENCES "public"."sos_incidents"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stock_receipts"
    ADD CONSTRAINT "stock_receipts_matched_receipt_id_fkey" FOREIGN KEY ("matched_receipt_id") REFERENCES "public"."stock_receipts"("id");



ALTER TABLE ONLY "public"."user_pois"
    ADD CONSTRAINT "user_pois_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_saved_routes"
    ADD CONSTRAINT "user_saved_routes_source_route_id_fkey" FOREIGN KEY ("source_route_id") REFERENCES "public"."routes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_saved_routes"
    ADD CONSTRAINT "user_saved_routes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "user_visited_places_poi_id_fkey" FOREIGN KEY ("poi_id") REFERENCES "public"."points_of_interest"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "user_visited_places_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "public"."routes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "user_visited_places_route_poi_id_fkey" FOREIGN KEY ("route_poi_id") REFERENCES "public"."route_pois"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "user_visited_places_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_visited_places"
    ADD CONSTRAINT "user_visited_places_user_poi_id_fkey" FOREIGN KEY ("user_poi_id") REFERENCES "public"."user_pois"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_buyer_id_fkey" FOREIGN KEY ("buyer_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."admin_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."shop_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vouchers"
    ADD CONSTRAINT "vouchers_redeemed_by_fkey" FOREIGN KEY ("redeemed_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



CREATE POLICY "Admin all" ON "public"."ai_public_conversations" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "Admin can view own record" ON "public"."admin_users" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Admin full access" ON "public"."accessory_types" USING ("public"."is_admin"());



CREATE POLICY "Admin full access" ON "public"."branch_accessories" USING ("public"."is_admin"());



CREATE POLICY "Admin full access" ON "public"."branch_door_codes" USING ("public"."is_admin"());



CREATE POLICY "Admin full access" ON "public"."emp_attendance" USING ("public"."is_admin"());



CREATE POLICY "Admin full access" ON "public"."emp_documents" USING ("public"."is_admin"());



CREATE POLICY "Admin full access" ON "public"."emp_shifts" USING ("public"."is_admin"());



CREATE POLICY "Admin full access" ON "public"."emp_vacations" USING ("public"."is_admin"());



CREATE POLICY "Admin full access booking_complaints" ON "public"."booking_complaints" USING (true);



CREATE POLICY "Admin full access contracts" ON "public"."contracts" USING ("public"."is_admin"());



CREATE POLICY "Admin full access delivery_notes" ON "public"."delivery_notes" USING ("public"."is_admin"());



CREATE POLICY "Admin full access extras_catalog" ON "public"."extras_catalog" USING ("public"."is_admin"());



CREATE POLICY "Admin full access on ai_citations" ON "public"."ai_citations" USING ("public"."is_admin"());



CREATE POLICY "Admin full access on api_keys" ON "public"."api_keys" USING ("public"."is_admin"());



CREATE POLICY "Admin read ai_traffic_log" ON "public"."ai_traffic_log" FOR SELECT USING ("public"."is_admin"());



CREATE POLICY "Admin write" ON "public"."loyalty_levels" USING ("public"."is_admin"());



CREATE POLICY "Admin write" ON "public"."loyalty_monthly_winners" USING ("public"."is_admin"());



CREATE POLICY "Admins can delete bookings" ON "public"."bookings" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can insert SOS timeline" ON "public"."sos_timeline" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can insert bookings" ON "public"."bookings" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Admins can manage AI actions" ON "public"."ai_actions" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage AI conversations" ON "public"."ai_conversations" USING ((("auth"."uid"() = "admin_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = 'superadmin'::"public"."admin_role"))))));



CREATE POLICY "Admins can manage CMS pages" ON "public"."cms_pages" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage CMS variables" ON "public"."cms_variables" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage accounting entries" ON "public"."accounting_entries" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("accounting_entries"."branch_id" = ANY ("admin_users"."branch_access")))))));



CREATE POLICY "Admins can manage all admin messages" ON "public"."admin_messages" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage automation rules" ON "public"."automation_rules" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage booking extras" ON "public"."booking_extras" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage branches" ON "public"."branches" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = 'superadmin'::"public"."admin_role")))));



CREATE POLICY "Admins can manage daily stats" ON "public"."daily_stats" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("daily_stats"."branch_id" = ANY ("admin_users"."branch_access")))))));



CREATE POLICY "Admins can manage extras catalog" ON "public"."extras_catalog" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("extras_catalog"."branch_id" = ANY ("admin_users"."branch_access")))))));



CREATE POLICY "Admins can manage feature flags" ON "public"."feature_flags" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = 'superadmin'::"public"."admin_role")))));



CREATE POLICY "Admins can manage generated documents" ON "public"."generated_documents" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage inventory" ON "public"."inventory" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("inventory"."branch_id" = ANY ("admin_users"."branch_access")))))));



CREATE POLICY "Admins can manage inventory movements" ON "public"."inventory_movements" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage invoices" ON "public"."invoices" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage maintenance log" ON "public"."maintenance_log" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage maintenance schedules" ON "public"."maintenance_schedules" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage message threads" ON "public"."message_threads" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage motorcycles" ON "public"."motorcycles" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("motorcycles"."branch_id" = ANY ("admin_users"."branch_access")))))));



CREATE POLICY "Admins can manage notification log" ON "public"."notification_log" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage notification rules" ON "public"."notification_rules" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage pricing rules" ON "public"."pricing_rules" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage purchase order items" ON "public"."purchase_order_items" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can manage purchase orders" ON "public"."purchase_orders" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role", 'operator'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage reviews" ON "public"."reviews" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can manage suppliers" ON "public"."suppliers" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role", 'operator'::"public"."admin_role"]))))));



CREATE POLICY "Admins can view AI logs" ON "public"."ai_logs" FOR SELECT USING ((("auth"."uid"() = "admin_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = 'superadmin'::"public"."admin_role"))))));



CREATE POLICY "Admins can view admin users" ON "public"."admin_users" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users" "au"
  WHERE (("au"."id" = "auth"."uid"()) AND ("au"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Admins can view audit log" ON "public"."admin_audit_log" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users" "au"
  WHERE ("au"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can view branch performance" ON "public"."branch_performance" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("branch_performance"."branch_id" = ANY ("admin_users"."branch_access")))))));



CREATE POLICY "Admins can view moto performance" ON "public"."moto_performance" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "Admins can view predictions" ON "public"."predictions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND ("admin_users"."role" = ANY (ARRAY['superadmin'::"public"."admin_role", 'manager'::"public"."admin_role"]))))));



CREATE POLICY "Anyone and admins can view reviews" ON "public"."reviews" FOR SELECT USING (true);



CREATE POLICY "Anyone can view CMS variables" ON "public"."cms_variables" FOR SELECT USING (true);



CREATE POLICY "Anyone can view branches with admin write" ON "public"."branches" FOR SELECT USING (true);



CREATE POLICY "Anyone can view extras catalog" ON "public"."extras_catalog" FOR SELECT USING (true);



CREATE POLICY "Anyone can view feature flags" ON "public"."feature_flags" FOR SELECT USING (true);



CREATE POLICY "Anyone can view message templates" ON "public"."message_templates" FOR SELECT USING (true);



CREATE POLICY "Anyone can view motorcycles with admin write" ON "public"."motorcycles" FOR SELECT USING (true);



CREATE POLICY "Anyone can view pricing rules" ON "public"."pricing_rules" FOR SELECT USING (true);



CREATE POLICY "Anyone can view published CMS pages" ON "public"."cms_pages" FOR SELECT USING (("published" = true));



CREATE POLICY "Authenticated users can create bookings" ON "public"."bookings" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Authenticated users can create reviews" ON "public"."reviews" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Customer read own codes" ON "public"."branch_door_codes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."bookings"
  WHERE (("bookings"."id" = "branch_door_codes"."booking_id") AND ("bookings"."user_id" = "auth"."uid"())))));



CREATE POLICY "Public read" ON "public"."accessory_types" FOR SELECT USING (true);



CREATE POLICY "Public read" ON "public"."loyalty_levels" FOR SELECT USING (true);



CREATE POLICY "Public read" ON "public"."loyalty_monthly_winners" FOR SELECT USING (true);



CREATE POLICY "Public read extras_catalog" ON "public"."extras_catalog" FOR SELECT USING (true);



CREATE POLICY "Public read non-secret" ON "public"."app_settings" FOR SELECT USING (("key" <> ALL (ARRAY['service_role_key'::"text", 'cms_admin_token'::"text"])));



CREATE POLICY "Service role insert ai_traffic_log" ON "public"."ai_traffic_log" FOR INSERT WITH CHECK (true);



CREATE POLICY "Service update" ON "public"."ai_public_conversations" FOR UPDATE USING (true) WITH CHECK (true);



CREATE POLICY "Service write" ON "public"."ai_public_conversations" FOR INSERT WITH CHECK (true);



CREATE POLICY "Superadmin can manage admin users" ON "public"."admin_users" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users" "au"
  WHERE (("au"."id" = "auth"."uid"()) AND ("au"."role" = 'superadmin'::"public"."admin_role")))));



CREATE POLICY "Users and admins can send messages" ON "public"."messages" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."message_threads"
  WHERE (("message_threads"."id" = "messages"."thread_id") AND ("message_threads"."customer_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Users and admins can update bookings" ON "public"."bookings" FOR UPDATE USING (((("auth"."uid"() = "user_id") AND ("status" = ANY (ARRAY['pending'::"public"."booking_status", 'active'::"public"."booking_status"]))) OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("bookings"."branch_id" = ANY ("admin_users"."branch_access"))))))));



CREATE POLICY "Users and admins can upload documents" ON "public"."documents" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Users and admins can view SOS incidents" ON "public"."sos_incidents" USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR (EXISTS ( SELECT 1
           FROM ("public"."bookings" "b2"
             JOIN "public"."admin_users" "au" ON (("au"."id" = "auth"."uid"())))
          WHERE (("b2"."id" = "sos_incidents"."booking_id") AND ("b2"."branch_id" = ANY ("au"."branch_access")))))))))));



CREATE POLICY "Users and admins can view SOS timeline" ON "public"."sos_timeline" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."sos_incidents"
  WHERE (("sos_incidents"."id" = "sos_timeline"."incident_id") AND ("sos_incidents"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Users and admins can view bookings" ON "public"."bookings" FOR SELECT USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR ("bookings"."branch_id" = ANY ("admin_users"."branch_access"))))))));



CREATE POLICY "Users and admins can view documents" ON "public"."documents" FOR SELECT USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE (("admin_users"."id" = "auth"."uid"()) AND (("admin_users"."role" = 'superadmin'::"public"."admin_role") OR (EXISTS ( SELECT 1
           FROM ("public"."bookings" "b2"
             JOIN "public"."admin_users" "au" ON (("au"."id" = "auth"."uid"())))
          WHERE (("b2"."id" = "documents"."booking_id") AND ("b2"."branch_id" = ANY ("au"."branch_access")))))))))));



CREATE POLICY "Users and admins can view generated documents" ON "public"."generated_documents" FOR SELECT USING ((("auth"."uid"() = "customer_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Users and admins can view message threads" ON "public"."message_threads" FOR SELECT USING ((("auth"."uid"() = "customer_id") OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Users and admins can view messages" ON "public"."messages" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."message_threads"
  WHERE (("message_threads"."id" = "messages"."thread_id") AND ("message_threads"."customer_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"())))));



CREATE POLICY "Users can create message threads" ON "public"."message_threads" FOR INSERT WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Users can create own booking extras" ON "public"."booking_extras" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."bookings"
  WHERE (("bookings"."id" = "booking_extras"."booking_id") AND ("bookings"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can mark own messages as read" ON "public"."admin_messages" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read own messages" ON "public"."admin_messages" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can update own message read status" ON "public"."admin_messages" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view own admin messages" ON "public"."admin_messages" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own booking extras" ON "public"."booking_extras" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."bookings"
  WHERE (("bookings"."id" = "booking_extras"."booking_id") AND ("bookings"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view own invoices" ON "public"."invoices" FOR SELECT USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Users manage own push tokens" ON "public"."push_tokens" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."acc_depreciation_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_employees" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_liabilities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_long_term_assets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_payrolls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_short_term_assets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_tax_returns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."acc_vat_returns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."accessory_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."accounting_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."accounting_exceptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_acc_depreciation_entries" ON "public"."acc_depreciation_entries" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_employees" ON "public"."acc_employees" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_exceptions" ON "public"."accounting_exceptions" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_liabilities" ON "public"."acc_liabilities" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_long_term_assets" ON "public"."acc_long_term_assets" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_payrolls" ON "public"."acc_payrolls" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_short_term_assets" ON "public"."acc_short_term_assets" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_tax_returns" ON "public"."acc_tax_returns" USING ("public"."is_admin"());



CREATE POLICY "admin_acc_vat_returns" ON "public"."acc_vat_returns" USING ("public"."is_admin"());



CREATE POLICY "admin_all" ON "public"."ai_customer_conversations" USING ("public"."is_admin"());



CREATE POLICY "admin_all_service_parts" ON "public"."service_parts" USING ("public"."is_admin"());



CREATE POLICY "admin_app_settings" ON "public"."app_settings" USING ("public"."is_admin"());



CREATE POLICY "admin_approval_queue" ON "public"."approval_queue" USING ("public"."is_admin"());



ALTER TABLE "public"."admin_audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_cash_register" ON "public"."cash_register" USING ("public"."is_admin"());



CREATE POLICY "admin_financial_events" ON "public"."financial_events" USING ("public"."is_admin"());



CREATE POLICY "admin_flexi_reports" ON "public"."flexi_reports" USING ("public"."is_admin"());



CREATE POLICY "admin_flexi_sync_log" ON "public"."flexi_sync_log" USING ("public"."is_admin"());



CREATE POLICY "admin_full_access_auto_order_rules" ON "public"."auto_order_rules" USING ("public"."is_admin"());



ALTER TABLE "public"."admin_messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_messages_admin_all" ON "public"."admin_messages" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "admin_messages_admin_insert" ON "public"."admin_messages" FOR INSERT WITH CHECK ("public"."is_admin"());



CREATE POLICY "admin_messages_user_select" ON "public"."admin_messages" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "admin_messages_user_update" ON "public"."admin_messages" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "admin_tax_records" ON "public"."tax_records" USING ("public"."is_admin"());



CREATE POLICY "admin_users_read" ON "public"."admin_users" FOR SELECT USING ("public"."is_admin"());



CREATE POLICY "admin_users_write" ON "public"."admin_users" USING ("public"."is_superadmin"()) WITH CHECK ("public"."is_superadmin"());



ALTER TABLE "public"."ai_actions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ai_actions_admin_all" ON "public"."ai_actions" USING ("public"."is_admin"());



ALTER TABLE "public"."ai_citations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_conversations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ai_conversations_admin_all" ON "public"."ai_conversations" USING ("public"."is_admin"());



CREATE POLICY "ai_conversations_own" ON "public"."ai_conversations" USING ((("admin_id" = "auth"."uid"()) OR "public"."is_superadmin"())) WITH CHECK (("admin_id" = "auth"."uid"()));



ALTER TABLE "public"."ai_customer_conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ai_logs_admin_all" ON "public"."ai_logs" USING ("public"."is_admin"());



ALTER TABLE "public"."ai_public_conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ai_traffic_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."api_keys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_crash_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_debug_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_installations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_installations_admin_read" ON "public"."app_installations" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "app_installations_owner_rw" ON "public"."app_installations" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."app_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "app_settings_admin" ON "public"."app_settings" USING ("public"."is_admin"());



ALTER TABLE "public"."approval_queue" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_log_delete" ON "public"."admin_audit_log" FOR DELETE USING ("public"."is_superadmin"());



CREATE POLICY "audit_log_insert" ON "public"."admin_audit_log" FOR INSERT WITH CHECK ("public"."is_admin"());



CREATE POLICY "audit_log_modify" ON "public"."admin_audit_log" FOR UPDATE USING ("public"."is_superadmin"());



CREATE POLICY "audit_log_read" ON "public"."admin_audit_log" FOR SELECT USING ("public"."is_admin"());



ALTER TABLE "public"."auto_order_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."automation_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_cancellations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "booking_cancellations_admin" ON "public"."booking_cancellations" USING ("public"."is_admin"());



CREATE POLICY "booking_cancellations_customer_read" ON "public"."booking_cancellations" FOR SELECT USING (("cancelled_by" = "auth"."uid"()));



ALTER TABLE "public"."booking_complaints" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_extras" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bookings_admin_delete" ON "public"."bookings" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "bookings_anon_pending_realtime" ON "public"."bookings" FOR SELECT TO "anon" USING ((("booking_source" = 'web'::"text") AND ("status" = 'pending'::"public"."booking_status") AND ("payment_status" = 'unpaid'::"public"."payment_status") AND ("created_at" > ("now"() - '04:00:00'::interval))));



CREATE POLICY "bookings_user_insert" ON "public"."bookings" FOR INSERT WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "bookings_user_select" ON "public"."bookings" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "bookings_user_update" ON "public"."bookings" FOR UPDATE USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."branch_accessories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branch_cameras" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branch_cameras_admin" ON "public"."branch_cameras" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."branch_door_codes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branch_door_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branch_door_events_admin" ON "public"."branch_door_events" FOR SELECT USING ("public"."is_admin"());



ALTER TABLE "public"."branch_doors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branch_doors_admin" ON "public"."branch_doors" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."branch_kiosk_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branch_kiosk_config_admin" ON "public"."branch_kiosk_config" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."branch_performance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branch_power_status" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branch_power_status_admin" ON "public"."branch_power_status" FOR SELECT USING ("public"."is_admin"());



ALTER TABLE "public"."branch_service_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branch_service_codes_admin" ON "public"."branch_service_codes" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."branches" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "branches_admin" ON "public"."branches" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "branches_public_read" ON "public"."branches" FOR SELECT USING (true);



ALTER TABLE "public"."broadcast_campaigns" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "broadcast_campaigns_admin" ON "public"."broadcast_campaigns" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."cash_register" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cms_pages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cms_variables" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contracts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "crash_reports_admin_all" ON "public"."app_crash_reports" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "crash_reports_insert_own" ON "public"."app_crash_reports" FOR INSERT WITH CHECK ((("user_id" IS NULL) OR ("user_id" = "auth"."uid"())));



ALTER TABLE "public"."custom_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "custom_documents_admin" ON "public"."custom_documents" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "custom_documents_public_read" ON "public"."custom_documents" FOR SELECT USING ((("active" = true) AND ("show_on_web" = true)));



CREATE POLICY "customer_delete_own" ON "public"."ai_customer_conversations" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "customer_delete_own_documents" ON "public"."documents" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "customer_delete_own_generated_docs" ON "public"."generated_documents" FOR DELETE USING (("customer_id" = "auth"."uid"()));



CREATE POLICY "customer_insert_own" ON "public"."ai_customer_conversations" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "customer_select_own" ON "public"."ai_customer_conversations" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "customer_update_own" ON "public"."ai_customer_conversations" FOR UPDATE USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."daily_stats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."debug_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "debug_log_admin" ON "public"."debug_log" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "debug_logs_admin_all" ON "public"."app_debug_logs" USING ((EXISTS ( SELECT 1
   FROM "public"."admin_users"
  WHERE ("admin_users"."id" = "auth"."uid"()))));



CREATE POLICY "debug_logs_insert_own" ON "public"."app_debug_logs" FOR INSERT WITH CHECK ((("user_id" IS NULL) OR ("user_id" = "auth"."uid"())));



ALTER TABLE "public"."delivery_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."document_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "document_templates_admin_delete" ON "public"."document_templates" FOR DELETE USING ("public"."is_admin"());



CREATE POLICY "document_templates_admin_update" ON "public"."document_templates" FOR UPDATE USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "document_templates_admin_write" ON "public"."document_templates" FOR INSERT WITH CHECK ("public"."is_admin"());



CREATE POLICY "document_templates_select" ON "public"."document_templates" FOR SELECT USING ((("active" = true) OR "public"."is_admin"()));



ALTER TABLE "public"."documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "documents_admin" ON "public"."documents" USING ("public"."is_admin"());



CREATE POLICY "documents_customer_insert" ON "public"."documents" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "documents_customer_read" ON "public"."documents" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "documents_user_insert" ON "public"."documents" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "documents_user_select" ON "public"."documents" FOR SELECT USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."email_send_locks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."email_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "email_templates_admin" ON "public"."email_templates" USING ("public"."is_admin"());



ALTER TABLE "public"."emp_attendance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emp_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emp_shifts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."emp_vacations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."extras_catalog" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "faq_admin_all" ON "public"."faq_items" USING ("public"."is_admin"());



ALTER TABLE "public"."faq_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "faq_public_select" ON "public"."faq_items" FOR SELECT USING (("published" = true));



ALTER TABLE "public"."feature_flags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."financial_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."flexi_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."flexi_sync_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gear_shortages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "gear_shortages_admin_all" ON "public"."gear_shortages" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."generated_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "generated_documents_admin" ON "public"."generated_documents" USING ("public"."is_admin"());



CREATE POLICY "generated_documents_customer_select" ON "public"."generated_documents" FOR SELECT USING (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."inventory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_movements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invoices_admin" ON "public"."invoices" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "invoices_customer_insert" ON "public"."invoices" FOR INSERT WITH CHECK (("customer_id" = "auth"."uid"()));



CREATE POLICY "invoices_customer_select" ON "public"."invoices" FOR SELECT USING (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."kiosk_commands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kiosk_commands_admin" ON "public"."kiosk_commands" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."kiosk_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kiosk_devices_admin" ON "public"."kiosk_devices" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."kiosk_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "kiosk_logs_admin" ON "public"."kiosk_logs" FOR SELECT USING ("public"."is_admin"());



ALTER TABLE "public"."loyalty_levels" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."loyalty_monthly_winners" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."maintenance_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maintenance_log_admin" ON "public"."maintenance_log" USING ("public"."is_admin"());



CREATE POLICY "maintenance_log_admin_all" ON "public"."maintenance_log" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "maintenance_log_public_read" ON "public"."maintenance_log" FOR SELECT USING (true);



ALTER TABLE "public"."maintenance_schedules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."message_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "message_log_admin" ON "public"."message_log" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "message_log_read" ON "public"."message_log" FOR SELECT USING ("public"."is_admin"());



ALTER TABLE "public"."message_templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "message_templates_read" ON "public"."message_templates" FOR SELECT USING (true);



CREATE POLICY "message_templates_write" ON "public"."message_templates" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."message_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "message_threads_admin" ON "public"."message_threads" USING ("public"."is_admin"());



CREATE POLICY "message_threads_customer_select" ON "public"."message_threads" FOR SELECT USING (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "messages_admin" ON "public"."messages" USING ("public"."is_admin"());



CREATE POLICY "messages_customer_insert" ON "public"."messages" FOR INSERT WITH CHECK ((("direction" = 'customer'::"text") AND ("thread_id" IN ( SELECT "message_threads"."id"
   FROM "public"."message_threads"
  WHERE ("message_threads"."customer_id" = "auth"."uid"())))));



CREATE POLICY "messages_customer_select" ON "public"."messages" FOR SELECT USING (("thread_id" IN ( SELECT "message_threads"."id"
   FROM "public"."message_threads"
  WHERE ("message_threads"."customer_id" = "auth"."uid"()))));



ALTER TABLE "public"."moto_day_prices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "moto_day_prices_admin" ON "public"."moto_day_prices" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "moto_day_prices_public_read" ON "public"."moto_day_prices" FOR SELECT USING (true);



ALTER TABLE "public"."moto_locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "moto_locations_admin" ON "public"."moto_locations" USING ("public"."is_admin"());



CREATE POLICY "moto_locations_read" ON "public"."moto_locations" FOR SELECT USING (true);



ALTER TABLE "public"."moto_performance" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."motorcycles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "motorcycles_admin_all" ON "public"."motorcycles" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "motorcycles_public_read" ON "public"."motorcycles" FOR SELECT USING (true);



ALTER TABLE "public"."notification_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payment_methods" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pm_admin_all" ON "public"."payment_methods" USING ("public"."is_admin"());



CREATE POLICY "pm_user_delete" ON "public"."payment_methods" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "pm_user_insert" ON "public"."payment_methods" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "pm_user_select" ON "public"."payment_methods" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "pm_user_update" ON "public"."payment_methods" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "poi_catalog_admin_all" ON "public"."points_of_interest" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "poi_catalog_public_read" ON "public"."points_of_interest" FOR SELECT TO "authenticated", "anon" USING ((("is_active" = true) OR "public"."is_admin"()));



ALTER TABLE "public"."poi_ratings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "poi_ratings_admin_all" ON "public"."poi_ratings" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "poi_ratings_owner_write" ON "public"."poi_ratings" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "poi_ratings_public_read" ON "public"."poi_ratings" FOR SELECT TO "authenticated", "anon" USING ((("status" = 'approved'::"text") OR ("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."points_of_interest" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."predictions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pricing_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_admin_all" ON "public"."products" USING ("public"."is_admin"());



CREATE POLICY "products_public_read" ON "public"."products" FOR SELECT USING (true);



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_admin_all" ON "public"."profiles" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "profiles_user_select" ON "public"."profiles" FOR SELECT USING ((("id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "profiles_user_update" ON "public"."profiles" FOR UPDATE USING (("id" = "auth"."uid"()));



ALTER TABLE "public"."promo_code_usage" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "promo_code_usage_admin" ON "public"."promo_code_usage" USING ("public"."is_admin"());



CREATE POLICY "promo_code_usage_customer" ON "public"."promo_code_usage" FOR SELECT USING (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."promo_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "promo_codes_admin" ON "public"."promo_codes" USING ("public"."is_admin"());



CREATE POLICY "promo_usage_admin" ON "public"."promo_code_usage" USING ("public"."is_admin"());



CREATE POLICY "promo_usage_customer_insert" ON "public"."promo_code_usage" FOR INSERT WITH CHECK (("customer_id" = "auth"."uid"()));



CREATE POLICY "promo_usage_customer_read" ON "public"."promo_code_usage" FOR SELECT USING ((("customer_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "public_read_service_parts" ON "public"."service_parts" FOR SELECT USING (true);



ALTER TABLE "public"."purchase_order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."purchase_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reviews_admin" ON "public"."reviews" USING ("public"."is_admin"());



CREATE POLICY "reviews_customer_insert" ON "public"."reviews" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "reviews_customer_read" ON "public"."reviews" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR ("visible" = true)));



CREATE POLICY "reviews_public_read" ON "public"."reviews" FOR SELECT USING (true);



ALTER TABLE "public"."route_pois" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "route_pois_admin_all" ON "public"."route_pois" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "route_pois_public_read" ON "public"."route_pois" FOR SELECT TO "authenticated", "anon" USING ((EXISTS ( SELECT 1
   FROM "public"."routes" "r"
  WHERE (("r"."id" = "route_pois"."route_id") AND (("r"."is_active" = true) OR "public"."is_admin"())))));



ALTER TABLE "public"."route_reviews" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "route_reviews_admin_all" ON "public"."route_reviews" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "route_reviews_owner_write" ON "public"."route_reviews" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "route_reviews_public_read" ON "public"."route_reviews" FOR SELECT TO "authenticated", "anon" USING ((("status" = 'approved'::"text") OR ("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."routes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "routes_admin_all" ON "public"."routes" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "routes_public_read" ON "public"."routes" FOR SELECT TO "authenticated", "anon" USING (((("is_active" = true) AND ("status" = 'approved'::"text")) OR "public"."is_admin"()));



CREATE POLICY "routes_user_submit" ON "public"."routes" FOR INSERT TO "authenticated" WITH CHECK ((("created_by" = "auth"."uid"()) AND ("status" = 'pending'::"text") AND ("is_active" = false)));



ALTER TABLE "public"."sent_emails" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sent_emails_admin" ON "public"."sent_emails" USING ("public"."is_admin"());



ALTER TABLE "public"."service_orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_orders_admin" ON "public"."service_orders" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



ALTER TABLE "public"."service_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shop_order_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "shop_order_items_admin" ON "public"."shop_order_items" USING ("public"."is_admin"());



CREATE POLICY "shop_order_items_customer" ON "public"."shop_order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."shop_orders"
  WHERE (("shop_orders"."id" = "shop_order_items"."order_id") AND ("shop_orders"."customer_id" = "auth"."uid"())))));



CREATE POLICY "shop_order_items_customer_insert" ON "public"."shop_order_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."shop_orders"
  WHERE (("shop_orders"."id" = "shop_order_items"."order_id") AND ("shop_orders"."customer_id" = "auth"."uid"())))));



ALTER TABLE "public"."shop_orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "shop_orders_admin" ON "public"."shop_orders" USING ("public"."is_admin"());



CREATE POLICY "shop_orders_customer_insert" ON "public"."shop_orders" FOR INSERT WITH CHECK (("customer_id" = "auth"."uid"()));



CREATE POLICY "shop_orders_customer_read" ON "public"."shop_orders" FOR SELECT USING (("customer_id" = "auth"."uid"()));



CREATE POLICY "shop_orders_customer_update" ON "public"."shop_orders" FOR UPDATE USING (("customer_id" = "auth"."uid"())) WITH CHECK (("customer_id" = "auth"."uid"()));



ALTER TABLE "public"."sku_catalog" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sku_catalog_admin_all" ON "public"."sku_catalog" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "sku_catalog_read" ON "public"."sku_catalog" FOR SELECT USING (true);



ALTER TABLE "public"."sos_incidents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sos_incidents_admin" ON "public"."sos_incidents" USING ("public"."is_admin"());



CREATE POLICY "sos_incidents_customer_insert" ON "public"."sos_incidents" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "sos_incidents_customer_read" ON "public"."sos_incidents" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "sos_incidents_customer_update" ON "public"."sos_incidents" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."sos_timeline" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sos_timeline_admin" ON "public"."sos_timeline" USING ("public"."is_admin"());



CREATE POLICY "sos_timeline_customer_insert" ON "public"."sos_timeline" FOR INSERT WITH CHECK (("incident_id" IN ( SELECT "sos_incidents"."id"
   FROM "public"."sos_incidents"
  WHERE ("sos_incidents"."user_id" = "auth"."uid"()))));



CREATE POLICY "sos_timeline_customer_read" ON "public"."sos_timeline" FOR SELECT USING (("incident_id" IN ( SELECT "sos_incidents"."id"
   FROM "public"."sos_incidents"
  WHERE ("sos_incidents"."user_id" = "auth"."uid"()))));



ALTER TABLE "public"."stock_receipts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_receipts_admin_all" ON "public"."stock_receipts" TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tax_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_pois" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_pois_admin_all" ON "public"."user_pois" TO "authenticated" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "user_pois_public_read" ON "public"."user_pois" FOR SELECT TO "authenticated", "anon" USING ((("status" = 'approved'::"text") OR ("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "user_pois_user_insert" ON "public"."user_pois" FOR INSERT TO "authenticated" WITH CHECK ((("user_id" = "auth"."uid"()) AND ("status" = 'pending'::"text")));



ALTER TABLE "public"."user_saved_routes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_saved_routes_admin_read" ON "public"."user_saved_routes" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "user_saved_routes_owner" ON "public"."user_saved_routes" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."user_visited_places" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_visited_places_admin_read" ON "public"."user_visited_places" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "user_visited_places_owner" ON "public"."user_visited_places" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."visitor_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "visitor_log_admin_select" ON "public"."visitor_log" FOR SELECT USING ("public"."is_admin"());



CREATE POLICY "visitor_log_anon_insert" ON "public"."visitor_log" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);



ALTER TABLE "public"."vouchers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "vouchers_admin_all" ON "public"."vouchers" USING ("public"."is_admin"()) WITH CHECK ("public"."is_admin"());



CREATE POLICY "vouchers_user_select" ON "public"."vouchers" FOR SELECT USING ((("buyer_id" = "auth"."uid"()) OR ("redeemed_by" = "auth"."uid"())));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."_activate_on_handover_protocol_doc"() TO "anon";
GRANT ALL ON FUNCTION "public"."_activate_on_handover_protocol_doc"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_activate_on_handover_protocol_doc"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."_apply_booking_changes_core"("p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time without time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_apply_booking_changes_core"("p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."_apply_discount_variant_b"("p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_dtype" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_apply_discount_variant_b"("p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_dtype" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_apply_discount_variant_b"("p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_dtype" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_booking_discount_type"("p_promo_code_id" "uuid", "p_promo_code" "text", "p_discount_code" "text", "p_voucher_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_booking_discount_type"("p_promo_code_id" "uuid", "p_promo_code" "text", "p_discount_code" "text", "p_voucher_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_booking_discount_type"("p_promo_code_id" "uuid", "p_promo_code" "text", "p_discount_code" "text", "p_voucher_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."_calc_stacked_discount"("p_gross" numeric, "p_discounts" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."_calc_stacked_discount"("p_gross" numeric, "p_discounts" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_calc_stacked_discount"("p_gross" numeric, "p_discounts" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."_cap_refund_to_paid"() TO "anon";
GRANT ALL ON FUNCTION "public"."_cap_refund_to_paid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_cap_refund_to_paid"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."_create_gear_po"("p_shortage_id" "uuid", "p_qty" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_create_gear_po"("p_shortage_id" "uuid", "p_qty" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."_gate_obsluzna_activation"() TO "anon";
GRANT ALL ON FUNCTION "public"."_gate_obsluzna_activation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_gate_obsluzna_activation"() TO "service_role";



GRANT ALL ON FUNCTION "public"."_is_self_service_booking"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."_is_self_service_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_is_self_service_booking"("p_booking_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_late_pickup_discount"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_pickup_time" time without time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_late_pickup_discount"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_pickup_time" time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_late_pickup_discount"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_pickup_time" time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."_license_moto_rank"("p_g" "public"."license_group") TO "anon";
GRANT ALL ON FUNCTION "public"."_license_moto_rank"("p_g" "public"."license_group") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_license_moto_rank"("p_g" "public"."license_group") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_loyalty_effective_count"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_loyalty_effective_count"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."_loyalty_qualifying_count"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_loyalty_qualifying_count"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."_moto_dayprice_sum"("p_moto_id" "uuid", "p_start" "date", "p_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."_moto_dayprice_sum"("p_moto_id" "uuid", "p_start" "date", "p_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_moto_dayprice_sum"("p_moto_id" "uuid", "p_start" "date", "p_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."_norm_supplier"("p" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."_norm_supplier"("p" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_norm_supplier"("p" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."_reallocate_booking_discounts"("p_booking_id" "uuid", "p_target" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."_reallocate_booking_discounts"("p_booking_id" "uuid", "p_target" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_reallocate_booking_discounts"("p_booking_id" "uuid", "p_target" numeric) TO "service_role";



REVOKE ALL ON FUNCTION "public"."_recalc_booking_discount"("p_booking_id" "uuid", "p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_apply" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."_recalc_booking_discount"("p_booking_id" "uuid", "p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_apply" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."_recalc_booking_discount"("p_booking_id" "uuid", "p_old_total" numeric, "p_old_discount" numeric, "p_gross_diff" numeric, "p_apply" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_create_customer"("p_full_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_create_customer"("p_full_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_create_customer"("p_full_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ai_booking_readiness"("p_ref" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ai_booking_readiness"("p_ref" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_booking_readiness"("p_ref" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_booking_readiness"("p_ref" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ai_get_booking_emails"("p_ref" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ai_get_booking_emails"("p_ref" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_get_booking_emails"("p_ref" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_get_booking_emails"("p_ref" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ai_get_order_status"("p_contact" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ai_get_order_status"("p_contact" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_get_order_status"("p_contact" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_get_order_status"("p_contact" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ai_lookup_bookings_by_contact"("p_contact" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ai_lookup_bookings_by_contact"("p_contact" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."ai_lookup_bookings_by_contact"("p_contact" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ai_lookup_bookings_by_contact"("p_contact" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."analytics_customer_km"() TO "anon";
GRANT ALL ON FUNCTION "public"."analytics_customer_km"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analytics_customer_km"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analytics_moto_km"() TO "anon";
GRANT ALL ON FUNCTION "public"."analytics_moto_km"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analytics_moto_km"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analytics_moto_rental_km"() TO "anon";
GRANT ALL ON FUNCTION "public"."analytics_moto_rental_km"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analytics_moto_rental_km"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analytics_service_plan"("p_default_daily_km" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."analytics_service_plan"("p_default_daily_km" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."analytics_service_plan"("p_default_daily_km" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."app_installations_touch"() TO "anon";
GRANT ALL ON FUNCTION "public"."app_installations_touch"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."app_installations_touch"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_save_full_profile"("p_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."app_save_full_profile"("p_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."app_save_full_profile"("p_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_booking_change_light"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_fee" numeric, "p_new_pickup_time" time without time zone, "p_reason" "text", "p_dry_run" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."apply_booking_change_light"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_fee" numeric, "p_new_pickup_time" time without time zone, "p_reason" "text", "p_dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_booking_change_light"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_fee" numeric, "p_new_pickup_time" time without time zone, "p_reason" "text", "p_dry_run" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_booking_changes"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_new_pickup_time" time without time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_booking_changes"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_new_pickup_time" time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_booking_changes"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_new_pickup_time" time without time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_booking_changes_anon"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."apply_booking_changes_anon"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_booking_changes_anon"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_paid_gear_change"("p_booking_id" "uuid", "p_sizes" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_paid_gear_change"("p_booking_id" "uuid", "p_sizes" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_profile_license_group"("p_user_id" "uuid", "p_group" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."apply_profile_license_group"("p_user_id" "uuid", "p_group" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_profile_license_group"("p_user_id" "uuid", "p_group" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_accounting_on_booking_paid"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_accounting_on_booking_paid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_accounting_on_booking_paid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_activate_reserved_bookings"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_activate_reserved_bookings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_activate_reserved_bookings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_cancel_expired_pending"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_cancel_expired_pending"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_cancel_expired_pending"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_check_service_parts"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_check_service_parts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_check_service_parts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_complete_expired_bookings"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_complete_expired_bookings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_complete_expired_bookings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_deactivate_door_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_deactivate_door_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_deactivate_door_codes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_generate_door_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_generate_door_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_generate_door_codes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_liabilities_from_payroll"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_liabilities_from_payroll"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_liabilities_from_payroll"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."auto_order_gear_shortages"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."auto_order_gear_shortages"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_order_gear_shortages"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_process_voucher_order"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_process_voucher_order"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_process_voucher_order"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_reply_sos"("p_incident_id" "uuid", "p_reply_type" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."auto_reply_sos"("p_incident_id" "uuid", "p_reply_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_reply_sos"("p_incident_id" "uuid", "p_reply_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_schedule_services"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_schedule_services"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_schedule_services"() TO "service_role";



GRANT ALL ON FUNCTION "public"."autofill_overdue_handover_protocols"() TO "anon";
GRANT ALL ON FUNCTION "public"."autofill_overdue_handover_protocols"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."autofill_overdue_handover_protocols"() TO "service_role";



GRANT ALL ON FUNCTION "public"."bridge_admin_message_to_app"() TO "anon";
GRANT ALL ON FUNCTION "public"."bridge_admin_message_to_app"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."bridge_admin_message_to_app"() TO "service_role";



GRANT ALL ON FUNCTION "public"."calc_booking_price_v2"("p_moto_id" "uuid", "p_start" "date", "p_end" "date", "p_promo" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."calc_booking_price_v2"("p_moto_id" "uuid", "p_start" "date", "p_end" "date", "p_promo" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calc_booking_price_v2"("p_moto_id" "uuid", "p_start" "date", "p_end" "date", "p_promo" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_moto_roi"("p_moto_id" "uuid", "p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_moto_roi"("p_moto_id" "uuid", "p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_moto_roi"("p_moto_id" "uuid", "p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_booking_tracked"("p_booking_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_booking_tracked"("p_booking_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_booking_tracked"("p_booking_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_pending_web_booking"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_pending_web_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_pending_web_booking"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_admin_permission"("p_user_id" "uuid", "p_permission" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_admin_permission"("p_user_id" "uuid", "p_permission" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_admin_permission"("p_user_id" "uuid", "p_permission" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_asset_status"("p_asset_type" "text", "p_vin" "text", "p_spz" "text", "p_name" "text", "p_amount" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."check_asset_status"("p_asset_type" "text", "p_vin" "text", "p_spz" "text", "p_name" "text", "p_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_asset_status"("p_asset_type" "text", "p_vin" "text", "p_spz" "text", "p_name" "text", "p_amount" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_booking_docs_status"("p_user_id" "uuid", "p_end_date" "date", "p_moto_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_booking_docs_status"("p_user_id" "uuid", "p_end_date" "date", "p_moto_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_booking_docs_status"("p_user_id" "uuid", "p_end_date" "date", "p_moto_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_booking_overlap"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_booking_overlap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_booking_overlap"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_document_status"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."check_document_status"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_document_status"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_license_for_moto"("p_moto_id" "uuid", "p_rental_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."check_license_for_moto"("p_moto_id" "uuid", "p_rental_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_license_for_moto"("p_moto_id" "uuid", "p_rental_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_moto_availability"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_exclude_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_moto_availability"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_exclude_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_moto_availability"("p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_exclude_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_one_active_sos"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_one_active_sos"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_one_active_sos"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_trailer_overlap"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_trailer_overlap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_trailer_overlap"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_user_booking_overlap"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_user_booking_overlap"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_user_booking_overlap"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."check_web_booking_email"("p_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."check_web_booking_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_web_booking_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_web_booking_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_web_booking_user_overlap"("p_email" "text", "p_start" "date", "p_end" "date", "p_exclude_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."check_web_booking_user_overlap"("p_email" "text", "p_start" "date", "p_end" "date", "p_exclude_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_web_booking_user_overlap"("p_email" "text", "p_start" "date", "p_end" "date", "p_exclude_booking_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_email_send"("p_booking_id" "uuid", "p_slug" "text", "p_window_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_email_send"("p_booking_id" "uuid", "p_slug" "text", "p_window_minutes" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_all_test_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_all_test_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_all_test_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_old_verification_documents"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_old_verification_documents"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_old_verification_documents"() TO "service_role";



GRANT ALL ON FUNCTION "public"."confirm_booking_surcharge"("p_booking_id" "uuid", "p_method" "text", "p_vs" "text", "p_paid_date" "date", "p_transaction_ref" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_booking_surcharge"("p_booking_id" "uuid", "p_method" "text", "p_vs" "text", "p_paid_date" "date", "p_transaction_ref" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_booking_surcharge"("p_booking_id" "uuid", "p_method" "text", "p_vs" "text", "p_paid_date" "date", "p_transaction_ref" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."confirm_payment"("p_booking_id" "uuid", "p_method" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_payment"("p_booking_id" "uuid", "p_method" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_payment"("p_booking_id" "uuid", "p_method" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."confirm_shop_payment"("p_order_id" "uuid", "p_method" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_shop_payment"("p_order_id" "uuid", "p_method" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_shop_payment"("p_order_id" "uuid", "p_method" "text") TO "service_role";



GRANT ALL ON TABLE "public"."motorcycles" TO "anon";
GRANT ALL ON TABLE "public"."motorcycles" TO "authenticated";
GRANT ALL ON TABLE "public"."motorcycles" TO "service_role";



GRANT ALL ON FUNCTION "public"."correct_motorcycle_mileage"("p_moto_id" "uuid", "p_km" integer, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."correct_motorcycle_mileage"("p_moto_id" "uuid", "p_km" integer, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."correct_motorcycle_mileage"("p_moto_id" "uuid", "p_km" integer, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_api_key"("p_partner_name" "text", "p_partner_email" "text", "p_partner_url" "text", "p_rate_limit_rpm" integer, "p_scopes" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."create_api_key"("p_partner_name" "text", "p_partner_email" "text", "p_partner_url" "text", "p_rate_limit_rpm" integer, "p_scopes" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_api_key"("p_partner_name" "text", "p_partner_email" "text", "p_partner_url" "text", "p_rate_limit_rpm" integer, "p_scopes" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_gear_purchase_order"("p_shortage_id" "uuid", "p_qty" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_gear_purchase_order"("p_shortage_id" "uuid", "p_qty" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_gear_purchase_order"("p_shortage_id" "uuid", "p_qty" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_shop_order"("p_items" "jsonb", "p_shipping_method" "text", "p_shipping_address" "jsonb", "p_payment_method" "text", "p_promo_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_shop_order"("p_items" "jsonb", "p_shipping_method" "text", "p_shipping_address" "jsonb", "p_payment_method" "text", "p_promo_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_shop_order"("p_items" "jsonb", "p_shipping_method" "text", "p_shipping_address" "jsonb", "p_payment_method" "text", "p_promo_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_sos_incident"("p_type" "public"."sos_type", "p_booking_id" "uuid", "p_lat" numeric, "p_lng" numeric, "p_description" "text", "p_is_fault" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."create_sos_incident"("p_type" "public"."sos_type", "p_booking_id" "uuid", "p_lat" numeric, "p_lng" numeric, "p_description" "text", "p_is_fault" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_sos_incident"("p_type" "public"."sos_type", "p_booking_id" "uuid", "p_lat" numeric, "p_lng" numeric, "p_description" "text", "p_is_fault" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_test_booking"("p_user_id" "uuid", "p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."create_test_booking"("p_user_id" "uuid", "p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_test_booking"("p_user_id" "uuid", "p_moto_id" "uuid", "p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_test_customer"("p_email" "text", "p_full_name" "text", "p_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_test_customer"("p_email" "text", "p_full_name" "text", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_test_customer"("p_email" "text", "p_full_name" "text", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_test_maintenance_log"("p_moto_id" "uuid", "p_service_type" "text", "p_description" "text", "p_labor_hours" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."create_test_maintenance_log"("p_moto_id" "uuid", "p_service_type" "text", "p_description" "text", "p_labor_hours" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_test_maintenance_log"("p_moto_id" "uuid", "p_service_type" "text", "p_description" "text", "p_labor_hours" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_test_service_order"("p_moto_id" "uuid", "p_type" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_test_service_order"("p_moto_id" "uuid", "p_type" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_test_service_order"("p_moto_id" "uuid", "p_type" "text", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_test_sos_incident"("p_user_id" "uuid", "p_booking_id" "uuid", "p_moto_id" "uuid", "p_type" "public"."sos_type", "p_description" "text", "p_lat" numeric, "p_lng" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."create_test_sos_incident"("p_user_id" "uuid", "p_booking_id" "uuid", "p_moto_id" "uuid", "p_type" "public"."sos_type", "p_description" "text", "p_lat" numeric, "p_lng" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_test_sos_incident"("p_user_id" "uuid", "p_booking_id" "uuid", "p_moto_id" "uuid", "p_type" "public"."sos_type", "p_description" "text", "p_lat" numeric, "p_lng" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_test_sos_timeline"("p_incident_id" "uuid", "p_action" "text", "p_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_test_sos_timeline"("p_incident_id" "uuid", "p_action" "text", "p_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_test_sos_timeline"("p_incident_id" "uuid", "p_action" "text", "p_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid", "p_discounts" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid", "p_discounts" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text", "p_city" "text", "p_zip" "text", "p_country" "text", "p_note" "text", "p_pickup_time" time without time zone, "p_delivery_address" "text", "p_return_address" "text", "p_extras" "jsonb", "p_discount_amount" numeric, "p_discount_code" "text", "p_promo_code" "text", "p_voucher_id" "uuid", "p_license_group" "text", "p_password" "text", "p_helmet_size" "text", "p_jacket_size" "text", "p_pants_size" "text", "p_boots_size" "text", "p_gloves_size" "text", "p_passenger_helmet_size" "text", "p_passenger_jacket_size" "text", "p_passenger_gloves_size" "text", "p_passenger_boots_size" "text", "p_return_time" "text", "p_existing_booking_id" "uuid", "p_passenger_pants_size" "text", "p_consent_vop" boolean, "p_consent_gdpr" boolean, "p_marketing_consent" boolean, "p_consent_photo" boolean, "p_date_of_birth" "text", "p_trailer_moto_id" "uuid", "p_discounts" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_web_shop_order"("items" "jsonb", "customer_name" "text", "customer_email" "text", "customer_phone" "text", "shipping_method" "text", "shipping_address" "text", "payment_method" "text", "promo_code" "text", "notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_web_shop_order"("items" "jsonb", "customer_name" "text", "customer_email" "text", "customer_phone" "text", "shipping_method" "text", "shipping_address" "text", "payment_method" "text", "promo_code" "text", "notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_web_shop_order"("items" "jsonb", "customer_name" "text", "customer_email" "text", "customer_phone" "text", "shipping_method" "text", "shipping_address" "text", "payment_method" "text", "promo_code" "text", "notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_customer_account"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_route_review"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_route_review"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_route_review"("p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_user_route"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_user_route"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_user_route"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."detect_consecutive_booking"() TO "anon";
GRANT ALL ON FUNCTION "public"."detect_consecutive_booking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."detect_consecutive_booking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."detect_customer_language"("p_user_id" "uuid", "p_booking_id" "uuid", "p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."detect_customer_language"("p_user_id" "uuid", "p_booking_id" "uuid", "p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."detect_customer_language"("p_user_id" "uuid", "p_booking_id" "uuid", "p_order_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."detect_gear_shortages"("p_horizon_days" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."detect_gear_shortages"("p_horizon_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."detect_gear_shortages"("p_horizon_days" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."detect_gear_shortages_for_window"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."detect_gear_shortages_for_window"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."detect_gear_shortages_for_window"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."dispatch_email_event"("p_event_slug" "text", "p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."dispatch_email_event"("p_event_slug" "text", "p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dispatch_email_event"("p_event_slug" "text", "p_payload" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."expire_vouchers"() TO "anon";
GRANT ALL ON FUNCTION "public"."expire_vouchers"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expire_vouchers"() TO "service_role";



GRANT ALL ON FUNCTION "public"."expire_vouchers_and_promos"() TO "anon";
GRANT ALL ON FUNCTION "public"."expire_vouchers_and_promos"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."expire_vouchers_and_promos"() TO "service_role";



GRANT ALL ON FUNCTION "public"."extend_booking"("p_booking_id" "uuid", "p_new_end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."extend_booking"("p_booking_id" "uuid", "p_new_end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."extend_booking"("p_booking_id" "uuid", "p_new_end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."find_booking_for_modification"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."find_booking_for_modification"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_booking_for_modification"("p_booking_id" "uuid", "p_contact" "text", "p_password_last4" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_booking_light"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."find_booking_light"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_booking_light"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_email_templates_for_event"("p_event_slug" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."find_email_templates_for_event"("p_event_slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_email_templates_for_event"("p_event_slug" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."find_gear_surplus_branches"("p_type" "text", "p_size" "text", "p_from" "date", "p_to" "date", "p_exclude_branch" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."find_gear_surplus_branches"("p_type" "text", "p_size" "text", "p_from" "date", "p_to" "date", "p_exclude_branch" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_gear_surplus_branches"("p_type" "text", "p_size" "text", "p_from" "date", "p_to" "date", "p_exclude_branch" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fix_auth_users_null_tokens"() TO "anon";
GRANT ALL ON FUNCTION "public"."fix_auth_users_null_tokens"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."fix_auth_users_null_tokens"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_final_invoice_on_complete"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_final_invoice_on_complete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_final_invoice_on_complete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_invoice_number"("prefix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_invoice_number"("prefix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_invoice_number"("prefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_shop_final_on_ship"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_shop_final_on_ship"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_shop_final_on_ship"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_shop_order_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_shop_order_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_shop_order_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ai_traffic_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_ai_traffic_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ai_traffic_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_app_install_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_app_install_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_app_install_stats"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_app_install_timeseries"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_app_install_timeseries"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_app_install_timeseries"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_available_motos"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_category" "text", "p_license" "public"."license_group", "p_branch_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_available_motos"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_category" "text", "p_license" "public"."license_group", "p_branch_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_available_motos"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_category" "text", "p_license" "public"."license_group", "p_branch_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_booking_loyalty_rate"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_booking_loyalty_rate"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_booking_loyalty_rate"("p_booking_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_branch_gear_calendar"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_branch_gear_calendar"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_branch_gear_calendar"("p_branch_id" "uuid", "p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_branch_routes"("p_branch_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_branch_routes"("p_branch_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_branch_routes"("p_branch_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_branch_routes_lite"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_branch_routes_lite"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_branch_routes_lite"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_document_translation"("p_template_slug" "text", "p_language" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_document_translation"("p_template_slug" "text", "p_language" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_document_translation"("p_template_slug" "text", "p_language" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_handover_protocol_state"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_handover_protocol_state"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_handover_protocol_state"("p_booking_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_loyalty_celebration_motos"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_loyalty_celebration_motos"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_loyalty_celebration_motos"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_loyalty_leaderboard"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_loyalty_leaderboard"("p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_loyalty_leaderboard"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_loyalty_status"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_loyalty_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_loyalty_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_moto_booked_dates"("p_moto_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_moto_booked_dates"("p_moto_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_moto_booked_dates"("p_moto_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_motos_availability_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_motos_availability_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_motos_availability_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_places"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_places"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_places"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_saved_routes"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_saved_routes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_saved_routes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_page_ai_traffic"("p_path" "text", "p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_page_ai_traffic"("p_path" "text", "p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_page_ai_traffic"("p_path" "text", "p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_poi_detail"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_poi_detail"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_poi_detail"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_poi_reviews"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_poi_reviews"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_poi_reviews"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_pois_catalog"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_pois_catalog"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_pois_catalog"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_promo_code_type"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_promo_code_type"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_promo_code_type"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_route_detail"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_route_detail"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_route_detail"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_route_poi_detail"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_route_poi_detail"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_route_poi_detail"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_route_reviews"("p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_route_reviews"("p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_route_reviews"("p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_trailer_availability"("p_start" "date", "p_end" "date", "p_exclude_booking" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_trailer_availability"("p_start" "date", "p_end" "date", "p_exclude_booking" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_trailer_availability"("p_start" "date", "p_end" "date", "p_exclude_booking" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unread_thread_message_count"("p_customer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unread_thread_message_count"("p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unread_thread_message_count"("p_customer_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_visitor_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_host" "text", "p_granularity" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_visitor_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_host" "text", "p_granularity" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_visitor_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_host" "text", "p_granularity" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_visitor_stats"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_host" "text", "p_granularity" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_web_booking_confirmation"("p_session_id" "text", "p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_web_booking_confirmation"("p_session_id" "text", "p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_web_booking_confirmation"("p_session_id" "text", "p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_web_booking_confirmation"("p_session_id" "text", "p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_web_booking_resume"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_web_booking_resume"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_web_booking_resume"("p_booking_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_web_shop_order_confirmation"("p_order_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_web_shop_order_confirmation"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_web_shop_order_confirmation"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_web_shop_order_confirmation"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_superadmin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_superadmin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_superadmin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."jsonb_name_translations"("t" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."jsonb_name_translations"("t" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."jsonb_name_translations"("t" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."kiosk_command_broadcast"() TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_command_broadcast"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_command_broadcast"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_complete_command"("p_device_id" "uuid", "p_device_token" "uuid", "p_command_id" "uuid", "p_success" boolean, "p_result" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_complete_command"("p_device_id" "uuid", "p_device_token" "uuid", "p_command_id" "uuid", "p_success" boolean, "p_result" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_complete_command"("p_device_id" "uuid", "p_device_token" "uuid", "p_command_id" "uuid", "p_success" boolean, "p_result" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_complete_command"("p_device_id" "uuid", "p_device_token" "uuid", "p_command_id" "uuid", "p_success" boolean, "p_result" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_device_branch"("p_device_id" "uuid", "p_device_token" "uuid", "p_touch" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_device_branch"("p_device_id" "uuid", "p_device_token" "uuid", "p_touch" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_device_branch"("p_device_id" "uuid", "p_device_token" "uuid", "p_touch" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_device_branch"("p_device_id" "uuid", "p_device_token" "uuid", "p_touch" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_fetch_commands"("p_device_id" "uuid", "p_device_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_fetch_commands"("p_device_id" "uuid", "p_device_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_fetch_commands"("p_device_id" "uuid", "p_device_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_fetch_commands"("p_device_id" "uuid", "p_device_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_heartbeat"("p_device_id" "uuid", "p_device_token" "uuid", "p_app_version" "text", "p_platform" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_heartbeat"("p_device_id" "uuid", "p_device_token" "uuid", "p_app_version" "text", "p_platform" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_heartbeat"("p_device_id" "uuid", "p_device_token" "uuid", "p_app_version" "text", "p_platform" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_heartbeat"("p_device_id" "uuid", "p_device_token" "uuid", "p_app_version" "text", "p_platform" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."kiosk_jbool"("p" "jsonb", VARIADIC "keys" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_jbool"("p" "jsonb", VARIADIC "keys" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_jbool"("p" "jsonb", VARIADIC "keys" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."kiosk_jnum"("p" "jsonb", VARIADIC "keys" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_jnum"("p" "jsonb", VARIADIC "keys" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_jnum"("p" "jsonb", VARIADIC "keys" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_log_event"("p_device_id" "uuid", "p_device_token" "uuid", "p_level" "text", "p_source" "text", "p_message" "text", "p_detail" "jsonb", "p_app_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_log_event"("p_device_id" "uuid", "p_device_token" "uuid", "p_level" "text", "p_source" "text", "p_message" "text", "p_detail" "jsonb", "p_app_version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_log_event"("p_device_id" "uuid", "p_device_token" "uuid", "p_level" "text", "p_source" "text", "p_message" "text", "p_detail" "jsonb", "p_app_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_log_event"("p_device_id" "uuid", "p_device_token" "uuid", "p_level" "text", "p_source" "text", "p_message" "text", "p_detail" "jsonb", "p_app_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_log_open"("p_device_id" "uuid", "p_device_token" "uuid", "p_door_id" "uuid", "p_kind" "text", "p_booking_id" "uuid", "p_success" boolean, "p_detail" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_log_open"("p_device_id" "uuid", "p_device_token" "uuid", "p_door_id" "uuid", "p_kind" "text", "p_booking_id" "uuid", "p_success" boolean, "p_detail" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_log_open"("p_device_id" "uuid", "p_device_token" "uuid", "p_door_id" "uuid", "p_kind" "text", "p_booking_id" "uuid", "p_success" boolean, "p_detail" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_log_open"("p_device_id" "uuid", "p_device_token" "uuid", "p_door_id" "uuid", "p_kind" "text", "p_booking_id" "uuid", "p_success" boolean, "p_detail" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_report_power"("p_device_id" "uuid", "p_device_token" "uuid", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_report_power"("p_device_id" "uuid", "p_device_token" "uuid", "p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_report_power"("p_device_id" "uuid", "p_device_token" "uuid", "p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_report_power"("p_device_id" "uuid", "p_device_token" "uuid", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_resolve_code"("p_device_id" "uuid", "p_device_token" "uuid", "p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."kiosk_sync_codes"("p_device_id" "uuid", "p_device_token" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."kiosk_sync_codes"("p_device_id" "uuid", "p_device_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."kiosk_sync_codes"("p_device_id" "uuid", "p_device_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."kiosk_sync_codes"("p_device_id" "uuid", "p_device_token" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."learn_sku"("p_sku" "text", "p_name" "text", "p_category" "text", "p_type" "text", "p_size" "text", "p_alias" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."learn_sku"("p_sku" "text", "p_name" "text", "p_category" "text", "p_type" "text", "p_size" "text", "p_alias" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."learn_sku"("p_sku" "text", "p_name" "text", "p_category" "text", "p_type" "text", "p_size" "text", "p_alias" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."list_pending_ai_suggestions"("p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."list_pending_ai_suggestions"("p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_pending_ai_suggestions"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."log_stock_movement"("p_item" "uuid", "p_type" "text", "p_qty" integer, "p_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."log_stock_movement"("p_item" "uuid", "p_type" "text", "p_qty" integer, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_stock_movement"("p_item" "uuid", "p_type" "text", "p_qty" integer, "p_note" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."loyalty_advance_celebrated"("p_level" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."loyalty_advance_celebrated"("p_level" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."loyalty_advance_celebrated"("p_level" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."loyalty_award_monthly_winner"("p_month" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."loyalty_award_monthly_winner"("p_month" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."loyalty_get_celebrated"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."loyalty_get_celebrated"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."loyalty_get_celebrated"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_place_visited"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_route_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_place_visited"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_route_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_place_visited"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_route_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."merge_license_group"("p_existing" "public"."license_group"[], "p_new" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."merge_license_group"("p_existing" "public"."license_group"[], "p_new" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_license_group"("p_existing" "public"."license_group"[], "p_new" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."merge_license_group_multi"("p_existing" "public"."license_group"[], "p_raw" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."merge_license_group_multi"("p_existing" "public"."license_group"[], "p_raw" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_license_group_multi"("p_existing" "public"."license_group"[], "p_raw" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."mirror_route_images_tick"() TO "anon";
GRANT ALL ON FUNCTION "public"."mirror_route_images_tick"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mirror_route_images_tick"() TO "service_role";



GRANT ALL ON FUNCTION "public"."next_document_number"("p_prefix" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."next_document_number"("p_prefix" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."next_document_number"("p_prefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_registration_source"() TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_registration_source"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_registration_source"() TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_supplier_name"("input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_supplier_name"("input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_supplier_name"("input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_booking_activated_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_booking_activated_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_booking_activated_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_booking_cancelled_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_booking_cancelled_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_booking_cancelled_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_booking_completed_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_booking_completed_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_booking_completed_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_sos_incident_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_sos_incident_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_sos_incident_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_web_booking_abandoned"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_web_booking_abandoned"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_web_booking_abandoned"() TO "service_role";



GRANT ALL ON FUNCTION "public"."poi_rating_summary"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."poi_rating_summary"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."poi_rating_summary"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."point_country"("p_lat" double precision, "p_lng" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."point_country"("p_lat" double precision, "p_lng" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."point_country"("p_lat" double precision, "p_lng" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."post_invoice_to_financial_event"() TO "anon";
GRANT ALL ON FUNCTION "public"."post_invoice_to_financial_event"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."post_invoice_to_financial_event"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rate_poi"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_rating" integer, "p_poi_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."rate_poi"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_rating" integer, "p_poi_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rate_poi"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_rating" integer, "p_poi_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."receive_stock_from_document"("p_lines" "jsonb", "p_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."receive_stock_from_document"("p_lines" "jsonb", "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."receive_stock_from_document"("p_lines" "jsonb", "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_stock_receipt"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric, "p_financial_event_id" "uuid", "p_will_stock" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."record_stock_receipt"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric, "p_financial_event_id" "uuid", "p_will_stock" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_stock_receipt"("p_doc_type" "text", "p_doc_number" "text", "p_doc_date" "date", "p_variable_symbol" "text", "p_supplier_ico" "text", "p_supplier_name" "text", "p_amount" numeric, "p_financial_event_id" "uuid", "p_will_stock" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."redeem_booking_discounts_on_paid"() TO "anon";
GRANT ALL ON FUNCTION "public"."redeem_booking_discounts_on_paid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."redeem_booking_discounts_on_paid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."regen_door_codes_on_moto_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."regen_door_codes_on_moto_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."regen_door_codes_on_moto_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."regen_voucher_for_order"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."regen_voucher_for_order"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."regen_voucher_for_order"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."release_codes_on_profile_verify"() TO "anon";
GRANT ALL ON FUNCTION "public"."release_codes_on_profile_verify"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_codes_on_profile_verify"() TO "service_role";



GRANT ALL ON FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_my_door_codes"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."release_swap_next_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."release_swap_next_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_swap_next_codes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."release_withheld_door_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."release_withheld_door_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_withheld_door_codes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."release_withheld_door_codes_for_user"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."release_withheld_door_codes_for_user"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_withheld_door_codes_for_user"("p_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reschedule_booking_free"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_source" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reschedule_booking_free"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_source" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reschedule_booking_free"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_source" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_booking_ref"("p_ref" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_booking_ref"("p_ref" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_booking_ref"("p_ref" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."restore_vouchers_on_cancel"() TO "anon";
GRANT ALL ON FUNCTION "public"."restore_vouchers_on_cancel"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."restore_vouchers_on_cancel"() TO "service_role";



GRANT ALL ON FUNCTION "public"."revoke_api_key"("p_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."revoke_api_key"("p_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_api_key"("p_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."route_detect_countries"("p_waypoints" "jsonb", "p_geometry" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."route_detect_countries"("p_waypoints" "jsonb", "p_geometry" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."route_detect_countries"("p_waypoints" "jsonb", "p_geometry" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."routes_set_countries"() TO "anon";
GRANT ALL ON FUNCTION "public"."routes_set_countries"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."routes_set_countries"() TO "service_role";



GRANT ALL ON FUNCTION "public"."save_user_route"("p_name" "text", "p_description" "text", "p_source_route_id" "uuid", "p_waypoints" "jsonb", "p_poi_refs" "jsonb", "p_profile" "text", "p_distance_km" numeric, "p_duration_min" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."save_user_route"("p_name" "text", "p_description" "text", "p_source_route_id" "uuid", "p_waypoints" "jsonb", "p_poi_refs" "jsonb", "p_profile" "text", "p_distance_km" numeric, "p_duration_min" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_user_route"("p_name" "text", "p_description" "text", "p_source_route_id" "uuid", "p_waypoints" "jsonb", "p_poi_refs" "jsonb", "p_profile" "text", "p_distance_km" numeric, "p_duration_min" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."send_abandoned_booking_emails"() TO "anon";
GRANT ALL ON FUNCTION "public"."send_abandoned_booking_emails"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_abandoned_booking_emails"() TO "service_role";



GRANT ALL ON FUNCTION "public"."send_admin_message"("p_user_id" "uuid", "p_title" "text", "p_message" "text", "p_type" "text", "p_incident_id" "uuid", "p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."send_admin_message"("p_user_id" "uuid", "p_title" "text", "p_message" "text", "p_type" "text", "p_incident_id" "uuid", "p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_admin_message"("p_user_id" "uuid", "p_title" "text", "p_message" "text", "p_type" "text", "p_incident_id" "uuid", "p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_door_codes_email"("p_booking_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."send_door_codes_email"("p_booking_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_door_codes_email"("p_booking_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_message_via_edge"("p_channel" "text", "p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_missing_booking_reserved_emails"() TO "anon";
GRANT ALL ON FUNCTION "public"."send_missing_booking_reserved_emails"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_missing_booking_reserved_emails"() TO "service_role";



GRANT ALL ON FUNCTION "public"."send_push_via_edge"("p_user_id" "uuid", "p_title" "text", "p_body" "text", "p_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."send_push_via_edge"("p_user_id" "uuid", "p_title" "text", "p_body" "text", "p_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_push_via_edge"("p_user_id" "uuid", "p_title" "text", "p_body" "text", "p_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_sms_and_wa"("p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."send_sms_and_wa"("p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_sms_and_wa"("p_to" "text", "p_template_slug" "text", "p_template_vars" "jsonb", "p_customer_id" "uuid", "p_booking_id" "uuid", "p_language" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_booking_form_seconds"("p_booking_id" "uuid", "p_started_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_booking_form_seconds"("p_booking_id" "uuid", "p_started_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."set_booking_form_seconds"("p_booking_id" "uuid", "p_started_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_booking_form_seconds"("p_booking_id" "uuid", "p_started_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_booking_mod_surcharge"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_booking_mod_surcharge"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_booking_mod_surcharge"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_booking_qr_payment"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_booking_qr_payment"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_booking_qr_payment"("p_booking_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_loyalty_leaderboard_optin"("p_opt_in" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_loyalty_leaderboard_optin"("p_opt_in" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_loyalty_leaderboard_optin"("p_opt_in" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_loyalty_nickname"("p_nickname" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_loyalty_nickname"("p_nickname" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_loyalty_nickname"("p_nickname" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_my_license_group"("p_groups" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."set_my_license_group"("p_groups" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_my_license_group"("p_groups" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_promo_code_source"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_promo_code_source"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_promo_code_source"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at_now"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at_now"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at_now"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_web_booking_chosen_method"("p_booking_id" "uuid", "p_method" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_web_booking_chosen_method"("p_booking_id" "uuid", "p_method" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_web_booking_chosen_method"("p_booking_id" "uuid", "p_method" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_web_booking_company"("p_booking_id" "uuid", "p_company_name" "text", "p_ico" "text", "p_dic" "text", "p_company_address" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_web_booking_company"("p_booking_id" "uuid", "p_company_name" "text", "p_ico" "text", "p_dic" "text", "p_company_address" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_web_booking_company"("p_booking_id" "uuid", "p_company_name" "text", "p_ico" "text", "p_dic" "text", "p_company_address" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_web_booking_device"("p_booking_id" "uuid", "p_device" "text", "p_phase" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_web_booking_device"("p_booking_id" "uuid", "p_device" "text", "p_phase" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_web_booking_device"("p_booking_id" "uuid", "p_device" "text", "p_phase" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_web_booking_docs"("p_booking_id" "uuid", "p_id_number" "text", "p_license_number" "text", "p_license_expiry" "text", "p_license_group" "text", "p_date_of_birth" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_web_booking_docs"("p_booking_id" "uuid", "p_id_number" "text", "p_license_number" "text", "p_license_expiry" "text", "p_license_group" "text", "p_date_of_birth" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_web_booking_docs"("p_booking_id" "uuid", "p_id_number" "text", "p_license_number" "text", "p_license_expiry" "text", "p_license_group" "text", "p_date_of_birth" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_web_booking_docs_completed"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_web_booking_docs_completed"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_web_booking_docs_completed"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_web_booking_password"("p_booking_id" "uuid", "p_password" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_web_booking_password"("p_booking_id" "uuid", "p_password" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_web_booking_password"("p_booking_id" "uuid", "p_password" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."shorten_booking_with_refund"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."shorten_booking_with_refund"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."shorten_booking_with_refund"("p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."slevomat_auto_apply_on_redeem"() TO "anon";
GRANT ALL ON FUNCTION "public"."slevomat_auto_apply_on_redeem"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."slevomat_auto_apply_on_redeem"() TO "service_role";



GRANT ALL ON FUNCTION "public"."snapshot_daily_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."snapshot_daily_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."snapshot_daily_stats"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sos_auto_severity"() TO "anon";
GRANT ALL ON FUNCTION "public"."sos_auto_severity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sos_auto_severity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sos_auto_timeline"() TO "anon";
GRANT ALL ON FUNCTION "public"."sos_auto_timeline"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sos_auto_timeline"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sos_notify_user_on_create"() TO "anon";
GRANT ALL ON FUNCTION "public"."sos_notify_user_on_create"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sos_notify_user_on_create"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sos_share_location"("p_incident_id" "uuid", "p_lat" numeric, "p_lng" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."sos_share_location"("p_incident_id" "uuid", "p_lat" numeric, "p_lng" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sos_share_location"("p_incident_id" "uuid", "p_lat" numeric, "p_lng" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."sos_swap_bookings"("p_incident_id" "uuid", "p_replacement_moto_id" "uuid", "p_replacement_model" "text", "p_delivery_fee" numeric, "p_daily_price" numeric, "p_is_free" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sos_swap_bookings"("p_incident_id" "uuid", "p_replacement_moto_id" "uuid", "p_replacement_model" "text", "p_delivery_fee" numeric, "p_daily_price" numeric, "p_is_free" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sos_swap_bookings"("p_incident_id" "uuid", "p_replacement_moto_id" "uuid", "p_replacement_model" "text", "p_delivery_fee" numeric, "p_daily_price" numeric, "p_is_free" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."split_booking_moto_swap"("p_booking_id" "uuid", "p_new_moto_id" "uuid", "p_swap_date" "date", "p_swap_time" "text", "p_dry_run" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."split_booking_moto_swap"("p_booking_id" "uuid", "p_new_moto_id" "uuid", "p_swap_date" "date", "p_swap_time" "text", "p_dry_run" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."split_booking_moto_swap"("p_booking_id" "uuid", "p_new_moto_id" "uuid", "p_swap_date" "date", "p_swap_time" "text", "p_dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."split_booking_moto_swap"("p_booking_id" "uuid", "p_new_moto_id" "uuid", "p_swap_date" "date", "p_swap_time" "text", "p_dry_run" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."start_handover_protocol_window"("p_booking_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."start_handover_protocol_window"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_handover_protocol_window"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."submit_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."submit_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_poi_review"("p_route_poi_id" "uuid", "p_user_poi_id" "uuid", "p_poi_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."submit_route_review"("p_route_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."submit_route_review"("p_route_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_route_review"("p_route_id" "uuid", "p_rating" integer, "p_review_text" "text", "p_photos" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."swap_handoff_bookings"("p_prev" "uuid", "p_next" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."swap_handoff_bookings"("p_prev" "uuid", "p_next" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."swap_handoff_bookings"("p_prev" "uuid", "p_next" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_cms_flat_to_nested"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_cms_flat_to_nested"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_cms_flat_to_nested"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_generated_doc_to_documents"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_generated_doc_to_documents"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_generated_doc_to_documents"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_invoice_pdf_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_invoice_pdf_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_invoice_pdf_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_invoice_to_documents"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_invoice_to_documents"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_invoice_to_documents"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_moto_day_prices_to_motorcycles"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_moto_day_prices_to_motorcycles"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_moto_day_prices_to_motorcycles"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_motorcycle_to_assets"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_motorcycle_to_assets"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_motorcycle_to_assets"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."track_booking_content_changes"() TO "anon";
GRANT ALL ON FUNCTION "public"."track_booking_content_changes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."track_booking_content_changes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."transfer_branch_gear"("p_from_branch" "uuid", "p_to_branch" "uuid", "p_type" "text", "p_size" "text", "p_qty" integer, "p_shortage_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."transfer_branch_gear"("p_from_branch" "uuid", "p_to_branch" "uuid", "p_type" "text", "p_size" "text", "p_qty" integer, "p_shortage_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."transfer_branch_gear"("p_from_branch" "uuid", "p_to_branch" "uuid", "p_type" "text", "p_size" "text", "p_qty" integer, "p_shortage_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_booking_mileage_to_moto"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_booking_mileage_to_moto"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_booking_mileage_to_moto"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_booking_payment_fill_seconds"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_booking_payment_fill_seconds"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_booking_payment_fill_seconds"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_email_on_door_codes_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_email_on_door_codes_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_email_on_door_codes_message"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_gear_shortage_on_booking"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_gear_shortage_on_booking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_gear_shortage_on_booking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_moto_purchase_mileage_floor"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_moto_purchase_mileage_floor"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_moto_purchase_mileage_floor"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_notify_booking_cancelled"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_notify_booking_cancelled"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_notify_booking_cancelled"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_notify_booking_confirmed"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_notify_booking_confirmed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_notify_booking_confirmed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_notify_door_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_notify_door_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_notify_door_codes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_notify_ride_completed"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_notify_ride_completed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_notify_ride_completed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_push_on_admin_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_push_on_admin_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_push_on_admin_message"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_realloc_booking_discounts"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_realloc_booking_discounts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_realloc_booking_discounts"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_send_booking_completed_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_send_booking_completed_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_send_booking_completed_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_send_booking_modified_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_send_booking_modified_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_send_booking_modified_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trg_send_shop_order_confirmed_email"() TO "anon";
GRANT ALL ON FUNCTION "public"."trg_send_shop_order_confirmed_email"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trg_send_shop_order_confirmed_email"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_poi_photo_backfill"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_poi_photo_backfill"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_poi_photo_backfill"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_poi_surroundings_backfill"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_poi_surroundings_backfill"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_poi_surroundings_backfill"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_route_translation_backfill"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_route_translation_backfill"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_route_translation_backfill"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_booking_gear"("p_booking_id" "uuid", "p_sizes" "jsonb", "p_dry_run" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_moto_after_service"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_moto_after_service"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_moto_after_service"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_test_booking_fields"("p_booking_id" "uuid", "p_fields" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_test_booking_fields"("p_booking_id" "uuid", "p_fields" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_test_booking_fields"("p_booking_id" "uuid", "p_fields" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_test_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status", "p_payment_status" "public"."payment_status") TO "anon";
GRANT ALL ON FUNCTION "public"."update_test_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status", "p_payment_status" "public"."payment_status") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_test_booking_status"("p_booking_id" "uuid", "p_status" "public"."booking_status", "p_payment_status" "public"."payment_status") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_test_profile"("p_user_id" "uuid", "p_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_test_profile"("p_user_id" "uuid", "p_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_test_profile"("p_user_id" "uuid", "p_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_test_sos_status"("p_incident_id" "uuid", "p_status" "public"."sos_status", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_test_sos_status"("p_incident_id" "uuid", "p_status" "public"."sos_status", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_test_sos_status"("p_incident_id" "uuid", "p_status" "public"."sos_status", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."use_promo_code"("p_code" "text", "p_booking_id" "uuid", "p_base_amount" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."use_promo_code"("p_code" "text", "p_booking_id" "uuid", "p_base_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."use_promo_code"("p_code" "text", "p_booking_id" "uuid", "p_base_amount" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_app_loyalty_discount"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_app_loyalty_discount"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_app_loyalty_discount"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_late_pickup_discount"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_late_pickup_discount"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_late_pickup_discount"() TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_promo_code"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_promo_code"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_promo_code"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_voucher_code"("p_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_voucher_code"("p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_voucher_code"("p_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."verify_customer_docs"("p_ocr_name" "text", "p_ocr_dob" "text", "p_ocr_id_number" "text", "p_ocr_license_number" "text", "p_ocr_license_category" "text", "p_ocr_license_expiry" "text", "p_rental_end" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."verify_customer_docs"("p_ocr_name" "text", "p_ocr_dob" "text", "p_ocr_id_number" "text", "p_ocr_license_number" "text", "p_ocr_license_category" "text", "p_ocr_license_expiry" "text", "p_rental_end" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."verify_customer_docs"("p_ocr_name" "text", "p_ocr_dob" "text", "p_ocr_id_number" "text", "p_ocr_license_number" "text", "p_ocr_license_category" "text", "p_ocr_license_expiry" "text", "p_rental_end" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."withhold_swap_next_codes"() TO "anon";
GRANT ALL ON FUNCTION "public"."withhold_swap_next_codes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."withhold_swap_next_codes"() TO "service_role";



GRANT ALL ON TABLE "public"."_git_migrations" TO "anon";
GRANT ALL ON TABLE "public"."_git_migrations" TO "authenticated";
GRANT ALL ON TABLE "public"."_git_migrations" TO "service_role";



GRANT ALL ON TABLE "public"."acc_depreciation_entries" TO "anon";
GRANT ALL ON TABLE "public"."acc_depreciation_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_depreciation_entries" TO "service_role";



GRANT ALL ON TABLE "public"."acc_employees" TO "anon";
GRANT ALL ON TABLE "public"."acc_employees" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_employees" TO "service_role";



GRANT ALL ON TABLE "public"."acc_liabilities" TO "anon";
GRANT ALL ON TABLE "public"."acc_liabilities" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_liabilities" TO "service_role";



GRANT ALL ON TABLE "public"."acc_long_term_assets" TO "anon";
GRANT ALL ON TABLE "public"."acc_long_term_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_long_term_assets" TO "service_role";



GRANT ALL ON TABLE "public"."acc_payrolls" TO "anon";
GRANT ALL ON TABLE "public"."acc_payrolls" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_payrolls" TO "service_role";



GRANT ALL ON TABLE "public"."acc_short_term_assets" TO "anon";
GRANT ALL ON TABLE "public"."acc_short_term_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_short_term_assets" TO "service_role";



GRANT ALL ON TABLE "public"."acc_tax_returns" TO "anon";
GRANT ALL ON TABLE "public"."acc_tax_returns" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_tax_returns" TO "service_role";



GRANT ALL ON TABLE "public"."acc_vat_returns" TO "anon";
GRANT ALL ON TABLE "public"."acc_vat_returns" TO "authenticated";
GRANT ALL ON TABLE "public"."acc_vat_returns" TO "service_role";



GRANT ALL ON TABLE "public"."accessory_types" TO "anon";
GRANT ALL ON TABLE "public"."accessory_types" TO "authenticated";
GRANT ALL ON TABLE "public"."accessory_types" TO "service_role";



GRANT ALL ON TABLE "public"."accounting_entries" TO "anon";
GRANT ALL ON TABLE "public"."accounting_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."accounting_entries" TO "service_role";



GRANT ALL ON TABLE "public"."accounting_exceptions" TO "anon";
GRANT ALL ON TABLE "public"."accounting_exceptions" TO "authenticated";
GRANT ALL ON TABLE "public"."accounting_exceptions" TO "service_role";



GRANT ALL ON TABLE "public"."admin_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."admin_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."admin_messages" TO "anon";
GRANT ALL ON TABLE "public"."admin_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_messages" TO "service_role";



GRANT ALL ON TABLE "public"."admin_users" TO "anon";
GRANT ALL ON TABLE "public"."admin_users" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_users" TO "service_role";



GRANT ALL ON TABLE "public"."ai_actions" TO "anon";
GRANT ALL ON TABLE "public"."ai_actions" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_actions" TO "service_role";



GRANT ALL ON TABLE "public"."ai_citations" TO "anon";
GRANT ALL ON TABLE "public"."ai_citations" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_citations" TO "service_role";



GRANT ALL ON TABLE "public"."ai_conversations" TO "anon";
GRANT ALL ON TABLE "public"."ai_conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_conversations" TO "service_role";



GRANT ALL ON TABLE "public"."ai_customer_conversations" TO "anon";
GRANT ALL ON TABLE "public"."ai_customer_conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_customer_conversations" TO "service_role";



GRANT ALL ON TABLE "public"."ai_logs" TO "anon";
GRANT ALL ON TABLE "public"."ai_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_logs" TO "service_role";



GRANT ALL ON TABLE "public"."ai_public_conversations" TO "anon";
GRANT ALL ON TABLE "public"."ai_public_conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_public_conversations" TO "service_role";



GRANT ALL ON TABLE "public"."ai_traffic_log" TO "anon";
GRANT ALL ON TABLE "public"."ai_traffic_log" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_traffic_log" TO "service_role";



GRANT ALL ON TABLE "public"."api_keys" TO "anon";
GRANT ALL ON TABLE "public"."api_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."api_keys" TO "service_role";



GRANT ALL ON TABLE "public"."app_crash_reports" TO "anon";
GRANT ALL ON TABLE "public"."app_crash_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."app_crash_reports" TO "service_role";



GRANT ALL ON TABLE "public"."app_debug_logs" TO "anon";
GRANT ALL ON TABLE "public"."app_debug_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."app_debug_logs" TO "service_role";



GRANT ALL ON TABLE "public"."app_installations" TO "anon";
GRANT ALL ON TABLE "public"."app_installations" TO "authenticated";
GRANT ALL ON TABLE "public"."app_installations" TO "service_role";



GRANT ALL ON TABLE "public"."app_settings" TO "anon";
GRANT ALL ON TABLE "public"."app_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."app_settings" TO "service_role";



GRANT ALL ON TABLE "public"."approval_queue" TO "anon";
GRANT ALL ON TABLE "public"."approval_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."approval_queue" TO "service_role";



GRANT ALL ON TABLE "public"."auto_order_rules" TO "anon";
GRANT ALL ON TABLE "public"."auto_order_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."auto_order_rules" TO "service_role";



GRANT ALL ON TABLE "public"."automation_rules" TO "anon";
GRANT ALL ON TABLE "public"."automation_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."automation_rules" TO "service_role";



GRANT ALL ON TABLE "public"."booking_cancellations" TO "anon";
GRANT ALL ON TABLE "public"."booking_cancellations" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_cancellations" TO "service_role";



GRANT ALL ON TABLE "public"."booking_complaints" TO "anon";
GRANT ALL ON TABLE "public"."booking_complaints" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_complaints" TO "service_role";



GRANT ALL ON TABLE "public"."booking_discounts" TO "anon";
GRANT ALL ON TABLE "public"."booking_discounts" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_discounts" TO "service_role";



GRANT ALL ON TABLE "public"."booking_extras" TO "anon";
GRANT ALL ON TABLE "public"."booking_extras" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_extras" TO "service_role";



GRANT ALL ON SEQUENCE "public"."booking_vs_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."booking_vs_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."booking_vs_seq" TO "service_role";



GRANT ALL ON TABLE "public"."bookings" TO "anon";
GRANT ALL ON TABLE "public"."bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."bookings" TO "service_role";



GRANT ALL ON TABLE "public"."branch_accessories" TO "anon";
GRANT ALL ON TABLE "public"."branch_accessories" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_accessories" TO "service_role";



GRANT ALL ON TABLE "public"."branch_cameras" TO "anon";
GRANT ALL ON TABLE "public"."branch_cameras" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_cameras" TO "service_role";



GRANT ALL ON TABLE "public"."branch_door_codes" TO "anon";
GRANT ALL ON TABLE "public"."branch_door_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_door_codes" TO "service_role";



GRANT ALL ON TABLE "public"."branch_door_events" TO "anon";
GRANT ALL ON TABLE "public"."branch_door_events" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_door_events" TO "service_role";



GRANT ALL ON TABLE "public"."branch_doors" TO "anon";
GRANT ALL ON TABLE "public"."branch_doors" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_doors" TO "service_role";



GRANT ALL ON TABLE "public"."branch_kiosk_config" TO "anon";
GRANT ALL ON TABLE "public"."branch_kiosk_config" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_kiosk_config" TO "service_role";



GRANT ALL ON TABLE "public"."branch_performance" TO "anon";
GRANT ALL ON TABLE "public"."branch_performance" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_performance" TO "service_role";



GRANT ALL ON TABLE "public"."branch_power_status" TO "anon";
GRANT ALL ON TABLE "public"."branch_power_status" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_power_status" TO "service_role";



GRANT ALL ON TABLE "public"."branch_service_codes" TO "anon";
GRANT ALL ON TABLE "public"."branch_service_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_service_codes" TO "service_role";



GRANT ALL ON TABLE "public"."branches" TO "anon";
GRANT ALL ON TABLE "public"."branches" TO "authenticated";
GRANT ALL ON TABLE "public"."branches" TO "service_role";



GRANT ALL ON TABLE "public"."broadcast_campaigns" TO "anon";
GRANT ALL ON TABLE "public"."broadcast_campaigns" TO "authenticated";
GRANT ALL ON TABLE "public"."broadcast_campaigns" TO "service_role";



GRANT ALL ON TABLE "public"."cash_register" TO "anon";
GRANT ALL ON TABLE "public"."cash_register" TO "authenticated";
GRANT ALL ON TABLE "public"."cash_register" TO "service_role";



GRANT ALL ON TABLE "public"."cms_pages" TO "anon";
GRANT ALL ON TABLE "public"."cms_pages" TO "authenticated";
GRANT ALL ON TABLE "public"."cms_pages" TO "service_role";



GRANT ALL ON TABLE "public"."cms_variables" TO "anon";
GRANT ALL ON TABLE "public"."cms_variables" TO "authenticated";
GRANT ALL ON TABLE "public"."cms_variables" TO "service_role";



GRANT ALL ON TABLE "public"."contracts" TO "anon";
GRANT ALL ON TABLE "public"."contracts" TO "authenticated";
GRANT ALL ON TABLE "public"."contracts" TO "service_role";



GRANT ALL ON TABLE "public"."custom_documents" TO "anon";
GRANT ALL ON TABLE "public"."custom_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_documents" TO "service_role";



GRANT ALL ON TABLE "public"."daily_stats" TO "anon";
GRANT ALL ON TABLE "public"."daily_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_stats" TO "service_role";



GRANT ALL ON TABLE "public"."debug_log" TO "anon";
GRANT ALL ON TABLE "public"."debug_log" TO "authenticated";
GRANT ALL ON TABLE "public"."debug_log" TO "service_role";



GRANT ALL ON TABLE "public"."delivery_notes" TO "anon";
GRANT ALL ON TABLE "public"."delivery_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."delivery_notes" TO "service_role";



GRANT ALL ON TABLE "public"."document_number_counters" TO "anon";
GRANT ALL ON TABLE "public"."document_number_counters" TO "authenticated";
GRANT ALL ON TABLE "public"."document_number_counters" TO "service_role";



GRANT ALL ON TABLE "public"."document_templates" TO "anon";
GRANT ALL ON TABLE "public"."document_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."document_templates" TO "service_role";



GRANT ALL ON TABLE "public"."documents" TO "anon";
GRANT ALL ON TABLE "public"."documents" TO "authenticated";
GRANT ALL ON TABLE "public"."documents" TO "service_role";



GRANT ALL ON TABLE "public"."email_send_locks" TO "anon";
GRANT ALL ON TABLE "public"."email_send_locks" TO "authenticated";
GRANT ALL ON TABLE "public"."email_send_locks" TO "service_role";



GRANT ALL ON TABLE "public"."email_templates" TO "anon";
GRANT ALL ON TABLE "public"."email_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."email_templates" TO "service_role";



GRANT ALL ON TABLE "public"."emp_attendance" TO "anon";
GRANT ALL ON TABLE "public"."emp_attendance" TO "authenticated";
GRANT ALL ON TABLE "public"."emp_attendance" TO "service_role";



GRANT ALL ON TABLE "public"."emp_documents" TO "anon";
GRANT ALL ON TABLE "public"."emp_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."emp_documents" TO "service_role";



GRANT ALL ON TABLE "public"."emp_shifts" TO "anon";
GRANT ALL ON TABLE "public"."emp_shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."emp_shifts" TO "service_role";



GRANT ALL ON TABLE "public"."emp_vacations" TO "anon";
GRANT ALL ON TABLE "public"."emp_vacations" TO "authenticated";
GRANT ALL ON TABLE "public"."emp_vacations" TO "service_role";



GRANT ALL ON TABLE "public"."extras_catalog" TO "anon";
GRANT ALL ON TABLE "public"."extras_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."extras_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."faq_items" TO "anon";
GRANT ALL ON TABLE "public"."faq_items" TO "authenticated";
GRANT ALL ON TABLE "public"."faq_items" TO "service_role";



GRANT ALL ON TABLE "public"."feature_flags" TO "anon";
GRANT ALL ON TABLE "public"."feature_flags" TO "authenticated";
GRANT ALL ON TABLE "public"."feature_flags" TO "service_role";



GRANT ALL ON TABLE "public"."financial_events" TO "anon";
GRANT ALL ON TABLE "public"."financial_events" TO "authenticated";
GRANT ALL ON TABLE "public"."financial_events" TO "service_role";



GRANT ALL ON TABLE "public"."flexi_reports" TO "anon";
GRANT ALL ON TABLE "public"."flexi_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."flexi_reports" TO "service_role";



GRANT ALL ON TABLE "public"."flexi_sync_log" TO "anon";
GRANT ALL ON TABLE "public"."flexi_sync_log" TO "authenticated";
GRANT ALL ON TABLE "public"."flexi_sync_log" TO "service_role";



GRANT ALL ON TABLE "public"."gear_shortages" TO "anon";
GRANT ALL ON TABLE "public"."gear_shortages" TO "authenticated";
GRANT ALL ON TABLE "public"."gear_shortages" TO "service_role";



GRANT ALL ON TABLE "public"."generated_documents" TO "anon";
GRANT ALL ON TABLE "public"."generated_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."generated_documents" TO "service_role";



GRANT ALL ON TABLE "public"."inventory" TO "anon";
GRANT ALL ON TABLE "public"."inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_movements" TO "anon";
GRANT ALL ON TABLE "public"."inventory_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_movements" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT ALL ON TABLE "public"."kiosk_commands" TO "anon";
GRANT ALL ON TABLE "public"."kiosk_commands" TO "authenticated";
GRANT ALL ON TABLE "public"."kiosk_commands" TO "service_role";



GRANT ALL ON TABLE "public"."kiosk_devices" TO "anon";
GRANT ALL ON TABLE "public"."kiosk_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."kiosk_devices" TO "service_role";



GRANT ALL ON TABLE "public"."kiosk_logs" TO "anon";
GRANT ALL ON TABLE "public"."kiosk_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."kiosk_logs" TO "service_role";



GRANT ALL ON TABLE "public"."loyalty_levels" TO "anon";
GRANT ALL ON TABLE "public"."loyalty_levels" TO "authenticated";
GRANT ALL ON TABLE "public"."loyalty_levels" TO "service_role";



GRANT ALL ON TABLE "public"."loyalty_monthly_winners" TO "anon";
GRANT ALL ON TABLE "public"."loyalty_monthly_winners" TO "authenticated";
GRANT ALL ON TABLE "public"."loyalty_monthly_winners" TO "service_role";



GRANT ALL ON TABLE "public"."maintenance_log" TO "anon";
GRANT ALL ON TABLE "public"."maintenance_log" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_log" TO "service_role";



GRANT ALL ON TABLE "public"."maintenance_schedules" TO "anon";
GRANT ALL ON TABLE "public"."maintenance_schedules" TO "authenticated";
GRANT ALL ON TABLE "public"."maintenance_schedules" TO "service_role";



GRANT ALL ON TABLE "public"."message_log" TO "anon";
GRANT ALL ON TABLE "public"."message_log" TO "authenticated";
GRANT ALL ON TABLE "public"."message_log" TO "service_role";



GRANT ALL ON TABLE "public"."message_templates" TO "anon";
GRANT ALL ON TABLE "public"."message_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."message_templates" TO "service_role";



GRANT ALL ON TABLE "public"."message_threads" TO "anon";
GRANT ALL ON TABLE "public"."message_threads" TO "authenticated";
GRANT ALL ON TABLE "public"."message_threads" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."moto_day_prices" TO "anon";
GRANT ALL ON TABLE "public"."moto_day_prices" TO "authenticated";
GRANT ALL ON TABLE "public"."moto_day_prices" TO "service_role";



GRANT ALL ON TABLE "public"."moto_locations" TO "anon";
GRANT ALL ON TABLE "public"."moto_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."moto_locations" TO "service_role";



GRANT ALL ON TABLE "public"."moto_performance" TO "anon";
GRANT ALL ON TABLE "public"."moto_performance" TO "authenticated";
GRANT ALL ON TABLE "public"."moto_performance" TO "service_role";



GRANT ALL ON TABLE "public"."notification_log" TO "anon";
GRANT ALL ON TABLE "public"."notification_log" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_log" TO "service_role";



GRANT ALL ON TABLE "public"."notification_rules" TO "anon";
GRANT ALL ON TABLE "public"."notification_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_rules" TO "service_role";



GRANT ALL ON TABLE "public"."payment_methods" TO "anon";
GRANT ALL ON TABLE "public"."payment_methods" TO "authenticated";
GRANT ALL ON TABLE "public"."payment_methods" TO "service_role";



GRANT ALL ON TABLE "public"."poi_ratings" TO "anon";
GRANT ALL ON TABLE "public"."poi_ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."poi_ratings" TO "service_role";



GRANT ALL ON TABLE "public"."points_of_interest" TO "anon";
GRANT ALL ON TABLE "public"."points_of_interest" TO "authenticated";
GRANT ALL ON TABLE "public"."points_of_interest" TO "service_role";



GRANT ALL ON TABLE "public"."predictions" TO "anon";
GRANT ALL ON TABLE "public"."predictions" TO "authenticated";
GRANT ALL ON TABLE "public"."predictions" TO "service_role";



GRANT ALL ON TABLE "public"."pricing_rules" TO "anon";
GRANT ALL ON TABLE "public"."pricing_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."pricing_rules" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."promo_code_usage" TO "anon";
GRANT ALL ON TABLE "public"."promo_code_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."promo_code_usage" TO "service_role";



GRANT ALL ON TABLE "public"."promo_codes" TO "anon";
GRANT ALL ON TABLE "public"."promo_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."promo_codes" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_order_items" TO "anon";
GRANT ALL ON TABLE "public"."purchase_order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_order_items" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_orders" TO "anon";
GRANT ALL ON TABLE "public"."purchase_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_orders" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."reviews" TO "anon";
GRANT ALL ON TABLE "public"."reviews" TO "authenticated";
GRANT ALL ON TABLE "public"."reviews" TO "service_role";



GRANT ALL ON TABLE "public"."route_pois" TO "anon";
GRANT ALL ON TABLE "public"."route_pois" TO "authenticated";
GRANT ALL ON TABLE "public"."route_pois" TO "service_role";



GRANT ALL ON TABLE "public"."route_reviews" TO "anon";
GRANT ALL ON TABLE "public"."route_reviews" TO "authenticated";
GRANT ALL ON TABLE "public"."route_reviews" TO "service_role";



GRANT ALL ON TABLE "public"."routes" TO "anon";
GRANT ALL ON TABLE "public"."routes" TO "authenticated";
GRANT ALL ON TABLE "public"."routes" TO "service_role";



GRANT ALL ON TABLE "public"."sent_emails" TO "anon";
GRANT ALL ON TABLE "public"."sent_emails" TO "authenticated";
GRANT ALL ON TABLE "public"."sent_emails" TO "service_role";



GRANT ALL ON TABLE "public"."service_orders" TO "anon";
GRANT ALL ON TABLE "public"."service_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."service_orders" TO "service_role";



GRANT ALL ON TABLE "public"."service_parts" TO "anon";
GRANT ALL ON TABLE "public"."service_parts" TO "authenticated";
GRANT ALL ON TABLE "public"."service_parts" TO "service_role";



GRANT ALL ON TABLE "public"."shop_order_items" TO "anon";
GRANT ALL ON TABLE "public"."shop_order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."shop_order_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."shop_order_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."shop_order_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."shop_order_seq" TO "service_role";



GRANT ALL ON TABLE "public"."shop_orders" TO "anon";
GRANT ALL ON TABLE "public"."shop_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."shop_orders" TO "service_role";



GRANT ALL ON TABLE "public"."sku_catalog" TO "anon";
GRANT ALL ON TABLE "public"."sku_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."sku_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."sos_incidents" TO "anon";
GRANT ALL ON TABLE "public"."sos_incidents" TO "authenticated";
GRANT ALL ON TABLE "public"."sos_incidents" TO "service_role";



GRANT ALL ON TABLE "public"."sos_timeline" TO "anon";
GRANT ALL ON TABLE "public"."sos_timeline" TO "authenticated";
GRANT ALL ON TABLE "public"."sos_timeline" TO "service_role";



GRANT ALL ON TABLE "public"."stock_receipts" TO "anon";
GRANT ALL ON TABLE "public"."stock_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_receipts" TO "service_role";



GRANT ALL ON TABLE "public"."suppliers" TO "anon";
GRANT ALL ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."tax_records" TO "anon";
GRANT ALL ON TABLE "public"."tax_records" TO "authenticated";
GRANT ALL ON TABLE "public"."tax_records" TO "service_role";



GRANT ALL ON TABLE "public"."user_pois" TO "anon";
GRANT ALL ON TABLE "public"."user_pois" TO "authenticated";
GRANT ALL ON TABLE "public"."user_pois" TO "service_role";



GRANT ALL ON TABLE "public"."user_saved_routes" TO "anon";
GRANT ALL ON TABLE "public"."user_saved_routes" TO "authenticated";
GRANT ALL ON TABLE "public"."user_saved_routes" TO "service_role";



GRANT ALL ON TABLE "public"."user_visited_places" TO "anon";
GRANT ALL ON TABLE "public"."user_visited_places" TO "authenticated";
GRANT ALL ON TABLE "public"."user_visited_places" TO "service_role";



GRANT ALL ON TABLE "public"."v_api_performance" TO "anon";
GRANT ALL ON TABLE "public"."v_api_performance" TO "authenticated";
GRANT ALL ON TABLE "public"."v_api_performance" TO "service_role";



GRANT ALL ON TABLE "public"."v_recent_crashes" TO "anon";
GRANT ALL ON TABLE "public"."v_recent_crashes" TO "authenticated";
GRANT ALL ON TABLE "public"."v_recent_crashes" TO "service_role";



GRANT ALL ON TABLE "public"."v_screen_error_rate" TO "anon";
GRANT ALL ON TABLE "public"."v_screen_error_rate" TO "authenticated";
GRANT ALL ON TABLE "public"."v_screen_error_rate" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_debug_timeline" TO "anon";
GRANT ALL ON TABLE "public"."v_user_debug_timeline" TO "authenticated";
GRANT ALL ON TABLE "public"."v_user_debug_timeline" TO "service_role";



GRANT ALL ON TABLE "public"."visitor_log" TO "anon";
GRANT ALL ON TABLE "public"."visitor_log" TO "authenticated";
GRANT ALL ON TABLE "public"."visitor_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."visitor_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."visitor_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."visitor_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."vouchers" TO "anon";
GRANT ALL ON TABLE "public"."vouchers" TO "authenticated";
GRANT ALL ON TABLE "public"."vouchers" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







