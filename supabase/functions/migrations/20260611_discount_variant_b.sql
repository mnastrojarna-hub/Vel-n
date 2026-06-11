-- =============================================================================
-- MIGRACE 2026-06-11 (D): Varianta B — sleva se při úpravě rezervace přepočítá
--                          na nový obsah rezervace
--
-- Problém: refund při úpravě (zkrácení / levnější motorka / odebraná výbava)
-- se počítal z HRUBÝCH cen. Zákazník s 98% slevou (zaplatil 60 Kč) by při
-- zkrácení matematicky dostal zpět stovky/tisíce Kč (Stripe clamp to sice
-- ořízl na 60 Kč, ale i tak: jel zdarma A dostal zpět vše, co zaplatil).
--
-- Schválené řešení (varianta B):
--   Při každé úpravě se spočítá nová HRUBÁ cena obsahu rezervace a znovu se
--   na ni aplikuje původní sleva:
--     - procentuální: efektivní sazba r = discount_amount / (total + discount)
--       odvozená z reálných čísel rezervace → new_discount = new_gross × r
--     - absolutní (voucher / fixed promo): new_discount = MIN(hodnota, new_gross)
--   net_diff = (new_gross − new_discount) − staré total_price
--     > 0 → doplatek přes bránu (rozdílový DP)
--     < 0 → Stripe refund + dobropis na net částku
--   bookings.discount_amount se aktualizuje na new_discount (KF rozpis sedí).
--   Storno tabulka (100/50/0 %) se dál aplikuje na hrubý rozdíl PŘED slevou
--   (pro procentuální slevu je výsledek matematicky identický s pořadím naopak).
--
-- Příklady:
--   98% sleva, hrubá 3000, zaplaceno 60; zkrácení o 1500 hrubého (storno 100 %)
--     → new_gross 1500, new_discount 1470, new_total 30 → vrací se 30 Kč.
--   Voucher 1000, hrubá 3000, zaplaceno 2000; zkrácení na hrubých 1500
--     → new_discount 1000, new_total 500 → vrací se 1500 Kč.
--   Voucher 2950, zaplaceno 50; zkrácení na hrubých 1000 → new_total 0
--     → vrací se max 50 Kč (jen co reálně zaplatil; zbytek voucheru propadá).
--   Prodloužení s 20% slevou o hrubých 1000 → doplatek 800 Kč (sleva platí
--     i na prodloužení). 100% sleva → prodloužení zdarma (konzistentní).
--
-- Mění se: _apply_booking_changes_core, shorten_booking_with_refund,
--          update_booking_gear + 2 nové helpery.
-- Re-aplikované dřívější fixy (snapshot 2026-06-04 je neobsahoval):
--   - _apply_booking_changes_core: čtení URL/key z app_settings + izolovaný
--     refund dispatch + delivery_fee CASE (fix 2026-06-09)
--   - shorten_booking_with_refund: STEJNÝ GUC bug (current_setting
--     'app.settings.*' na managed Supabase neexistuje → refund dispatch tiše
--     padal a rollbackoval transakci) — nyní app_settings + BEGIN/EXCEPTION.
-- =============================================================================

