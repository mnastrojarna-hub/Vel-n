-- =============================================================================
-- 2026-10-23 (b/8): Výpůjčka výbavy — Velín (založení, úprava) a zákazník (velikosti)
--  • admin_create_gear_booking: Velín → „Jen výbava“ (booking_source 'velin');
--    sklad / termín mimo nastavení = jen varování, zavřená pobočka = chyba.
--  • admin_update_gear_booking: dry-run (výchozí) / provedení změny termínu,
--    kusů, pobočky a časů; přepočet řádků, ceny/den a ceny; záznam do
--    modification_history. Platby/vratky řeší Velín (vrací diff).
--  • customer_update_gear_sizes: zákazník (vlastník) mění JEN velikosti stejných
--    kusů, zdarma, před převzetím; limity samoobsluhy + sklad; e-mail o úpravě.
--  • _gear_notify_modified: e-mail booking_modified s changes.gear (send-booking-email
--    vybere gear šablonu); dedup jako trg_send_booking_modified_email.
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._gear_notify_modified(p_booking_id uuid, p_changes jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_url text; v_key text;
BEGIN
  SELECT bk.*, p.email AS cust_email, p.full_name AS cust_name INTO b
    FROM bookings bk LEFT JOIN profiles p ON p.id = bk.user_id WHERE bk.id = p_booking_id;
  IF NOT FOUND OR b.status NOT IN ('reserved', 'active') OR NULLIF(b.cust_email, '') IS NULL THEN RETURN false; END IF;
  -- dedup: stejná úprava už mail spustila (trigger úprav nebo předchozí volání) ≤ 60 s / 5 min
  IF EXISTS (SELECT 1 FROM message_log WHERE booking_id = b.id AND template_slug LIKE 'booking_modified%'
               AND status = 'sent' AND created_at > now() - interval '5 minutes')
     OR EXISTS (SELECT 1 FROM debug_log WHERE created_at > now() - interval '60 seconds'
               AND source = 'trg_booking_modified_email' AND action = 'http_post_queued'
               AND request_data->>'booking_id' = b.id::text) THEN
    RETURN false;
  END IF;
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF NULLIF(v_url, '') IS NULL OR NULLIF(v_key, '') IS NULL THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('gear_booking_modified', 'app_settings_missing', 'error', 'supabase_url or service_role_key empty',
            jsonb_build_object('booking_id', b.id));
    RETURN false;
  END IF;
  BEGIN
    PERFORM net.http_post(url := v_url || '/functions/v1/send-booking-email',
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
      body := jsonb_build_object('type', 'booking_modified', 'booking_id', b.id, 'booking_kind', 'gear',
        'customer_email', b.cust_email, 'customer_name', COALESCE(b.cust_name, ''),
        'source', COALESCE(b.booking_source, 'web'), 'motorcycle', '',
        'start_date', b.start_date, 'end_date', b.end_date, 'total_price', b.total_price, 'price_difference', 0,
        'pickup_time', COALESCE(b.pickup_time::text, ''), 'return_time', COALESCE(b.return_time, ''),
        'original_start_date', b.start_date, 'original_end_date', b.end_date, 'original_total_price', b.total_price,
        'changes', COALESCE(p_changes, '{}'::jsonb)));
    -- stejná stopa jako trigger úprav → jeho dedup tentýž mail nezdvojí
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email', 'http_post_queued', 'info',
            jsonb_build_object('booking_id', b.id, 'recipient', b.cust_email, 'via', 'gear_rpc'));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('gear_booking_modified', 'http_post_failed', 'error', SQLERRM, jsonb_build_object('booking_id', b.id));
    RETURN false;
  END;
  RETURN true;
END $$;

-- Velikosti gear rezervace jako {klíč: velikost} (jen vyplněné)
CREATE OR REPLACE FUNCTION public._gear_booking_sizes(p_booking_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object('helmet', helmet_size, 'jacket', jacket_size, 'pants', pants_size,
           'gloves', gloves_size, 'boots', boots_size))
    FROM bookings WHERE id = p_booking_id;
$$;

