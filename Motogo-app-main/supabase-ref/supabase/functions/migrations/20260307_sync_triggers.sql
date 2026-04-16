-- =====================================================
-- Sync triggers: Velín → MotoGo zákaznická appka
-- Když Velín vytvoří fakturu/smlouvu/protokol,
-- automaticky se propíše do documents tabulky,
-- kterou čte zákaznická appka.
-- =====================================================

-- TRIGGER 1: invoices → documents (sync pro zákazníka)
-- Když Velín vytvoří fakturu, zákazník ji uvidí v appce

CREATE OR REPLACE FUNCTION sync_invoice_to_documents()
RETURNS TRIGGER AS $$
DECLARE
  v_user_id uuid;
  v_doc_type text;
BEGIN
  SELECT user_id INTO v_user_id
  FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN
    v_user_id := NEW.customer_id;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.type IN ('proforma', 'advance', 'shop_proforma') THEN
    v_doc_type := 'invoice_advance';
  ELSIF NEW.type = 'payment_receipt' THEN
    v_doc_type := 'payment_receipt';
  ELSIF NEW.type IN ('shop_final') THEN
    v_doc_type := 'invoice_shop';
  ELSE
    v_doc_type := 'invoice_final';
  END IF;

  INSERT INTO documents (booking_id, user_id, type, file_name, file_path)
  SELECT NEW.booking_id, v_user_id, v_doc_type,
    'Faktura ' || NEW.number || '.pdf',
    COALESCE(NEW.pdf_path, 'invoices/' || NEW.id || '.html')
  WHERE NOT EXISTS (
    SELECT 1 FROM documents
    WHERE booking_id = NEW.booking_id
      AND user_id = v_user_id
      AND type = v_doc_type
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_invoice_to_documents ON invoices;
CREATE TRIGGER trg_sync_invoice_to_documents
  AFTER INSERT ON invoices
  FOR EACH ROW EXECUTE FUNCTION sync_invoice_to_documents();

-- =====================================================
-- TRIGGER 2: generated_documents → documents
-- Když Velín vygeneruje smlouvu/protokol, zákazník ji uvidí
-- =====================================================

CREATE OR REPLACE FUNCTION sync_generated_doc_to_documents()
RETURNS TRIGGER AS $$
DECLARE
  v_user_id uuid;
  v_template_type text;
  v_doc_type text;
  v_file_name text;
BEGIN
  SELECT user_id INTO v_user_id
  FROM bookings WHERE id = NEW.booking_id;
  IF v_user_id IS NULL THEN
    v_user_id := NEW.customer_id;
  END IF;
  IF v_user_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.template_id IS NOT NULL THEN
    SELECT type INTO v_template_type
    FROM document_templates WHERE id = NEW.template_id;
  END IF;

  IF v_template_type = 'rental_contract' OR v_template_type ILIKE '%contract%' THEN
    v_doc_type := 'contract';
    v_file_name := 'Smlouva o pronájmu.pdf';
  ELSIF v_template_type = 'handover_protocol' OR v_template_type ILIKE '%protocol%' THEN
    v_doc_type := 'protocol';
    v_file_name := 'Předávací protokol.pdf';
  ELSE
    v_doc_type := 'contract';
    v_file_name := 'Dokument.pdf';
  END IF;

  INSERT INTO documents (booking_id, user_id, type, file_name, file_path)
  SELECT NEW.booking_id, v_user_id, v_doc_type, v_file_name,
    COALESCE(NEW.pdf_path, 'generated/' || NEW.id || '.html')
  WHERE NOT EXISTS (
    SELECT 1 FROM documents
    WHERE booking_id = NEW.booking_id
      AND user_id = v_user_id
      AND type = v_doc_type
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_generated_doc_to_documents ON generated_documents;
CREATE TRIGGER trg_sync_generated_doc_to_documents
  AFTER INSERT ON generated_documents
  FOR EACH ROW EXECUTE FUNCTION sync_generated_doc_to_documents();

-- =====================================================
-- TRIGGER 3: update pdf_path sync
-- Když se aktualizuje pdf_path na faktuře, promítne se do documents
-- =====================================================

CREATE OR REPLACE FUNCTION sync_invoice_pdf_update()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.pdf_path IS DISTINCT FROM OLD.pdf_path AND NEW.pdf_path IS NOT NULL THEN
    UPDATE documents
    SET file_path = NEW.pdf_path
    WHERE booking_id = NEW.booking_id
      AND type IN ('invoice_advance', 'invoice_final')
      AND file_path LIKE 'invoices/%';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sync_invoice_pdf_update ON invoices;
CREATE TRIGGER trg_sync_invoice_pdf_update
  AFTER UPDATE OF pdf_path ON invoices
  FOR EACH ROW EXECUTE FUNCTION sync_invoice_pdf_update();

-- =====================================================
-- RLS policies — zákazník vidí své dokumenty
-- =====================================================

DROP POLICY IF EXISTS generated_documents_customer_select ON generated_documents;
CREATE POLICY generated_documents_customer_select ON generated_documents
  FOR SELECT USING (customer_id = auth.uid());

DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());
