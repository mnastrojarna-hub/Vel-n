-- MotoGo24: Analytics & Reporting
-- Denní statistiky, výkonnost motorek a poboček, predikce

CREATE TABLE daily_stats (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    date DATE NOT NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    total_bookings INT DEFAULT 0,
    revenue NUMERIC(12,2) DEFAULT 0,
    active_motos INT DEFAULT 0,
    utilization_pct NUMERIC(5,2) DEFAULT 0,
    new_customers INT DEFAULT 0,
    sos_incidents INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_daily_stats_date_branch UNIQUE (date, branch_id)
);

CREATE TABLE moto_performance (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE CASCADE,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    revenue NUMERIC(12,2) DEFAULT 0,
    bookings_count INT DEFAULT 0,
    utilization_pct NUMERIC(5,2) DEFAULT 0,
    avg_daily_price NUMERIC(10,2) DEFAULT 0,
    maintenance_cost NUMERIC(10,2) DEFAULT 0,
    profit NUMERIC(12,2) DEFAULT 0,
    roi NUMERIC(5,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE branch_performance (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    branch_id UUID REFERENCES branches(id) ON DELETE CASCADE,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    revenue NUMERIC(12,2) DEFAULT 0,
    costs NUMERIC(12,2) DEFAULT 0,
    profit NUMERIC(12,2) DEFAULT 0,
    avg_utilization NUMERIC(5,2) DEFAULT 0,
    customer_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE predictions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('demand', 'revenue', 'maintenance', 'stock')),
    target_period_start DATE NOT NULL,
    target_period_end DATE NOT NULL,
    data JSONB NOT NULL,
    confidence_pct NUMERIC(5,2),
    model_version TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== FUNKCE =====

-- Snapshot denních statistik (volá se cron jobem)
CREATE OR REPLACE FUNCTION snapshot_daily_stats()
RETURNS VOID AS $$
DECLARE
    yesterday DATE := CURRENT_DATE - 1;
    branch RECORD;
BEGIN
    FOR branch IN SELECT id FROM branches LOOP
        INSERT INTO daily_stats (date, branch_id, total_bookings, revenue, active_motos, utilization_pct, new_customers, sos_incidents)
        VALUES (
            yesterday,
            branch.id,
            (SELECT COUNT(*) FROM bookings WHERE branch_id = branch.id AND start_date::DATE <= yesterday AND end_date::DATE >= yesterday AND status IN ('active', 'completed')),
            (SELECT COALESCE(SUM(total_price), 0) FROM bookings WHERE branch_id = branch.id AND start_date::DATE = yesterday AND payment_status = 'paid'),
            (SELECT COUNT(*) FROM motorcycles WHERE branch_id = branch.id AND status = 'active'),
            (SELECT ROUND(
                COUNT(DISTINCT b.moto_id)::NUMERIC /
                NULLIF((SELECT COUNT(*) FROM motorcycles WHERE branch_id = branch.id AND status = 'active'), 0) * 100, 2
            ) FROM bookings b WHERE b.branch_id = branch.id AND b.start_date::DATE <= yesterday AND b.end_date::DATE >= yesterday AND b.status IN ('active', 'completed')),
            (SELECT COUNT(*) FROM profiles WHERE created_at::DATE = yesterday AND preferred_branch = branch.id),
            (SELECT COUNT(*) FROM sos_incidents si JOIN bookings bk ON si.booking_id = bk.id WHERE bk.branch_id = branch.id AND si.created_at::DATE = yesterday)
        )
        ON CONFLICT (date, branch_id) DO UPDATE SET
            total_bookings = EXCLUDED.total_bookings,
            revenue = EXCLUDED.revenue,
            active_motos = EXCLUDED.active_motos,
            utilization_pct = EXCLUDED.utilization_pct,
            new_customers = EXCLUDED.new_customers,
            sos_incidents = EXCLUDED.sos_incidents;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Výpočet ROI motorky
CREATE OR REPLACE FUNCTION calculate_moto_roi(
    p_moto_id UUID,
    p_from DATE,
    p_to DATE
) RETURNS JSONB AS $$
DECLARE
    total_revenue NUMERIC;
    total_maintenance NUMERIC;
    total_bookings INT;
    total_days INT;
    booked_days INT;
    utilization NUMERIC;
    avg_price NUMERIC;
    profit NUMERIC;
    roi_val NUMERIC;
BEGIN
    total_days := (p_to - p_from) + 1;

    SELECT COALESCE(SUM(total_price), 0), COUNT(*)
    INTO total_revenue, total_bookings
    FROM bookings
    WHERE moto_id = p_moto_id
      AND start_date::DATE >= p_from AND end_date::DATE <= p_to
      AND status IN ('active', 'completed')
      AND payment_status = 'paid';

    SELECT COALESCE(SUM(total_cost), 0)
    INTO total_maintenance
    FROM maintenance_log
    WHERE moto_id = p_moto_id
      AND service_date >= p_from AND service_date <= p_to;

    SELECT COALESCE(SUM(LEAST(end_date::DATE, p_to) - GREATEST(start_date::DATE, p_from) + 1), 0)
    INTO booked_days
    FROM bookings
    WHERE moto_id = p_moto_id
      AND start_date::DATE <= p_to AND end_date::DATE >= p_from
      AND status IN ('active', 'completed');

    utilization := ROUND(booked_days::NUMERIC / NULLIF(total_days, 0) * 100, 2);
    avg_price := ROUND(total_revenue / NULLIF(booked_days, 0), 2);
    profit := total_revenue - total_maintenance;
    roi_val := ROUND(profit / NULLIF(total_maintenance, 0) * 100, 2);

    RETURN jsonb_build_object(
        'moto_id', p_moto_id,
        'period_from', p_from,
        'period_to', p_to,
        'revenue', total_revenue,
        'maintenance_cost', total_maintenance,
        'profit', profit,
        'bookings_count', total_bookings,
        'booked_days', booked_days,
        'total_days', total_days,
        'utilization_pct', utilization,
        'avg_daily_price', avg_price,
        'roi_pct', roi_val
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ===== INDEXY =====

CREATE INDEX idx_daily_stats_date ON daily_stats(date DESC);
CREATE INDEX idx_daily_stats_branch ON daily_stats(branch_id);
CREATE INDEX idx_moto_performance_moto ON moto_performance(moto_id);
CREATE INDEX idx_moto_performance_period ON moto_performance(period_start, period_end);
CREATE INDEX idx_branch_performance_branch ON branch_performance(branch_id);
CREATE INDEX idx_branch_performance_period ON branch_performance(period_start, period_end);
CREATE INDEX idx_predictions_type ON predictions(type);
CREATE INDEX idx_predictions_period ON predictions(target_period_start, target_period_end);

-- ===== RLS =====

ALTER TABLE daily_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE moto_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE branch_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;

-- Admin-only (rozšíří 013)
CREATE POLICY "Authenticated can view daily stats" ON daily_stats
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view moto performance" ON moto_performance
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view branch performance" ON branch_performance
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view predictions" ON predictions
    FOR SELECT USING (auth.uid() IS NOT NULL);

COMMENT ON TABLE daily_stats IS 'Denní statistiky — bookings, revenue, utilizace per pobočka';
COMMENT ON TABLE moto_performance IS 'Výkonnostní metriky motorek za období';
COMMENT ON TABLE branch_performance IS 'Výkonnostní metriky poboček za období';
COMMENT ON TABLE predictions IS 'AI predikce — poptávka, revenue, údržba, stock';
