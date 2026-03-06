-- MotoGo24: Accounting & Invoicing
-- Účetnictví, faktury, daňové záznamy, pokladna

CREATE TYPE entry_type AS ENUM ('income', 'expense');
CREATE TYPE tax_type AS ENUM ('dph_monthly', 'dph_quarterly', 'dppo_annual', 'kontrolni_hlaseni', 'silnicni_dan');

CREATE TABLE accounting_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type entry_type NOT NULL,
    category TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    tax_rate NUMERIC(4,2) DEFAULT 21,
    tax_amount NUMERIC(12,2),
    description TEXT,
    reference_type TEXT,        -- 'booking', 'invoice', 'maintenance', 'purchase_order'
    reference_id UUID,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    invoice_id UUID,
    date DATE DEFAULT CURRENT_DATE,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE invoices (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    number TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('issued', 'received')),
    customer_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    issue_date DATE NOT NULL,
    due_date DATE NOT NULL,
    paid_date DATE,
    subtotal NUMERIC(12,2) NOT NULL,
    tax_amount NUMERIC(12,2) NOT NULL,
    total NUMERIC(12,2) NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('draft', 'issued', 'paid', 'overdue', 'cancelled')) DEFAULT 'draft',
    pdf_path TEXT,
    items JSONB DEFAULT '[]',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE tax_records (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type tax_type NOT NULL,
    period_from DATE NOT NULL,
    period_to DATE NOT NULL,
    data JSONB,
    xml_export TEXT,
    status TEXT NOT NULL CHECK (status IN ('draft', 'generated', 'submitted', 'accepted')) DEFAULT 'draft',
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE cash_register (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
    amount NUMERIC(12,2) NOT NULL,
    description TEXT,
    reference_id UUID,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== FUNKCE =====

-- Generování čísla faktury: FV-2026-0001
CREATE OR REPLACE FUNCTION generate_invoice_number(prefix TEXT DEFAULT 'FV')
RETURNS TEXT AS $$
DECLARE
    current_year TEXT;
    seq INT;
    result TEXT;
BEGIN
    current_year := EXTRACT(YEAR FROM CURRENT_DATE)::TEXT;
    SELECT COALESCE(MAX(
        CAST(NULLIF(SPLIT_PART(number, '-', 3), '') AS INT)
    ), 0) + 1
    INTO seq
    FROM invoices
    WHERE number LIKE prefix || '-' || current_year || '-%';

    result := prefix || '-' || current_year || '-' || LPAD(seq::TEXT, 4, '0');
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Trigger: po zaplacení bookingu auto-INSERT do accounting_entries
CREATE OR REPLACE FUNCTION auto_accounting_on_booking_paid()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.payment_status = 'paid' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'paid') THEN
        INSERT INTO accounting_entries (type, category, amount, tax_rate, tax_amount, description, reference_type, reference_id, branch_id, date, created_by)
        VALUES (
            'income',
            'pronájem',
            NEW.total_price,
            21,
            ROUND(NEW.total_price * 21 / 121, 2),
            'Platba za rezervaci #' || LEFT(NEW.id::TEXT, 8),
            'booking',
            NEW.id,
            NEW.branch_id,
            CURRENT_DATE,
            NEW.user_id
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER bookings_auto_accounting
    AFTER UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION auto_accounting_on_booking_paid();

-- ===== INDEXY =====

CREATE INDEX idx_accounting_entries_type ON accounting_entries(type);
CREATE INDEX idx_accounting_entries_date ON accounting_entries(date DESC);
CREATE INDEX idx_accounting_entries_branch ON accounting_entries(branch_id);
CREATE INDEX idx_accounting_entries_reference ON accounting_entries(reference_type, reference_id);
CREATE INDEX idx_invoices_number ON invoices(number);
CREATE INDEX idx_invoices_type ON invoices(type);
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_customer ON invoices(customer_id);
CREATE INDEX idx_invoices_booking ON invoices(booking_id);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);
CREATE INDEX idx_tax_records_type ON tax_records(type);
CREATE INDEX idx_tax_records_period ON tax_records(period_from, period_to);
CREATE INDEX idx_cash_register_branch ON cash_register(branch_id);
CREATE INDEX idx_cash_register_created ON cash_register(created_at DESC);

-- ===== RLS =====

ALTER TABLE accounting_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_register ENABLE ROW LEVEL SECURITY;

-- Zákazník vidí své faktury
CREATE POLICY "Users can view own invoices" ON invoices
    FOR SELECT USING (auth.uid() = customer_id);

-- Admin-only (rozšíří 013)
CREATE POLICY "Authenticated can view accounting entries" ON accounting_entries
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view tax records" ON tax_records
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view cash register" ON cash_register
    FOR SELECT USING (auth.uid() IS NOT NULL);

COMMENT ON TABLE accounting_entries IS 'Účetní záznamy — příjmy a výdaje';
COMMENT ON TABLE invoices IS 'Faktury vydané a přijaté';
COMMENT ON TABLE tax_records IS 'Daňové záznamy — DPH, DPPO, kontrolní hlášení';
COMMENT ON TABLE cash_register IS 'Pokladna — příjmy a výdaje v hotovosti';
