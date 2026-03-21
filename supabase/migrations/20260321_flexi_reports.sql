-- flexi_reports: Stores reports pulled from Abra Flexi for review + submission
CREATE TABLE IF NOT EXISTS flexi_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_type TEXT NOT NULL CHECK (report_type IN (
    'vat_return',
    'income_tax',
    'balance_sheet',
    'profit_loss',
    'ossz',
    'vzp',
    'cash_flow',
    'accounting_closing'
  )),
  period_from DATE,
  period_to DATE,
  year INTEGER,
  quarter INTEGER,
  raw_data JSONB NOT NULL,
  rendered_html TEXT,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'approved', 'submitted', 'rejected')),
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  submitted_at TIMESTAMPTZ,
  datova_schranka_message_id TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE flexi_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_flexi_reports" ON flexi_reports FOR ALL USING (is_admin());

CREATE INDEX ON flexi_reports(report_type, year, quarter);
CREATE INDEX ON flexi_reports(status);

CREATE TRIGGER trg_flexi_reports_updated BEFORE UPDATE ON flexi_reports
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Unique constraint for upsert support
CREATE UNIQUE INDEX ON flexi_reports(report_type, year, quarter) WHERE quarter IS NOT NULL;
CREATE UNIQUE INDEX ON flexi_reports(report_type, year) WHERE quarter IS NULL;
