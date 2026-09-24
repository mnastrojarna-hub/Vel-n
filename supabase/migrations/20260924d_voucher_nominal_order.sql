-- =============================================================================
-- DÁRKOVÝ POUKAZ Z APPKY: hodnota poukazu = nominál (bez tisku a poštovného)
-- Migrace: 20260924d_voucher_nominal_order.sql (1/2 — create_shop_order;
--          2/2 = 20260924e_voucher_nominal_value.sql, trigger + regen)
--
-- NÁLEZ 2026-09-24 (testy e-shopu část 2): tištěný poukaz 1000 Kč koupený
-- v appce se vygeneroval v hodnotě 1180 Kč. Appka (a create_shop_order) měla
-- poukaz jako JEDNU položku za N + 180 Kč (tisk + poštovné) a trigger
-- auto_process_voucher_order bere hodnotu poukazu z ceny položky. Web to má
-- správně (handleWebShopCheckout): položka „Dárkový poukaz“ = nominál +
-- samostatná položka „Tisk a poštovné“ 180 Kč.
--
-- OPRAVA (zadání uživatele „tohle oprav“):
--   * create_shop_order: tištěný poukaz = položka N Kč + položka „Tisk
--     a poštovné“ 180 Kč (jako web). Celková cena, platba ani appka se nemění.
--   * auto_process_voucher_order + regen_voucher_for_order: u položek z appky
--     (SKU voucher_<N>_<p|d>_<ts>) je hodnota poukazu N, nejvýš cena položky
--     (LEAST — staré objednávky mohly mít cenu od klienta) — pokryje i čekající
--     objednávky založené dřív (jedna položka N+180), zaplacené až po nasazení
--     (jen s cs/en názvem položky — poukaz se pozná podle „poukaz/voucher“).
--     Web / Velín (bez takového SKU) beze změny: hodnota = cena položky.
--   Už vydané poukazy se NEMĚNÍ (zákazník dostal kód s hodnotou e-mailem).
--
-- Těla = živé verze (create_shop_order z 20260924b, regen z 20260924a,
-- auto_process_voucher_order ze supabase-live-snapshot 2026-09-24) + jen
-- výše popsané změny. Idempotentní (CREATE OR REPLACE), granty zachovány.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_shop_order(
  p_items jsonb,
  p_shipping_method text DEFAULT 'post'::text,
  p_shipping_address jsonb DEFAULT NULL::jsonb,
  p_payment_method text DEFAULT 'card'::text,
  p_promo_code text DEFAULT NULL::text
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_uid uuid; v_profile profiles%ROWTYPE; v_order_id uuid; v_prod products%ROWTYPE;
  v_item jsonb; v_line jsonb; v_lines jsonb := '[]'::jsonb;
  v_id text; v_m text[]; v_pid uuid; v_size text; v_qty integer;
  v_price numeric; v_name text; v_n integer; v_printed boolean; v_avail integer;
  v_has_physical boolean := false; v_has_voucher_line boolean := false;
  v_subtotal numeric := 0; v_shipping numeric := 0; v_ship_method text;
  v_codes text[] := '{}'; v_code text; v_res jsonb;
  v_pct jsonb := NULL; v_fixed jsonb := '[]'::jsonb; v_disc jsonb := '[]'::jsonb;
  v_base numeric; v_pct_amount numeric := 0; v_remaining numeric; v_amt numeric;
  v_discount numeric := 0; v_total numeric; v_promo_id uuid := NULL; v_addr text;
  v_auto boolean := false;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Neprihlasen'); END IF;
  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('error','Prazdna objednavka');
  END IF;
  IF jsonb_array_length(p_items) > 50 THEN
    RETURN jsonb_build_object('error','too_many_items','message','Příliš mnoho položek v košíku.');
  END IF;

  -- 1) Položky — cenu určuje server
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_id := COALESCE(v_item->>'id', '');
    v_qty := CASE WHEN COALESCE(v_item->>'qty','') ~ '^[0-9]{1,3}$'
                  THEN (v_item->>'qty')::integer END;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN
      RETURN jsonb_build_object('error','bad_qty','message','Neplatné množství položky v košíku.');
    END IF;

    v_m := regexp_match(v_id, '^voucher_([0-9]{1,5})_([pd])_[0-9]+$');
    IF v_m IS NOT NULL THEN
      v_n := v_m[1]::integer;
      v_printed := (v_m[2] = 'p');
      IF v_n < 100 THEN
        RETURN jsonb_build_object('error','bad_voucher_item','message','Neplatná hodnota dárkového poukazu.');
      END IF;
      -- Poukaz = JEN nominál (z ceny položky bere trigger auto_process_voucher_order
      -- hodnotu poukazu); tisk + poštovné je samostatná položka níže — jako web.
      v_price := v_n;
      v_name := 'Dárkový poukaz ' || v_n || ' Kč' || CASE WHEN v_printed THEN ' (tištěný)' ELSE '' END;
      v_pid := NULL; v_size := NULL;
      v_has_voucher_line := true;
    ELSE
      v_pid := CASE WHEN COALESCE(v_item->>'product_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                    THEN (v_item->>'product_id')::uuid
                    WHEN v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                    THEN substr(v_id, 1, 36)::uuid END;
      IF v_pid IS NULL THEN
        RETURN jsonb_build_object('error','invalid_item','message','Neznámá položka v košíku.');
      END IF;
      v_size := NULLIF(btrim(COALESCE(v_item->>'size',
                  CASE WHEN length(v_id) > 37 AND substr(v_id, 37, 1) = '-' THEN substr(v_id, 38) END, '')), '');
      SELECT * INTO v_prod FROM products WHERE id = v_pid FOR UPDATE;
      IF NOT FOUND OR NOT COALESCE(v_prod.is_active, true) THEN
        RETURN jsonb_build_object('error','product_not_found','message','Produkt v košíku už není v nabídce.');
      END IF;
      IF v_size IS NOT NULL AND COALESCE(array_length(v_prod.sizes, 1), 0) > 0
         AND NOT (v_size = ANY(v_prod.sizes)) THEN
        RETURN jsonb_build_object('error','bad_size','message','Zvolená velikost už není v nabídce.');
      END IF;
      v_price := v_prod.price;
      v_name := v_prod.name || CASE WHEN v_size IS NOT NULL THEN ' (' || v_size || ')' ELSE '' END;
      v_has_physical := true;
    END IF;

    v_subtotal := v_subtotal + v_price * v_qty;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'pid', v_pid, 'size', v_size, 'qty', v_qty, 'price', v_price, 'name', v_name, 'sku', v_id));
    -- Tištěný poukaz: tisk + poštovné 180 Kč jako vlastní položka (stejně jako web
    -- handleWebShopCheckout). Název NESMÍ obsahovat „poukaz/voucher“, jinak by z ní
    -- trigger vyrobil další poukaz. Celková cena se nemění (N + 180).
    IF v_m IS NOT NULL AND v_printed THEN
      v_subtotal := v_subtotal + 180 * v_qty;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'pid', NULL, 'size', NULL, 'qty', v_qty, 'price', 180, 'name', 'Tisk a poštovné', 'sku', NULL));
    END IF;
  END LOOP;
  IF v_subtotal <= 0 THEN RETURN jsonb_build_object('error','Prazdna objednavka'); END IF;

  -- 2) Sklad (součet za produkt + velikost), stejná odpověď jako dřív
  FOR v_line IN
    SELECT jsonb_build_object('pid', pid, 'size', size, 'qty', sum(qty))
    FROM (SELECT (l->>'pid')::uuid AS pid, l->>'size' AS size, (l->>'qty')::integer AS qty
          FROM jsonb_array_elements(v_lines) l WHERE l->>'pid' IS NOT NULL) x
    GROUP BY pid, size
  LOOP
    v_pid := (v_line->>'pid')::uuid; v_size := v_line->>'size'; v_qty := (v_line->>'qty')::integer;
    IF v_size IS NOT NULL THEN
      SELECT COALESCE((size_stock->>v_size)::integer, 0) INTO v_avail FROM products WHERE id = v_pid;
    ELSE
      SELECT COALESCE(stock_quantity, 0) INTO v_avail FROM products WHERE id = v_pid;
    END IF;
    IF v_avail < v_qty THEN
      RETURN jsonb_build_object('error','out_of_stock','product_id',v_pid,'size',v_size,'available',v_avail,'requested',v_qty);
    END IF;
  END LOOP;

  -- 3) Doprava — jako appka (košík jen z poukazů = bez poštovného)
  IF NOT v_has_physical THEN
    v_shipping := 0; v_ship_method := NULL;
  ELSIF p_shipping_method = 'post' THEN
    v_shipping := 99; v_ship_method := 'post';
  ELSIF p_shipping_method = 'pickup' THEN
    v_shipping := 0; v_ship_method := 'pickup';
  ELSE
    RETURN jsonb_build_object('error','bad_shipping','message','Neplatný způsob dopravy.');
  END IF;

  -- 4) Kódy — jen promo kódy
  IF p_promo_code IS NOT NULL THEN
    FOREACH v_code IN ARRAY string_to_array(p_promo_code, ',') LOOP
      v_code := upper(btrim(v_code));
      CONTINUE WHEN v_code = '' OR v_code = ANY(v_codes);
      v_codes := v_codes || v_code;
    END LOOP;
  END IF;
  IF COALESCE(array_length(v_codes, 1), 0) > 0 AND v_has_voucher_line THEN
    RETURN jsonb_build_object('error','code_not_allowed_for_voucher',
      'message','Slevový kód nelze uplatnit na nákup dárkového poukazu.');
  END IF;
  FOREACH v_code IN ARRAY v_codes LOOP
    v_res := validate_promo_code(v_code);
    IF COALESCE((v_res->>'valid')::boolean, false) THEN
      IF v_res->>'type' = 'percent' THEN
        IF v_pct IS NOT NULL THEN
          RETURN jsonb_build_object('error','multiple_percent','message','Nelze kombinovat dva procentuální kódy.');
        END IF;
        v_pct := jsonb_build_object('code', v_code, 'promo_code_id', v_res->>'id',
                                    'type', 'percent', 'value', (v_res->>'value')::numeric);
      ELSE
        v_fixed := v_fixed || jsonb_build_array(jsonb_build_object('code', v_code,
                     'promo_code_id', v_res->>'id', 'type', 'fixed', 'value', (v_res->>'value')::numeric));
      END IF;
      v_promo_id := COALESCE(v_promo_id, (v_res->>'id')::uuid);
    ELSIF EXISTS (SELECT 1 FROM vouchers WHERE upper(code) = v_code) THEN
      RETURN jsonb_build_object('error','voucher_not_allowed','code', v_code,
        'message','Dárkový poukaz ani poukaz ze Slevomatu nelze uplatnit v e-shopu — platí jen na půjčení motorky.');
    ELSE
      RETURN jsonb_build_object('error','code_invalid','code', v_code,
        'message','Slevový kód ' || v_code || ' není platný.');
    END IF;
  END LOOP;

  -- 5) Sleva — přesně jako PriceCalculator.calcDiscounts (appka):
  --    % z plné částky (mezisoučet + poštovné) nejdřív, pevné slevy na zbytek.
  v_base := v_subtotal + v_shipping;
  IF v_pct IS NOT NULL THEN
    v_pct_amount := ROUND(v_base * (v_pct->>'value')::numeric / 100);
    v_disc := v_disc || jsonb_build_array(v_pct || jsonb_build_object('amount', v_pct_amount));
  END IF;
  v_remaining := GREATEST(v_base - v_pct_amount, 0);
  v_discount := v_pct_amount;
  FOR v_line IN SELECT * FROM jsonb_array_elements(v_fixed) LOOP
    v_amt := LEAST(GREATEST((v_line->>'value')::numeric, 0), v_remaining);
    v_remaining := v_remaining - v_amt;
    v_discount := v_discount + v_amt;
    v_disc := v_disc || jsonb_build_array(v_line || jsonb_build_object('amount', v_amt));
  END LOOP;
  v_discount := LEAST(v_discount, v_base);
  v_total := GREATEST(v_base - v_discount, 0);

  IF p_shipping_address IS NOT NULL THEN
    v_addr := COALESCE(p_shipping_address->>'name', v_profile.full_name) || ', ' ||
              COALESCE(p_shipping_address->>'street', v_profile.street) || ', ' ||
              COALESCE(p_shipping_address->>'zip', v_profile.zip) || ' ' ||
              COALESCE(p_shipping_address->>'city', v_profile.city);
  END IF;

  INSERT INTO shop_orders (
    customer_id, customer_name, customer_email, customer_phone,
    shipping_address, shipping_method, status, payment_status, payment_method,
    subtotal, shipping_cost, discount, total, promo_code_id, discount_codes
  ) VALUES (
    v_uid, v_profile.full_name, v_profile.email, v_profile.phone,
    v_addr, v_ship_method, 'new', 'pending', 'card',
    v_subtotal, v_shipping, v_discount, v_total, v_promo_id,
    CASE WHEN jsonb_array_length(v_disc) > 0 THEN v_disc END
  ) RETURNING id INTO v_order_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(v_lines) LOOP
    v_pid := NULLIF(v_line->>'pid', '')::uuid;
    v_size := v_line->>'size';
    v_qty := (v_line->>'qty')::integer;
    v_price := (v_line->>'price')::numeric;
    INSERT INTO shop_order_items (order_id, product_id, product_name, product_sku, size, quantity, unit_price, total_price)
    VALUES (v_order_id, v_pid, v_line->>'name', v_line->>'sku', v_size, v_qty, v_price, v_price * v_qty);
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

  -- 6) Celá objednávka pokrytá promo kódem → potvrdit hned (triggery pošlou
  --    potvrzení a zapíšou použití kódu). Zákazník to sám potvrdit nesmí.
  IF v_total = 0 AND v_discount > 0 THEN
    UPDATE shop_orders SET
      payment_status = 'paid', payment_method = 'free',
      confirmed_at = COALESCE(confirmed_at, now()),
      status = CASE WHEN status = 'new' THEN 'confirmed' ELSE status END
    WHERE id = v_order_id AND payment_status IS DISTINCT FROM 'paid';
    v_auto := true;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'order_id', v_order_id,
    'subtotal', v_subtotal, 'shipping_cost', v_shipping,
    'discount', v_discount, 'total', v_total,
    'auto_confirmed', v_auto, 'pricing_version', 2);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) TO service_role;
