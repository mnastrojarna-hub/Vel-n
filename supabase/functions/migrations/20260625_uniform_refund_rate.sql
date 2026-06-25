-- =============================================================================
-- MIGRACE 2026-06-25: FIX vratky — UNIFORMNÍ poměrná sazba (i voucher se krátí)
--
-- Problém: při zkrácení/odebrání stará varianta B nechala FIXNÍ voucher celý a
-- krátila jen procentní část → vracelo se VÍC, než jsme za odebraný obsah vydělali.
-- Příklad: ceník 9000, sleva 3900 (10 % 900 + voucher 3000), zaplaceno 5100.
--   Zkrácení o 1 den (−3000 hrubého): stará logika vrátila 2700 (špatně).
--   Správně: vratka = poměr ZAPLACENÉHO = 3000 × 5100/9000 = 1700.
--
-- Oprava: VRATKA krátí CELOU slevu (procento i voucher) stejnou efektivní sazbou
--   new_discount = ROUND(new_gross × old_discount / old_gross)
-- → new_total = new_gross − new_discount; vratka = old_total − new_total.
-- DOPLATEK (gross >= 0) beze změny: plná cena, sleva zachována (option B).
-- Re-alokace booking_discounts.amount nově proporcionální (řádky drží poměr a
-- sečtou přesně na discount_amount).
-- =============================================================================

-- ── Jádro: doplatek = plná cena; vratka = uniformní poměrná sleva ─────────────
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
    v_new_disc := v_old_disc;                                  -- DOPLATEK: plná cena, sleva zachována
  ELSIF v_old_gross > 0 THEN
    v_new_disc := ROUND(v_new_gross * v_old_disc / v_old_gross); -- VRATKA: poměr zaplaceného (i voucher)
  ELSE
    v_new_disc := 0;
  END IF;
  v_new_total := GREATEST(0, v_new_gross - v_new_disc);
  RETURN jsonb_build_object('new_gross',v_new_gross,'new_discount',v_new_disc,
    'new_total',v_new_total,'net_diff',v_new_total - v_old_total);
END; $$;

-- ── _recalc_booking_discount → tenký wrapper (uniformní math je v jádře) ──────
-- Re-alokaci řádků řeší trigger realloc_booking_discounts po UPDATE ceny.
CREATE OR REPLACE FUNCTION public._recalc_booking_discount(
  p_booking_id uuid, p_old_total numeric, p_old_discount numeric,
  p_gross_diff numeric, p_apply boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN public._apply_discount_variant_b(p_old_total, p_old_discount, p_gross_diff, NULL);
END; $$;

-- ── Re-alokace: rozpočítej discount_amount na řádky PROPORCIONÁLNĚ ────────────
CREATE OR REPLACE FUNCTION public._reallocate_booking_discounts(p_booking_id uuid, p_target numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sum numeric; v_target numeric := GREATEST(0, COALESCE(p_target,0));
  r record; v_acc numeric := 0; v_first uuid; v_amt numeric;
BEGIN
  SELECT SUM(amount) INTO v_sum FROM booking_discounts WHERE booking_id = p_booking_id;
  IF v_sum IS NULL OR v_sum <= 0 THEN RETURN; END IF;
  FOR r IN SELECT id, amount FROM booking_discounts WHERE booking_id = p_booking_id ORDER BY created_at, id LOOP
    v_amt := ROUND(r.amount * v_target / v_sum);
    UPDATE booking_discounts SET amount = v_amt WHERE id = r.id;
    v_acc := v_acc + v_amt;
    IF v_first IS NULL THEN v_first := r.id; END IF;
  END LOOP;
  IF v_first IS NOT NULL AND v_acc <> v_target THEN  -- dorovnání zaokrouhlení
    UPDATE booking_discounts SET amount = amount + (v_target - v_acc) WHERE id = v_first;
  END IF;
END; $$;

-- Trigger fn cílí na NEW.discount_amount (proporcionální rozpočet).
CREATE OR REPLACE FUNCTION public.trg_realloc_booking_discounts() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.discount_amount IS DISTINCT FROM OLD.discount_amount THEN
    PERFORM public._reallocate_booking_discounts(NEW.id, NEW.discount_amount);
  END IF;
  RETURN NEW;
END; $$;