-- Nové velikosti do uložených řádků (cena řádků beze změny)
CREATE OR REPLACE FUNCTION public._gear_lines_resize(p_lines jsonb, p_sizes jsonb, p_days integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(l
           || jsonb_build_object('sizes', COALESCE((SELECT jsonb_object_agg(e.key, COALESCE(p_sizes->e.key, e.value))
                                                     FROM jsonb_each(l->'sizes') e), '{}'::jsonb))
           || CASE WHEN p_days IS NULL THEN '{}'::jsonb
                   ELSE jsonb_build_object('total', (l->>'price_per_day')::numeric * p_days) END
           ORDER BY o), '[]'::jsonb)
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) WITH ORDINALITY x(l, o);
$$;

CREATE OR REPLACE FUNCTION public.customer_update_gear_sizes(p_booking_id uuid, p_sizes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); b record; v_from jsonb; v_to jsonb; v_ch jsonb := '{}'::jsonb;
  r record; v_s text; v_list text[]; v_ss boolean; v_short jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'unauthenticated'); END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR b.booking_kind IS DISTINCT FROM 'gear' OR b.user_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;
  IF b.status NOT IN ('pending', 'reserved') OR b.picked_up_at IS NOT NULL OR b.gear_collected_at IS NOT NULL
     OR b.handover_protocol_filled_at IS NOT NULL
     OR (b.end_date AT TIME ZONE 'Europe/Prague')::date < (now() AT TIME ZONE 'Europe/Prague')::date THEN
    RETURN jsonb_build_object('error', 'not_editable');
  END IF;
  IF jsonb_typeof(p_sizes) IS DISTINCT FROM 'object' OR p_sizes = '{}'::jsonb THEN
    RETURN jsonb_build_object('error', 'no_items');
  END IF;
  v_from := public._gear_booking_sizes(b.id);
  v_ss := public.branch_is_self_service(b.branch_id);
  FOR r IN SELECT e.key, NULLIF(btrim(COALESCE(e.value, '')), '') AS size FROM jsonb_each_text(p_sizes) e LOOP
    IF NOT (v_from ? r.key) THEN RETURN jsonb_build_object('error', 'bad_item', 'key', r.key); END IF;
    SELECT p.sizes INTO v_list FROM gear_rental_prices p WHERE p.key = r.key AND p.kind = 'item';
    IF r.size IS NULL OR (cardinality(COALESCE(v_list, '{}'::text[])) > 0 AND NOT (r.size = ANY (v_list))) THEN
      RETURN jsonb_build_object('error', 'bad_size', 'key', r.key, 'size', r.size);
    END IF;
    IF v_ss AND NOT public._gear_ss_size_ok(r.key, r.size) THEN
      RETURN jsonb_build_object('error', 'bad_size', 'key', r.key, 'size', r.size, 'reason', 'self_service');
    END IF;
    IF r.size IS DISTINCT FROM v_from->>r.key THEN
      v_ch := v_ch || jsonb_build_object(r.key, r.size);
    END IF;
  END LOOP;
  IF v_ch = '{}'::jsonb THEN
    RETURN jsonb_build_object('success', true, 'changed', false, 'sizes', v_from);
  END IF;
  v_to := v_from || v_ch;

  IF public._gear_stock_check_on('gear_rental') THEN
    PERFORM pg_advisory_xact_lock(hashtext('gear_stock'), hashtext(b.branch_id::text));
    v_short := public._gear_stock_shortfall(b.branch_id, b.start_date::date, b.end_date::date, v_ch, b.id);
    IF jsonb_array_length(v_short) > 0 THEN RETURN jsonb_build_object('error', 'out_of_stock', 'items', v_short); END IF;
  END IF;

  PERFORM set_config('motogo.gear_rpc', '1', true);
  UPDATE bookings SET
    helmet_size = CASE WHEN v_ch ? 'helmet' THEN v_ch->>'helmet' ELSE helmet_size END,
    jacket_size = CASE WHEN v_ch ? 'jacket' THEN v_ch->>'jacket' ELSE jacket_size END,
    pants_size  = CASE WHEN v_ch ? 'pants'  THEN v_ch->>'pants'  ELSE pants_size END,
    gloves_size = CASE WHEN v_ch ? 'gloves' THEN v_ch->>'gloves' ELSE gloves_size END,
    boots_size  = CASE WHEN v_ch ? 'boots'  THEN v_ch->>'boots'  ELSE boots_size END,
    gear_lines  = public._gear_lines_resize(gear_lines, v_ch, NULL),
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'source', 'web', 'type', 'gear_sizes', 'from', v_from, 'to', v_to)
   WHERE id = b.id;
  PERFORM set_config('motogo.gear_rpc', '', true);

  PERFORM public._gear_notify_modified(b.id, jsonb_build_object('gear', jsonb_build_object('from', v_from, 'to', v_to)));
  RETURN jsonb_build_object('success', true, 'changed', true, 'from', v_from, 'sizes', v_to);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', 'failed', 'message', SQLERRM);
