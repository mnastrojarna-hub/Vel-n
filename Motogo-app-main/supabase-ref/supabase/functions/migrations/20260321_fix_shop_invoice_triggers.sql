-- =============================================================
-- Migration: Fix shop invoice triggers (ZF/DP/FK)
-- Date: 2026-03-21
-- =============================================================
-- ZF = zálohová faktura → trigger: vytvoření objednávky (frontend)
-- DP = doklad k přijaté platbě → trigger: zaplacení (frontend)
-- FK = konečná faktura za 0 Kč (s odečtem DP) → trigger: odesláno/doručeno
-- =============================================================

-- 1. ZRUŠ starý trigger: generate_shop_invoice (vytvářel shop_final při platbě)
DROP TRIGGER IF EXISTS trg_generate_shop_invoice ON shop_orders;
DROP FUNCTION IF EXISTS generate_shop_invoice();

-- 2. Nový trigger: auto-generuje záznam shop_final při odesláno/doručeno
CREATE OR REPLACE FUNCTION generate_shop_final_on_ship()
RETURNS TRIGGER AS $$
DECLARE
  v_dp_total NUMERIC;
BEGIN
  -- Reaguje pouze na změnu status → shipped nebo delivered
  IF NEW.status NOT IN ('shipped', 'delivered') THEN
    RETURN NEW;
  END IF;
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Objednávka musí být zaplacená
  IF NEW.payment_status != 'paid' THEN
    RETURN NEW;
  END IF;

  -- Už existuje shop_final? → skip
  IF EXISTS (
    SELECT 1 FROM invoices
    WHERE order_id = NEW.id AND type = 'shop_final'
  ) THEN
    RETURN NEW;
  END IF;

  -- Zjisti částku z DP (doklad k přijaté platbě)
  SELECT COALESCE(total, 0) INTO v_dp_total
  FROM invoices
  WHERE order_id = NEW.id AND type = 'payment_receipt'
  ORDER BY created_at DESC LIMIT 1;

  -- Vlož konečnou fakturu za 0 Kč (celá částka odečtena přes DP)
  INSERT INTO invoices (
    order_id, customer_id, amount, currency,
    status, type, source, issued_at
  ) VALUES (
    NEW.id, NEW.customer_id,
    GREATEST(NEW.total_amount - COALESCE(v_dp_total, 0), 0),
    COALESCE(NEW.currency, 'CZK'),
    'issued', 'shop_final', 'shop', NOW()
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_generate_shop_final_on_ship ON shop_orders;
CREATE TRIGGER trg_generate_shop_final_on_ship
  AFTER UPDATE OF status ON shop_orders
  FOR EACH ROW
  WHEN (NEW.status IN ('shipped', 'delivered')
    AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION generate_shop_final_on_ship();

-- 3. Fix sync_invoice_to_documents — podpora order_id (shop objednávky)
CREATE OR REPLACE FUNCTION sync_invoice_to_documents()
RETURNS TRIGGER AS $$
DECLARE
  v_user_id uuid;
  v_doc_type text;
BEGIN
  -- Pro shop objednávky: customer_id přímo z invoices
  -- Pro booking: z bookings tabulky
  IF NEW.booking_id IS NOT NULL THEN
    SELECT user_id INTO v_user_id FROM bookings WHERE id = NEW.booking_id;
  END IF;
  IF v_user_id IS NULL THEN
    v_user_id := NEW.customer_id;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.type IN ('proforma', 'advance', 'shop_proforma') THEN
    v_doc_type := 'invoice_advance';
  ELSIF NEW.type = 'payment_receipt' THEN
    v_doc_type := 'payment_receipt';
  ELSIF NEW.type = 'shop_final' THEN
    v_doc_type := 'invoice_shop';
  ELSE
    v_doc_type := 'invoice_final';
  END IF;

  -- Pro shop: booking_id je NULL, použij order_id pro deduplikaci
  INSERT INTO documents (booking_id, user_id, type, file_name, file_path)
  SELECT NEW.booking_id, v_user_id, v_doc_type,
    CASE
      WHEN NEW.type = 'payment_receipt' THEN 'DP ' || NEW.number || '.html'
      WHEN NEW.type = 'shop_proforma' THEN 'ZF ' || NEW.number || '.html'
      WHEN NEW.type = 'shop_final' THEN 'FV ' || NEW.number || '.html'
      ELSE 'Faktura ' || NEW.number || '.html'
    END,
    COALESCE(NEW.pdf_path, 'invoices/' || NEW.id || '.html')
  WHERE NOT EXISTS (
    SELECT 1 FROM documents
    WHERE user_id = v_user_id
      AND type = v_doc_type
      AND file_path = COALESCE(NEW.pdf_path, 'invoices/' || NEW.id || '.html')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_invoice_to_documents ON invoices;
CREATE TRIGGER trg_sync_invoice_to_documents
  AFTER INSERT ON invoices
  FOR EACH ROW EXECUTE FUNCTION sync_invoice_to_documents();
