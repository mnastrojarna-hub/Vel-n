-- ============================================================
-- SUPPORTING TABLES for Velín Finance module
-- accounting_entries, cash_register, tax_records, app_settings
-- ============================================================

-- 1. ACCOUNTING ENTRIES — záznamník příjmů/výdajů
-- Používá: Finance přehled, Dashboard, Statistics, BookingPaymentsTab
CREATE TABLE IF NOT EXISTS accounting_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('revenue', 'expense')),
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  description TEXT,
  category TEXT,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  booking_id UUID,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ON accounting_entries(date);
CREATE INDEX ON accounting_entries(type);
CREATE INDEX ON accounting_entries(booking_id);

ALTER TABLE accounting_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_accounting_entries" ON accounting_entries FOR ALL USING (is_admin());

CREATE TRIGGER trg_accounting_entries_updated BEFORE UPDATE ON accounting_entries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 2. CASH REGISTER — pokladna
-- Používá: CashRegisterTab
CREATE TABLE IF NOT EXISTS cash_register (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  description TEXT,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  balance NUMERIC(12,2) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ON cash_register(date);

ALTER TABLE cash_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_cash_register" ON cash_register FOR ALL USING (is_admin());

-- 3. TAX RECORDS — daňové záznamy
-- Používá: TaxTab
CREATE TABLE IF NOT EXISTS tax_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT DEFAULT 'income_tax',
  period_from DATE,
  period_to DATE,
  total NUMERIC(12,2) DEFAULT 0,
  tax_base NUMERIC(12,2) DEFAULT 0,
  tax_amount NUMERIC(12,2) DEFAULT 0,
  status TEXT DEFAULT 'prepared' CHECK (status IN ('prepared', 'submitted', 'paid')),
  notes TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE tax_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_tax_records" ON tax_records FOR ALL USING (is_admin());

-- 4. APP SETTINGS — klíč-hodnota nastavení
-- Používá: abraFlexi.js, VATReturnsTab, TaxReturnsTab
CREATE TABLE IF NOT EXISTS app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL UNIQUE,
  value JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_app_settings" ON app_settings FOR ALL USING (is_admin());
