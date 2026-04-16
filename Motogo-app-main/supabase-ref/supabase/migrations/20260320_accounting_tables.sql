-- =====================================================
-- ACCOUNTING TABLES for MotoGo24 Velín
-- Kompletní účetnictví: zaměstnanci, DPH, daně, majetek, odpisy, závazky
-- =====================================================

-- 1. ZAMĚSTNANCI
CREATE TABLE IF NOT EXISTS acc_employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  contract_type TEXT NOT NULL CHECK (contract_type IN ('hpp', 'dpp', 'dpc', 'ico')),
  gross_salary NUMERIC DEFAULT 0,
  start_date DATE,
  end_date DATE,
  personal_id TEXT,
  bank_account TEXT,
  tax_discount NUMERIC DEFAULT 2570,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE acc_employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_employees" ON acc_employees FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_employees_updated BEFORE UPDATE ON acc_employees
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 2. VÝPOČTY MEZD
CREATE TABLE IF NOT EXISTS acc_payrolls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES acc_employees(id) ON DELETE CASCADE,
  year INTEGER NOT NULL,
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  contract_type TEXT,
  gross_salary NUMERIC DEFAULT 0,
  social_employee NUMERIC DEFAULT 0,
  health_employee NUMERIC DEFAULT 0,
  tax_advance NUMERIC DEFAULT 0,
  net_salary NUMERIC DEFAULT 0,
  social_employer NUMERIC DEFAULT 0,
  health_employer NUMERIC DEFAULT 0,
  total_employer_cost NUMERIC DEFAULT 0,
  status TEXT DEFAULT 'prepared' CHECK (status IN ('prepared', 'paid')),
  paid_date DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(employee_id, year, month)
);

ALTER TABLE acc_payrolls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_payrolls" ON acc_payrolls FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_payrolls_updated BEFORE UPDATE ON acc_payrolls
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 3. PŘIZNÁNÍ K DPH
CREATE TABLE IF NOT EXISTS acc_vat_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  year INTEGER NOT NULL,
  quarter INTEGER NOT NULL CHECK (quarter BETWEEN 1 AND 4),
  period_from DATE NOT NULL,
  period_to DATE NOT NULL,
  taxable_outputs NUMERIC DEFAULT 0,
  output_vat NUMERIC DEFAULT 0,
  taxable_inputs NUMERIC DEFAULT 0,
  input_vat NUMERIC DEFAULT 0,
  vat_difference NUMERIC DEFAULT 0,
  vat_to_pay NUMERIC DEFAULT 0,
  vat_to_refund NUMERIC DEFAULT 0,
  total_invoices_issued INTEGER DEFAULT 0,
  total_invoices_received INTEGER DEFAULT 0,
  status TEXT DEFAULT 'prepared' CHECK (status IN ('prepared', 'submitted')),
  submitted_at TIMESTAMPTZ,
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(year, quarter)
);

ALTER TABLE acc_vat_returns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_vat_returns" ON acc_vat_returns FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_vat_returns_updated BEFORE UPDATE ON acc_vat_returns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 4. DAŇOVÉ PŘIZNÁNÍ (roční)
CREATE TABLE IF NOT EXISTS acc_tax_returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  year INTEGER NOT NULL UNIQUE,
  total_revenue NUMERIC DEFAULT 0,
  total_expenses NUMERIC DEFAULT 0,
  payroll_costs NUMERIC DEFAULT 0,
  depreciation NUMERIC DEFAULT 0,
  gross_income NUMERIC DEFAULT 0,
  deductible_expenses NUMERIC DEFAULT 0,
  tax_base NUMERIC DEFAULT 0,
  rounded_tax_base NUMERIC DEFAULT 0,
  income_tax_15 NUMERIC DEFAULT 0,
  income_tax_23 NUMERIC DEFAULT 0,
  total_income_tax NUMERIC DEFAULT 0,
  tax_discount NUMERIC DEFAULT 30840,
  tax_after_discount NUMERIC DEFAULT 0,
  paid_advances NUMERIC DEFAULT 0,
  tax_to_pay NUMERIC DEFAULT 0,
  tax_to_refund NUMERIC DEFAULT 0,
  status TEXT DEFAULT 'prepared' CHECK (status IN ('prepared', 'submitted')),
  submitted_at TIMESTAMPTZ,
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE acc_tax_returns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_tax_returns" ON acc_tax_returns FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_tax_returns_updated BEFORE UPDATE ON acc_tax_returns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 5. KRÁTKODOBÝ MAJETEK
CREATE TABLE IF NOT EXISTS acc_short_term_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('material', 'inventory', 'supplies', 'receivables', 'cash', 'bank', 'prepaid')),
  purchase_price NUMERIC DEFAULT 0,
  current_value NUMERIC DEFAULT 0,
  acquired_date DATE,
  disposed_date DATE,
  description TEXT,
  invoice_number TEXT,
  supplier TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'disposed')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE acc_short_term_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_short_term_assets" ON acc_short_term_assets FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_short_term_assets_updated BEFORE UPDATE ON acc_short_term_assets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 6. DLOUHODOBÝ MAJETEK
