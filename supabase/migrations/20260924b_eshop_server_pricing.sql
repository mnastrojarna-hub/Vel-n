-- =============================================================================
-- BEZPEČNOST E-SHOPU (část 2): cenu objednávky z appky počítá SERVER
-- Migrace: 20260924b_eshop_server_pricing.sql
--
-- NÁLEZ 2026-09-24: create_shop_order přebíral od appky ceny položek, slevu
-- počítal jinak než appka (jen 1 promo kód, % bez poštovného, dárkové poukazy
-- vůbec) a process-payment strhával částku, kterou poslala appka. Cenu tak
-- určoval klient; dárkové poukazy použité v e-shopu appky se navíc nikdy
-- neuplatnily (šly použít opakovaně).
--
-- ROZHODNUTÍ PROVOZOVATELE (2026-09-24):
--   1) dárkové poukazy v e-shopu NE (FAQ upraveno v 20260924c),
--   2) poukazy ze Slevomatu v e-shopu NE,
--   3) nový dárkový poukaz nelze koupit s poukazem ani promo kódem,
--   4) procentní promo kód se počítá i z poštovného (jako appka),
--   5) nedoplatek se nesmí stát → částku k platbě bere process-payment
--      z shop_orders.total (tato funkce), jiná částka = odmítnuto.
--
-- create_shop_order (STEJNÁ signatura — vydané appky iOS 4.0.4 / Android
-- ≤ 4.0.7 volají dál, čtou jen order_id):
--   * cena produktu = products.price (produkt musí existovat a být aktivní),
--     dárkový poukaz = nominál z id položky `voucher_<N>_<p|d>_<ts>`
--     (+180 Kč tištěný — stejně jako appka); název poukazu normalizován na
--     „Dárkový poukaz N Kč (tištěný)“, aby ho trigger auto_process_voucher_order
--     poznal ve všech jazycích appky (dřív jen cs/en);
--   * poštovné 99 Kč (post) / 0 (pickup, košík jen z poukazů);
--   * kódy: jen promo kódy (validate_promo_code), max. jeden procentní;
--     % z (mezisoučet + poštovné) nejdřív, pevné slevy na zbytek, celkem ≥ 0
--     — PŘESNĚ jako PriceCalculator.calcDiscounts v appce;
--     dárkový / Slevomat poukaz → 'voucher_not_allowed';
--     jakýkoli kód v košíku s dárkovým poukazem → 'code_not_allowed_for_voucher';
--   * used_count se už nezvyšuje při založení — použití promo kódu se zapíše
--     do promo_code_usage až při zaplacení (trigger níže), takže max_uses
--     konečně platí i pro e-shop;
--   * objednávka za 0 Kč (celá pokrytá promo kódem) se potvrdí rovnou zde
--     (payment_method 'free') — zákazník ji už potvrdit nesmí (níže);
--   * vrací i subtotal / shipping_cost / discount / total / auto_confirmed.
--
-- confirm_shop_payment: ruší úzkou zákaznickou výjimku z 20260924a (objednávka
-- za 0 Kč) — tu teď potvrzuje server výše; zákazník vždy 'forbidden', kontrola
-- PŘED čtením objednávky. Guard/granty jinak beze změny proti 20260924a.
--
-- Idempotentní (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE, DROP TRIGGER IF
-- EXISTS). Tabulky a sloupce ověřeny proti supabase-live-snapshot 2026-09-24.
-- =============================================================================

ALTER TABLE public.shop_orders
  ADD COLUMN IF NOT EXISTS discount_codes jsonb;
COMMENT ON COLUMN public.shop_orders.discount_codes IS
  'Uplatněné promo kódy (create_shop_order v2): [{code, promo_code_id, type, value, amount}]';

