-- =====================================================
-- MotoGo24 — Migrace pro auto-generování faktur a dokumentů
-- Rozšíření invoices tabulky + RLS pro documents INSERT
-- Spustit v Supabase SQL Editoru — idempotentní
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. INVOICES — přidat variable_symbol sloupec
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'invoices' AND column_name = 'variable_symbol'
  ) THEN
    ALTER TABLE invoices ADD COLUMN variable_symbol text;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 2. INVOICES — rozšířit type CHECK constraint
--    Původní 007_accounting.sql má CHECK (type IN ('issued','received'))
--    Potřebujeme: 'issued','received','final','proforma','shop_proforma'
-- ═══════════════════════════════════════════════════════
DO $$
BEGIN
  -- Odebrat starý constraint pokud existuje (z 007_accounting.sql)
  IF EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_name = 'invoices' AND column_name = 'type'
    AND constraint_name LIKE '%type%check%'
  ) THEN
    EXECUTE 'ALTER TABLE invoices DROP CONSTRAINT ' ||
      (SELECT constraint_name FROM information_schema.constraint_column_usage
       WHERE table_name = 'invoices' AND column_name = 'type'
       AND constraint_name LIKE '%type%check%' LIMIT 1);
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL; -- Constraint neexistuje, pokračujeme
END $$;

-- Zkusit obecný název constraintu
DO $$
BEGIN
  ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_type_check;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Přidat nový rozšířený constraint
DO $$
BEGIN
  ALTER TABLE invoices ADD CONSTRAINT invoices_type_check
    CHECK (type IN ('issued', 'received', 'final', 'proforma', 'shop_proforma', 'advance'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ═══════════════════════════════════════════════════════
-- 3. INVOICES — rozšířit status CHECK constraint
--    Přidat 'paid' status pokud chybí
-- ═══════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════
-- 4. DOCUMENTS — RLS policy pro INSERT zákazníkem
--    Zákazník musí moci vkládat dokumenty (auto-generace)
-- ═══════════════════════════════════════════════════════
DROP POLICY IF EXISTS documents_user_insert ON documents;
CREATE POLICY documents_user_insert ON documents
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Zákazník může číst své dokumenty
DROP POLICY IF EXISTS documents_user_select ON documents;
CREATE POLICY documents_user_select ON documents
  FOR SELECT USING (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 5. INVOICES — RLS policy pro INSERT zákazníkem
--    Auto-generovaná faktura musí mít INSERT právo
-- ═══════════════════════════════════════════════════════
DROP POLICY IF EXISTS invoices_customer_insert ON invoices;
CREATE POLICY invoices_customer_insert ON invoices
  FOR INSERT WITH CHECK (customer_id = auth.uid());

-- Zákazník může číst své faktury (pokud chybí)
DROP POLICY IF EXISTS invoices_customer_select ON invoices;
CREATE POLICY invoices_customer_select ON invoices
  FOR SELECT USING (customer_id = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 6. INDEX pro rychlejší vyhledávání dokumentů
-- ═══════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_documents_user_type ON documents(user_id, type);
CREATE INDEX IF NOT EXISTS idx_documents_booking ON documents(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_variable_symbol ON invoices(variable_symbol);
