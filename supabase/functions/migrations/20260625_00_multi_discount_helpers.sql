-- =============================================================================
-- MIGRACE 2026-06-25 (00): Multi-sleva — schéma + helpery (Fáze 2, kroky 1, 3a, 3b)
-- Ověřeno na živé DB (uživatel potvrdil "success" pro každý blok).
--   1)  booking_discounts (víc slev na rezervaci) + _calc_stacked_discount
--   3a) _recalc_booking_discount — option B (doplatek plná cena, vratka poměrná) + multi
--   3b) _apply_discount_variant_b — option B i pro legacy single-sleva
-- Pravidla: cena NIKDY < 0; max JEDNA procentní sleva; vratka nevrací víc, než
-- jsme vydělali. Loyalty (rank) se neřeší zde (zvlášť, app).
-- =============================================================================

-- ── 1) Vazební tabulka: víc slev na jednu rezervaci ──────────────────────────
CREATE TABLE IF NOT EXISTS booking_discounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('promo_code','voucher')),
  code text NOT NULL,
  promo_code_id uuid REFERENCES promo_codes(id) ON DELETE SET NULL,
  voucher_id uuid REFERENCES vouchers(id) ON DELETE SET NULL,
  discount_type text NOT NULL CHECK (discount_type IN ('percent','fixed')),
  value numeric NOT NULL DEFAULT 0,   -- % sazba nebo nominální Kč
  amount numeric NOT NULL DEFAULT 0,  -- skutečně odečtená Kč
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_booking_discounts_booking ON booking_discounts(booking_id);

-- ── Helper: složená sleva (max jedna %, fixní capováno na zbytek; cena >= 0) ──
CREATE OR REPLACE FUNCTION _calc_stacked_discount(p_gross numeric, p_discounts jsonb)
RETURNS jsonb AS $$
DECLARE
  d jsonb; v_pct_count int := 0; v_pct_rate numeric := 0;
  v_pct_amt numeric := 0; v_fixed_sum numeric := 0; v_fixed_amt numeric := 0;
BEGIN
  IF p_discounts IS NULL THEN
    RETURN jsonb_build_object('percent_rate',0,'percent_amount',0,'fixed_amount',0,'total',0);
  END IF;
  FOR d IN SELECT * FROM jsonb_array_elements(p_discounts) LOOP
    IF (d->>'discount_type') = 'percent' THEN
      v_pct_count := v_pct_count + 1;
      IF v_pct_count > 1 THEN RAISE EXCEPTION 'Lze uplatnit nejvýše jednu procentní slevu'; END IF;
      v_pct_rate := COALESCE((d->>'value')::numeric, 0);
    ELSE
      v_fixed_sum := v_fixed_sum + COALESCE((d->>'value')::numeric, 0);
    END IF;
  END LOOP;
  v_pct_amt   := ROUND(p_gross * v_pct_rate / 100);
  v_fixed_amt := LEAST(v_fixed_sum, GREATEST(0, p_gross - v_pct_amt));
  RETURN jsonb_build_object('percent_rate', v_pct_rate, 'percent_amount', v_pct_amt,
    'fixed_amount', v_fixed_amt, 'total', v_pct_amt + v_fixed_amt);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ── 3b) option B přímo v jádře přepočtu (legacy single-sleva) ─────────────────
CREATE OR REPLACE FUNCTION public._apply_discount_variant_b(
  p_old_total numeric, p_old_discount numeric, p_gross_diff numeric, p_dtype text
) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_old_total numeric := COALESCE(p_old_total,0);
  v_old_disc  numeric := GREATEST(COALESCE(p_old_discount,0),0);
  v_old_gross numeric := COALESCE(p_old_total,0) + GREATEST(COALESCE(p_old_discount,0),0);
  v_new_gross numeric; v_new_disc numeric; v_new_total numeric;
