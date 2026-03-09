-- =====================================================
-- Fix invoice sync trigger + ensure all required columns
-- 2026-03-09
-- =====================================================

-- 1. Ensure all columns exist on invoices table
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS variable_symbol text;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS order_id uuid REFERENCES shop_orders(id) ON DELETE SET NULL;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- 2. Fix sync_invoice_to_documents to handle payment_receipt and shop types
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

-- 3. Ensure invoices type constraint includes all types
DO $$
BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_type_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_type_check
    CHECK (type IN ('issued', 'received', 'final', 'proforma', 'shop_proforma', 'shop_final', 'advance', 'payment_receipt'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 4. Ensure invoices status constraint includes all statuses
DO $$
BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_status_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_status_check
    CHECK (status IN ('draft', 'issued', 'paid', 'overdue', 'cancelled', 'sent', 'refunded'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 5. Ensure RLS policies exist for admin INSERT on invoices
DROP POLICY IF EXISTS invoices_admin ON invoices;
CREATE POLICY invoices_admin ON invoices
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 6. Ensure customer can also INSERT invoices (for mobile app scenarios)
DROP POLICY IF EXISTS invoices_customer_insert ON invoices;
CREATE POLICY invoices_customer_insert ON invoices
  FOR INSERT WITH CHECK (customer_id = auth.uid());

-- 7. Ensure customer SELECT policy
DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());