-- ── Helper 1: typ slevy rezervace ('percent' | 'fixed') ─────────────────────
-- voucher → fixed; promo_codes lookup přes promo_code_id, pak přes kód
-- (promo_code / discount_code). Neznámé → 'fixed' (konzervativní: absolutní
-- sleva se nepřepočítává nahoru, refund kryje Stripe clamp).
CREATE OR REPLACE FUNCTION public._booking_discount_type(
  p_promo_code_id uuid,
  p_promo_code    text,
  p_discount_code text,
  p_voucher_id    uuid
) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
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
REVOKE ALL ON FUNCTION public._booking_discount_type(uuid, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._booking_discount_type(uuid, text, text, uuid) TO authenticated, service_role;

-- ── Helper 2: jádro varianty B ───────────────────────────────────────────────
-- Vstup: staré total (netto), stará sleva (Kč), hrubý rozdíl úpravy (po stornu),
-- typ slevy. Výstup: {new_gross, new_discount, new_total, net_diff}.
CREATE OR REPLACE FUNCTION public._apply_discount_variant_b(
  p_old_total    numeric,
  p_old_discount numeric,
  p_gross_diff   numeric,
  p_dtype        text
) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_old_total    numeric := COALESCE(p_old_total, 0);
  v_old_discount numeric := GREATEST(COALESCE(p_old_discount, 0), 0);
  v_old_gross    numeric := COALESCE(p_old_total, 0) + GREATEST(COALESCE(p_old_discount, 0), 0);
  v_new_gross    numeric;
  v_new_discount numeric;
  v_new_total    numeric;
BEGIN
  v_new_gross := GREATEST(0, v_old_gross + COALESCE(p_gross_diff, 0));
  IF v_old_discount <= 0 THEN
    v_new_discount := 0;
  ELSIF p_dtype = 'percent' AND v_old_gross > 0 THEN
    -- efektivní sazba odvozená z reálných čísel rezervace
    v_new_discount := ROUND(v_new_gross * v_old_discount / v_old_gross);
  ELSE
    -- fixed / neznámý typ: absolutní hodnota, max do výše nové hrubé ceny
    v_new_discount := LEAST(v_old_discount, v_new_gross);
  END IF;
  v_new_total := GREATEST(0, v_new_gross - v_new_discount);
  RETURN jsonb_build_object(
    'new_gross',    v_new_gross,
    'new_discount', v_new_discount,
    'new_total',    v_new_total,
    'net_diff',     v_new_total - v_old_total
  );
END;
$$;

-- ── 1) _apply_booking_changes_core — varianta B + re-aplikace fixů 2026-06-09 ─
CREATE OR REPLACE FUNCTION "public"."_apply_booking_changes_core"("p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date", "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text", "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric, "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision, "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text", "p_dry_run" boolean, "p_source" "text") RETURNS "jsonb"
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
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.user_id <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  -- 'partial_refund'/'refund_pending' = rezervace po předchozí vratkové úpravě —
  -- musí jít upravit znovu (jinak by druhá úprava na webu vracela wrong_status).
  IF v_b.status NOT IN ('reserved','active') OR v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;

  v_is_active := (v_b.status = 'active');

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

  v_dates_diff := v_new_dates_total - v_old_dates_total;
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

  -- Hrubý rozdíl úpravy (po stornu na datumové části)
  v_gross_diff := v_dates_diff + v_moto_diff + v_pickup_fee_diff + v_return_fee_diff;

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  v_dtype := _booking_discount_type(v_b.promo_code_id, v_b.promo_code, v_b.discount_code, v_b.voucher_id);
  v_calc  := _apply_discount_variant_b(v_b.total_price, v_b.discount_amount, v_gross_diff, v_dtype);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_changed := (
    v_fs <> v_b.start_date OR v_fe <> v_b.end_date
    OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id)
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
      'success', true,
      'payment_required', v_payment_required,
      'net_diff', v_net_diff,
      'refund_amount', v_refund,
      'new_total', v_new_total,
      'new_discount', v_new_discount,
      'breakdown', jsonb_build_object(
        'dates_diff',       v_dates_diff,
        'moto_diff',        v_moto_diff,
        'pickup_fee_diff',  v_pickup_fee_diff,
        'return_fee_diff',  v_return_fee_diff,
        'gross_diff',       v_gross_diff,
        'discount_type',    v_dtype,
        'storno_pct',       v_storno_pct
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
    'net_diff', v_net_diff, 'gross_diff', v_gross_diff,
    'refund_amount', v_refund, 'storno_pct', v_storno_pct,
    'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
    'price_diff', v_net_diff,
    'reason', p_reason, 'source', COALESCE(p_source, 'web_customer')
  );

  UPDATE bookings SET
    original_start_date = COALESCE(original_start_date, start_date),
    original_end_date   = COALESCE(original_end_date,   end_date),
    start_date          = v_fs,
    end_date            = v_fe,
    moto_id             = v_use_moto.id,
    pickup_method       = COALESCE(p_new_pickup_method, pickup_method),
    pickup_address      = COALESCE(p_new_pickup_address, pickup_address),
    pickup_lat          = COALESCE(p_new_pickup_lat, pickup_lat),
    pickup_lng          = COALESCE(p_new_pickup_lng, pickup_lng),
    return_method       = COALESCE(p_new_return_method, return_method),
    return_address      = COALESCE(p_new_return_address, return_address),
    return_lat          = COALESCE(p_new_return_lat, return_lat),
    return_lng          = COALESCE(p_new_return_lng, return_lng),
    -- delivery_fee se přepíše JEN při reálné změně místa (fix 2026-06-09)
    delivery_fee        = CASE WHEN p_new_pickup_fee IS NOT NULL OR p_new_return_fee IS NOT NULL
                               THEN COALESCE(p_new_pickup_fee, 0) + COALESCE(p_new_return_fee, 0)
                               ELSE delivery_fee END,
    total_price         = v_new_total,
    discount_amount     = v_new_discount,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || v_history_entry
  WHERE id = p_booking_id;

  -- Refund dispatch — izolovaný blok, čte z app_settings (fix 2026-06-09;
  -- GUC app.settings.* na hostovaném Supabase neexistuje a throw by
  -- rollbacknul uloženou změnu).
  IF v_refund > 0 AND v_b.stripe_payment_intent_id IS NOT NULL THEN
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_key
          ),
          body := jsonb_build_object(
            'booking_id', p_booking_id,
            'amount', v_refund,
            'reason', COALESCE(p_reason, 'edit'),
            'source', 'edit'
          )
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
    'success', true,
    'payment_required', false,
    'net_diff', v_net_diff,
    'refund_amount', v_refund,
    'new_total', v_new_total,
    'new_discount', v_new_discount,
    'breakdown', jsonb_build_object(
      'dates_diff',       v_dates_diff,
      'moto_diff',        v_moto_diff,
      'pickup_fee_diff',  v_pickup_fee_diff,
      'return_fee_diff',  v_return_fee_diff,
      'gross_diff',       v_gross_diff,
      'discount_type',    v_dtype,
      'storno_pct',       v_storno_pct
    )
  );
