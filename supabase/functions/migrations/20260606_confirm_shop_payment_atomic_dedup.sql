-- FIX 2026-06-06: confirm_shop_payment — atomický dedup proti duplicitnímu Stripe webhooku
--
-- BUG: mail dárkového poukazu (`web_voucher_purchased`) chodil zákazníkovi 2× kompletně
-- včetně příloh (ZF, DP, Voucher PDF). Po Stripe platbě posílá Stripe dva eventy
-- (checkout.session.completed × payment_intent.succeeded) krátce po sobě a oba volají
-- confirmShopPayment() ve webhook-receiver. Edge kód (payment-confirmers.ts) duplicitu
-- řeší přes příznak `was_already_paid` z této RPC, JENŽE původní verze
-- (20260309_fix_shop_payment_and_docs.sql) tento příznak nikdy nevracela a nedělala
-- atomický UPDATE WHERE payment_status <> 'paid'. wasAlreadyPaid byl proto vždy false,
-- oba eventy prošly celým flow a send-booking-email se zavolal 2× (nemá vlastní dedup
-- přes message_log). Sesterská RPC confirm_payment (booking) tuto ochranu dostala už
-- 2026-05-08, na confirm_shop_payment se zapomnělo.
--
-- FIX: atomický UPDATE WHERE payment_status IS DISTINCT FROM 'paid' RETURNING — jen JEDNA
-- paralelní webhook session změní řádek (was_already_paid=false), druhý event nezmění nic
-- (was_already_paid=true) → webhook skipne mail/dokumenty/voucher. BEFORE/AFTER triggery
-- (auto_process_voucher_order, trg_shop_order_confirmed_email) se při 2. eventu nespustí.

CREATE OR REPLACE FUNCTION confirm_shop_payment(
  p_order_id uuid,
  p_method text DEFAULT 'card'
)
RETURNS jsonb AS $$
DECLARE
  v_order   shop_orders%ROWTYPE;
  v_updated shop_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM shop_orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Objednávka nenalezena');
  END IF;

  -- Ověření vlastníka nebo admina.
  -- service_role (webhook) má auth.uid()=NULL → porovnání je NULL → projde.
  -- Anonymní web voucher (customer_id IS NULL) také projde.
  IF v_order.customer_id IS NOT NULL
     AND v_order.customer_id <> auth.uid()
     AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nemáte oprávnění');
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
    -- Objednávka už byla 'paid' → duplicitní Stripe event, žádný side-effect
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION confirm_shop_payment(uuid, text) TO authenticated;
