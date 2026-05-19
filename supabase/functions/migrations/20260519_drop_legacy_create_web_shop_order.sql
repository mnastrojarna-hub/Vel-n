-- =====================================================================
-- 2026-05-19 — Eshop checkout: chyba „currency of relation shop_orders
-- does not exist" + odstranění Zásilkovny z dopravy.
--
-- Reportováno: zákazník v /eshop → /kosik → /objednavka klikne „Zaplatit
-- a dokončit objednávku" → alert „column 'currency' of relation
-- 'shop_orders' does not exist".
--
-- Root cause: migrace 20260508 vytvořila novou verzi `create_web_shop_order`
-- s non-prefix parametry (`items, customer_name, ...`) BEZ sloupce `currency`,
-- ale STARÁ verze s `p_*` parametry (a INSERTem `currency`) zůstala v DB
-- jako overload (lišila se typem `p_shipping_address jsonb`). PHP web
-- `checkout.js` volal staré p_-prefix params → zase chyba.
--
-- Fix:
--   1) DROP staré p_-prefix verze (jsonb i text varianta, IF EXISTS).
--   2) Recreate kanonické verze s odstraněnou Zásilkovnou z CASE
--      (UI ji už nenabízí, ale držíme RPC v sync — pickup/post).
--      Pozn.: shop_orders.shipping_method CHECK constraint dál povoluje
--      'zasilkovna' kvůli historickým objednávkám.
-- =====================================================================

DROP FUNCTION IF EXISTS public.create_web_shop_order(
  jsonb, text, text, text, text, jsonb, text, text, text
);
DROP FUNCTION IF EXISTS public.create_web_shop_order(
  jsonb, text, text, text, text, jsonb, text, text
);
DROP FUNCTION IF EXISTS public.create_web_shop_order(
  jsonb, text, text, text, text, jsonb, text
);

CREATE OR REPLACE FUNCTION public.create_web_shop_order(
  items jsonb,
  customer_name text,
  customer_email text,
  customer_phone text,
  shipping_method text,
  shipping_address text DEFAULT NULL::text,
  payment_method text DEFAULT 'stripe'::text,
  promo_code text DEFAULT NULL::text,
  notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order_id uuid := gen_random_uuid();
  v_subtotal numeric := 0;
  v_shipping numeric := 0;
  v_total numeric := 0;
  it jsonb;
  prod RECORD;
  v_qty int;
  v_size text;
  v_avail int;
BEGIN
  IF jsonb_typeof(items) <> 'array' OR jsonb_array_length(items) = 0 THEN
    RETURN jsonb_build_object('error','no_items');
  END IF;

  -- Doprava — Zásilkovnu jsme z nabídky odebrali (2026-05-19).
  v_shipping := CASE shipping_method
    WHEN 'pickup' THEN 0
    WHEN 'post' THEN 99
    ELSE 0 END;

  FOR it IN SELECT * FROM jsonb_array_elements(items) LOOP
    v_qty := COALESCE((it->>'qty')::int, 1);
    v_size := NULLIF(it->>'size','');
    IF v_qty < 1 THEN
      RETURN jsonb_build_object('error','bad_qty');
    END IF;

    SELECT id, name, sku, price, sizes, stock_quantity, size_stock, is_active
      INTO prod
    FROM products
    WHERE id = (it->>'product_id')::uuid
    FOR UPDATE;

    IF NOT FOUND OR NOT prod.is_active THEN
      RETURN jsonb_build_object('error','product_not_found','product_id', it->>'product_id');
    END IF;

    IF prod.sizes IS NOT NULL AND array_length(prod.sizes,1) > 0 THEN
      IF v_size IS NULL OR NOT (v_size = ANY(prod.sizes)) THEN
        RETURN jsonb_build_object('error','bad_size','product_id',prod.id,'size',v_size);
      END IF;
      v_avail := COALESCE((prod.size_stock->>v_size)::int, 0);
    ELSE
      v_avail := COALESCE(prod.stock_quantity, 0);
    END IF;

    IF v_avail < v_qty THEN
      RETURN jsonb_build_object(
        'error','out_of_stock','product_id',prod.id,
        'size',v_size,'available',v_avail,'requested',v_qty
      );
    END IF;

    v_subtotal := v_subtotal + (prod.price * v_qty);
  END LOOP;

  v_total := v_subtotal + v_shipping;

  INSERT INTO shop_orders (
    id, customer_name, customer_email, customer_phone,
    shipping_method, shipping_address, payment_method,
    status, payment_status, subtotal, shipping_cost, total, notes
  ) VALUES (
    v_order_id, customer_name, customer_email, customer_phone,
    shipping_method, shipping_address, payment_method,
    'new', 'pending', v_subtotal, v_shipping, v_total, notes
  );

  FOR it IN SELECT * FROM jsonb_array_elements(items) LOOP
    v_qty := COALESCE((it->>'qty')::int, 1);
    v_size := NULLIF(it->>'size','');

    SELECT id, name, sku, price, sizes, stock_quantity, size_stock
      INTO prod
    FROM products
    WHERE id = (it->>'product_id')::uuid
    FOR UPDATE;

    INSERT INTO shop_order_items (order_id, product_id, product_name, product_sku, size, quantity, unit_price, total_price)
    VALUES (v_order_id, prod.id, prod.name, prod.sku, v_size, v_qty, prod.price, prod.price * v_qty);

    IF prod.sizes IS NOT NULL AND array_length(prod.sizes,1) > 0 AND v_size IS NOT NULL THEN
      UPDATE products
        SET size_stock = jsonb_set(
              COALESCE(size_stock,'{}'::jsonb),
              ARRAY[v_size],
              to_jsonb(GREATEST(0, COALESCE((size_stock->>v_size)::int,0) - v_qty))
            ),
            stock_quantity = GREATEST(0, COALESCE(stock_quantity,0) - v_qty)
      WHERE id = prod.id;
    ELSE
      UPDATE products
        SET stock_quantity = GREATEST(0, COALESCE(stock_quantity,0) - v_qty)
      WHERE id = prod.id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.create_web_shop_order(
  jsonb, text, text, text, text, text, text, text, text
) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
