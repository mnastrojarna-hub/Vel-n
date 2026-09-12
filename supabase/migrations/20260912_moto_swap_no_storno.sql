-- 2026-09-12 — Výměna motorky v úpravě rezervace: rozdíl ceníku NEPODLÉHÁ stornu
-- ==========================================================================
-- Incident C69236EB (12. 9. 2026): zákazník v appce vyměnil Honda CRF 1000
-- Africa Twin → Benelli TRK 702 X den před startem. Rozdíl ceníku (levnější
-- motorka) se v obecné editaci (appka EditPriceCalc i toto SQL jádro pro web)
-- počítal do JEDNOHO čísla s odebranými dny a záporná část se krátila storno
-- tabulkou (≥168 h 100 %, ≥48 h 50 %, jinak 0 %) → rozdíl 0 Kč, total_price
-- beze změny, trigger poslal booking_modified s price_difference 0 → žádný
-- dobropis ani vratka. Záložka „Výměna motorky" (split_booking_moto_swap) i
-- Velín přitom vracejí plný rozdíl.
--
-- ZMĚNY v _apply_booking_changes_core (tělo 1:1 z 20260822c + tyto úpravy):
--   1) ROZDÍL TERMÍNU = nový rozsah oceněný ceníkem STARÉ motorky − starý
--      rozsah (vč. late slevy). JEN tato část se při záporné hodnotě krátí
--      storno % (+ strop po posunu termínu).
--   2) ROZDÍL VÝMĚNY MOTORKY = na NOVÉM rozsahu (nový ceník − starý ceník,
--      vč. late slevy) — 100 % v obou směrech (doplatek i vratka).
--      v_moto_diff byl dřív mrtvá proměnná (vždy 0).
--   3) Věrnostní sleva na doplatek (app) se počítá z kladného součtu obou částí.
--   4) Nová motorka smí být i status='maintenance' (web i appka ji nabízejí;
--      servisní dny blokuje kontrola maintenance_log) — dřív moto_not_found.
--   5) Důvod vratky pro process-refund = kód (moto_swap / edit_shortening /
--      edit) místo volného textu p_reason → dobropis nese „Výměna motorky".
--   6) modification_history nese navíc dates_diff + moto_diff.
-- Appka (oba stromy, EditPriceCalc.datesDiff + motoDiff) počítá totéž.
-- Idempotentní (CREATE OR REPLACE). Signatura beze změny.

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
  v_loy_level       int := 0;
  v_loy_pct         numeric := 0;
  v_loy_disc        numeric := 0;
  v_new_on_old_total numeric := 0;   -- nový rozsah oceněný ceníkem STARÉ motorky
  v_new_late_old    numeric := 0;    -- late sleva nového rozsahu dle STARÉ motorky
  v_moto_swapped    boolean := false;
  v_refund_reason   text;
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
    -- 2026-09-12: i 'maintenance' (web /upravit-rezervaci i appka je nabízejí —
    -- servisní dny blokuje kontrola maintenance_log níže; dřív server vracel
    -- moto_not_found a web výměnu neprovedl).
    SELECT * INTO v_new_moto FROM motorcycles WHERE id = p_new_moto_id AND status IN ('active','maintenance');
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
    v_moto_swapped := true;
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

  -- Nový rozsah oceněný ceníkem STARÉ motorky — základ rozdílu TERMÍNU
  -- (storno se krátí jen odebrané dny, ne rozdíl ceníku motorek).
  v_d := v_fs;
  WHILE v_d <= v_fe LOOP
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
    v_new_on_old_total := v_new_on_old_total + v_p_old;
    v_d := v_d + 1;
  END LOOP;

  -- ── LATE PICKUP ── stará = REÁLNĚ uložená hodnota (ne přepočet — jinak by
  -- legacy rezervace bez late vykázala fantomový rozdíl); nová = přepočet pro
  -- nový obsah + efektivní čas vyzvednutí.
  v_old_late     := COALESCE(v_b.late_pickup_discount_amount, 0);
  v_new_late     := public._late_pickup_discount(v_use_moto.id, v_fs, v_fe, v_eff_pickup);
  v_new_late_old := CASE WHEN v_moto_swapped
                         THEN public._late_pickup_discount(v_old_moto.id, v_fs, v_fe, v_eff_pickup)
                         ELSE v_new_late END;

  -- ── ROZDÍL TERMÍNU (ceník STARÉ motorky) — jen tahle část podléhá stornu ──
  v_dates_diff := (v_new_on_old_total - v_new_late_old) - (v_old_dates_total - v_old_late);
  -- ── ROZDÍL VÝMĚNY MOTORKY na novém rozsahu (nový − starý ceník) — 100 % v
  -- obou směrech, storno se NEvztahuje (2026-09-12, parita split_booking_moto_swap
  -- a Velín; incident C69236EB: levnější motorka <48 h před startem → storno 0 %
  -- → rozdíl 0 Kč → žádný dobropis). ──
  v_moto_diff := CASE WHEN v_moto_swapped
                      THEN (v_new_dates_total - v_new_late) - (v_new_on_old_total - v_new_late_old)
                      ELSE 0 END;
  IF v_dates_diff < 0 THEN
    v_storno_pct := CASE
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 168 THEN 100
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 48  THEN 50
      ELSE 0
    END;
    -- 2026-08-22c: STROP PO POSUNU TERMÍNU — jakmile byl start rezervace
    -- kdykoli posunut, vratka za odebrané dny už nikdy není 100 %
    -- (viz _storno_cap_after_move; vždy přísnější sazba pro zákazníka).
    v_storno_pct := LEAST(v_storno_pct, public._storno_cap_after_move(
      v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
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
  IF COALESCE(v_b.booking_source, 'web') = 'app' AND (v_dates_diff + v_moto_diff) > 0 THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(v_b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND((v_dates_diff + v_moto_diff) * v_loy_pct / 100.0);
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
    'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
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
    -- Důvod vratky = kód pro položku dobropisu (process-refund reasonTextFor):
    -- jen výměna motorky → „Výměna motorky", změna termínu → „Zkrácení
    -- rezervace", jinak „Úprava rezervace". p_reason je volný text zákazníka
    -- (web textarea) — do dokladu nepatří, zůstává jen v historii.
    v_refund_reason := CASE
      WHEN v_moto_swapped AND v_fs = v_b.start_date AND v_fe = v_b.end_date THEN 'moto_swap'
      WHEN v_fs <> v_b.start_date OR v_fe <> v_b.end_date THEN 'edit_shortening'
      ELSE 'edit' END;
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', v_refund_reason, 'source', 'edit')
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
REVOKE ALL ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) FROM PUBLIC, anon, authenticated;
