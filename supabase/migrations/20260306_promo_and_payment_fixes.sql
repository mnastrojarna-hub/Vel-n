-- =====================================================
-- MotoGo24 — Opravy promo kódů a plateb
-- 1. validate_promo_code: počítá skutečné použití z promo_code_usage
-- 2. Synchronizace used_count s reálnými daty
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. VALIDATE_PROMO_CODE — oprava: počítat z promo_code_usage
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION validate_promo_code(p_code text)
RETURNS jsonb AS $$
DECLARE
  v_promo promo_codes%ROWTYPE;
  v_actual_uses integer;
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

  -- Počítej skutečné použití z promo_code_usage (ne z used_count sloupce)
  SELECT count(*) INTO v_actual_uses
    FROM promo_code_usage WHERE promo_code_id = v_promo.id;

  -- Synchronizuj used_count pokud se liší
  IF v_promo.used_count IS DISTINCT FROM v_actual_uses THEN
    UPDATE promo_codes SET used_count = v_actual_uses WHERE id = v_promo.id;
  END IF;

  IF v_promo.max_uses IS NOT NULL AND v_promo.max_uses > 0 AND v_actual_uses >= v_promo.max_uses THEN
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
-- 2. USE_PROMO_CODE — oprava: počítat z promo_code_usage
-- ═══════════════════════════════════════════════════════

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
  v_actual_uses integer;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_promo FROM promo_codes
    WHERE code = upper(p_code) AND active = true
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód neexistuje nebo není aktivní');
  END IF;

  IF v_promo.valid_from IS NOT NULL AND v_promo.valid_from > CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód ještě není platný');
  END IF;

  IF v_promo.valid_to IS NOT NULL AND v_promo.valid_to < CURRENT_DATE THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód vypršel');
  END IF;

  -- Počítej skutečné použití
  SELECT count(*) INTO v_actual_uses
    FROM promo_code_usage WHERE promo_code_id = v_promo.id;

  IF v_promo.max_uses IS NOT NULL AND v_promo.max_uses > 0 AND v_actual_uses >= v_promo.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'error', 'Kód byl vyčerpán');
  END IF;

  IF v_promo.min_order_amount IS NOT NULL AND p_base_amount < v_promo.min_order_amount THEN
    RETURN jsonb_build_object('valid', false, 'error',
      'Minimální hodnota objednávky je ' || v_promo.min_order_amount || ' Kč');
  END IF;

  -- Vypočítej slevu
  IF v_promo.type = 'percent' THEN
    v_discount := ROUND(p_base_amount * v_promo.value / 100);
  ELSE
    v_discount := v_promo.value;
  END IF;

  -- Aktualizuj used_count na skutečný počet + 1
  UPDATE promo_codes SET used_count = v_actual_uses + 1
    WHERE id = v_promo.id;

  -- Zaloguj použití
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

-- ═══════════════════════════════════════════════════════
-- 3. Jednorázová synchronizace used_count s promo_code_usage
-- ═══════════════════════════════════════════════════════

UPDATE promo_codes pc SET used_count = (
  SELECT count(*) FROM promo_code_usage pcu WHERE pcu.promo_code_id = pc.id
);
