-- =============================================================================
-- MIGRACE 2026-08-22c: STORNO STROP PO POSUNU TERMÍNU (uzavření díry ve vratkách)
--
-- Problém: zákazník s rezervací začínající za <7 dní (vratka 50 %) nebo <2 dny
-- (vratka 0 %) si termín NEJDŘÍV zdarma posunul o 7+ dní dopředu
-- (reschedule_booking_free / úprava rezervace) a PAK stornoval — storno tabulka
-- se počítala jen z aktuálního start_date, takže dostal 100 % zpět.
--
-- Pravidlo (zadání 2026-08-22): storno vždy bere v úvahu původní termín.
-- Jakmile byl start rezervace kdykoli posunut, vratka při zrušení už NIKDY
-- není 100 %:
--   * posun provedený ≥168 h před TEHDEJŠÍM (před-posunovým) startem → strop 50 %
--   * posun provedený <168 h před tehdejším startem                 → strop 0 %
-- Při více posunech platí nejpřísnější strop; finální % = LEAST(storno tabulka
-- z aktuálního startu, strop) — vždy přísnější sazba pro zákazníka.
--
-- Zdroj posunů: bookings.modification_history (záznamy s from_start<>to_start;
-- zapisují VŠECHNY cesty: reschedule_booking_free, _apply_booking_changes_core,
-- shorten_booking_with_refund, appka klient-side, Velín BookingModifyModal
-- i auto-trigger track_booking_content_changes). Pojistka: liší-li se
-- original_start_date od start_date a historie žádný posun nenese (starý
-- klient), počítá se přísnější odhad z původního startu vůči now().
--
-- Aplikováno do: cancel_booking_tracked (plné storno), shorten_booking_with_refund
-- (zkrácení = částečné storno), _apply_booking_changes_core (vratková větev
-- úpravy). Klientská zrcadla: web js/pages-upravit-rezervaci.js
-- (_stornoCapAfterMove/_refundPercentFor), app StornoCalc (oba stromy).
-- Těla funkcí = poslední verze (20260804 / 20260806) + vložený strop.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._storno_cap_after_move(
  p_history        jsonb,
  p_original_start date,
  p_current_start  date
) RETURNS integer
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_cap   integer := 100;
  v_moved boolean := false;
  e       jsonb;
  v_from  date;
  v_to    date;
  v_at    timestamptz;
  v_hours numeric;
BEGIN
  IF p_history IS NOT NULL AND jsonb_typeof(p_history) = 'array' THEN
    FOR e IN SELECT * FROM jsonb_array_elements(p_history) LOOP
      BEGIN
        IF (e ? 'from_start') AND (e ? 'to_start')
           AND COALESCE(e->>'from_start','') <> '' AND COALESCE(e->>'to_start','') <> '' THEN
          v_from := (e->>'from_start')::date;
          v_to   := (e->>'to_start')::date;
          IF v_from IS DISTINCT FROM v_to THEN
            v_moved := true;
            v_at    := COALESCE((e->>'at')::timestamptz, now());
            v_hours := EXTRACT(EPOCH FROM (v_from::timestamptz - v_at)) / 3600.0;
            v_cap   := LEAST(v_cap, CASE WHEN v_hours >= 168 THEN 50 ELSE 0 END);
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL; -- nevalidní záznam historie nesmí shodit výpočet stropu
      END;
    END LOOP;
  END IF;

  -- Pojistka: start se od původního liší, ale historie posun nezachytila —
  -- čas posunu neznáme, platí přísnější odhad z původního startu vůči now().
  IF NOT v_moved AND p_original_start IS NOT NULL
     AND p_current_start IS NOT NULL AND p_original_start <> p_current_start THEN
    v_hours := EXTRACT(EPOCH FROM (p_original_start::timestamptz - now())) / 3600.0;
    v_cap   := LEAST(v_cap, CASE WHEN v_hours >= 168 THEN 50 ELSE 0 END);
  END IF;

  RETURN v_cap;
END;
$$;

-- ── 1) cancel_booking_tracked — plné storno se stropem po posunu ─────────────
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
  -- 2026-08-22c: STROP PO POSUNU TERMÍNU — storno tabulka se počítá z
  -- AKTUÁLNÍHO startu, ale posunutá rezervace už nikdy nemá 100% vratku:
  -- posun ≥168 h před PŮVODNÍM (před-posunovým) startem → max 50 %, pozdější
  -- posun → 0 %. Vždy přísnější sazba (LEAST). Viz _storno_cap_after_move.
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

-- ── 2) shorten_booking_with_refund — zkrácení (částečné storno) se stropem ───

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
  -- 2026-08-22c: strop po posunu termínu — po posunu startu už nikdy 100 %
  v_percent := LEAST(v_percent, public._storno_cap_after_move(
    v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
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

-- ── 3) _apply_booking_changes_core — vratková větev úpravy se stropem ────────
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
REVOKE ALL ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) FROM PUBLIC, anon, authenticated;
