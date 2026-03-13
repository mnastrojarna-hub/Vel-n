-- AUTO PROCESS VOUCHER ORDER
-- Automatická generace voucherů + in-app notifikace při zaplacení shop objednávky
-- BEFORE UPDATE trigger na shop_orders — spouští se při payment_status → 'paid'

-- 1. Funkce pro automatické zpracování voucher objednávky
CREATE OR REPLACE FUNCTION auto_process_voucher_order()
RETURNS TRIGGER AS $$
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
BEGIN
  -- Only process when payment_status changes to 'paid' AND order was 'new'
  -- (OLD.status = 'new' ensures we don't re-process already handled orders)
  IF OLD.status != 'new' THEN
    RETURN NEW;
  END IF;

  -- Count total items and voucher items
  SELECT COUNT(*) INTO v_all_items_count
  FROM shop_order_items WHERE order_id = NEW.id;

  SELECT COUNT(*) INTO v_voucher_items_count
  FROM shop_order_items WHERE order_id = NEW.id
    AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%');

  IF v_all_items_count = 0 THEN
    RETURN NEW;
  END IF;

  -- Check if there are physical vouchers (tištěný/fyzický)
  SELECT EXISTS(
    SELECT 1 FROM shop_order_items WHERE order_id = NEW.id
      AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
      AND (LOWER(product_name) LIKE '%tišt%' OR LOWER(product_name) LIKE '%fyzick%' OR LOWER(product_name) LIKE '%printed%')
  ) INTO v_has_physical_voucher;

  v_is_all_vouchers := (v_voucher_items_count = v_all_items_count);

  -- Guard: check if vouchers already generated for this order
  IF EXISTS (SELECT 1 FROM vouchers WHERE order_id = NEW.id) THEN
    -- Vouchers exist — just update status
    IF v_is_all_vouchers AND NOT v_has_physical_voucher THEN
      NEW.status := 'delivered';
      NEW.delivered_at := NOW();
    ELSE
      NEW.status := 'confirmed';
    END IF;
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
    RETURN NEW;
  END IF;

  -- Generate voucher codes for voucher items (respecting quantity)
  IF v_voucher_items_count > 0 THEN
    v_valid_until := CURRENT_DATE + INTERVAL '1 year';

    FOR v_item IN
      SELECT * FROM shop_order_items WHERE order_id = NEW.id
        AND (LOWER(product_name) LIKE '%voucher%' OR LOWER(product_name) LIKE '%poukaz%')
    LOOP
      -- Generate one voucher code per quantity unit
      FOR v_i IN 1..GREATEST(v_item.quantity, 1) LOOP
        -- Generate unique code: MG + 6 alphanumeric chars
        v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text || v_i::text) FROM 1 FOR 6));

        -- Ensure uniqueness
        WHILE EXISTS (SELECT 1 FROM vouchers WHERE code = v_code) LOOP
          v_code := 'MG' || UPPER(SUBSTRING(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));
        END LOOP;

        v_codes := array_append(v_codes, v_code);
        v_codes_with_amounts := array_append(v_codes_with_amounts,
          v_code || ' (' || COALESCE(v_item.unit_price, v_item.total_price, 0)::int || ' Kč)');

        INSERT INTO vouchers (code, amount, currency, status, buyer_id, buyer_name, buyer_email,
                              valid_from, valid_until, source, order_id)
        VALUES (v_code,
                COALESCE(v_item.unit_price, v_item.total_price, 0),
                'CZK', 'active',
                NEW.customer_id,
                COALESCE(NEW.customer_name, ''),
                COALESCE(NEW.customer_email, ''),
                CURRENT_DATE, v_valid_until,
                'eshop', NEW.id);
      END LOOP;
    END LOOP;

    -- Send in-app notification with voucher codes
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
  END IF;

  -- Set order status based on content
  IF v_is_all_vouchers AND NOT v_has_physical_voucher THEN
    -- Pure digital voucher order → fully auto-fulfilled
    NEW.status := 'delivered';
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
    NEW.delivered_at := NOW();
  ELSIF v_voucher_items_count > 0 THEN
    -- Mixed order (vouchers + physical goods) or physical voucher → partially auto
    -- Voucher codes generated, physical items need manual shipping
    NEW.status := 'confirmed';
    NEW.confirmed_at := COALESCE(NEW.confirmed_at, NOW());
  END IF;
  -- If no voucher items at all, status stays as set by confirm_shop_payment ('confirmed')

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Don't block payment on error — log and continue
  RAISE WARNING 'auto_process_voucher_order error for order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger: fires BEFORE UPDATE when payment_status changes to 'paid'
DROP TRIGGER IF EXISTS trg_auto_process_voucher_order ON shop_orders;
CREATE TRIGGER trg_auto_process_voucher_order
  BEFORE UPDATE OF payment_status ON shop_orders
  FOR EACH ROW
  WHEN (NEW.payment_status = 'paid' AND OLD.payment_status IS DISTINCT FROM 'paid')
  EXECUTE FUNCTION auto_process_voucher_order();

-- 3. Ensure delivered_at column exists on shop_orders (may not exist yet)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_orders' AND column_name = 'delivered_at'
  ) THEN
    ALTER TABLE shop_orders ADD COLUMN delivered_at timestamptz;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_orders' AND column_name = 'shipped_at'
  ) THEN
    ALTER TABLE shop_orders ADD COLUMN shipped_at timestamptz;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_orders' AND column_name = 'cancelled_at'
  ) THEN
    ALTER TABLE shop_orders ADD COLUMN cancelled_at timestamptz;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_orders' AND column_name = 'customer_name'
  ) THEN
    ALTER TABLE shop_orders ADD COLUMN customer_name text;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'shop_orders' AND column_name = 'customer_email'
  ) THEN
    ALTER TABLE shop_orders ADD COLUMN customer_email text;
  END IF;
END $$;
