-- ===== Web: slevové kódy a dárkové poukazy u výpůjčky výbavy a u nákupu dárkového poukazu (část 3/3) =====
-- 2026-11-27, schváleno majitelem 2026-11-27. Celé zadání a popis viz 20261127a1_web_discount_codes_helpers.sql.
-- Tato část: quote_web_voucher_order — cena nákupu dárkového poukazu na webu se slevovými kódy (potřebuje část 1/3).
-- Idempotentní (DROP IF EXISTS starých podpisů + CREATE OR REPLACE), bez změn dat.

-- Nákup dárkového poukazu na webu: cena se slevovými kódy (stránka i process-payment)
CREATE OR REPLACE FUNCTION public.quote_web_voucher_order(p_amount numeric, p_print boolean DEFAULT false, p_codes text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_amt numeric := round(COALESCE(p_amount, 0), 2); v_fee numeric := CASE WHEN p_print THEN 180 ELSE 0 END;
  v_base numeric; v_dl jsonb; v_disc numeric := 0; v_total numeric; v_out jsonb; v_promo uuid;
BEGIN
  IF v_amt < 100 OR v_amt > 100000 THEN RETURN jsonb_build_object('success', false, 'error', 'bad_amount'); END IF;
  v_base := v_amt + v_fee;
  v_dl := public._web_discount_lines(p_codes, v_base, false);
  v_disc := (v_dl->>'discount')::numeric;
  v_total := GREATEST(v_base - v_disc, 0);
  SELECT (x->>'promo_code_id')::uuid INTO v_promo FROM jsonb_array_elements(v_dl->'lines') x LIMIT 1;
  v_out := jsonb_build_object('success', true, 'amount', v_amt, 'print_fee', v_fee, 'subtotal', v_base,
    'discount', v_disc, 'total', v_total, 'discount_codes', v_dl->'lines', 'promo_code_id', v_promo);
  IF jsonb_array_length(v_dl->'invalid') > 0 THEN
    v_out := v_out || jsonb_build_object('success', false, 'error', 'bad_code', 'code', v_dl->'invalid'->0->>'code',
      'message', v_dl->'invalid'->0->>'message', 'invalid', v_dl->'invalid');
  ELSIF v_total < 15 THEN
    -- kartou nejde zaplatit méně než 15 Kč; poukaz zdarma jen přes kód nevydáváme (poukaz s doklady
    -- posílá až potvrzení platby ze Stripe)
    v_out := v_out || jsonb_build_object('success', false, 'error', 'below_minimum', 'min', 15,
      'message', 'Po slevě musí zbýt k zaplacení aspoň 15 Kč.');
  END IF;
  RETURN v_out;
END $$;
REVOKE ALL ON FUNCTION public.quote_web_voucher_order(numeric, boolean, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_web_voucher_order(numeric, boolean, text[]) TO anon, authenticated, service_role;
