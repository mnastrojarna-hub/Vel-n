-- =============================================================================
-- BEZPEČNOST E-SHOPU (část 1): zaplacení objednávky a poukazy jen přes server
-- Migrace: 20260924a_eshop_payment_lockdown.sql
--
-- NÁLEZ 2026-09-24 (analýza e-shopu po opravě confirm_payment, ověřeno proti
-- živému schématu supabase-live-snapshot 2026-09-24):
--   1) confirm_shop_payment (SECURITY DEFINER, EXECUTE anon+authenticated):
--      vlastník objednávky — u web objednávek bez customer_id kdokoli — si ji
--      mohl označit jako zaplacenou → trigger vygeneroval poukazy, odešly maily.
--   2) regen_voucher_for_order (anon+authenticated): bez kontroly role
--      i stavu platby → poukazy k libovolné, i nezaplacené objednávce.
--   3) RLS: shop_orders_customer_update (zákazník mohl přímo přepsat
--      payment_status/total/…), shop_orders_customer_insert
--      a shop_order_items_customer_insert (vlastní objednávky/položky mimo
--      RPC), invoices_customer_insert (vlastní „faktury“),
--      promo_usage_customer_insert; use_promo_code volatelná anon (mrtvý kód).
--
-- LEGITIMNÍ VOLAJÍCÍ (grep repa): confirm_shop_payment — webhook-receiver
-- a process-payment verify_shop_session (service_role), Velín jako admin;
-- vydané appky ji volají z klienta (po platbě kartou — tam ji nově nahrazuje
-- webhook, chyba se v appce ignoruje; u objednávky za 0 Kč — ponechaná úzká
-- výjimka níže). regen_voucher_for_order — webhook + process-payment
-- (service_role), vždy AŽ po zaplacení. Objednávky vznikají výhradně přes
-- SECURITY DEFINER RPC create_shop_order / create_web_shop_order (RLS
-- neobcházejí), appka ani web do shop_orders/shop_order_items/invoices přímo
-- nezapisují.
--
-- Těla funkcí = živá verze 1:1 + guard (a SET search_path). Idempotentní.
-- =============================================================================

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

  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Objednávka nenalezena');
  END IF;

  IF NOT v_priv THEN
    -- Jediná výjimka pro zákazníka: jeho vlastní ČEKAJÍCÍ objednávka za 0 Kč
    -- (celá pokrytá promo kódem ověřeným v create_shop_order). Vydané appky
    -- (iOS 4.0.4, Android ≤ 4.0.7) ji potvrzují z klienta a na serveru jiná
    -- cesta není. create_shop_order přebírá ceny od klienta → každá položka
    -- musí stát aspoň katalogovou cenu (produkt) / nominál (dárkový poukaz).
    IF auth.uid() IS NULL
       OR v_order.customer_id IS DISTINCT FROM auth.uid()
       OR v_order.payment_status <> 'pending'
       OR v_order.total > 0
       OR v_order.promo_code_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM shop_order_items WHERE order_id = p_order_id)
       OR ABS(v_order.subtotal - (SELECT COALESCE(SUM(i.unit_price * i.quantity), 0)
                                   FROM shop_order_items i
                                   WHERE i.order_id = p_order_id)) > 0.5
       OR EXISTS (
         SELECT 1
         FROM shop_order_items i
         LEFT JOIN products p ON p.id = i.product_id
         WHERE i.order_id = p_order_id
           AND (i.quantity < 1
                OR i.unit_price < 0
                OR CASE
                     WHEN i.product_id IS NOT NULL
                       THEN p.id IS NULL OR i.unit_price < p.price
                     WHEN i.product_sku ~ '^voucher_[0-9]{1,7}_[pd]_'
                       THEN i.unit_price < split_part(i.product_sku, '_', 2)::numeric
                     ELSE true
                   END)
       ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'forbidden');
    END IF;
    p_method := 'voucher';
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


CREATE OR REPLACE FUNCTION "public"."regen_voucher_for_order"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order shop_orders%ROWTYPE;
  v_item RECORD;
  v_all_items_count INT;
  v_voucher_items_count INT;
  v_is_all_vouchers BOOL;
  v_has_physical_voucher BOOL := false;
  v_code TEXT;
  v_valid_until DATE := CURRENT_DATE + INTERVAL '3 years';
  v_codes TEXT[] := '{}';
  v_i INT;
