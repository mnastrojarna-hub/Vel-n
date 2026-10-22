-- =============================================================================
-- 2026-10-23 (b/5): Výpůjčka výbavy — společná validace + nacenění, dostupnost
--  • _gear_prepare: jediné místo pravidel (nastavení gear_rental, pobočka, termín,
--    uzavření, kusy + velikosti z ceníku, limity samoobsluhy, sklad dle přepínače
--    gear_stock_check.gear_rental, minimum Stripe). Zákazník = chyba, Velín
--    (p_admin) = u nastavení/termínu/skladu jen varování.
--  • _gear_voucher: jen DÁRKOVÝ poukaz (vouchers), stejné ověření jako
--    create_web_booking; promo kódy / věrnost / VRACENI pro výbavu ne.
--  • quote_gear_booking (anon): živá cena na webu (dry-run, bez identity).
--  • get_gear_rental_availability (anon): volné velikosti skladovaných typů.
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._gear_prepare(p_branch_id uuid, p_start date, p_end date, p_items jsonb,
  p_exclude_booking uuid DEFAULT NULL, p_admin boolean DEFAULT false, p_lock boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg jsonb; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_max int; v_ahead int; v_days int; v_br record; v_sizes text[];
  it jsonb; k text; s text; v_items jsonb := '[]'::jsonb; v_q jsonb;
  v_warn jsonb := '[]'::jsonb; v_short jsonb := '[]'::jsonb; v_lines jsonb; v_sub numeric;
BEGIN
  SELECT value INTO v_cfg FROM app_settings WHERE key = 'gear_rental';
  IF COALESCE(v_cfg->>'enabled', 'true') = 'false' THEN
    IF NOT p_admin THEN RETURN jsonb_build_object('error', 'disabled'); END IF;
    v_warn := v_warn || '"disabled"'::jsonb;
  END IF;
  v_max := LEAST(GREATEST(COALESCE((v_cfg->>'max_days')::int, 30), 1), 366);
  v_ahead := LEAST(GREATEST(COALESCE((v_cfg->>'max_ahead_days')::int, 400), 1), 800);

  SELECT id, name, type, active INTO v_br FROM branches WHERE id = p_branch_id;
  IF NOT FOUND OR v_br.active IS NOT TRUE THEN RETURN jsonb_build_object('error', 'bad_branch'); END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN RETURN jsonb_build_object('error', 'bad_dates'); END IF;
  v_days := (p_end - p_start) + 1;
  IF v_days > 366 THEN RETURN jsonb_build_object('error', 'too_long', 'max_days', CASE WHEN p_admin THEN 366 ELSE v_max END); END IF;
  IF p_start < v_today OR p_start > v_today + v_ahead THEN
    IF NOT p_admin THEN RETURN jsonb_build_object('error', 'bad_dates'); END IF;
    v_warn := v_warn || to_jsonb(CASE WHEN p_start < v_today THEN 'start_in_past' ELSE 'too_far_ahead' END);
  END IF;
  IF v_days > v_max THEN
    IF NOT p_admin THEN RETURN jsonb_build_object('error', 'too_long', 'max_days', v_max); END IF;
    v_warn := v_warn || '"too_long"'::jsonb;
  END IF;
  IF public.branch_is_closed(p_branch_id, p_start, p_end) THEN
    RETURN jsonb_build_object('error', 'branch_closed');
  END IF;

  -- Kusy: jen klíče se sloupcem velikosti v rezervaci; kus bez velikostní řady = 'UNI'
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('error', 'no_items');
  END IF;
  IF jsonb_array_length(p_items) > 12 THEN RETURN jsonb_build_object('error', 'too_many_items'); END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF jsonb_typeof(it) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('error', 'bad_item'); END IF;
    k := it->>'key';
    IF k IS NULL OR NOT (k = ANY (ARRAY['helmet', 'jacket', 'pants', 'gloves', 'boots'])) THEN
      RETURN jsonb_build_object('error', 'bad_item', 'key', k);
    END IF;
    s := NULLIF(btrim(COALESCE(it->>'size', '')), '');
    SELECT p.sizes INTO v_sizes FROM gear_rental_prices p WHERE p.key = k AND p.kind = 'item' AND p.is_active;
    IF FOUND AND cardinality(v_sizes) = 0 AND s IS NULL THEN s := 'UNI'; END IF;
    v_items := v_items || jsonb_build_object('key', k, 'size', s);
  END LOOP;
  v_q := public._gear_rental_quote(v_items);
  IF v_q ? 'error' THEN RETURN v_q; END IF;

  IF v_br.type = 'samoobslužná' THEN
    FOR k, s IN SELECT e.key, e.value FROM jsonb_each_text(v_q->'sizes') e LOOP
      IF NOT public._gear_ss_size_ok(k, s) THEN
        RETURN jsonb_build_object('error', 'bad_size', 'key', k, 'size', s, 'reason', 'self_service');
      END IF;
    END LOOP;
  END IF;

  IF public._gear_stock_check_on('gear_rental') THEN
    -- souběžná založení na téže pobočce se řadí (zámek do konce transakce)
    IF p_lock THEN PERFORM pg_advisory_xact_lock(hashtext('gear_stock'), hashtext(p_branch_id::text)); END IF;
    v_short := public._gear_stock_shortfall(p_branch_id, p_start, p_end, v_q->'sizes', p_exclude_booking);
    IF jsonb_array_length(v_short) > 0 THEN
      IF NOT p_admin THEN RETURN jsonb_build_object('error', 'out_of_stock', 'items', v_short); END IF;
      v_warn := v_warn || '"out_of_stock"'::jsonb;
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(l || jsonb_build_object('total', (l->>'price_per_day')::numeric * v_days) ORDER BY o), '[]'::jsonb)
    INTO v_lines FROM jsonb_array_elements(v_q->'lines') WITH ORDINALITY e(l, o);
  v_sub := (v_q->>'per_day')::numeric * v_days;
  IF v_sub < 15 THEN   -- minimum karetní platby (CZK)
    IF NOT p_admin THEN RETURN jsonb_build_object('error', 'below_minimum'); END IF;
    v_warn := v_warn || '"below_minimum"'::jsonb;
  END IF;

  RETURN jsonb_build_object('days', v_days, 'per_day', (v_q->>'per_day')::numeric, 'subtotal', v_sub,
    'lines', v_lines, 'keys', v_q->'keys', 'sizes', v_q->'sizes',
    'branch_type', v_br.type, 'warnings', v_warn, 'stock_short', v_short);
