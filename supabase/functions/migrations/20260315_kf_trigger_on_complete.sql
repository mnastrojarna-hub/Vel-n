-- =============================================================================
-- MIGRACE: KF (konečná faktura) se generuje triggerem při active → completed
-- Datum: 2026-03-15
--
-- Změny:
-- 1. auto_complete_expired_bookings() — POUZE mění status, negeneruje KF
-- 2. Nová funkce generate_final_invoice_on_complete() — trigger pro KF
-- 3. Trigger trg_generate_final_invoice na bookings (AFTER UPDATE OF status)
-- =============================================================================

-- 1. Přepsat auto_complete_expired_bookings() — jen status change, žádná fakturace
CREATE OR REPLACE FUNCTION auto_complete_expired_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE bookings
  SET status = 'completed'::booking_status,
      returned_at = NOW()
  WHERE status IN ('active', 'reserved')
    AND end_date < CURRENT_DATE
    AND payment_status = 'paid';
END;
$$;

-- 2. Trigger funkce: generuje KF při přechodu active → completed
CREATE OR REPLACE FUNCTION generate_final_invoice_on_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inv_num text;
  v_seq int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_items jsonb;
  v_total numeric;
  v_moto_model text;
  v_moto_spz text;
BEGIN
  -- Pouze při přechodu z active na completed
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN
    RETURN NEW;
  END IF;

  -- Přeskoč pokud už KF existuje
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN
    RETURN NEW;
  END IF;

  -- Přeskoč pokud nebylo zaplaceno
  IF NEW.payment_status != 'paid' THEN
    RETURN NEW;
  END IF;

  -- Získej data motorky
  SELECT model, spz INTO v_moto_model, v_moto_spz
  FROM motorcycles WHERE id = NEW.moto_id;

  -- Generuj číslo faktury KF-YYYY-NNNN
  SELECT COALESCE(MAX(CAST(SUBSTRING(number FROM '-(\d+)$') AS int)), 0) + 1
  INTO v_seq FROM invoices WHERE number LIKE 'KF-' || v_year || '-%';
  v_inv_num := 'KF-' || v_year || '-' || LPAD(v_seq::text, 4, '0');

  -- Položky faktury
  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', COALESCE(NEW.total_price, 0)
  ));

  -- Odpočet záloh (DP = payment_receipt)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number,
      'qty', 1, 'unit_price', -total
    )) FROM invoices
    WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  -- Celková částka
  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- Vlož fakturu
  INSERT INTO invoices (number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
                        issue_date, due_date, status, variable_symbol, source)
  VALUES (v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
          CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary');

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Loguj chybu ale neblokuj UPDATE bookingu
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- 3. Trigger na bookings — AFTER UPDATE OF status
DROP TRIGGER IF EXISTS trg_generate_final_invoice ON bookings;
CREATE TRIGGER trg_generate_final_invoice
  AFTER UPDATE OF status ON bookings
  FOR EACH ROW
  WHEN (OLD.status = 'active' AND NEW.status = 'completed')
  EXECUTE FUNCTION generate_final_invoice_on_complete();
