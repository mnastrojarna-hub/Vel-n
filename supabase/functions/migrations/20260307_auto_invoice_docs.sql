-- =====================================================
-- MotoGo24 — Migrace pro auto-generovani faktur a dokumentu
-- Rozsireni invoices tabulky + RLS pro documents INSERT
-- Idempotentni — bezpecne spustit opakovane
-- =====================================================

-- 1. INVOICES — pridat variable_symbol sloupec

ALTER TABLE invoices ADD COLUMN IF NOT EXISTS variable_symbol text;

-- 2. INVOICES — rozsirit type CHECK constraint

DO $$ BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_type_check;
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_type_check
    CHECK (type IN ('issued', 'received', 'final', 'proforma', 'shop_proforma', 'advance'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 3. INVOICES — rozsirit status CHECK constraint

DO $$ BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_status_check;
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_status_check
    CHECK (status IN ('draft', 'issued', 'paid', 'overdue', 'cancelled', 'sent'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 4. DOCUMENTS — RLS policy pro INSERT zakaznikem

DROP POLICY IF EXISTS documents_user_insert ON documents;
CREATE POLICY documents_user_insert ON documents
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS documents_user_select ON documents;
CREATE POLICY documents_user_select ON documents
  FOR SELECT USING (user_id = auth.uid());

-- 5. INVOICES — RLS policy pro INSERT zakaznikem

DROP POLICY IF EXISTS invoices_customer_insert ON invoices;
CREATE POLICY invoices_customer_insert ON invoices
  FOR INSERT WITH CHECK (customer_id = auth.uid());

DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());

-- 6. INDEX pro rychlejsi vyhledavani

CREATE INDEX IF NOT EXISTS idx_documents_user_type ON documents(user_id, type);
CREATE INDEX IF NOT EXISTS idx_documents_booking ON documents(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_variable_symbol ON invoices(variable_symbol);
