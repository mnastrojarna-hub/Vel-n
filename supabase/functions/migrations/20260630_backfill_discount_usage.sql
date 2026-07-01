-- =============================================================================
-- BACKFILL 2026-06-30: zpětné uplatnění slev/voucherů pro existující rezervace
--   (jednorázový skript — spuštěn a ověřen na živé DB uživatelem 2026-06-30)
--
--   A) rekonstrukce booking_discounts ze starých sloupců (discount_code parse +
--      promo_code_id / voucher_id fallback) u zaplacených nezrušených rezervací
--   B) doplnění promo_code_usage + autoritativní přepočet promo_codes.used_count
--   C) označení voucherů status='redeemed'
--
-- Kontext: do 2026-06-30 create_web_booking neplnil booking_discounts (viz
--   20260630_create_web_booking_populate_booking_discounts.sql), takže
--   redeem_booking_discounts_on_paid nikdy neinkrementoval used_count ani
--   neredeemoval vouchery. Tento skript srovná historii.
--
-- Idempotentní: A vkládá jen tam, kde řádky chybí; C flipuje jen active→redeemed;
--   B recomputuje used_count autoritativně z promo_code_usage.
-- Eligibilita: payment_status IN (paid, partial_refund, refund_pending) AND status<>'cancelled'
--
-- Ověřeno 2026-06-30: 6 zaplacených slevových rezervací = 6 započtených použití
--   (DANHANA=1, TEST98=2, RODINA1=1, OMLUVA1=1, VRACENI-73229E67=1); 0 uplatněných
--   voucherů (3 aktivní e-shop poukazy nebyly na žádné zaplacené rezervaci).
-- =============================================================================

-- ── A) Rekonstrukce booking_discounts ────────────────────────────────────────
DO $$
DECLARE
  b record;
  v_codes text[];
  v_code text;
  v_seen text[];
  v_promo_id uuid; v_promo_type text; v_promo_value numeric; v_promo_code text;
  v_vou_id uuid; v_vou_amount numeric; v_vou_code text;
  v_gross numeric;
