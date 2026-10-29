-- =============================================================================
-- 2026-10-23 (e_d): Odebrání kusu ze zaplacené výpůjčky výbavy (zákazník, web).
-- Navazuje na 20261023e_refund_unify.sql (_refund_tier_pct, _gear_lines_for_days).
-- Jen rezervovaná (nepřevzatá) výbava, zůstat musí aspoň 1 kus (jinak storno).
-- Nová cena/den: nedotčené řádky drží uloženou cenu; řádek s odebraným kusem —
-- kus zmizí, komplet se rozpadne na zbylé kusy přeceněné ceníkem (nikdy dráž než
-- komplet; jinak zůstane komplet bez kusu za stejnou cenu → price_unchanged).
-- Vratka = rozdíl ceny/den × zbývající dny × pásmo (_refund_tier_pct +
-- _storno_cap_after_move), rozpad slevy přes _recalc_booking_discount.
-- p_dry_run = jen náhled (bez zámku řádku). Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.customer_remove_gear_item(p_booking_id uuid, p_key text, p_dry_run boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_b bookings%ROWTYPE; v_key text := lower(btrim(COALESCE(p_key, '')));
  v_from jsonb; v_to jsonb; ln jsonb; v_lines jsonb := '[]'::jsonb; v_rest text[]; v_q jsonb;
  v_old_pd numeric; v_new_pd numeric := 0; v_lines_pd numeric := 0; v_set_pd numeric; v_days int; v_pct int; v_gross numeric;
  v_calc jsonb; v_new_total numeric; v_new_disc numeric; v_refund numeric; v_now timestamptz := now();
  v_url text; v_srk text; v_email text; v_name text; v_diff numeric; v_mail boolean := false; v_marker uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'unauthenticated'); END IF;
  IF p_dry_run THEN
    SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  ELSE
    SELECT * INTO v_b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  END IF;
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
  v_pct := LEAST(public._refund_tier_pct(v_b.start_date, LEAST(v_b.refund_pickup_time, v_b.pickup_time), v_now),
                 public._storno_cap_after_move(v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
  v_gross := ROUND((v_old_pd - v_new_pd) * v_days * v_pct / 100.0);
  v_calc := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, -v_gross, false);
  v_new_total := (v_calc->>'new_total')::numeric;
  v_new_disc  := (v_calc->>'new_discount')::numeric;
  v_refund    := GREATEST(0, -((v_calc->>'net_diff')::numeric));
  v_lines := public._gear_lines_for_days(v_lines, (v_b.end_date::date - v_b.start_date::date) + 1);
  v_diff := COALESCE(v_new_total, 0) - COALESCE(v_b.total_price, 0);

  IF p_dry_run THEN
    RETURN jsonb_build_object('success', true, 'dry_run', true, 'refund_amount', v_refund, 'refund_percent', v_pct,
      'price_unchanged', v_new_pd = v_old_pd,
      'removed_value', (v_old_pd - v_new_pd) * v_days, 'old_per_day', v_old_pd, 'new_per_day', v_new_pd,
      'new_total', v_new_total, 'lines', v_lines, 'from', v_from, 'to', v_to);
  END IF;

  -- Mail „Rezervace upravena" = JEDEN, s řádkem kusů (changes.gear) i s cenou.
  -- Mění-li se cena, trigger úprav (trg_booking_modified_email) by poslal vlastní
  -- mail jen s cenou a jeho stopa by pak potlačila mail s kusy → stejnou stopu
  -- zapíšeme PŘED zápisem (trigger ho přeskočí jako duplicitu) a mail + zprávu do
  -- appky (jako trigger) pošleme níže sami. Dedup stejný jako trigger.
  IF v_diff <> 0 THEN
    v_mail := NOT EXISTS (SELECT 1 FROM message_log WHERE booking_id = v_b.id AND template_slug LIKE 'booking_modified%'
                            AND status = 'sent' AND created_at > now() - interval '5 minutes')
          AND NOT EXISTS (SELECT 1 FROM debug_log WHERE created_at > now() - interval '60 seconds'
                            AND source = 'trg_booking_modified_email' AND action = 'http_post_queued'
                            AND request_data->>'booking_id' = v_b.id::text);
    IF v_mail THEN
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('trg_booking_modified_email', 'http_post_queued', 'info',
              jsonb_build_object('booking_id', v_b.id, 'via', 'gear_remove'))
      RETURNING id INTO v_marker;
    END IF;
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
      'refund_amount', v_refund, 'refund_percent', v_pct, 'gross_refund', v_gross, 'price_diff', v_diff)
  WHERE id = p_booking_id;
  -- Trigger už stopu viděl → přejmenovat na vlastní akci helperu (jako _gear_notify_modified),
  -- ať 60s dedup triggeru nepotlačí mail o NÁSLEDNÉ úpravě termínu (FIX-R1, 2026-10-23).
  IF v_marker IS NOT NULL THEN UPDATE debug_log SET action = 'gear_post_queued' WHERE id = v_marker; END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_srk FROM app_settings WHERE key = 'service_role_key';
  IF v_refund > 0 THEN
    BEGIN
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

  IF v_diff = 0 THEN
    -- cena beze změny → trigger úprav nic neposílá; mail s kusy pošle helper (20261023b)
    BEGIN
      PERFORM public._gear_notify_modified(p_booking_id,
        jsonb_build_object('gear', jsonb_build_object('from', v_from, 'to', v_to)));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('customer_remove_gear_item', 'notify_failed', 'error', SQLERRM, jsonb_build_object('booking_id', p_booking_id));
    END;
  ELSIF v_mail THEN
    BEGIN
      SELECT email, full_name INTO v_email, v_name FROM profiles WHERE id = v_b.user_id;
      IF COALESCE(v_url, '') = '' OR COALESCE(v_srk, '') = '' OR COALESCE(v_email, '') = '' THEN
        DELETE FROM debug_log WHERE id = v_marker;
        INSERT INTO debug_log(source, action, status, request_data)
        VALUES ('gear_booking_modified', CASE WHEN COALESCE(v_email, '') = '' THEN 'skipped_no_email' ELSE 'app_settings_missing' END,
                CASE WHEN COALESCE(v_email, '') = '' THEN 'info' ELSE 'error' END, jsonb_build_object('booking_id', v_b.id));
      ELSE
        -- tělo jako _gear_notify_modified + rozdíl ceny (dobropis v příloze, send-booking-email)
        PERFORM net.http_post(url := v_url || '/functions/v1/send-booking-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_srk),
          body := jsonb_build_object('type', 'booking_modified', 'booking_id', v_b.id, 'booking_kind', 'gear',
            'customer_email', v_email, 'customer_name', COALESCE(v_name, ''),
            'source', 'web', 'motorcycle', '',   -- slug web_booking_modified: 5min dedup triggeru ho nepočítá (jako _gear_notify_modified)
            'start_date', v_b.start_date, 'end_date', v_b.end_date, 'total_price', v_new_total, 'price_difference', v_diff,
            'pickup_time', COALESCE(v_b.pickup_time::text, ''), 'return_time', COALESCE(v_b.return_time, ''),
            'original_start_date', v_b.start_date, 'original_end_date', v_b.end_date, 'original_total_price', v_b.total_price,
            'changes', jsonb_build_object('gear', jsonb_build_object('from', v_from, 'to', v_to))));
        UPDATE debug_log SET request_data = request_data || jsonb_build_object('recipient', v_email) WHERE id = v_marker;
        -- zpráva do appky — stejný text jako trigger úprav (KROK 3)
        INSERT INTO admin_messages (user_id, booking_id, title, message, type)
        VALUES (v_b.user_id, v_b.id, 'Rezervace upravena',
          'Vaše rezervace č. ' || UPPER(RIGHT(v_b.id::text, 8)) || ' byla upravena.'
          || CASE WHEN v_diff > 0 THEN ' Doplatek ' || ROUND(v_diff)::text || ' Kč — doklad o platbě najdete v e-mailu.'
                  ELSE ' Vracíme ' || ROUND(ABS(v_diff))::text || ' Kč zpět na kartu — dobropis najdete v e-mailu.' END
          || ' Detaily a aktualizovanou smlouvu jsme poslali e-mailem.', 'info');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      DELETE FROM debug_log WHERE id = v_marker;
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('gear_booking_modified', 'http_post_failed', 'error', SQLERRM, jsonb_build_object('booking_id', v_b.id, 'via', 'gear_remove'));
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'refund_amount', v_refund, 'refund_percent', v_pct,
    'price_unchanged', v_new_pd = v_old_pd,
    'removed_key', v_key, 'old_per_day', v_old_pd, 'new_per_day', v_new_pd, 'new_total', v_new_total, 'lines', v_lines);
END $$;
REVOKE ALL ON FUNCTION public.customer_remove_gear_item(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_remove_gear_item(uuid, text, boolean) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
