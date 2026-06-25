-- =============================================================================
-- MIGRACE 2026-06-25: Krok 4 — každá sleva/voucher samostatný řádek na ZF/DP/KF
--   4a) re-alokace booking_discounts.amount po změně ceny rezervace (trigger)
--   4c) KF trigger generate_final_invoice_on_complete — řádek za každou slevu
-- Loyalty a pozdní vyzvednutí už samostatné řádky měly. Edge fn generate-invoice
-- (ZF/DP) řešena v kódu (commit). Legacy rezervace bez booking_discounts → souhrn.
-- =============================================================================

-- ── 4a) re-alokace booking_discounts.amount ──────────────────────────────────
CREATE OR REPLACE FUNCTION public._reallocate_booking_discounts(p_booking_id uuid, p_gross numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pct_rate numeric := 0; v_pct_amt numeric; v_fixed_remaining numeric; r record; v_amt numeric;
  v_g numeric := GREATEST(0, COALESCE(p_gross,0));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM booking_discounts WHERE booking_id = p_booking_id) THEN RETURN; END IF;
  SELECT COALESCE(value,0) INTO v_pct_rate FROM booking_discounts
    WHERE booking_id=p_booking_id AND discount_type='percent' LIMIT 1;
  v_pct_rate := COALESCE(v_pct_rate,0);
  v_pct_amt := ROUND(v_g * v_pct_rate / 100);
  v_fixed_remaining := GREATEST(0, v_g - v_pct_amt);
  FOR r IN SELECT id, discount_type, value FROM booking_discounts
           WHERE booking_id=p_booking_id ORDER BY created_at, id LOOP
    IF r.discount_type='percent' THEN v_amt := v_pct_amt;
    ELSE v_amt := LEAST(COALESCE(r.value,0), v_fixed_remaining); v_fixed_remaining := v_fixed_remaining - v_amt; END IF;
    UPDATE booking_discounts SET amount = v_amt WHERE id = r.id;
  END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION public.trg_realloc_booking_discounts() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
     OR NEW.total_price IS DISTINCT FROM OLD.total_price THEN
    PERFORM public._reallocate_booking_discounts(NEW.id,
      COALESCE(NEW.total_price,0) + GREATEST(COALESCE(NEW.discount_amount,0),0));
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS realloc_booking_discounts ON bookings;
CREATE TRIGGER realloc_booking_discounts AFTER UPDATE OF discount_amount, total_price ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.trg_realloc_booking_discounts();

