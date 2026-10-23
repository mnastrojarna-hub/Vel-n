-- =============================================================================
-- 2026-10-23 (e_a): Storno a web „Zkrátit" — jednotné pásmo vratky (§1.11).
-- Pásmo od teď do AKTUÁLNÍHO začátku v čase vyzvednutí (Praha) přes
-- _refund_tier_pct (20261023e_refund_unify.sql); strop _storno_cap_after_move
-- a rozpad slevy beze změny. Výbava: cena dne = gear_per_day. Idempotentní.
-- =============================================================================

-- ---- 1) Storno: pásmo k času vyzvednutí (Praha) ---------------------------------
-- Tělo dle živé DB; mění se jen výpočet pásma (dřív hodiny do 00:00 UTC dne
-- začátku) + search_path. Výbava: motorcycle = '' (send-cancellation-email
-- pozná výbavu podle booking_id).
CREATE OR REPLACE FUNCTION public.cancel_booking_tracked(p_booking_id uuid, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_booking      bookings%ROWTYPE;
  v_profile      profiles%ROWTYPE;
  v_moto_model   text;
  v_uid          uuid;
  v_refund_pct   integer;
  v_refund_amt   numeric;
  v_url          text;
  v_key          text;
  v_staff        boolean;  -- 2026-10-11
BEGIN
  v_uid := auth.uid();
  v_staff := public._rpc_caller_is_staff();  -- 2026-10-11

  -- 2026-10-11: bez přihlášení (a mimo server) vůbec nehledat
  IF v_uid IS NULL AND NOT v_staff THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;

  -- 2026-10-11: NULL-bezpečně — vlastník, admin nebo server
  IF NOT v_staff AND v_booking.user_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'Rezervace je již stornována');
  END IF;

  -- 2026-10-23e: zákazník stornuje jen nezačatou rezervaci (čeká na platbu / nadcházející);
  -- probíhající ani dokončenou ne (dřív to RPC pustilo → zrušené kódy za jízdy). Obsluha beze změny.
  IF NOT v_staff AND v_booking.status NOT IN ('pending', 'reserved') THEN
    RETURN jsonb_build_object('error', 'wrong_status');
  END IF;

  -- 2026-10-23e: pásmo od teď do začátku v čase vyzvednutí (Praha) — VOP čl. 3c
  -- „7 dní před sjednaným termínem převzetí"; hranice ≥168 h / ≥48 h beze změny.
  v_refund_pct := public._refund_tier_pct(v_booking.start_date, LEAST(v_booking.refund_pickup_time, v_booking.pickup_time));
  -- 2026-08-22c: STROP PO POSUNU TERMÍNU — posunutá rezervace už nikdy nemá
  -- 100% vratku (posun ≥168 h před PŮVODNÍM startem → max 50 %, pozdější → 0 %).
  v_refund_pct := LEAST(v_refund_pct, public._storno_cap_after_move(
    v_booking.modification_history, v_booking.original_start_date::date, v_booking.start_date::date));
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
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
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

  RETURN jsonb_build_object('success', true, 'refund_percent', v_refund_pct, 'refund_amount', v_refund_amt);
END;
$$;

