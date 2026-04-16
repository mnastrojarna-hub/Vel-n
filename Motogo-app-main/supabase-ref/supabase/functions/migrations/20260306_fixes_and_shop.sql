-- =====================================================
-- MotoGo24 Velín — Opravy + Shop objednávky
-- Přidává: acquired_at, completed_date, shop_orders,
--          shop_order_items, promo validační funkce
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 0. BRANCHES — zajistit existenci tabulky
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  city text,
  address text,
  phone text,
  email text,
  opening_hours text,
  gps_lat numeric(10,7),
  gps_lng numeric(10,7),
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Admin: plný přístup
DROP POLICY IF EXISTS branches_admin ON branches;
CREATE POLICY branches_admin ON branches
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- Veřejné čtení
DROP POLICY IF EXISTS branches_public_read ON branches;
CREATE POLICY branches_public_read ON branches
  FOR SELECT USING (true);

DROP TRIGGER IF EXISTS trg_branches_updated ON branches;
CREATE TRIGGER trg_branches_updated
  BEFORE UPDATE ON branches
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 1. MOTORCYCLES — zajistit sloupec acquired_at
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'motorcycles' AND column_name = 'acquired_at'
  ) THEN
    ALTER TABLE motorcycles ADD COLUMN acquired_at date;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 2. MAINTENANCE_LOG — zajistit sloupec completed_date
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'maintenance_log' AND column_name = 'completed_date'
  ) THEN
    ALTER TABLE maintenance_log ADD COLUMN completed_date date;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'maintenance_log' AND column_name = 'scheduled_date'
  ) THEN
    ALTER TABLE maintenance_log ADD COLUMN scheduled_date date;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 3. SHOP_ORDERS (e-shop objednávky)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS shop_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number text NOT NULL UNIQUE,
  customer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  customer_name text,
  customer_email text,
  customer_phone text,
  shipping_address text,
  billing_address text,
  status text NOT NULL DEFAULT 'new'
    CHECK (status IN (
      'new','confirmed','processing','shipped',
      'delivered','cancelled','returned','refunded'
    )),
  payment_status text NOT NULL DEFAULT 'pending'
    CHECK (payment_status IN ('pending','paid','refunded','failed')),
  payment_method text,
  subtotal numeric(10,2) NOT NULL DEFAULT 0,
  shipping_cost numeric(10,2) NOT NULL DEFAULT 0,
  discount numeric(10,2) NOT NULL DEFAULT 0,
  total numeric(10,2) NOT NULL DEFAULT 0,
  promo_code_id uuid REFERENCES promo_codes(id) ON DELETE SET NULL,
  notes text,
  tracking_number text,
  shipped_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shop_orders_status
  ON shop_orders(status);
CREATE INDEX IF NOT EXISTS idx_shop_orders_customer
  ON shop_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_shop_orders_created
  ON shop_orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shop_orders_number
  ON shop_orders(order_number);

ALTER TABLE shop_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shop_orders_admin ON shop_orders;
CREATE POLICY shop_orders_admin ON shop_orders
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS shop_orders_customer_read ON shop_orders;
CREATE POLICY shop_orders_customer_read ON shop_orders
  FOR SELECT USING (customer_id = auth.uid());

DROP TRIGGER IF EXISTS trg_shop_orders_updated ON shop_orders;
CREATE TRIGGER trg_shop_orders_updated
  BEFORE UPDATE ON shop_orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════
-- 4. SHOP_ORDER_ITEMS (položky objednávky)
-- ═══════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS shop_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  product_name text NOT NULL,
  product_sku text,
  quantity integer NOT NULL DEFAULT 1,
  unit_price numeric(10,2) NOT NULL DEFAULT 0,
  total_price numeric(10,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shop_order_items_order
  ON shop_order_items(order_id);

ALTER TABLE shop_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shop_order_items_admin ON shop_order_items;
CREATE POLICY shop_order_items_admin ON shop_order_items
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS shop_order_items_customer ON shop_order_items;
CREATE POLICY shop_order_items_customer ON shop_order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM shop_orders
      WHERE shop_orders.id = shop_order_items.order_id
        AND shop_orders.customer_id = auth.uid()
    )
  );

-- ═══════════════════════════════════════════════════════
-- 5. PROMO_CODES — validační funkce
-- ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION validate_promo_code(p_code text)
RETURNS jsonb AS $$
DECLARE
  v_promo promo_codes%ROWTYPE;
BEGIN
  SELECT * INTO v_promo FROM promo_codes
    WHERE code = upper(p_code) AND active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód neexistuje nebo není aktivní');
  END IF;

  IF v_promo.valid_from IS NOT NULL AND v_promo.valid_from > CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód ještě není platný');
  END IF;

  IF v_promo.valid_to IS NOT NULL AND v_promo.valid_to < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód vypršel');
  END IF;

  IF v_promo.max_uses IS NOT NULL AND v_promo.used_count >= v_promo.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód byl vyčerpán');
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'id', v_promo.id,
    'type', v_promo.type,
    'value', v_promo.value,
    'min_order_amount', v_promo.min_order_amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════
-- 6. SEKVENCE pro čísla objednávek
-- ═══════════════════════════════════════════════════════
CREATE SEQUENCE IF NOT EXISTS shop_order_seq START 1001;

CREATE OR REPLACE FUNCTION generate_shop_order_number()
RETURNS trigger AS $$
BEGIN
  IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
    NEW.order_number := 'OBJ-' || to_char(now(), 'YYYY') || '-' ||
      lpad(nextval('shop_order_seq')::text, 5, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_shop_order_number ON shop_orders;
CREATE TRIGGER trg_shop_order_number
  BEFORE INSERT ON shop_orders
  FOR EACH ROW EXECUTE FUNCTION generate_shop_order_number();