-- ── 4c) KF trigger — řádek za každou slevu/voucher (tělo 1:1 z 20260623) ──────
CREATE OR REPLACE FUNCTION public.generate_final_invoice_on_complete()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_inv_num text; v_seq int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_items jsonb; v_total numeric;
  v_moto_model text; v_moto_spz text;
  v_base_rental numeric; v_extras numeric; v_delivery numeric;
  v_discount numeric; v_discount_code text;
  v_loyalty numeric; v_loyalty_pct int;
  v_late_pickup numeric;
  v_booking_short text; v_promo_code text;
  v_cn_number text;                              -- NOVÉ #3
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN RETURN NEW; END IF;
  IF NEW.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN RETURN NEW; END IF;
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT model, spz INTO v_moto_model, v_moto_spz FROM motorcycles WHERE id = NEW.moto_id;

  v_inv_num := next_document_number('KF');       -- NOVÉ #3: atomické číslo (místo MAX+1)

  v_extras   := COALESCE(NEW.extras_price, 0);
  v_delivery := COALESCE(NEW.delivery_fee, 0);
  v_discount := COALESCE(NEW.discount_amount, 0);
  v_discount_code := COALESCE(NEW.discount_code, '');
  v_loyalty     := COALESCE(NEW.loyalty_discount_amount, 0);
  v_loyalty_pct := COALESCE(NEW.loyalty_percent, 0);
  v_late_pickup := COALESCE(NEW.late_pickup_discount_amount, 0);
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery
                   + v_discount + v_loyalty + v_late_pickup;

  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', v_base_rental
  ));

  IF v_extras > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Příslušenství a výbava', 'qty', 1, 'unit_price', v_extras));
  END IF;

  IF v_delivery > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Přistavení / odvoz motorky', 'qty', 1, 'unit_price', v_delivery));
  END IF;

  IF v_discount > 0 THEN
    IF EXISTS (SELECT 1 FROM booking_discounts WHERE booking_id = NEW.id) THEN
      v_items := v_items || COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'description', CASE WHEN bd.kind = 'voucher' THEN 'Voucher (' || bd.code || ')'
                              WHEN bd.discount_type = 'percent' THEN 'Slevový kód ' || bd.code || ' (' || bd.value || ' %)'
                              ELSE 'Slevový kód ' || bd.code END,
          'qty', 1, 'unit_price', -bd.amount) ORDER BY bd.created_at, bd.id)
        FROM booking_discounts bd WHERE bd.booking_id = NEW.id AND bd.amount > 0
      ), '[]'::jsonb);
    ELSE
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'description', CASE WHEN v_discount_code <> '' THEN 'Sleva (kód: ' || v_discount_code || ')'
                            ELSE 'Sleva / voucher' END,
        'qty', 1, 'unit_price', -v_discount));
    END IF;
  END IF;

  IF v_loyalty > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Věrnostní sleva' ||
        CASE WHEN v_loyalty_pct > 0 THEN ' ' || v_loyalty_pct || ' %' ELSE '' END ||
        ' — rezervace přes aplikaci MotoGo24',
      'qty', 1, 'unit_price', -v_loyalty));
  END IF;

  IF v_late_pickup > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Sleva 50 % na 1. den (pozdní vyzvednutí)',
      'qty', 1, 'unit_price', -v_late_pickup));
  END IF;

  -- Odpočet všech přijatých plateb (DP)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  -- Vrácené peníze (existující dobropisy z úprav / refundů)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'credit_note' AND status != 'cancelled'
  ), '[]'::jsonb);

  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- NOVÉ #3: záporná KF = zákazník přeplatil (záloha > finální cena).
  -- Vystav dobropis na přeplatek a KF dorovnej na 0 (místo záporné KF).
  IF ROUND(v_total::numeric, 2) < 0 THEN
    v_cn_number := next_document_number('DB');
    INSERT INTO invoices (number, type, customer_id, booking_id, items,
      subtotal, tax_amount, total, issue_date, due_date, status, variable_symbol, source)
    VALUES (v_cn_number, 'credit_note', NEW.user_id, NEW.id,
      jsonb_build_array(jsonb_build_object(
        'description', 'Přeplatek – záloha převyšuje finální cenu rezervace',
        'qty', 1, 'unit_price', v_total)),     -- v_total je záporné = částka dobropisu
      v_total, 0, v_total, CURRENT_DATE, CURRENT_DATE, 'issued', v_cn_number, 'final_overpay');

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || v_cn_number, 'qty', 1, 'unit_price', -v_total));
    v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
                FROM jsonb_array_elements(v_items) AS item);   -- = 0
  END IF;

  IF ROUND(v_total::numeric, 2) <> 0 THEN
    INSERT INTO debug_log (source, action, component, status, error_message, request_data)
    VALUES (
      'generate_final_invoice_on_complete', 'kf_total_not_zero', 'KF assertion', 'warning',
      'KF total != 0 (booking: ' || NEW.id || ', total: ' || v_total || ' Kč) — chybí DP/dobropis pro plné pokrytí?',
      jsonb_build_object(
        'booking_id', NEW.id, 'kf_number', v_inv_num, 'computed_total', v_total,
        'base_rental', v_base_rental, 'extras', v_extras, 'delivery', v_delivery,
        'discount', v_discount, 'loyalty_discount', v_loyalty,
        'late_pickup_discount', v_late_pickup, 'items', v_items,
        'sum_dp', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='payment_receipt' AND status!='cancelled'),
        'sum_credit_notes', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='credit_note' AND status!='cancelled')
      )
    );
    RAISE WARNING 'KF % pro booking % má total=% Kč (očekáváno 0). Zaloggováno do debug_log.',
      v_inv_num, NEW.id, v_total;
  END IF;

  v_booking_short := UPPER(RIGHT(REPLACE(NEW.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;

  INSERT INTO promo_codes (code, type, value, active, valid_from, valid_to, max_uses, used_count)
  VALUES (v_promo_code, 'fixed', 200, true, now(),
          (CURRENT_DATE + INTERVAL '1 year')::timestamptz, 1, 0)
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO invoices (
    number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
    issue_date, due_date, status, variable_symbol, source
  )
  VALUES (
    v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
    CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary'
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