BEGIN
  FOR b IN
    SELECT id, user_id, total_price, discount_amount, discount_code,
           promo_code_id, voucher_id
      FROM bookings
     WHERE payment_status IN ('paid','partial_refund','refund_pending')
       AND status <> 'cancelled'
       AND (promo_code_id IS NOT NULL
            OR voucher_id IS NOT NULL
            OR (discount_code IS NOT NULL AND btrim(discount_code) <> ''))
       AND NOT EXISTS (SELECT 1 FROM booking_discounts bd WHERE bd.booking_id = bookings.id)
  LOOP
    v_seen := ARRAY[]::text[];

    -- parse comma-list z discount_code (mirror create_web_booking)
    IF b.discount_code IS NOT NULL AND btrim(b.discount_code) <> '' THEN
      v_codes := string_to_array(b.discount_code, ',');
    ELSE
      v_codes := ARRAY[]::text[];
    END IF;

    FOREACH v_code IN ARRAY v_codes LOOP
      v_code := upper(btrim(v_code));
      CONTINUE WHEN v_code = '' OR v_code = ANY(v_seen);
      v_seen := array_append(v_seen, v_code);

      v_promo_id := NULL;
      SELECT id, type, value INTO v_promo_id, v_promo_type, v_promo_value
        FROM promo_codes WHERE upper(code) = v_code LIMIT 1;
      IF v_promo_id IS NOT NULL THEN
        INSERT INTO booking_discounts(booking_id,kind,code,promo_code_id,voucher_id,discount_type,value,amount)
        VALUES (b.id,'promo_code',v_code,v_promo_id,NULL,v_promo_type,COALESCE(v_promo_value,0),0);
        CONTINUE;
      END IF;

      v_vou_id := NULL;
      SELECT id, amount INTO v_vou_id, v_vou_amount
        FROM vouchers WHERE upper(code) = v_code LIMIT 1;
      IF v_vou_id IS NOT NULL THEN
        INSERT INTO booking_discounts(booking_id,kind,code,promo_code_id,voucher_id,discount_type,value,amount)
        VALUES (b.id,'voucher',v_code,NULL,v_vou_id,'fixed',COALESCE(v_vou_amount,0),0);
      END IF;
    END LOOP;

    -- fallback: promo_code_id sloupec nepokrytý přes discount_code
    IF b.promo_code_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM booking_discounts bd
                        WHERE bd.booking_id=b.id AND bd.promo_code_id=b.promo_code_id) THEN
      v_promo_id := NULL;
      SELECT id, type, value, code INTO v_promo_id, v_promo_type, v_promo_value, v_promo_code
        FROM promo_codes WHERE id=b.promo_code_id;
      IF v_promo_id IS NOT NULL THEN
        INSERT INTO booking_discounts(booking_id,kind,code,promo_code_id,voucher_id,discount_type,value,amount)
        VALUES (b.id,'promo_code',upper(v_promo_code),v_promo_id,NULL,v_promo_type,COALESCE(v_promo_value,0),0);
      END IF;
    END IF;

    -- fallback: voucher_id sloupec nepokrytý přes discount_code
    IF b.voucher_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM booking_discounts bd
                        WHERE bd.booking_id=b.id AND bd.voucher_id=b.voucher_id) THEN
      v_vou_id := NULL;
      SELECT id, amount, code INTO v_vou_id, v_vou_amount, v_vou_code
        FROM vouchers WHERE id=b.voucher_id;
      IF v_vou_id IS NOT NULL THEN
        INSERT INTO booking_discounts(booking_id,kind,code,promo_code_id,voucher_id,discount_type,value,amount)
        VALUES (b.id,'voucher',upper(v_vou_code),NULL,v_vou_id,'fixed',COALESCE(v_vou_amount,0),0);
      END IF;
    END IF;

    -- rozpočítej skutečně odečtené částky (best-effort) proti hrubé ceně
    v_gross := COALESCE(b.total_price,0) + GREATEST(COALESCE(b.discount_amount,0),0);
    PERFORM public._reallocate_booking_discounts(b.id, v_gross);
  END LOOP;
END $$;

-- ── B) promo_code_usage doplnění + autoritativní přepočet used_count ──────────
INSERT INTO promo_code_usage (promo_code_id, booking_id, customer_id, discount_applied, used_at)
SELECT bd.promo_code_id, bd.booking_id, b.user_id, bd.amount,
       COALESCE(b.confirmed_at, b.updated_at, now())
  FROM booking_discounts bd
  JOIN bookings b ON b.id = bd.booking_id
 WHERE bd.kind='promo_code' AND bd.promo_code_id IS NOT NULL
   AND b.payment_status IN ('paid','partial_refund','refund_pending')
   AND b.status <> 'cancelled'
   AND NOT EXISTS (SELECT 1 FROM promo_code_usage u
                    WHERE u.promo_code_id=bd.promo_code_id AND u.booking_id=bd.booking_id);

-- used_count = počet distinct rezervací z promo_code_usage (autoritativní, i 0)
UPDATE promo_codes p
   SET used_count = COALESCE((
     SELECT COUNT(DISTINCT u.booking_id)
       FROM promo_code_usage u WHERE u.promo_code_id = p.id
   ), 0);

-- ── C) vouchery → redeemed ───────────────────────────────────────────────────
UPDATE vouchers v
   SET status='redeemed',
       redeemed_at = COALESCE(v.redeemed_at, b.confirmed_at, b.updated_at, now()),
       redeemed_by = COALESCE(v.redeemed_by, b.user_id),
       booking_id  = COALESCE(v.booking_id, b.id),
       updated_at = now()
  FROM booking_discounts bd
  JOIN bookings b ON b.id = bd.booking_id
 WHERE bd.kind='voucher' AND bd.voucher_id = v.id
   AND b.payment_status IN ('paid','partial_refund','refund_pending')
   AND b.status <> 'cancelled'
   AND v.status = 'active';