END $$;

CREATE OR REPLACE FUNCTION public.admin_create_gear_booking(p_user_id uuid, p_branch_id uuid, p_start date, p_end date,
  p_items jsonb, p_pickup_time text, p_return_time text, p_note text,
  p_mark_paid boolean DEFAULT false, p_lang text DEFAULT 'cs')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p jsonb; v_id uuid; v_sz jsonb; v_lang text;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('error', 'forbidden'); END IF;
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('error', 'bad_customer');
  END IF;
  v_p := public._gear_prepare(p_branch_id, p_start, p_end, p_items, NULL, true, true);
  IF v_p ? 'error' THEN RETURN v_p; END IF;
  v_sz := v_p->'sizes';
  v_lang := CASE WHEN p_lang IN ('cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk') THEN p_lang ELSE 'cs' END;
  PERFORM set_config('motogo.gear_rpc', '1', true);
  INSERT INTO bookings (user_id, moto_id, branch_id, booking_kind, start_date, end_date, status, payment_status,
    confirmed_at, total_price, extras_price, delivery_fee, late_pickup_discount_amount, discount_amount,
    booking_source, source, pickup_method, return_method, pickup_time, return_time, notes, language,
    helmet_size, jacket_size, pants_size, gloves_size, boots_size, gear_lines, gear_per_day)
  VALUES (p_user_id, NULL, p_branch_id, 'gear', (p_start::timestamp AT TIME ZONE 'UTC'), (p_end::timestamp AT TIME ZONE 'UTC'),
    CASE WHEN p_mark_paid THEN 'reserved' ELSE 'pending' END::booking_status,
    CASE WHEN p_mark_paid THEN 'paid' ELSE 'unpaid' END::payment_status,
    CASE WHEN p_mark_paid THEN now() END, (v_p->>'subtotal')::numeric, 0, 0, 0, 0,
    'velin', 'velin', 'store', 'store', public._gear_parse_time(p_pickup_time),
    to_char(public._gear_parse_time(p_return_time), 'HH24:MI'), NULLIF(left(btrim(COALESCE(p_note, '')), 1000), ''), v_lang,
    v_sz->>'helmet', v_sz->>'jacket', v_sz->>'pants', v_sz->>'gloves', v_sz->>'boots', v_p->'lines', (v_p->>'per_day')::numeric)
  RETURNING id INTO v_id;
  PERFORM set_config('motogo.gear_rpc', '', true);
  BEGIN
    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, new_data)
    VALUES (auth.uid(), 'gear_booking_created_admin', 'bookings', v_id,
            jsonb_build_object('branch_id', p_branch_id, 'sizes', v_sz, 'total', v_p->'subtotal', 'paid', p_mark_paid));
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN jsonb_build_object('success', true, 'booking_id', v_id, 'booking_number', upper(right(v_id::text, 8)),
    'total', (v_p->>'subtotal')::numeric, 'per_day', (v_p->>'per_day')::numeric, 'days', (v_p->>'days')::int,
    'lines', v_p->'lines', 'warnings', v_p->'warnings', 'stock_short', v_p->'stock_short');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', 'failed', 'message', SQLERRM);
END $$;
