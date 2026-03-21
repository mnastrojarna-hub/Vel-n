-- ============================================================
-- FINANCIAL EVENT PIPELINE + ABRA FLEXI INTEGRATION
-- Migration: 20260320_financial_events.sql
-- NOTE: Existing acc_* tables and inventory tables are UNCHANGED.
-- NOTE: Firma NENÍ plátcem DPH. vat_rate=0 as default.
--       VAT columns exist for future use only — NO VAT logic active.
-- ============================================================

-- 1. financial_events
CREATE TABLE IF NOT EXISTS financial_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL CHECK (event_type IN ('revenue','expense','asset','payroll')),
  source TEXT NOT NULL CHECK (source IN ('stripe','ocr','system','manual')),
  amount_czk NUMERIC(12,2) NOT NULL,
  vat_rate NUMERIC(5,2) NOT NULL DEFAULT 0,
  -- vat_rate: 0 = neplátce DPH. Až bude firma plátcem, změnit default na 21.
  -- Sloupec existuje pro budoucí potřebu, NEVYUŽÍVEJ pro výpočty nyní.
  duzp DATE NOT NULL,
  linked_entity_type TEXT,   -- 'booking','order','motorcycle','supplier'
  linked_entity_id UUID,
  confidence_score NUMERIC(3,2) DEFAULT 1.0 CHECK (confidence_score BETWEEN 0 AND 1),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','enriched','validated','exported','approved','submitted','error')),
  flexi_id TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ON financial_events(status);
CREATE INDEX ON financial_events(duzp);
CREATE INDEX ON financial_events(linked_entity_id);

ALTER TABLE financial_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_financial_events" ON financial_events FOR ALL USING (is_admin());

CREATE TRIGGER trg_fe_updated BEFORE UPDATE ON financial_events
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 2. flexi_sync_log
CREATE TABLE IF NOT EXISTS flexi_sync_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id UUID REFERENCES financial_events(id) ON DELETE CASCADE,
  direction TEXT NOT NULL CHECK (direction IN ('push','pull')),
  flexi_entity_type TEXT,
  payload JSONB,
  response_code INT,
  response_body JSONB,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','success','error','retry')),
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ON flexi_sync_log(financial_event_id);

ALTER TABLE flexi_sync_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_flexi_sync_log" ON flexi_sync_log FOR ALL USING (is_admin());

-- 3. accounting_exceptions
CREATE TABLE IF NOT EXISTS accounting_exceptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id UUID REFERENCES financial_events(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  suggested_fix JSONB,
  assigned_to TEXT DEFAULT 'admin',
  resolved_at TIMESTAMPTZ,
  resolution_note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE accounting_exceptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_acc_exceptions" ON accounting_exceptions FOR ALL USING (is_admin());

-- 4. approval_queue
CREATE TABLE IF NOT EXISTS approval_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  financial_event_id UUID REFERENCES financial_events(id) ON DELETE CASCADE,
  approval_type TEXT NOT NULL
    CHECK (approval_type IN ('invoice_export','expense_export','asset_registration','payroll','bank_reconciliation')),
  submitted_by TEXT DEFAULT 'system',
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected')),
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE approval_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_approval_queue" ON approval_queue FOR ALL USING (is_admin());

-- 5. TRIGGER: Flotila → acc_long_term_assets
-- Každá motorka v tabulce motorcycles se automaticky synchronizuje
-- do acc_long_term_assets jako dlouhodobý majetek.
-- Sklady (inventory tabulky) se NEMĚNÍ.
CREATE OR REPLACE FUNCTION sync_motorcycle_to_assets()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO acc_long_term_assets (
      name,
      category,
      purchase_price,
      current_value,
      acquired_date,
      depreciation_group,
      depreciation_method,
      description,
      status
    ) VALUES (
      NEW.brand || ' ' || NEW.model || ' (' || COALESCE(NEW.year::text, '?') || ')',
      'vehicles',
      COALESCE(NEW.purchase_price, 0),
      COALESCE(NEW.purchase_price, 0),
      COALESCE(NEW.acquired_date, CURRENT_DATE),
      2,        -- odpisová skupina 2 pro motorky (5 let)
      'linear',
      'Motorka MotoGo24 - ID: ' || NEW.id::text,
      'active'
    )
    ON CONFLICT DO NOTHING;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    -- Aktualizuj název a stav pokud se změní
    UPDATE acc_long_term_assets
    SET
      name = NEW.brand || ' ' || NEW.model || ' (' || COALESCE(NEW.year::text, '?') || ')',
      status = CASE WHEN NEW.status = 'retired' THEN 'disposed' ELSE 'active' END,
      updated_at = now()
    WHERE description LIKE '%' || NEW.id::text || '%';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Nikdy neblokuj operaci na motorcycles kvůli účetní sync
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_sync_moto_to_assets
  AFTER INSERT OR UPDATE ON motorcycles
  FOR EACH ROW
  EXECUTE FUNCTION sync_motorcycle_to_assets();
