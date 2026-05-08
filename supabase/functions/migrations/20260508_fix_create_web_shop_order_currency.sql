-- =====================================================================
-- 2026-05-08 — Fix `create_web_shop_order` RPC: column "currency" does not exist
--
-- Reportováno: Zákazník na `motogo24.cz/rezervace` v kroku 2 přidá doplněk
-- (např. kuklu) a klikne „Pokračovat k platbě" → alert „Nepodařilo se vytvořit
-- objednávku doplňků: column 'currency' of relation 'shop_orders' does not exist".
--
-- Root cause (2 bugy ve funkci, oba ze stejné historické inerce):
--   1) INSERT do `shop_orders` zapisuje sloupec `currency` ('CZK'), který v
--      tabulce neexistuje (CREATE TABLE z 20260306_fixes_and_shop.sql nemá
--      žádný `currency` — Stripe si měnu řeší v line items, do DB se neukládá).
--      Stejný typ bugu byl 2026-05-07 opraven v `process-payment` edge fn —
--      tato RPC ho zdědila a nikdy se neopravila.
--   2) INSERT zapisuje `payment_status = 'unpaid'`. CHECK constraint na
--      `shop_orders.payment_status` povoluje jen `pending/paid/refunded/failed`
--      (na rozdíl od `bookings.payment_status`, kde 'unpaid' platí).
--      Po opravě bugu č. 1 by request padl na tomto.
--
-- Fix: ze zachycené verze funkce (z DB) odstraňuji sloupec `currency` z
-- INSERT column listu i hodnotu `'CZK'` z VALUES; měním `'unpaid'` na
-- `'pending'`. Veškerá ostatní logika (per-velikost sklad, FOR UPDATE,
-- validace, dekrement) zůstává beze změny — návaznost na předchozí RPC.
-- =====================================================================

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

  -- Doprava
  v_shipping := CASE shipping_method
    WHEN 'pickup' THEN 0
    WHEN 'post' THEN 99
    WHEN 'zasilkovna' THEN 79
    ELSE 0 END;

  -- Validace + suma
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

    -- Validace velikosti
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

  -- Vytvoř order — BEZ sloupce `currency` (neexistuje v shop_orders).
  -- payment_status='pending' (CHECK constraint nepovoluje 'unpaid' jako u bookings).
  INSERT INTO shop_orders (
    id, customer_name, customer_email, customer_phone,
    shipping_method, shipping_address, payment_method,
    status, payment_status, subtotal, shipping_cost, total, notes
  ) VALUES (
    v_order_id, customer_name, customer_email, customer_phone,
    shipping_method, shipping_address, payment_method,
    'new', 'pending', v_subtotal, v_shipping, v_total, notes
  );

  -- Insert items + dekrement skladu (atomicky)
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