END $$;

-- Dárkový poukaz: NULL = bez kódu, {error:'bad_voucher'}, jinak {voucher_id, code, value, amount}
CREATE OR REPLACE FUNCTION public._gear_voucher(p_code text, p_subtotal numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v record;
BEGIN
  IF NULLIF(btrim(COALESCE(p_code, '')), '') IS NULL THEN RETURN NULL; END IF;
  SELECT id, code, amount INTO v FROM vouchers
   WHERE code = upper(btrim(p_code)) AND status = 'active'
     AND (valid_until IS NULL OR valid_until >= current_date)
   LIMIT 1;
  IF v.id IS NULL THEN RETURN jsonb_build_object('error', 'bad_voucher'); END IF;
  RETURN jsonb_build_object('voucher_id', v.id, 'code', v.code, 'value', COALESCE(v.amount, 0),
    'amount', LEAST(COALESCE(v.amount, 0), GREATEST(COALESCE(p_subtotal, 0), 0)));
END $$;

CREATE OR REPLACE FUNCTION public.quote_gear_booking(p_branch_id uuid, p_start date, p_end date, p_items jsonb,
                                                     p_voucher_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p jsonb; v_v jsonb; v_disc numeric := 0; v_out jsonb;
BEGIN
  v_p := public._gear_prepare(p_branch_id, p_start, p_end, p_items, NULL, false, false);
  IF v_p ? 'error' THEN RETURN v_p; END IF;
  v_v := public._gear_voucher(p_voucher_code, (v_p->>'subtotal')::numeric);
  IF v_v IS NOT NULL AND NOT (v_v ? 'error') THEN v_disc := (v_v->>'amount')::numeric; END IF;
  v_out := jsonb_build_object('success', true, 'days', v_p->'days', 'per_day', v_p->'per_day',
    'subtotal', v_p->'subtotal', 'lines', v_p->'lines', 'sizes', v_p->'sizes',
    'voucher', CASE WHEN v_v IS NOT NULL AND NOT (v_v ? 'error')
                    THEN jsonb_build_object('code', v_v->>'code', 'amount', v_disc) END,
    'discount', v_disc, 'total', (v_p->>'subtotal')::numeric - v_disc, 'amount', (v_p->>'subtotal')::numeric - v_disc);
  -- neplatný poukaz: cena se ukáže bez slevy + chyba poukazu
  IF v_v ? 'error' THEN v_out := v_out || jsonb_build_object('success', false, 'error', 'bad_voucher'); END IF;
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', 'failed', 'message', SQLERRM);
END $$;

CREATE OR REPLACE FUNCTION public.get_gear_rental_availability(p_branch_id uuid, p_start date, p_end date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keep int := public._gear_stock_keep_free(); v_sizes jsonb;
BEGIN
  IF NOT public._gear_stock_check_on('gear_rental') THEN RETURN jsonb_build_object('enabled', false); END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start OR p_end - p_start > 366
     OR NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND active) THEN
    RETURN jsonb_build_object('enabled', false, 'error', 'bad_request');
  END IF;
  SELECT COALESCE(jsonb_object_agg(t.accessory_type, t.sizes), '{}'::jsonb) INTO v_sizes
    FROM (SELECT f.accessory_type,
                 jsonb_object_agg(f.size, LEAST(GREATEST(f.free - v_keep, 0), 9)) AS sizes
            FROM public.gear_stock_free(p_branch_id, p_start, p_end, NULL) f
           WHERE f.tracked
           GROUP BY f.accessory_type) t;
  RETURN jsonb_build_object('enabled', true, 'sizes', v_sizes);
END $$;

REVOKE ALL ON FUNCTION public._gear_prepare(uuid, date, date, jsonb, uuid, boolean, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_voucher(text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_prepare(uuid, date, date, jsonb, uuid, boolean, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_voucher(text, numeric) TO service_role;
REVOKE ALL ON FUNCTION public.quote_gear_booking(uuid, date, date, jsonb, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_gear_rental_availability(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_gear_booking(uuid, date, date, jsonb, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_gear_rental_availability(uuid, date, date) TO anon, authenticated, service_role;
