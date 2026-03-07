-- =====================================================
-- MotoGo24 — Integration fixes: Velin <-> App
-- Idempotentni — bezpecne spustit opakovane
-- =====================================================

-- 1. DOCUMENTS tabulka

CREATE TABLE IF NOT EXISTS documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  type text NOT NULL DEFAULT 'document',
  file_path text,
  file_name text,
  name text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_documents_user ON documents(user_id);
CREATE INDEX IF NOT EXISTS idx_documents_booking ON documents(booking_id);

ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS documents_admin ON documents;
CREATE POLICY documents_admin ON documents
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS documents_customer_read ON documents;
CREATE POLICY documents_customer_read ON documents
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS documents_customer_insert ON documents;
CREATE POLICY documents_customer_insert ON documents
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 2. REVIEWS tabulka

CREATE TABLE IF NOT EXISTS reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  moto_id uuid REFERENCES motorcycles(id) ON DELETE SET NULL,
  rating integer CHECK (rating >= 1 AND rating <= 5),
  comment text,
  admin_reply text,
  visible boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Zajistit, ze sloupce existuji
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS rating integer;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS comment text;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS admin_reply text;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS visible boolean NOT NULL DEFAULT true;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS moto_id uuid;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS booking_id uuid;

CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_moto ON reviews(moto_id);

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reviews_admin ON reviews;
CREATE POLICY reviews_admin ON reviews
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS reviews_customer_read ON reviews;
CREATE POLICY reviews_customer_read ON reviews
  FOR SELECT USING (user_id = auth.uid() OR visible = true);

DROP POLICY IF EXISTS reviews_customer_insert ON reviews;
CREATE POLICY reviews_customer_insert ON reviews
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 3. USE_PROMO_CODE — atomicka RPC funkce