ALTER TABLE public.promo_code_usage
  ADD COLUMN IF NOT EXISTS shop_order_id uuid
  REFERENCES public.shop_orders(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_promo_code_usage_shop_order
  ON public.promo_code_usage(shop_order_id) WHERE shop_order_id IS NOT NULL;

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
      v_price := v_n + CASE WHEN v_printed THEN 180 ELSE 0 END;
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

-- Zákazník už nic nepotvrzuje (výjimka z 20260924a zrušena — objednávku za
-- 0 Kč potvrzuje create_shop_order výše). Tělo jinak = 20260924a.
CREATE OR REPLACE FUNCTION "public"."confirm_shop_payment"("p_order_id" "uuid", "p_method" "text" DEFAULT 'card'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order   shop_orders%ROWTYPE;
  v_updated shop_orders%ROWTYPE;
  v_priv    boolean;
BEGIN
  -- Guard 2026-09-24: zaplacení potvrzuje server (webhook / verify_shop_session
  -- = service_role), admin Velínu, nebo přímé připojení k DB bez JWT.
  -- Dřív stačilo být vlastníkem objednávky (u web objednávek bez customer_id
  -- dokonce kdokoli s anon klíčem) → objednávka + vouchery bez platby.
  v_priv := auth.role() IS NULL
            OR auth.role() = 'service_role'
            OR COALESCE(public.is_admin(), false);

  IF NOT v_priv THEN
    -- Zákazník už nic nepotvrzuje: kartu/Apple Pay potvrdí webhook, objednávku
    -- za 0 Kč (celou pokrytou promo kódem) potvrdí rovnou create_shop_order
    -- (20260924b, serverový výpočet ceny). Vydané appky volání z klienta
    -- dělají dál — dostanou 'forbidden' a chybu ignorují. Kontrola je PŘED
    -- čtením objednávky (žádný zámek řádku ani prozrazení, že ID existuje).
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Objednávka nenalezena');
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

REVOKE EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) TO service_role;

-- Použití promo kódu v e-shopu se eviduje až při zaplacení (webhook, admin,
-- auto-potvrzení 0 Kč). validate_promo_code počítá použití z promo_code_usage,
-- takže max_uses nově platí i pro e-shop.
CREATE OR REPLACE FUNCTION public.record_shop_promo_usage_on_paid()
RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_d jsonb;
  v_pc uuid;
BEGIN
  IF NEW.discount_codes IS NULL OR jsonb_typeof(NEW.discount_codes) <> 'array' THEN
    RETURN NEW;
  END IF;
  FOR v_d IN SELECT * FROM jsonb_array_elements(NEW.discount_codes) LOOP
    v_pc := NULLIF(v_d->>'promo_code_id', '')::uuid;
    CONTINUE WHEN v_pc IS NULL;
    IF NOT EXISTS (SELECT 1 FROM promo_code_usage
                   WHERE shop_order_id = NEW.id AND promo_code_id = v_pc) THEN
      INSERT INTO promo_code_usage (promo_code_id, customer_id, shop_order_id, discount_applied)
      VALUES (v_pc, NEW.customer_id, NEW.id, COALESCE((v_d->>'amount')::numeric, 0));
      UPDATE promo_codes SET used_count = COALESCE(used_count, 0) + 1 WHERE id = v_pc;
    END IF;
  END LOOP;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Evidence použití nesmí zablokovat potvrzení zaplacené objednávky.
  RAISE WARNING 'record_shop_promo_usage_on_paid(%): %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_shop_promo_usage_on_paid ON public.shop_orders;
CREATE TRIGGER trg_shop_promo_usage_on_paid
  AFTER UPDATE OF payment_status ON public.shop_orders
  FOR EACH ROW
  WHEN (NEW.payment_status = 'paid' AND OLD.payment_status IS DISTINCT FROM 'paid')
  EXECUTE FUNCTION public.record_shop_promo_usage_on_paid();

REVOKE EXECUTE ON FUNCTION public.record_shop_promo_usage_on_paid() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_shop_promo_usage_on_paid() FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_shop_promo_usage_on_paid() FROM authenticated;
