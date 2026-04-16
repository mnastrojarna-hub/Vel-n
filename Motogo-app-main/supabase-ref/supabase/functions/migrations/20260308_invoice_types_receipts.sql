-- ═══════════════════════════════════════════════════════
-- Extend invoices type constraint to include payment_receipt and shop_final
-- ═══════════════════════════════════════════════════════

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

-- Add source column if not exists (tracks origin: booking, edit, sos, shop, restore)
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS source text;