END;
$$;

-- ── 2) shorten_booking_with_refund — varianta B + app_settings dispatch fix ──
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
  v_diff        numeric;            -- kladná = hrubá částka odebraná z obsahu
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
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.user_id <> v_user THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  IF v_b.status NOT IN ('reserved','active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;

  -- partial_refund/refund_pending = po předchozí vratkové úpravě → další zkrácení povoleno
  IF v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  IF p_new_start < v_b.start_date OR p_new_end > v_b.end_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_a_shortening');
  END IF;
  IF p_new_start > p_new_end THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_range');
  END IF;

  IF v_b.status = 'active' AND p_new_start <> v_b.start_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_start_locked');
  END IF;

  IF p_new_start = v_b.start_date AND p_new_end = v_b.end_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

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

  v_diff := v_orig_total - v_new_total_g;
  IF v_diff <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_diff');
  END IF;

  IF p_new_end < v_b.end_date THEN
    v_hours := EXTRACT(EPOCH FROM (p_new_end::timestamptz - v_now)) / 3600.0;
  ELSE
    v_hours := EXTRACT(EPOCH FROM (p_new_start::timestamptz - v_now)) / 3600.0;
  END IF;

  v_percent := CASE
    WHEN v_hours >= 168 THEN 100
    WHEN v_hours >= 48  THEN 50
    ELSE 0
  END;

  -- Hrubá vratka po stornu
  v_refund_gross := ROUND(v_diff * v_percent / 100.0);

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
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
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', v_now,
      'from_start', v_b.start_date,
      'from_end',   v_b.end_date,
      'to_start',   p_new_start,
      'to_end',     p_new_end,
      'source',     'web_customer',
      'refund_amount', v_refund,
      'refund_percent', v_percent,
      'gross_refund', v_refund_gross,
      'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
      'reason', p_reason
    )
  WHERE id = p_booking_id;

  -- Refund dispatch — app_settings + izolace (stejný GUC fix jako u core;
  -- původní current_setting('app.settings.*') na managed Supabase padal a
  -- ROLLBACKoval i uložené zkrácení).
  IF v_refund > 0 AND v_b.stripe_payment_intent_id IS NOT NULL THEN
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_key
          ),
          body := jsonb_build_object(
            'booking_id', p_booking_id,
            'amount', v_refund,
            'reason', COALESCE(p_reason, 'shorten'),
            'source', 'shorten'
          )
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

  RETURN jsonb_build_object(
    'success', true,
    'refund_amount', v_refund,
    'refund_percent', v_percent,
    'new_total', v_new_total
  );
END;
$$;

-- ── 3) update_booking_gear — varianta B na placené výbavě ────────────────────
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

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  -- v_diff je HRUBÝ rozdíl výbavy; net_diff (po slevě) je to, co se účtuje /
  -- vrací zákazníkovi.
  v_dtype := _booking_discount_type(b.promo_code_id, b.promo_code, b.discount_code, b.voucher_id);
  v_calc  := _apply_discount_variant_b(b.total_price, b.discount_amount, v_diff, v_dtype);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  IF p_dry_run THEN
    RETURN jsonb_build_object('success',true,'payment_required', v_net_diff>0,'net_diff',v_net_diff,
      'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
      'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount);
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
    discount_amount = v_new_discount
  WHERE id = p_booking_id;

  DELETE FROM booking_extras WHERE booking_id = p_booking_id
    AND ( lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%'
       OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );
  IF v_new_pass THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Výbava spolujezdce',v_pp,1); END IF;
  IF v_new_br   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty řidič',v_pbr,1); END IF;
  IF v_new_bp   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty spolujezdce',v_pbp,1); END IF;

  RETURN jsonb_build_object('success',true,'payment_required',false,'net_diff',v_net_diff,
    'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
    'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount);
END;
$$;

-- ── 4) _cap_refund_to_paid — správný základ capu ─────────────────────────────
-- PŮVODNÍ BUG: cap na bookings.total_price — jenže rezervace se při úpravě
-- aktualizuje na NOVÉ (nižší) total PŘED vystavením dobropisu → legitimní
-- dobropis větší než nová cena (zkrácení 3000→1000 = vratka 2000) se ořízl
-- na 1000 a účetnictví (i KF=0) se rozjelo se skutečným Stripe refundem.
-- NOVĚ: cap = Σ přijatých plateb (DP) − Σ už vystavených dobropisů. Bez DP
-- řádků se neořezává (jen warning do debug_log) — finanční ochranu drží
-- Stripe-side clamp v process-refund (charged − already refunded).
CREATE OR REPLACE FUNCTION public._cap_refund_to_paid() RETURNS trigger
LANGUAGE plpgsql
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