-- ---- 2) Zkrácení s vratkou (web „Zkrátit") ------------------------------------
-- Tělo dle živé DB. Změny 2026-10-23e: (a) pásmo k AKTUÁLNÍMU začátku v čase
-- vyzvednutí (dřív k novému konci, resp. začátku); (b) uloží se jen PŘIZNANÁ
-- late sleva (parita s jádrem 2026-10-01h); (c) důvod vratky pro dobropis
-- 'shortening' (volný text zákazníka jen v historii); (d) výbava: cena dne =
-- gear_per_day, řádky gear_lines na nový počet dní.
CREATE OR REPLACE FUNCTION public.shorten_booking_with_refund(p_booking_id uuid, p_new_start date, p_new_end date, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user        uuid := auth.uid();
  v_b           bookings%ROWTYPE;
  v_moto        motorcycles%ROWTYPE;
  v_orig_total  numeric;
  v_new_total_g numeric;
  v_diff        numeric;
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
  v_late_store  numeric := 0;
  v_gear        boolean;
BEGIN
  IF v_user IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  -- 2026-10-23e: NULL-bezpečně (rezervace bez vlastníka nepatří nikomu)
  IF NOT FOUND OR v_b.user_id IS DISTINCT FROM v_user THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF v_b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
  IF v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success', false, 'error', 'not_paid'); END IF;
  IF p_new_start < v_b.start_date OR p_new_end > v_b.end_date THEN RETURN jsonb_build_object('success', false, 'error', 'not_a_shortening'); END IF;
  IF p_new_start > p_new_end THEN RETURN jsonb_build_object('success', false, 'error', 'invalid_range'); END IF;
  IF v_b.status = 'active' AND p_new_start <> v_b.start_date THEN RETURN jsonb_build_object('success', false, 'error', 'active_start_locked'); END IF;
  IF p_new_start = v_b.start_date AND p_new_end = v_b.end_date THEN RETURN jsonb_build_object('success', false, 'error', 'no_change'); END IF;
  v_gear := (v_b.booking_kind = 'gear');

  IF v_gear THEN
    -- výbava: cena dne = gear_per_day (bez ceníku motorky)
    v_orig_total  := COALESCE(v_b.gear_per_day, 0) * ((v_b.end_date::date - v_b.start_date::date) + 1);
    v_new_total_g := COALESCE(v_b.gear_per_day, 0) * ((p_new_end - p_new_start) + 1);
  ELSE
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
  END IF;

  v_old_late := COALESCE(v_b.late_pickup_discount_amount, 0);   -- reálně uložená, ne přepočet
  v_new_late := public._late_pickup_discount(v_b.moto_id, p_new_start, p_new_end, v_b.pickup_time);  -- výbava: 0

  v_diff := (v_orig_total - v_old_late) - (v_new_total_g - v_new_late);
  IF v_diff <= 0 THEN RETURN jsonb_build_object('success', false, 'error', 'no_diff'); END IF;

  -- 2026-10-23e: pásmo k AKTUÁLNÍMU začátku (před změnou) v čase vyzvednutí, Praha
  v_percent := public._refund_tier_pct(v_b.start_date, LEAST(v_b.refund_pickup_time, v_b.pickup_time), v_now);
  -- 2026-08-22c: strop po posunu termínu — po posunu startu už nikdy 100 %
  v_percent := LEAST(v_percent, public._storno_cap_after_move(
    v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
  v_refund_gross := ROUND(v_diff * v_percent / 100.0);
  -- 2026-10-23e: uloží se jen přiznaná late sleva (neproplacená část zisku late
  -- slevy = storno z té části rozdílu, kterou late sleva tvoří) — parita s jádrem
  v_late_store := GREATEST(0, v_new_late - ROUND(LEAST(GREATEST(0, v_new_late - v_old_late), v_diff)
                                                 * (100 - v_percent) / 100.0));

  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, -v_refund_gross, false);
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;
  v_refund       := GREATEST(0, -((v_calc->>'net_diff')::numeric));

  IF v_gear THEN PERFORM set_config('motogo.gear_rpc', '1', true); END IF;
  UPDATE bookings SET
    original_start_date = COALESCE(original_start_date, start_date),
    original_end_date   = COALESCE(original_end_date,   end_date),
    start_date          = p_new_start,
    end_date            = p_new_end,
    total_price         = v_new_total,
    discount_amount     = v_new_discount,
    late_pickup_discount_amount = v_late_store,
    gear_lines          = CASE WHEN v_gear THEN public._gear_lines_for_days(gear_lines, (p_new_end - p_new_start) + 1)
                               ELSE gear_lines END,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', v_now, 'from_start', v_b.start_date, 'from_end', v_b.end_date,
      'to_start', p_new_start, 'to_end', p_new_end, 'source', 'web_customer',
      'refund_amount', v_refund, 'refund_percent', v_percent, 'gross_refund', v_refund_gross,
      'refund_ref', public._refund_tier_ref(v_b.start_date, LEAST(v_b.refund_pickup_time, v_b.pickup_time)),
      'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
      'from_late_pickup', v_old_late, 'to_late_pickup', v_late_store, 'reason', p_reason
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
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'shortening', 'source', 'shorten')
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

NOTIFY pgrst, 'reload schema';
