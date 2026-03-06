-- =====================================================
-- 015 — Auto-generování faktur a dokumentů
-- Rozšíření invoices CHECK constraints + variable_symbol
-- RLS policies pro documents a invoices INSERT zákazníkem
-- =====================================================

-- 1. Přidat variable_symbol sloupec
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'invoices' AND column_name = 'variable_symbol'
  ) THEN
    ALTER TABLE invoices ADD COLUMN variable_symbol text;
  END IF;
END $$;

-- 2. Rozšířit type CHECK constraint
DO $$
BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_type_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_type_check
    CHECK (type IN ('issued', 'received', 'final', 'proforma', 'shop_proforma', 'advance'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 3. Rozšířit status CHECK constraint
DO $$
BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_status_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_status_check
    CHECK (status IN ('draft', 'issued', 'paid', 'overdue', 'cancelled', 'sent'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 4. RLS: zákazník může vkládat dokumenty (auto-generace po platbě)
DROP POLICY IF EXISTS documents_user_insert ON documents;
CREATE POLICY documents_user_insert ON documents
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS documents_user_select ON documents;
CREATE POLICY documents_user_select ON documents
  FOR SELECT USING (user_id = auth.uid());

-- 5. RLS: zákazník může vkládat faktury (auto-generace po platbě)
DROP POLICY IF EXISTS invoices_customer_insert ON invoices;
CREATE POLICY invoices_customer_insert ON invoices
  FOR INSERT WITH CHECK (customer_id = auth.uid());

DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());

-- 6. Indexy
CREATE INDEX IF NOT EXISTS idx_documents_user_type ON documents(user_id, type);
CREATE INDEX IF NOT EXISTS idx_documents_booking ON documents(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_variable_symbol ON invoices(variable_symbol);