CREATE TABLE IF NOT EXISTS acc_long_term_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('vehicles', 'machinery', 'buildings', 'land', 'equipment', 'intangible')),
  purchase_price NUMERIC DEFAULT 0,
  current_value NUMERIC DEFAULT 0,
  total_depreciated NUMERIC DEFAULT 0,
  acquired_date DATE,
  disposed_date DATE,
  depreciation_group INTEGER CHECK (depreciation_group BETWEEN 1 AND 6),
  depreciation_method TEXT DEFAULT 'linear' CHECK (depreciation_method IN ('linear', 'accelerated')),
  description TEXT,
  invoice_number TEXT,
  supplier TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'fully_depreciated', 'disposed')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE acc_long_term_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_long_term_assets" ON acc_long_term_assets FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_long_term_assets_updated BEFORE UPDATE ON acc_long_term_assets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 7. ODPISY (záznamy o odpisech)
CREATE TABLE IF NOT EXISTS acc_depreciation_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id UUID NOT NULL REFERENCES acc_long_term_assets(id) ON DELETE CASCADE,
  year INTEGER NOT NULL,
  year_number INTEGER NOT NULL,
  annual_amount NUMERIC DEFAULT 0,
  cumulative_amount NUMERIC DEFAULT 0,
  remaining_value NUMERIC DEFAULT 0,
  method TEXT,
  depreciation_group INTEGER,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(asset_id, year)
);

ALTER TABLE acc_depreciation_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_depreciation_entries" ON acc_depreciation_entries FOR ALL USING (is_admin());

-- 8. ZÁVAZKY
CREATE TABLE IF NOT EXISTS acc_liabilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  counterparty TEXT,
  type TEXT NOT NULL CHECK (type IN ('supplier', 'tax', 'social', 'health', 'salary', 'loan', 'other')),
  amount NUMERIC DEFAULT 0,
  paid_amount NUMERIC DEFAULT 0,
  due_date DATE,
  paid_date DATE,
  description TEXT,
  variable_symbol TEXT,
  invoice_number TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'partial', 'paid', 'overdue')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE acc_liabilities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_liabilities" ON acc_liabilities FOR ALL USING (is_admin());

CREATE TRIGGER trg_acc_liabilities_updated BEFORE UPDATE ON acc_liabilities
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- AUTO-GENERATE LIABILITIES FROM PAYROLLS
-- When a payroll is created, auto-create liabilities for SP, ZP, tax
-- =====================================================
CREATE OR REPLACE FUNCTION auto_liabilities_from_payroll()
RETURNS TRIGGER AS $$
BEGIN
  -- Social insurance liability (employer + employee)
  IF (NEW.social_employer + NEW.social_employee) > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      'CSSZ',
      'social',
      NEW.social_employer + NEW.social_employee,
      'SP ' || NEW.month || '/' || NEW.year || ' - ' || (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-20')::date,
      'pending'
    );
  END IF;

  -- Health insurance liability
  IF (NEW.health_employer + NEW.health_employee) > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      'Zdravotni pojistovna',
      'health',
      NEW.health_employer + NEW.health_employee,
      'ZP ' || NEW.month || '/' || NEW.year || ' - ' || (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-20')::date,
      'pending'
    );
  END IF;

  -- Tax advance liability
  IF NEW.tax_advance > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      'Financni urad',
      'tax',
      NEW.tax_advance,
      'Zaloha dan ' || NEW.month || '/' || NEW.year || ' - ' || (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-20')::date,
      'pending'
    );
  END IF;

  -- Salary liability
  IF NEW.net_salary > 0 THEN
    INSERT INTO acc_liabilities (counterparty, type, amount, description, due_date, status)
    VALUES (
      (SELECT name FROM acc_employees WHERE id = NEW.employee_id),
      'salary',
      NEW.net_salary,
      'Mzda ' || NEW.month || '/' || NEW.year,
      (NEW.year || '-' || LPAD(NEW.month::text, 2, '0') || '-15')::date,
      'pending'
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_auto_liabilities_payroll
  AFTER INSERT ON acc_payrolls
  FOR EACH ROW
  EXECUTE FUNCTION auto_liabilities_from_payroll();
