-- MotoGo24: SOS / Incident systém
-- Zákazník hlásí nehody, krádeže, poruchy přímo z appky

CREATE TYPE sos_type AS ENUM (
    'accident_minor',       -- lehká nehoda, jedu dál
    'accident_major',       -- vážná nehoda, nepojízdná
    'theft',                -- krádež motorky
    'breakdown_minor',      -- drobná závada, jedu dál
    'breakdown_major',      -- nepojízdná porucha
    'location_share'        -- sdílení GPS polohy
);

CREATE TYPE sos_status AS ENUM (
    'reported',             -- nahlášeno z appky
    'acknowledged',         -- admin viděl
    'in_progress',          -- řeší se
    'resolved',             -- vyřešeno
    'closed'                -- uzavřeno
);

CREATE TABLE sos_incidents (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE SET NULL,
    type sos_type NOT NULL,
    status sos_status DEFAULT 'reported',
    latitude NUMERIC(10,7),
    longitude NUMERIC(10,7),
    description TEXT,
    is_customer_fault BOOLEAN,          -- true = zaviněná nehoda
    photos TEXT[] DEFAULT '{}',         -- URL fotek
    police_report_number TEXT,          -- číslo jednací PČR
    admin_notes TEXT,
    replacement_moto_id UUID REFERENCES motorcycles(id),
    tow_requested BOOLEAN DEFAULT false,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE sos_timeline (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    incident_id UUID REFERENCES sos_incidents(id) ON DELETE CASCADE,
    action TEXT NOT NULL,                -- 'reported','gps_shared','replacement_dispatched','tow_ordered','admin_note','resolved'
    performed_by UUID,
    data JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_sos_user ON sos_incidents(user_id);
CREATE INDEX idx_sos_status ON sos_incidents(status);
CREATE INDEX idx_sos_created ON sos_incidents(created_at DESC);
CREATE INDEX idx_sos_timeline_incident ON sos_timeline(incident_id);

ALTER TABLE sos_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_timeline ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own SOS incidents" ON sos_incidents
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users view own SOS timeline" ON sos_timeline
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM sos_incidents WHERE sos_incidents.id = sos_timeline.incident_id AND sos_incidents.user_id = auth.uid()
    ));

CREATE TRIGGER sos_incidents_updated_at BEFORE UPDATE ON sos_incidents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RPC: Vytvoření SOS incidentu
CREATE OR REPLACE FUNCTION create_sos_incident(
    p_type sos_type,
    p_booking_id UUID DEFAULT NULL,
    p_lat NUMERIC DEFAULT NULL,
    p_lng NUMERIC DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_is_fault BOOLEAN DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_moto_id UUID;
BEGIN
    IF p_booking_id IS NOT NULL THEN
        SELECT moto_id INTO v_moto_id FROM bookings WHERE id = p_booking_id AND user_id = auth.uid();
    END IF;

    INSERT INTO sos_incidents (user_id, booking_id, moto_id, type, latitude, longitude, description, is_customer_fault)
    VALUES (auth.uid(), p_booking_id, v_moto_id, p_type, p_lat, p_lng, p_description, p_is_fault)
    RETURNING id INTO v_id;

    INSERT INTO sos_timeline (incident_id, action, performed_by, data)
    VALUES (v_id, 'reported', auth.uid(), jsonb_build_object('type', p_type::TEXT, 'lat', p_lat, 'lng', p_lng));

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Sdílení GPS polohy na existující incident
CREATE OR REPLACE FUNCTION sos_share_location(
    p_incident_id UUID, p_lat NUMERIC, p_lng NUMERIC
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE sos_incidents SET latitude = p_lat, longitude = p_lng, updated_at = NOW()
    WHERE id = p_incident_id AND user_id = auth.uid();

    INSERT INTO sos_timeline (incident_id, action, performed_by, data)
    VALUES (p_incident_id, 'gps_shared', auth.uid(), jsonb_build_object('lat', p_lat, 'lng', p_lng));

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE sos_incidents IS 'SOS hlášení z mobilní app — nehody, krádeže, poruchy';
COMMENT ON TABLE sos_timeline IS 'Chronologický log událostí na SOS incidentu';
