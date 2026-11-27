-- ===== Web: slevové kódy a dárkové poukazy u výpůjčky výbavy a u nákupu dárkového poukazu (část 2/3) =====
-- 2026-11-27, schváleno majitelem 2026-11-27. Celé zadání a popis viz 20261127a1_web_discount_codes_helpers.sql.
-- Tato část: quote_gear_booking a create_web_gear_booking s novým parametrem p_codes text[] (potřebuje část 1/3).
-- Idempotentní (DROP IF EXISTS starých podpisů + CREATE OR REPLACE), bez změn dat.

DROP FUNCTION IF EXISTS public.quote_gear_booking(uuid, date, date, jsonb, text);
CREATE OR REPLACE FUNCTION public.quote_gear_booking(p_branch_id uuid, p_start date, p_end date, p_items jsonb,
  p_voucher_code text DEFAULT NULL, p_codes text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p jsonb; v_v jsonb; v_dl jsonb; v_disc numeric := 0; v_out jsonb; v_sub numeric;
BEGIN
  v_p := public._gear_prepare(p_branch_id, p_start, p_end, p_items, NULL, false, false);
  IF v_p ? 'error' THEN RETURN v_p; END IF;
  v_sub := (v_p->>'subtotal')::numeric;
  IF p_codes IS NOT NULL THEN
    -- web: seznam kódů (slevové kódy + dárkové poukazy); neplatné se do ceny nepočítají
    v_dl := public._web_discount_lines(p_codes, v_sub, true);
    v_disc := (v_dl->>'discount')::numeric;
    SELECT x INTO v_v FROM jsonb_array_elements(v_dl->'lines') x WHERE x->>'kind' = 'voucher' LIMIT 1;
    v_out := jsonb_build_object('success', true, 'days', v_p->'days', 'per_day', v_p->'per_day',
      'subtotal', v_p->'subtotal', 'lines', v_p->'lines', 'sizes', v_p->'sizes',
      'voucher', CASE WHEN v_v IS NOT NULL THEN jsonb_build_object('code', v_v->>'code', 'amount', (v_v->>'amount')::numeric) END,
      'discounts', v_dl->'lines', 'discount', v_disc, 'total', v_sub - v_disc, 'amount', v_sub - v_disc);
    IF jsonb_array_length(v_dl->'invalid') > 0 THEN
      v_out := v_out || jsonb_build_object('success', false, 'error', 'bad_code', 'code', v_dl->'invalid'->0->>'code',
        'message', v_dl->'invalid'->0->>'message', 'invalid', v_dl->'invalid');
    END IF;
  ELSE
    -- appka (p_voucher_code = jeden dárkový poukaz) — beze změny
    v_v := public._gear_voucher(p_voucher_code, v_sub);
    IF v_v IS NOT NULL AND NOT (v_v ? 'error') THEN v_disc := (v_v->>'amount')::numeric; END IF;
    v_out := jsonb_build_object('success', true, 'days', v_p->'days', 'per_day', v_p->'per_day',
      'subtotal', v_p->'subtotal', 'lines', v_p->'lines', 'sizes', v_p->'sizes',
      'voucher', CASE WHEN v_v IS NOT NULL AND NOT (v_v ? 'error')
                      THEN jsonb_build_object('code', v_v->>'code', 'amount', v_disc) END,
      'discount', v_disc, 'total', v_sub - v_disc, 'amount', v_sub - v_disc);
    -- neplatný poukaz: cena se ukáže bez slevy + chyba poukazu
    IF v_v ? 'error' THEN v_out := v_out || jsonb_build_object('success', false) || v_v; END IF;
  END IF;
  -- sleva nechala 1–14 Kč → kartou nezaplatitelné (create_web_gear_booking odmítne stejně)
  IF public._gear_below_card_min((v_out->>'total')::numeric) THEN
    v_out := v_out || jsonb_build_object('success', false, 'error', 'below_minimum', 'min', 15);
  END IF;
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  RETURN public._gear_rpc_failed('quote_gear_booking', SQLSTATE, SQLERRM, jsonb_build_object('branch_id', p_branch_id));
END $$;
REVOKE ALL ON FUNCTION public.quote_gear_booking(uuid, date, date, jsonb, text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_gear_booking(uuid, date, date, jsonb, text, text[]) TO anon, authenticated, service_role;

DROP FUNCTION IF EXISTS public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb);
CREATE OR REPLACE FUNCTION public.create_web_gear_booking(p_branch_id uuid, p_start date, p_end date, p_items jsonb,
  p_customer jsonb, p_pickup_time text DEFAULT NULL, p_return_time text DEFAULT NULL, p_lang text DEFAULT 'cs',
  p_note text DEFAULT NULL, p_voucher_code text DEFAULT NULL, p_existing_booking_id uuid DEFAULT NULL,
  p_password text DEFAULT NULL, p_consents jsonb DEFAULT '{}'::jsonb, p_codes text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $_$
DECLARE
  v_c jsonb := COALESCE(p_customer, '{}'::jsonb); v_cons jsonb := COALESCE(p_consents, '{}'::jsonb);
  v_name text; v_email text; v_phone text; v_p jsonb; v_v jsonb; v_disc numeric := 0; v_total numeric;
  v_existing uuid; v_user uuid; v_reuse boolean := false; v_id uuid; v_sz jsonb;
  v_time time; v_rtime text; v_lang text; v_note text;
  v_dl jsonb; v_lines jsonb := '[]'::jsonb; v_l jsonb; v_promo uuid; v_codes text;
BEGIN
  v_name := left(btrim(COALESCE(v_c->>'name', '')), 200);
  v_email := lower(left(btrim(COALESCE(v_c->>'email', '')), 200));
  v_phone := NULLIF(left(btrim(COALESCE(v_c->>'phone', '')), 30), '');
  IF length(v_name) < 3 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR v_phone IS NULL THEN
    RETURN jsonb_build_object('error', 'bad_customer');
  END IF;
  IF COALESCE(v_cons->>'vop', '') <> 'true' OR COALESCE(v_cons->>'gdpr', '') <> 'true' THEN
    RETURN jsonb_build_object('error', 'consents_required');
  END IF;

  -- vlastní rozpracovaná (pending/unpaid) web výpůjčka výbavy téhož e-mailu → přepíše se
  SELECT id INTO v_existing FROM auth.users WHERE lower(email) = v_email LIMIT 1;
  IF v_existing IS NOT NULL THEN
    v_reuse := p_existing_booking_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM bookings eb WHERE eb.id = p_existing_booking_id AND eb.user_id = v_existing
         AND eb.status = 'pending' AND eb.payment_status = 'unpaid' AND eb.booking_source = 'web'
         AND eb.booking_kind = 'gear');
  END IF;

  -- pravidla + cena + sklad (se zámkem pobočky do konce transakce; přepisovaný koncept se nepočítá)
  v_p := public._gear_prepare(p_branch_id, p_start, p_end, p_items,
                              CASE WHEN v_reuse THEN p_existing_booking_id END, false, true);
  IF v_p ? 'error' THEN RETURN v_p; END IF;
  IF p_codes IS NOT NULL THEN
    -- web 2026-11-27: více kódů jako rezervace motorky (slevové kódy + dárkové poukazy)
    v_dl := public._web_discount_lines(p_codes, (v_p->>'subtotal')::numeric, true);
    IF jsonb_array_length(v_dl->'invalid') > 0 THEN
      RETURN jsonb_build_object('error', 'bad_code', 'code', v_dl->'invalid'->0->>'code',
        'message', v_dl->'invalid'->0->>'message', 'invalid', v_dl->'invalid');
    END IF;
    v_lines := v_dl->'lines';
    v_disc := (v_dl->>'discount')::numeric;
    FOR v_l IN SELECT * FROM jsonb_array_elements(v_lines) LOOP
      IF v_l->>'kind' = 'voucher' THEN
        IF public._web_voucher_in_use((v_l->>'voucher_id')::uuid, CASE WHEN v_reuse THEN p_existing_booking_id END) THEN
          RETURN jsonb_build_object('error', 'bad_code', 'code', v_l->>'code', 'in_use', true,
            'message', 'Poukaz už je použitý v jiné rozpracované rezervaci.');
        END IF;
        v_v := COALESCE(v_v, jsonb_build_object('voucher_id', v_l->>'voucher_id', 'code', v_l->>'code',
                 'value', v_l->'value', 'amount', v_l->'amount'));
      ELSE
        v_promo := COALESCE(v_promo, (v_l->>'promo_code_id')::uuid);
      END IF;
    END LOOP;
    SELECT string_agg(x->>'code', ', ') INTO v_codes FROM jsonb_array_elements(v_lines) x;
  ELSE
  v_v := public._gear_voucher(p_voucher_code, (v_p->>'subtotal')::numeric);
  IF v_v ? 'error' THEN RETURN v_v; END IF;
  -- Poukaz smí držet jen JEDNA živá rezervace (bezpečnostní review 2026-10-23: jinak
  -- jeden poukaz zlevnil libovolný počet nezaplacených rezervací). Zámek řádku poukazu
  -- do konce transakce = dvě souběžná založení ho nepoužijí obě; přepisovaný vlastní
  -- koncept se nepočítá.
  IF v_v IS NOT NULL THEN
    PERFORM 1 FROM vouchers WHERE id = (v_v->>'voucher_id')::uuid FOR UPDATE;
    IF EXISTS (SELECT 1 FROM booking_discounts d JOIN bookings ob ON ob.id = d.booking_id
                WHERE d.voucher_id = (v_v->>'voucher_id')::uuid
                  AND ob.status IN ('pending', 'reserved', 'active')
                  AND ob.id IS DISTINCT FROM CASE WHEN v_reuse THEN p_existing_booking_id END) THEN
      RETURN jsonb_build_object('error', 'bad_voucher', 'in_use', true);
    END IF;
    v_disc := (v_v->>'amount')::numeric;
    v_codes := v_v->>'code';
    v_lines := jsonb_build_array(jsonb_build_object('kind', 'voucher', 'code', v_v->>'code', 'voucher_id', v_v->>'voucher_id',
                 'discount_type', 'fixed', 'value', (v_v->>'value')::numeric, 'amount', v_disc));
  END IF;
  END IF;
  v_total := GREATEST((v_p->>'subtotal')::numeric - v_disc, 0);
  IF public._gear_below_card_min(v_total) THEN   -- poukaz nechal 1–14 Kč → kartou nezaplatitelné
    RETURN jsonb_build_object('error', 'below_minimum', 'min', 15, 'total', v_total);
  END IF;

  -- identita (pravidla create_web_booking)
  IF v_existing IS NOT NULL AND public._web_booking_caller_is_anon() AND NOT v_reuse THEN
    RETURN jsonb_build_object('error', 'email_exists',
      'message', 'Tento e-mail je v systému. Pro pokračování se přihlas, nebo si obnov heslo.');
  END IF;
  IF v_existing IS NOT NULL AND auth.uid() IS NOT NULL AND auth.uid() <> v_existing THEN
    RETURN jsonb_build_object('error', 'email_mismatch',
      'message', 'Přihlášený účet nesouhlasí se zadaným e-mailem.');
  END IF;
  IF v_existing IS NOT NULL AND NOT v_reuse AND (
       SELECT count(*) FROM bookings WHERE user_id = v_existing AND booking_kind = 'gear'
          AND status = 'pending' AND created_at > now() - interval '1 hour') >= 5 THEN
    RETURN jsonb_build_object('error', 'too_many');
  END IF;

  v_user := public._gear_web_upsert_customer(v_existing, v_name, v_email, v_phone, v_c, p_password, v_cons);
  v_time := public._gear_parse_time(p_pickup_time);
  v_rtime := to_char(public._gear_parse_time(p_return_time), 'HH24:MI');
  v_lang := CASE WHEN p_lang IN ('cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk') THEN p_lang ELSE 'cs' END;
  v_note := NULLIF(left(btrim(COALESCE(p_note, '')), 500), '');
  v_sz := v_p->'sizes';

  PERFORM set_config('motogo.gear_rpc', '1', true);   -- strážce gear řádku (20261023a)
  IF v_reuse THEN
    -- přepis konceptu anonymem = akce zákazníka, ne ruční oprava pobočky (bez auditu v _booking_set_branch)
    PERFORM set_config('motogo.branch_reattribution', 'gear_rpc', true);
    UPDATE bookings SET branch_id = p_branch_id,
      start_date = (p_start::timestamp AT TIME ZONE 'UTC'), end_date = (p_end::timestamp AT TIME ZONE 'UTC'),
      total_price = v_total, extras_price = 0, delivery_fee = 0, discount_amount = v_disc,
      discount_code = v_codes, voucher_id = (v_v->>'voucher_id')::uuid, promo_code_id = v_promo,
      pickup_time = v_time, return_time = v_rtime, notes = v_note, language = v_lang,
      helmet_size = v_sz->>'helmet', jacket_size = v_sz->>'jacket', pants_size = v_sz->>'pants',
      gloves_size = v_sz->>'gloves', boots_size = v_sz->>'boots',
      gear_lines = v_p->'lines', gear_per_day = (v_p->>'per_day')::numeric
     WHERE id = p_existing_booking_id;
    PERFORM set_config('motogo.branch_reattribution', '', true);
    v_id := p_existing_booking_id;
  ELSE
    INSERT INTO bookings (user_id, moto_id, branch_id, booking_kind, start_date, end_date, status, payment_status,
      total_price, extras_price, delivery_fee, late_pickup_discount_amount, discount_amount, discount_code, voucher_id, promo_code_id,
      booking_source, source, pickup_method, return_method, pickup_time, return_time, notes, language,
      helmet_size, jacket_size, pants_size, gloves_size, boots_size, gear_lines, gear_per_day)
    VALUES (v_user, NULL, p_branch_id, 'gear', (p_start::timestamp AT TIME ZONE 'UTC'), (p_end::timestamp AT TIME ZONE 'UTC'),
      'pending', 'unpaid', v_total, 0, 0, 0, v_disc, v_codes, (v_v->>'voucher_id')::uuid, v_promo,
      'web', 'web', 'store', 'store', v_time, v_rtime, v_note, v_lang,
      v_sz->>'helmet', v_sz->>'jacket', v_sz->>'pants', v_sz->>'gloves', v_sz->>'boots', v_p->'lines', (v_p->>'per_day')::numeric)
    RETURNING id INTO v_id;
  END IF;
  PERFORM set_config('motogo.gear_rpc', '', true);

  DELETE FROM booking_discounts WHERE booking_id = v_id;
  INSERT INTO booking_discounts (booking_id, kind, code, promo_code_id, voucher_id, discount_type, value, amount)
  SELECT v_id, x->>'kind', x->>'code', NULLIF(x->>'promo_code_id', '')::uuid, NULLIF(x->>'voucher_id', '')::uuid,
         x->>'discount_type', (x->>'value')::numeric, (x->>'amount')::numeric
    FROM jsonb_array_elements(v_lines) x;

  RETURN jsonb_build_object('success', true, 'booking_id', v_id, 'booking_number', upper(right(v_id::text, 8)),
    'amount', v_total, 'total', v_total, 'subtotal', (v_p->>'subtotal')::numeric, 'discount', v_disc,
    'per_day', (v_p->>'per_day')::numeric, 'days', (v_p->>'days')::int, 'lines', v_p->'lines',
    'user_id', v_user, 'is_new_user', v_existing IS NULL, 'reused', v_reuse,
    'voucher', CASE WHEN v_v IS NOT NULL THEN jsonb_build_object('code', v_v->>'code', 'amount', (v_v->>'amount')::numeric) END,
    'discounts', v_lines);
EXCEPTION WHEN OTHERS THEN
  RETURN public._gear_rpc_failed('create_web_gear_booking', SQLSTATE, SQLERRM,
    jsonb_build_object('branch_id', p_branch_id, 'existing_booking_id', p_existing_booking_id));
END $_$;
REVOKE ALL ON FUNCTION public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb, text[]) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb, text[]) IS
  'Web /pujceni-obleceni: výpůjčka JEN výbavy = bookings booking_kind=gear (pending/unpaid, web). Cena ze serveru, dárkový poukaz (p_voucher_code, appka) nebo seznam slevových kódů a poukazů (p_codes, web 2026-11-27), souhlasy VOP+GDPR, identita jako create_web_booking. 2026-10-23.';
