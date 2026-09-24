-- =============================================================================
-- DÁRKOVÝ POUKAZ Z APPKY: hodnota poukazu = nominál (bez tisku a poštovného)
-- Migrace: 20260924e_voucher_nominal_value.sql (2/2 — auto_process_voucher_order
--          + regen_voucher_for_order; 1/2 = 20260924d_voucher_nominal_order.sql)
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

CREATE OR REPLACE FUNCTION "public"."auto_process_voucher_order"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_item RECORD;
  v_all_items_count INT;
  v_voucher_items_count INT;
  v_is_all_vouchers BOOL;
  v_has_physical_voucher BOOL := false;
  v_code TEXT;
  v_valid_until DATE;
  v_codes TEXT[] := '{}';
  v_codes_with_amounts TEXT[] := '{}';
  v_codes_str TEXT;
  v_i INT;
  v_amount NUMERIC;
BEGIN
  IF OLD.status NOT IN ('new', 'pending') THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO v_all_items_count
  FROM shop_order_items WHERE order_id = NEW.id;

  SELECT COUNT(*) INTO v_voucher_items_count
  FROM shop_order_items WHERE order_id = NEW.id
    AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%');

  IF v_all_items_count = 0 THEN RETURN NEW; END IF;

  SELECT EXISTS(
    SELECT 1 FROM shop_order_items WHERE order_id = NEW.id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
      AND (LOWER(product_name) LIKE '%tišt%' OR LOWER(product_name) LIKE '%fyzick%' OR LOWER(product_name) LIKE '%printed%')
  ) INTO v_has_physical_voucher;

  IF NOT v_has_physical_voucher AND COALESCE(NEW.notes, '') ILIKE '%fyzick%' THEN
    v_has_physical_voucher := true;
  END IF;

  v_is_all_vouchers := (v_voucher_items_count = v_all_items_count);

  -- Idempotence: vouchery už existují, jen aktualizuj status
  IF EXISTS (SELECT 1 FROM vouchers WHERE order_id = NEW.id) THEN
    IF v_is_all_vouchers AND NOT v_has_physical_voucher THEN
      NEW.status := 'delivered';
      NEW.delivered_at := COALESCE(NEW.delivered_at, NOW());
    ELSE
      NEW.status := 'confirmed';
    END IF;
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
    RETURN NEW;
  END IF;

  IF v_voucher_items_count > 0 THEN
    v_valid_until := CURRENT_DATE + INTERVAL '3 years';

    FOR v_item IN
      SELECT * FROM shop_order_items WHERE order_id = NEW.id
        AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
    LOOP
      -- Hodnota poukazu = nominál. Položky z appky mají SKU voucher_<N>_<p|d>_<ts>
      -- (dřív u tištěného cena N+180 → poukaz o 180 Kč vyšší); web/Velín mají
      -- v ceně položky nominál (tisk je zvlášť), takže u nich beze změny.
      -- LEAST: nikdy víc než cena položky — čekající objednávky založené před
      -- 20260924b mohly mít cenu od klienta nižší než nominál v SKU.
      v_amount := CASE WHEN COALESCE(v_item.product_sku, '') ~ '^voucher_[0-9]{1,5}_[pd]_[0-9]+$'
                   THEN LEAST(split_part(v_item.product_sku, '_', 2)::numeric,
                              COALESCE(v_item.unit_price, v_item.total_price, 0))
                   ELSE COALESCE(v_item.unit_price, v_item.total_price, 0) END;
      FOR v_i IN 1..GREATEST(v_item.quantity, 1) LOOP
        v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text || v_i::text) FROM 1 FOR 6));
        WHILE EXISTS (SELECT 1 FROM vouchers WHERE code = v_code) LOOP
          v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));
        END LOOP;

        v_codes := array_append(v_codes, v_code);
        v_codes_with_amounts := array_append(v_codes_with_amounts,
          v_code || ' (' || v_amount::int || ' Kč)');

        INSERT INTO vouchers (
          code, amount, currency, status,
          buyer_id, buyer_name, buyer_email,
          valid_from, valid_until,
          source, order_id, category
        ) VALUES (
          v_code,
          v_amount,
          'CZK', 'active',
          NEW.customer_id,
          COALESCE(NULLIF(NEW.customer_name, ''), 'Web zákazník'),
          COALESCE(NULLIF(NEW.customer_email, ''), ''),
          CURRENT_DATE, v_valid_until,
          'eshop', NEW.id, 'gift'
        );
      END LOOP;
    END LOOP;

    -- In-app notifikace pro registrované zákazníky (Velín & Flutter app)
    IF NEW.customer_id IS NOT NULL AND array_length(v_codes, 1) > 0 THEN
      v_codes_str := array_to_string(v_codes_with_amounts, E'\n');
      INSERT INTO admin_messages (user_id, title, message, type, read)
      VALUES (
        NEW.customer_id,
        'Dárkový poukaz MotoGo24',
        E'Děkujeme za nákup dárkového poukazu!\n\n' ||
        E'Vaše poukazy:\n' || v_codes_str || E'\n\n' ||
        'Platnost do ' || to_char(v_valid_until, 'DD.MM.YYYY') || E'.\n' ||
        E'Kód uplatníte při rezervaci motorky v sekci „Slevový kód".\n\n' ||
        'Přejeme krásnou jízdu!',
        'voucher', false
      );
    END IF;

    -- ❌ ŽÁDNÝ pg_net mail. Mail "voucher_purchased" výhradně posílá
    -- webhook-receiver/confirmShopPayment (s přílohami DP + HTML voucher).
  END IF;

  IF v_is_all_vouchers AND NOT v_has_physical_voucher THEN
    NEW.status := 'delivered';
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
    NEW.delivered_at := NOW();
  ELSIF v_voucher_items_count > 0 THEN
    NEW.status := 'confirmed';
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_process_voucher_order error for order %: %', NEW.id, SQLERRM;
  RETURN NEW;
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
  v_amount NUMERIC;
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
    -- Hodnota poukazu = nominál (viz auto_process_voucher_order).
    v_amount := CASE WHEN COALESCE(v_item.product_sku, '') ~ '^voucher_[0-9]{1,5}_[pd]_[0-9]+$'
                 THEN LEAST(split_part(v_item.product_sku, '_', 2)::numeric,
                            COALESCE(v_item.unit_price, v_item.total_price, 0))
                 ELSE COALESCE(v_item.unit_price, v_item.total_price, 0) END;
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
        v_amount,
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

REVOKE EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.regen_voucher_for_order(uuid) TO service_role;