BEGIN
  v_new_gross := GREATEST(0, v_old_gross + COALESCE(p_gross_diff,0));
  IF COALESCE(p_gross_diff,0) >= 0 THEN
    v_new_disc := v_old_disc;                 -- DOPLATEK: plná cena, sleva zachována
  ELSIF v_old_disc <= 0 THEN
    v_new_disc := 0;
  ELSIF p_dtype = 'percent' AND v_old_gross > 0 THEN
    v_new_disc := ROUND(v_new_gross * v_old_disc / v_old_gross);   -- VRATKA: poměrně
  ELSE
    v_new_disc := LEAST(v_old_disc, v_new_gross);                  -- fixní: cap
  END IF;
  v_new_total := GREATEST(0, v_new_gross - v_new_disc);
  RETURN jsonb_build_object('new_gross',v_new_gross,'new_discount',v_new_disc,
    'new_total',v_new_total,'net_diff',v_new_total - v_old_total);
END; $$;

-- ── 3a) _recalc_booking_discount — option B + multi (procento + N voucherů) ───
CREATE OR REPLACE FUNCTION public._recalc_booking_discount(
  p_booking_id uuid, p_old_total numeric, p_old_discount numeric,
  p_gross_diff numeric, p_apply boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_old_total numeric := COALESCE(p_old_total,0);
  v_old_disc  numeric := GREATEST(COALESCE(p_old_discount,0),0);
  v_old_gross numeric := COALESCE(p_old_total,0) + GREATEST(COALESCE(p_old_discount,0),0);
  v_new_gross numeric;
  v_has_rows boolean;
  v_pct_rate numeric := 0; v_pct_amt numeric := 0;
  v_fixed_remaining numeric; v_new_disc numeric := 0; v_new_total numeric;
  r record; v_amt numeric; v_b bookings%ROWTYPE; v_dtype text;
BEGIN
  v_new_gross := GREATEST(0, v_old_gross + COALESCE(p_gross_diff,0));

  -- DOPLATEK (gross >= 0): plná cena, sleva ZACHOVÁNA (i změna na dražší motorku)
  IF COALESCE(p_gross_diff,0) >= 0 THEN
    v_new_disc := v_old_disc;
    v_new_total := GREATEST(0, v_new_gross - v_new_disc);
    RETURN jsonb_build_object('new_gross',v_new_gross,'new_discount',v_new_disc,
      'new_total',v_new_total,'net_diff',v_new_total - v_old_total);
  END IF;

  -- VRATKA (gross < 0): poměrná vyslevovaná částka — nevracíme víc, než jsme vydělali
  SELECT EXISTS(SELECT 1 FROM booking_discounts WHERE booking_id = p_booking_id) INTO v_has_rows;
  IF NOT v_has_rows THEN
    SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
    v_dtype := public._booking_discount_type(v_b.promo_code_id, v_b.promo_code, v_b.discount_code, v_b.voucher_id);
    RETURN public._apply_discount_variant_b(p_old_total, p_old_discount, p_gross_diff, v_dtype);
  END IF;

  SELECT COALESCE(value,0) INTO v_pct_rate FROM booking_discounts
    WHERE booking_id = p_booking_id AND discount_type = 'percent' LIMIT 1;
  v_pct_rate := COALESCE(v_pct_rate,0);
  v_pct_amt := ROUND(v_new_gross * v_pct_rate / 100);
  v_fixed_remaining := GREATEST(0, v_new_gross - v_pct_amt);
  v_new_disc := v_pct_amt;

  FOR r IN SELECT id, discount_type, value FROM booking_discounts
           WHERE booking_id = p_booking_id ORDER BY created_at, id LOOP
    IF r.discount_type = 'percent' THEN v_amt := v_pct_amt;
    ELSE v_amt := LEAST(COALESCE(r.value,0), v_fixed_remaining); v_fixed_remaining := v_fixed_remaining - v_amt; v_new_disc := v_new_disc + v_amt;
    END IF;
    IF p_apply THEN UPDATE booking_discounts SET amount = v_amt WHERE id = r.id; END IF;
  END LOOP;

  v_new_total := GREATEST(0, v_new_gross - v_new_disc);
  RETURN jsonb_build_object('new_gross',v_new_gross,'new_discount',v_new_disc,
    'new_total',v_new_total,'net_diff',v_new_total - v_old_total);
END;
$$;
REVOKE ALL ON FUNCTION public._recalc_booking_discount(uuid,numeric,numeric,numeric,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._recalc_booking_discount(uuid,numeric,numeric,numeric,boolean) TO authenticated, service_role;
