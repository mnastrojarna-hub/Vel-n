-- MotoGo24: Maintenance & Service
-- Evidence servisů, plány údržby motorek

CREATE TABLE maintenance_log (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE CASCADE,
    service_date DATE NOT NULL,
    mileage_at_service INT,
    service_type TEXT NOT NULL CHECK (service_type IN ('regular', 'extraordinary', 'repair')),
    description TEXT,
    parts_used JSONB DEFAULT '[]',
    labor_cost NUMERIC(10,2),
    parts_cost NUMERIC(10,2),
    total_cost NUMERIC(10,2) GENERATED ALWAYS AS (COALESCE(labor_cost, 0) + COALESCE(parts_cost, 0)) STORED,
    mechanic TEXT,
    photos TEXT[] DEFAULT '{}',
    next_service_date DATE,
    next_service_mileage INT,
    notes TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE maintenance_schedules (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE CASCADE,
    schedule_type TEXT NOT NULL CHECK (schedule_type IN ('mileage', 'time', 'both')),
    interval_km INT,
    interval_days INT,
    last_performed DATE,
    next_due DATE,
    description TEXT,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== TRIGGER: Auto-update motorcycles po INSERT na maintenance_log =====

CREATE OR REPLACE FUNCTION update_moto_after_service()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE motorcycles
    SET last_service_date = NEW.service_date,
        next_service_date = NEW.next_service_date,
        mileage = COALESCE(NEW.mileage_at_service, mileage)
    WHERE id = NEW.moto_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER maintenance_log_after_insert
    AFTER INSERT ON maintenance_log
    FOR EACH ROW EXECUTE FUNCTION update_moto_after_service();

-- ===== INDEXY =====

CREATE INDEX idx_maintenance_log_moto ON maintenance_log(moto_id);
CREATE INDEX idx_maintenance_log_date ON maintenance_log(service_date DESC);
CREATE INDEX idx_maintenance_log_type ON maintenance_log(service_type);
CREATE INDEX idx_maintenance_schedules_moto ON maintenance_schedules(moto_id);
CREATE INDEX idx_maintenance_schedules_next_due ON maintenance_schedules(next_due);
CREATE INDEX idx_maintenance_schedules_active ON maintenance_schedules(active) WHERE active = true;

-- ===== RLS =====

ALTER TABLE maintenance_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_schedules ENABLE ROW LEVEL SECURITY;

-- Admin-only (rozšíří 013)
CREATE POLICY "Authenticated can view maintenance log" ON maintenance_log
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view maintenance schedules" ON maintenance_schedules
    FOR SELECT USING (auth.uid() IS NOT NULL);

COMMENT ON TABLE maintenance_log IS 'Evidence servisních zásahů na motorkách';
COMMENT ON TABLE maintenance_schedules IS 'Plány pravidelné údržby — dle km nebo času';
