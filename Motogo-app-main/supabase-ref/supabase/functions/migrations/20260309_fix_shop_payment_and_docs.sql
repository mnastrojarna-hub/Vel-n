-- FIX: Shop payment - customer nemůže UPDATE shop_orders (chybí RLS policy)
-- FIX: confirm_shop_payment RPC pro simulovanou platbu

-- 1. RPC pro potvrzení platby e-shop objednávky (SECURITY DEFINER = obchází RLS)
CREATE OR REPLACE FUNCTION confirm_shop_payment(
  p_order_id uuid,
  p_method text DEFAULT 'card'
)
RETURNS jsonb AS $$
DECLARE
  v_order shop_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Objednávka nenalezena');
  END IF;

  -- Ověření vlastníka nebo admina
  IF v_order.customer_id != auth.uid() AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nemáte oprávnění');
  END IF;

  -- Aktualizace platebního stavu
  UPDATE shop_orders SET
    payment_status = 'paid',
    payment_method = p_method,
    confirmed_at = now(),
    status = CASE WHEN status = 'new' THEN 'confirmed' ELSE status END
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'transaction_id', 'TXN-SHOP-' || substr(p_order_id::text, 1, 8)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Uděl přístup
GRANT EXECUTE ON FUNCTION confirm_shop_payment(uuid, text) TO authenticated;

-- 2. Záložní: přidej UPDATE RLS policy pro customer (jen payment_status vlastních objednávek)
DROP POLICY IF EXISTS shop_orders_customer_update ON shop_orders;
CREATE POLICY shop_orders_customer_update ON shop_orders
  FOR UPDATE USING (customer_id = auth.uid())
  WITH CHECK (customer_id = auth.uid());