BEGIN
  -- Guard 2026-09-24: jen server (webhook / verify_shop_session, service_role),
  -- admin nebo přímé DB. Dřív ji mohl zavolat kdokoli s anon klíčem a vygenerovat
  -- poukazy i k NEZAPLACENÉ objednávce.
  IF auth.role() IS NOT NULL
     AND auth.role() <> 'service_role'
     AND NOT COALESCE(public.is_admin(), false) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;

  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  -- Poukazy jen k zaplacené objednávce (oba volající ji volají až po potvrzení).
  IF v_order.payment_status IS DISTINCT FROM 'paid' THEN
    RETURN jsonb_build_object('error', 'not_paid');
  END IF;

  -- Idempotence: pokud vouchery už existují, nedělej nic
  IF EXISTS (SELECT 1 FROM vouchers WHERE order_id = p_order_id) THEN
    RETURN jsonb_build_object('success', true, 'skipped', 'vouchers_exist');
  END IF;

  SELECT COUNT(*) INTO v_all_items_count FROM shop_order_items WHERE order_id = p_order_id;
  SELECT COUNT(*) INTO v_voucher_items_count
  FROM shop_order_items WHERE order_id = p_order_id
    AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%');

  IF v_voucher_items_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'skipped', 'no_voucher_items');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM shop_order_items WHERE order_id = p_order_id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
      AND (LOWER(product_name) LIKE '%tišt%' OR LOWER(product_name) LIKE '%fyzick%' OR LOWER(product_name) LIKE '%printed%')
  ) INTO v_has_physical_voucher;
  IF NOT v_has_physical_voucher AND COALESCE(v_order.notes, '') ILIKE '%fyzick%' THEN
    v_has_physical_voucher := true;
  END IF;
  v_is_all_vouchers := (v_voucher_items_count = v_all_items_count);

  FOR v_item IN
    SELECT * FROM shop_order_items WHERE order_id = p_order_id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
  LOOP
    FOR v_i IN 1..GREATEST(v_item.quantity, 1) LOOP
      v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text || v_i::text) FROM 1 FOR 6));
      WHILE EXISTS (SELECT 1 FROM vouchers WHERE code = v_code) LOOP
        v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));
      END LOOP;
      v_codes := array_append(v_codes, v_code);

      INSERT INTO vouchers (
        code, amount, currency, status,
        buyer_id, buyer_name, buyer_email,
        valid_from, valid_until,
        source, order_id, category
      ) VALUES (
        v_code,
        COALESCE(v_item.unit_price, v_item.total_price, 0),
        'CZK', 'active',
        v_order.customer_id,
        COALESCE(NULLIF(v_order.customer_name, ''), 'Web zákazník'),
        COALESCE(NULLIF(v_order.customer_email, ''), ''),
        CURRENT_DATE, v_valid_until,
        'eshop', p_order_id, 'gift'
      );
    END LOOP;
  END LOOP;

  -- Aktualizuj status
  UPDATE shop_orders SET
    status = CASE
      WHEN v_is_all_vouchers AND NOT v_has_physical_voucher THEN 'delivered'
      ELSE 'confirmed'
    END,
    confirmed_at = COALESCE(confirmed_at, NOW()),
    delivered_at = CASE
      WHEN v_is_all_vouchers AND NOT v_has_physical_voucher THEN NOW()
      ELSE delivered_at
    END
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'codes_generated', array_length(v_codes, 1),
    'is_digital', v_is_all_vouchers AND NOT v_has_physical_voucher
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_shop_payment(uuid, text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) TO service_role;

DROP POLICY IF EXISTS "shop_orders_customer_update" ON public.shop_orders;
DROP POLICY IF EXISTS "shop_orders_customer_insert" ON public.shop_orders;
DROP POLICY IF EXISTS "shop_order_items_customer_insert" ON public.shop_order_items;
DROP POLICY IF EXISTS "invoices_customer_insert" ON public.invoices;
-- promo_code_usage zapisuje jen SECURITY DEFINER kód (use_promo_code,
-- trigger redeem_booking_discounts_on_paid) — přímý zákaznický INSERT netřeba.
DROP POLICY IF EXISTS "promo_usage_customer_insert" ON public.promo_code_usage;

-- use_promo_code: žádný živý volající (jen mrtvý InvoiceService.usePromoCode),
-- přitom ji kdokoli s anon klíčem mohl volat a „vypotřebovat“ cizí promo kód.
REVOKE EXECUTE ON FUNCTION public.use_promo_code(text, uuid, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.use_promo_code(text, uuid, numeric) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.use_promo_code(text, uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.use_promo_code(text, uuid, numeric) TO service_role;

-- create_shop_order: volá jen přihlášená appka (tělo anon beztak odmítá).
REVOKE EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_shop_order(jsonb, text, jsonb, text, text) TO service_role;