CREATE OR REPLACE FUNCTION use_promo_code(
  p_code text,
  p_booking_id uuid DEFAULT NULL,
  p_base_amount numeric DEFAULT 0
)
RETURNS jsonb AS $$
DECLARE
  v_promo promo_codes%ROWTYPE;
  v_uid uuid;
  v_discount numeric;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_promo FROM promo_codes
    WHERE code = upper(p_code) AND active = true
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kod neexistuje nebo neni aktivni');
  END IF;

  IF v_promo.valid_from IS NOT NULL AND v_promo.valid_from > CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kod jeste neni platny');
  END IF;

  IF v_promo.valid_to IS NOT NULL AND v_promo.valid_to < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kod vyprsel');
  END IF;

  IF v_promo.max_uses IS NOT NULL AND v_promo.used_count >= v_promo.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kod byl vycerpan');
  END IF;

  IF v_promo.min_order_amount IS NOT NULL AND p_base_amount < v_promo.min_order_amount THEN
    RETURN jsonb_build_object('valid', false, 'error',
      'Minimalni hodnota objednavky je ' || v_promo.min_order_amount || ' Kc');
  END IF;

  IF v_promo.type = 'percent' THEN
    v_discount := ROUND(p_base_amount * v_promo.value / 100);
  ELSE
    v_discount := v_promo.value;
  END IF;

  UPDATE promo_codes SET used_count = COALESCE(used_count, 0) + 1
    WHERE id = v_promo.id;

  INSERT INTO promo_code_usage (promo_code_id, booking_id, customer_id, discount_applied, used_at)
    VALUES (v_promo.id, p_booking_id, v_uid, v_discount, now());

  RETURN jsonb_build_object(
    'valid', true,
    'id', v_promo.id,
    'type', v_promo.type,
    'value', v_promo.value,
    'discount', v_discount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. CREATE_SHOP_ORDER — RPC pro e-shop objednavky

CREATE OR REPLACE FUNCTION create_shop_order(
  p_items jsonb,
  p_shipping_method text DEFAULT 'post',
  p_shipping_address jsonb DEFAULT NULL,
  p_payment_method text DEFAULT 'card',
  p_promo_code text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_uid uuid;
  v_profile profiles%ROWTYPE;
  v_order_id uuid;
  v_subtotal numeric := 0;
  v_shipping_cost numeric := 0;
  v_discount numeric := 0;
  v_promo_result jsonb;
  v_item jsonb;
  v_addr text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Neprihlasen');
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_subtotal := v_subtotal + (v_item->>'price')::numeric * (v_item->>'qty')::integer;
  END LOOP;

  IF v_subtotal <= 0 THEN
    RETURN jsonb_build_object('error', 'Prazdna objednavka');
  END IF;

  IF p_shipping_method = 'post' THEN
    v_shipping_cost := 99;
  END IF;

  IF p_promo_code IS NOT NULL AND p_promo_code != '' THEN
    v_promo_result := validate_promo_code(p_promo_code);
    IF (v_promo_result->>'valid')::boolean THEN
      IF v_promo_result->>'type' = 'percent' THEN
        v_discount := ROUND(v_subtotal * (v_promo_result->>'value')::numeric / 100);
      ELSE
        v_discount := (v_promo_result->>'value')::numeric;
      END IF;
      UPDATE promo_codes SET used_count = COALESCE(used_count, 0) + 1
        WHERE id = (v_promo_result->>'id')::uuid;
    END IF;
  END IF;

  IF p_shipping_address IS NOT NULL THEN
    v_addr := COALESCE(p_shipping_address->>'name', v_profile.full_name) || ', ' ||
              COALESCE(p_shipping_address->>'street', v_profile.street) || ', ' ||
              COALESCE(p_shipping_address->>'zip', v_profile.zip) || ' ' ||
              COALESCE(p_shipping_address->>'city', v_profile.city);
  END IF;

  INSERT INTO shop_orders (
    customer_id, customer_name, customer_email, customer_phone,
    shipping_address, status, payment_status, payment_method,
    subtotal, shipping_cost, discount, total,
    promo_code_id
  ) VALUES (
    v_uid, v_profile.full_name, v_profile.email, v_profile.phone,
    v_addr, 'new', 'pending', p_payment_method,
    v_subtotal, v_shipping_cost, v_discount,
    v_subtotal + v_shipping_cost - v_discount,
    CASE WHEN v_promo_result IS NOT NULL AND (v_promo_result->>'valid')::boolean
         THEN (v_promo_result->>'id')::uuid ELSE NULL END
  ) RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO shop_order_items (order_id, product_name, product_sku, quantity, unit_price, total_price)
    VALUES (
      v_order_id,
      v_item->>'name',
      v_item->>'id',
      (v_item->>'qty')::integer,
      (v_item->>'price')::numeric,
      (v_item->>'price')::numeric * (v_item->>'qty')::integer
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. CANCEL_BOOKING — RPC s cancellation tracking

CREATE OR REPLACE FUNCTION cancel_booking_tracked(
  p_booking_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_uid uuid;
  v_hours_until numeric;
  v_refund_pct integer;
  v_refund_amt numeric;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;

  IF v_booking.user_id != v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'Nemate opravneni');
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'Rezervace je jiz stornovana');
  END IF;

  v_hours_until := EXTRACT(EPOCH FROM (v_booking.start_date - now())) / 3600;
  IF v_hours_until > 7 * 24 THEN v_refund_pct := 100;
  ELSIF v_hours_until > 48 THEN v_refund_pct := 50;
  ELSE v_refund_pct := 0;
  END IF;
  v_refund_amt := ROUND(COALESCE(v_booking.total_price, 0) * v_refund_pct / 100);

  UPDATE bookings SET status = 'cancelled' WHERE id = p_booking_id;

  INSERT INTO booking_cancellations (booking_id, cancelled_by, reason, refund_amount, refund_percent)
  VALUES (p_booking_id, v_uid, p_reason, v_refund_amt, v_refund_pct);

  RETURN jsonb_build_object(
    'success', true,
    'refund_percent', v_refund_pct,
    'refund_amount', v_refund_amt
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. ADMIN_MESSAGES — RLS pro zakazniky INSERT

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'admin_messages_admin_insert' AND tablename = 'admin_messages'
  ) THEN
    EXECUTE 'CREATE POLICY admin_messages_admin_insert ON admin_messages FOR INSERT WITH CHECK (is_admin())';
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END $$;

-- 7. SHOP_ORDERS — customer INSERT policy

DROP POLICY IF EXISTS shop_orders_customer_insert ON shop_orders;
CREATE POLICY shop_orders_customer_insert ON shop_orders
  FOR INSERT WITH CHECK (customer_id = auth.uid());

DROP POLICY IF EXISTS shop_order_items_customer_insert ON shop_order_items;
CREATE POLICY shop_order_items_customer_insert ON shop_order_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM shop_orders
      WHERE shop_orders.id = shop_order_items.order_id
        AND shop_orders.customer_id = auth.uid()
    )
  );

-- 8. BOOKING_CANCELLATIONS — zajistit vsechny sloupce

DO $$
BEGIN
  ALTER TABLE booking_cancellations ADD COLUMN IF NOT EXISTS refund_amount numeric(10,2) DEFAULT 0;
  ALTER TABLE booking_cancellations ADD COLUMN IF NOT EXISTS refund_percent integer DEFAULT 0;
EXCEPTION WHEN undefined_table THEN
  NULL;
END $$;

-- 9. PROFILES — email sloupec

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email text;

-- 10. SOS_INCIDENTS — zajistit user_id sloupec

ALTER TABLE sos_incidents ADD COLUMN IF NOT EXISTS user_id uuid;

-- 11. PROMO_CODE_USAGE — zajistit existenci

CREATE TABLE IF NOT EXISTS promo_code_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promo_code_id uuid REFERENCES promo_codes(id) ON DELETE CASCADE,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  customer_id uuid,
  discount_applied numeric(10,2),
  used_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE promo_code_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS promo_code_usage_admin ON promo_code_usage;
CREATE POLICY promo_code_usage_admin ON promo_code_usage
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS promo_code_usage_customer ON promo_code_usage;
CREATE POLICY promo_code_usage_customer ON promo_code_usage
  FOR SELECT USING (customer_id = auth.uid());
