-- ═══════════════════════════════════════════════════════════
-- MotoGo24 — KOMPLETNÍ DATABÁZE
-- Jedno copy-paste do Supabase SQL Editoru
-- Generováno automaticky z migrací 001-013 + seed
-- ═══════════════════════════════════════════════════════════

-- ====== 001: Base Schema ======
-- ===== MotoGo24 – Supabase Database Schema =====
-- Senior Backend Architecture for PostgreSQL (Supabase)
-- Run this in Supabase SQL Editor to create all tables, enums, RLS policies, functions.

-- ===== 1. EXTENSIONS =====
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ===== 2. CUSTOM ENUM TYPES =====
CREATE TYPE booking_status AS ENUM ('pending', 'active', 'completed', 'cancelled');
CREATE TYPE payment_status AS ENUM ('unpaid', 'paid', 'refunded', 'partial_refund');
CREATE TYPE moto_status AS ENUM ('active', 'maintenance', 'out_of_service');
CREATE TYPE document_type AS ENUM ('contract', 'protocol', 'invoice', 'license_photo', 'id_photo');
CREATE TYPE license_group AS ENUM ('A', 'A1', 'A2', 'AM', 'B');

-- ===== 3. TABLES =====

-- 3a. Branches (pobočky)
CREATE TABLE branches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    city TEXT NOT NULL,
    zip TEXT,
    coordinates POINT,
    phone TEXT,
    email TEXT,
    opening_hours JSONB DEFAULT '{"mo":"08:00-18:00","tu":"08:00-18:00","we":"08:00-18:00","th":"08:00-18:00","fr":"08:00-18:00","sa":"09:00-14:00","su":"closed"}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3b. Profiles (rozšíření auth.users)
CREATE TABLE profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    email TEXT,
    full_name TEXT,
    phone TEXT,
    license_group license_group[],
    date_of_birth DATE,
    street TEXT,
    city TEXT,
    zip TEXT,
    country TEXT DEFAULT 'CZ',
    gear_sizes JSONB DEFAULT '{}'::jsonb,
    reliability_score JSONB DEFAULT '{"late_returns":0,"accidents":0,"notes":""}'::jsonb,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3c. Motorcycles (motocykly)
CREATE TABLE motorcycles (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    model TEXT NOT NULL,
    vin TEXT UNIQUE,
    spz TEXT,
    category TEXT NOT NULL,
    license_required license_group DEFAULT 'A',
    power_kw INTEGER DEFAULT 0,
    engine_cc INTEGER DEFAULT 0,
    weight_kg INTEGER DEFAULT 0,
    seat_height_mm INTEGER DEFAULT 0,
    fuel_tank_l NUMERIC(4,1) DEFAULT 0,
    price_weekday NUMERIC(10,2) DEFAULT 0,
    price_weekend NUMERIC(10,2) DEFAULT 0,
    -- Day-of-week pricing (Po–Ne)
    price_mon NUMERIC(10,2),
    price_tue NUMERIC(10,2),
    price_wed NUMERIC(10,2),
    price_thu NUMERIC(10,2),
    price_fri NUMERIC(10,2),
    price_sat NUMERIC(10,2),
    price_sun NUMERIC(10,2),
    status moto_status DEFAULT 'active',
    mileage INTEGER DEFAULT 0,
    image_url TEXT,
    images TEXT[] DEFAULT '{}',
    features TEXT[] DEFAULT '{}',
    description TEXT,
    manual_url TEXT,
    last_service_date DATE,
    next_service_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3d. Bookings (rezervace) – hlavní transakční tabulka
CREATE TABLE bookings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE SET NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    actual_return_date TIMESTAMPTZ,
    pickup_time TIME DEFAULT '09:00',
    pickup_method TEXT DEFAULT 'store',
    pickup_address TEXT,
    return_method TEXT DEFAULT 'store',
    return_address TEXT,
    total_price NUMERIC(10,2) DEFAULT 0,
    extras_price NUMERIC(10,2) DEFAULT 0,
    delivery_fee NUMERIC(10,2) DEFAULT 0,
    discount_amount NUMERIC(10,2) DEFAULT 0,
    discount_code TEXT,
    status booking_status DEFAULT 'pending',
    payment_status payment_status DEFAULT 'unpaid',
    payment_method TEXT,
    contract_url TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    -- Constraint: prevent overlapping bookings for the same motorcycle
    CONSTRAINT valid_dates CHECK (end_date >= start_date)
);

-- 3e. Documents (dokumenty)
CREATE TABLE documents (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    type document_type NOT NULL,
    file_path TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3f. Reviews (recenze)
CREATE TABLE reviews (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE CASCADE,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== 4. INDEXES =====
CREATE INDEX idx_bookings_user ON bookings(user_id);
CREATE INDEX idx_bookings_moto ON bookings(moto_id);
CREATE INDEX idx_bookings_dates ON bookings(start_date, end_date);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_motorcycles_branch ON motorcycles(branch_id);
CREATE INDEX idx_motorcycles_status ON motorcycles(status);
CREATE INDEX idx_documents_booking ON documents(booking_id);
CREATE INDEX idx_reviews_moto ON reviews(moto_id);

-- ===== 5. FUNCTIONS =====

-- 5a. Auto-create profile on auth.users insert
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 5b. Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER motorcycles_updated_at BEFORE UPDATE ON motorcycles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER bookings_updated_at BEFORE UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 5c. Check motorcycle availability for a date range (RPC)
CREATE OR REPLACE FUNCTION check_moto_availability(
    p_moto_id UUID,
    p_start TIMESTAMPTZ,
    p_end TIMESTAMPTZ,
    p_exclude_booking_id UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    conflict_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO conflict_count
    FROM bookings
    WHERE moto_id = p_moto_id
      AND status IN ('pending', 'active')
      AND id IS DISTINCT FROM p_exclude_booking_id
      AND start_date < p_end
      AND end_date > p_start;
    RETURN conflict_count = 0;
END;
$$ LANGUAGE plpgsql STABLE;

-- 5d. Get available motorcycles for a date range (RPC)
CREATE OR REPLACE FUNCTION get_available_motos(
    p_start TIMESTAMPTZ,
    p_end TIMESTAMPTZ,
    p_category TEXT DEFAULT NULL,
    p_license license_group DEFAULT NULL,
    p_branch_id UUID DEFAULT NULL
)
RETURNS SETOF motorcycles AS $$
BEGIN
    RETURN QUERY
    SELECT m.*
    FROM motorcycles m
    WHERE m.status = 'active'
      AND (p_category IS NULL OR m.category = p_category)
      AND (p_license IS NULL OR m.license_required = p_license)
      AND (p_branch_id IS NULL OR m.branch_id = p_branch_id)
      AND NOT EXISTS (
          SELECT 1 FROM bookings b
          WHERE b.moto_id = m.id
            AND b.status IN ('pending', 'active')
            AND b.start_date < p_end
            AND b.end_date > p_start
      );
END;
$$ LANGUAGE plpgsql STABLE;

-- 5e. Calculate booking price using day-of-week pricing (RPC)
CREATE OR REPLACE FUNCTION calc_booking_price(
    p_moto_id UUID,
    p_start DATE,
    p_end DATE
)
RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC := 0;
    current_date_ DATE := p_start;
    dow INTEGER;
    day_price NUMERIC;
    moto RECORD;
BEGIN
    SELECT * INTO moto FROM motorcycles WHERE id = p_moto_id;
    IF NOT FOUND THEN RETURN 0; END IF;

    WHILE current_date_ <= p_end LOOP
        dow := EXTRACT(DOW FROM current_date_); -- 0=Sun,1=Mon,...,6=Sat
        day_price := CASE dow
            WHEN 1 THEN COALESCE(moto.price_mon, moto.price_weekday)
            WHEN 2 THEN COALESCE(moto.price_tue, moto.price_weekday)
            WHEN 3 THEN COALESCE(moto.price_wed, moto.price_weekday)
            WHEN 4 THEN COALESCE(moto.price_thu, moto.price_weekday)
            WHEN 5 THEN COALESCE(moto.price_fri, moto.price_weekend)
            WHEN 6 THEN COALESCE(moto.price_sat, moto.price_weekend)
            WHEN 0 THEN COALESCE(moto.price_sun, moto.price_weekend)
            ELSE moto.price_weekday
        END;
        total := total + day_price;
        current_date_ := current_date_ + INTERVAL '1 day';
    END LOOP;

    RETURN total;
END;
$$ LANGUAGE plpgsql STABLE;

-- 5f. Extend booking (RPC) – validates availability for new period
CREATE OR REPLACE FUNCTION extend_booking(
    p_booking_id UUID,
    p_new_end_date TIMESTAMPTZ
)
RETURNS JSONB AS $$
DECLARE
    booking RECORD;
    is_available BOOLEAN;
    extra_price NUMERIC;
BEGIN
    SELECT * INTO booking FROM bookings WHERE id = p_booking_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
    END IF;
    IF booking.status NOT IN ('pending', 'active') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Booking cannot be modified');
    END IF;
    IF p_new_end_date <= booking.end_date THEN
        RETURN jsonb_build_object('success', false, 'error', 'New end date must be after current end date');
    END IF;

    -- Check availability for the extended period
    is_available := check_moto_availability(
        booking.moto_id,
        booking.end_date,
        p_new_end_date,
        p_booking_id
    );
    IF NOT is_available THEN
        RETURN jsonb_build_object('success', false, 'error', 'Motorcycle not available for extended period');
    END IF;

    -- Calculate extra price
    extra_price := calc_booking_price(
        booking.moto_id,
        (booking.end_date + INTERVAL '1 day')::DATE,
        p_new_end_date::DATE
    );

    -- Update booking
    UPDATE bookings
    SET end_date = p_new_end_date,
        total_price = total_price + extra_price
    WHERE id = p_booking_id;

    RETURN jsonb_build_object(
        'success', true,
        'extra_price', extra_price,
        'new_end_date', p_new_end_date,
        'new_total', booking.total_price + extra_price
    );
END;
$$ LANGUAGE plpgsql;

-- ===== 6. ROW LEVEL SECURITY (RLS) =====

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE motorcycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read/update only their own profile
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

-- Bookings: users see only their own bookings, authenticated users can create
CREATE POLICY "Users can view own bookings"
    ON bookings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Authenticated users can create bookings"
    ON bookings FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own pending/active bookings"
    ON bookings FOR UPDATE
    USING (auth.uid() = user_id AND status IN ('pending', 'active'));

-- Documents: users see only their own documents
CREATE POLICY "Users can view own documents"
    ON documents FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can upload own documents"
    ON documents FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Reviews: users can view all, create own
CREATE POLICY "Anyone can view reviews"
    ON reviews FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create reviews"
    ON reviews FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Motorcycles: everyone can read
CREATE POLICY "Anyone can view motorcycles"
    ON motorcycles FOR SELECT
    USING (true);

-- Branches: everyone can read
CREATE POLICY "Anyone can view branches"
    ON branches FOR SELECT
    USING (true);

-- ===== 7. STORAGE BUCKET =====
-- Run in Supabase Dashboard > Storage or via API:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('documents', 'documents', false);
-- Path convention: {user_id}/{booking_id}/{document_type}.pdf

-- ====== 002: SOS System ======
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

-- ====== 003: Pricing & Extras ======
-- MotoGo24: Pricing rules, extras, push tokens + ALTER TABLE rozšíření
-- Sezónní, promo, long-term, early-bird cenotvorba + příslušenství k pronájmu

-- ===== TABULKY =====

CREATE TABLE pricing_rules (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    moto_id UUID REFERENCES motorcycles(id) ON DELETE CASCADE,  -- NULL = platí pro všechny
    type TEXT NOT NULL CHECK (type IN ('seasonal', 'promo', 'long_term', 'early_bird')),
    name TEXT NOT NULL,
    modifier NUMERIC(5,2) NOT NULL,         -- multiplikátor: 1.15 = +15%, 0.90 = -10%
    valid_from DATE,
    valid_to DATE,
    min_days INT,                           -- minimální délka pronájmu pro aplikaci pravidla
    promo_code TEXT,                        -- promo kód (jen pro type='promo')
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE extras_catalog (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('ochranné', 'zavazadla', 'navigace')),
    price_per_day NUMERIC(10,2) NOT NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    available INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE booking_extras (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
    extra_id UUID REFERENCES extras_catalog(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    quantity INT DEFAULT 1,
    unit_price NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE push_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== ALTER TABLE rozšíření =====

ALTER TABLE motorcycles
    ADD COLUMN IF NOT EXISTS year INT,
    ADD COLUMN IF NOT EXISTS color TEXT,
    ADD COLUMN IF NOT EXISTS deposit_amount NUMERIC(10,2) DEFAULT 5000,
    ADD COLUMN IF NOT EXISTS insurance_price NUMERIC(10,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS min_rental_days INT DEFAULT 1,
    ADD COLUMN IF NOT EXISTS max_rental_days INT DEFAULT 30;

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS emergency_contact TEXT,
    ADD COLUMN IF NOT EXISTS emergency_phone TEXT,
    ADD COLUMN IF NOT EXISTS riding_experience TEXT CHECK (riding_experience IN ('beginner', 'intermediate', 'advanced', 'expert')),
    ADD COLUMN IF NOT EXISTS preferred_branch UUID REFERENCES branches(id),
    ADD COLUMN IF NOT EXISTS marketing_consent BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS language TEXT DEFAULT 'cs';

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS insurance_type TEXT DEFAULT 'basic',
    ADD COLUMN IF NOT EXISTS signed_contract BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS mileage_start INT,
    ADD COLUMN IF NOT EXISTS mileage_end INT,
    ADD COLUMN IF NOT EXISTS damage_report TEXT,
    ADD COLUMN IF NOT EXISTS promo_code TEXT;

-- ===== FUNKCE =====

-- Rozšířený výpočet ceny s pricing_rules
CREATE OR REPLACE FUNCTION calc_booking_price_v2(
    p_moto_id UUID,
    p_start DATE,
    p_end DATE,
    p_promo TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    base_price NUMERIC := 0;
    current_day DATE := p_start;
    dow INTEGER;
    day_price NUMERIC;
    moto RECORD;
    num_days INT;
    seasonal_mod NUMERIC := 1.0;
    promo_mod NUMERIC := 1.0;
    long_term_mod NUMERIC := 1.0;
    rule RECORD;
    total_price NUMERIC;
    deposit NUMERIC;
BEGIN
    SELECT * INTO moto FROM motorcycles WHERE id = p_moto_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Motorcycle not found');
    END IF;

    num_days := (p_end - p_start) + 1;
    deposit := COALESCE(moto.deposit_amount, 5000);

    -- Výpočet základní ceny po dnech
    WHILE current_day <= p_end LOOP
        dow := EXTRACT(DOW FROM current_day);
        day_price := CASE dow
            WHEN 1 THEN COALESCE(moto.price_mon, moto.price_weekday)
            WHEN 2 THEN COALESCE(moto.price_tue, moto.price_weekday)
            WHEN 3 THEN COALESCE(moto.price_wed, moto.price_weekday)
            WHEN 4 THEN COALESCE(moto.price_thu, moto.price_weekday)
            WHEN 5 THEN COALESCE(moto.price_fri, moto.price_weekend)
            WHEN 6 THEN COALESCE(moto.price_sat, moto.price_weekend)
            WHEN 0 THEN COALESCE(moto.price_sun, moto.price_weekend)
            ELSE moto.price_weekday
        END;
        base_price := base_price + day_price;
        current_day := current_day + INTERVAL '1 day';
    END LOOP;

    -- Sezónní modifier
    FOR rule IN
        SELECT * FROM pricing_rules
        WHERE type = 'seasonal' AND active = true
          AND (moto_id IS NULL OR moto_id = p_moto_id)
          AND p_start >= valid_from AND p_end <= valid_to
    LOOP
        seasonal_mod := rule.modifier;
    END LOOP;

    -- Long-term modifier
    FOR rule IN
        SELECT * FROM pricing_rules
        WHERE type = 'long_term' AND active = true
          AND (moto_id IS NULL OR moto_id = p_moto_id)
          AND (min_days IS NULL OR num_days >= min_days)
        ORDER BY min_days DESC NULLS LAST
        LIMIT 1
    LOOP
        long_term_mod := rule.modifier;
    END LOOP;

    -- Promo kód modifier
    IF p_promo IS NOT NULL THEN
        FOR rule IN
            SELECT * FROM pricing_rules
            WHERE type = 'promo' AND active = true
              AND promo_code = p_promo
              AND (moto_id IS NULL OR moto_id = p_moto_id)
              AND (valid_from IS NULL OR CURRENT_DATE >= valid_from)
              AND (valid_to IS NULL OR CURRENT_DATE <= valid_to)
            LIMIT 1
        LOOP
            promo_mod := rule.modifier;
        END LOOP;
    END IF;

    total_price := ROUND(base_price * seasonal_mod * long_term_mod * promo_mod, 2);

    RETURN jsonb_build_object(
        'base_price', base_price,
        'total_price', total_price,
        'num_days', num_days,
        'seasonal_mod', seasonal_mod,
        'promo_mod', promo_mod,
        'long_term_mod', long_term_mod,
        'deposit', deposit,
        'currency', 'CZK'
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ===== INDEXY =====

CREATE INDEX idx_pricing_rules_type ON pricing_rules(type);
CREATE INDEX idx_pricing_rules_moto ON pricing_rules(moto_id);
CREATE INDEX idx_pricing_rules_active ON pricing_rules(active) WHERE active = true;
CREATE INDEX idx_extras_catalog_branch ON extras_catalog(branch_id);
CREATE INDEX idx_extras_catalog_category ON extras_catalog(category);
CREATE INDEX idx_booking_extras_booking ON booking_extras(booking_id);
CREATE INDEX idx_push_tokens_user ON push_tokens(user_id);
CREATE INDEX idx_push_tokens_active ON push_tokens(active) WHERE active = true;

-- ===== RLS =====

ALTER TABLE pricing_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE extras_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_extras ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

-- Pricing rules: veřejné čtení
CREATE POLICY "Anyone can view pricing rules" ON pricing_rules
    FOR SELECT USING (true);

-- Extras catalog: veřejné čtení
CREATE POLICY "Anyone can view extras catalog" ON extras_catalog
    FOR SELECT USING (true);

-- Booking extras: uživatel vidí své
CREATE POLICY "Users can view own booking extras" ON booking_extras
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM bookings WHERE bookings.id = booking_extras.booking_id AND bookings.user_id = auth.uid()
    ));

CREATE POLICY "Users can create own booking extras" ON booking_extras
    FOR INSERT WITH CHECK (EXISTS (
        SELECT 1 FROM bookings WHERE bookings.id = booking_extras.booking_id AND bookings.user_id = auth.uid()
    ));

-- Push tokens: uživatel spravuje své
CREATE POLICY "Users manage own push tokens" ON push_tokens
    FOR ALL USING (auth.uid() = user_id);

COMMENT ON TABLE pricing_rules IS 'Cenová pravidla — sezónní, promo, long-term, early-bird modifikátory';
COMMENT ON TABLE extras_catalog IS 'Katalog příslušenství k pronájmu (helmy, kufry, navigace)';
COMMENT ON TABLE booking_extras IS 'Extras přiřazené ke konkrétní rezervaci';
COMMENT ON TABLE push_tokens IS 'Push notification tokeny pro mobilní a webové klienty';

-- ====== 004: Inventory ======
-- MotoGo24: Inventory & Suppliers
-- Správa skladových zásob, dodavatelé, objednávky

CREATE TABLE suppliers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    contact_person TEXT,
    email TEXT,
    phone TEXT,
    address TEXT,
    ico TEXT,
    dic TEXT,
    payment_terms INT DEFAULT 14,
    bank_account TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE inventory (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    sku TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('ochranné', 'spotřební', 'náhradní_díly')),
    unit TEXT DEFAULT 'ks',
    stock INT DEFAULT 0,
    min_stock INT,
    max_stock INT,
    unit_price NUMERIC(10,2),
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    location TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE inventory_movements (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    inventory_id UUID REFERENCES inventory(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('in', 'out', 'adjustment', 'transfer')),
    quantity INT NOT NULL,
    reason TEXT,
    reference_type TEXT,
    reference_id UUID,
    from_branch UUID REFERENCES branches(id) ON DELETE SET NULL,
    to_branch UUID REFERENCES branches(id) ON DELETE SET NULL,
    performed_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE purchase_orders (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL CHECK (status IN ('draft', 'pending_approval', 'approved', 'ordered', 'received', 'cancelled')) DEFAULT 'draft',
    total_amount NUMERIC(12,2),
    approved_by UUID,
    notes TEXT,
    ordered_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE purchase_order_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id UUID REFERENCES purchase_orders(id) ON DELETE CASCADE,
    inventory_id UUID REFERENCES inventory(id) ON DELETE SET NULL,
    quantity INT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== INDEXY =====

CREATE INDEX idx_inventory_branch ON inventory(branch_id);
CREATE INDEX idx_inventory_sku ON inventory(sku);
CREATE INDEX idx_inventory_category ON inventory(category);
CREATE INDEX idx_inventory_supplier ON inventory(supplier_id);
CREATE INDEX idx_inventory_movements_inventory ON inventory_movements(inventory_id);
CREATE INDEX idx_inventory_movements_type ON inventory_movements(type);
CREATE INDEX idx_inventory_movements_created ON inventory_movements(created_at DESC);
CREATE INDEX idx_purchase_orders_supplier ON purchase_orders(supplier_id);
CREATE INDEX idx_purchase_orders_status ON purchase_orders(status);
CREATE INDEX idx_purchase_order_items_order ON purchase_order_items(order_id);

-- ===== TRIGGERY =====

CREATE TRIGGER inventory_updated_at BEFORE UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER purchase_orders_updated_at BEFORE UPDATE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ===== RLS =====

ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;

-- Admin-only policies (budou rozšířeny v 013_admin_roles.sql)
CREATE POLICY "Authenticated can view suppliers" ON suppliers
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view inventory" ON inventory
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view inventory movements" ON inventory_movements
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view purchase orders" ON purchase_orders
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view purchase order items" ON purchase_order_items
    FOR SELECT USING (auth.uid() IS NOT NULL);

COMMENT ON TABLE suppliers IS 'Dodavatelé náhradních dílů a spotřebního materiálu';
COMMENT ON TABLE inventory IS 'Skladové zásoby — ochranné pomůcky, spotřební, náhradní díly';
COMMENT ON TABLE inventory_movements IS 'Pohyby na skladě — příjem, výdej, přesun, korekce';
COMMENT ON TABLE purchase_orders IS 'Nákupní objednávky na dodavatele';
COMMENT ON TABLE purchase_order_items IS 'Položky nákupní objednávky';

-- ====== 005: Maintenance ======
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

-- ====== 006: Messaging ======
-- MotoGo24: Messaging System
-- Omnichannel komunikace se zákazníky (web, email, WhatsApp, Instagram, Facebook, SMS)

CREATE TABLE message_threads (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    customer_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    channel TEXT NOT NULL CHECK (channel IN ('web', 'email', 'whatsapp', 'instagram', 'facebook', 'sms')),
    status TEXT NOT NULL CHECK (status IN ('open', 'waiting', 'resolved', 'closed')) DEFAULT 'open',
    assigned_admin UUID,
    subject TEXT,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    thread_id UUID REFERENCES message_threads(id) ON DELETE CASCADE,
    direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    sender_name TEXT,
    content TEXT NOT NULL,
    attachments TEXT[] DEFAULT '{}',
    read_at TIMESTAMPTZ,
    ai_suggested_reply TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE message_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT,
    variables TEXT[] DEFAULT '{}',
    language TEXT DEFAULT 'cs',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== INDEXY =====

CREATE INDEX idx_message_threads_customer ON message_threads(customer_id);
CREATE INDEX idx_message_threads_status ON message_threads(status);
CREATE INDEX idx_message_threads_channel ON message_threads(channel);
CREATE INDEX idx_message_threads_assigned ON message_threads(assigned_admin);
CREATE INDEX idx_message_threads_last_msg ON message_threads(last_message_at DESC);
CREATE INDEX idx_messages_thread ON messages(thread_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);
CREATE INDEX idx_messages_unread ON messages(read_at) WHERE read_at IS NULL;

-- ===== RLS =====

ALTER TABLE message_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_templates ENABLE ROW LEVEL SECURITY;

-- Zákazník vidí své thready
CREATE POLICY "Users can view own message threads" ON message_threads
    FOR SELECT USING (auth.uid() = customer_id);

CREATE POLICY "Users can create message threads" ON message_threads
    FOR INSERT WITH CHECK (auth.uid() = customer_id);

-- Zákazník vidí zprávy ve svých threadech
CREATE POLICY "Users can view own messages" ON messages
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM message_threads
        WHERE message_threads.id = messages.thread_id AND message_threads.customer_id = auth.uid()
    ));

CREATE POLICY "Users can send messages" ON messages
    FOR INSERT WITH CHECK (EXISTS (
        SELECT 1 FROM message_threads
        WHERE message_threads.id = messages.thread_id AND message_threads.customer_id = auth.uid()
    ));

-- Šablony: veřejné čtení
CREATE POLICY "Anyone can view message templates" ON message_templates
    FOR SELECT USING (true);

COMMENT ON TABLE message_threads IS 'Vlákna konverzací se zákazníky — omnichannel (web, email, WhatsApp, IG, FB, SMS)';
COMMENT ON TABLE messages IS 'Jednotlivé zprávy v konverzačním vláknu';
COMMENT ON TABLE message_templates IS 'Šablony odpovědí pro rychlou komunikaci';

-- ====== 007: Accounting ======
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

-- ====== 008: Documents & Templates ======
-- MotoGo24: Documents & Templates
-- Šablony smluv, protokolů, faktur + generované dokumenty

CREATE TABLE document_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('smlouva', 'faktura', 'protokol', 'vop', 'dobropis', 'gdpr', 'pojistka')),
    name TEXT NOT NULL,
    html_content TEXT NOT NULL,
    variables JSONB DEFAULT '[]',
    version INT DEFAULT 1,
    status TEXT NOT NULL CHECK (status IN ('active', 'draft', 'archived')) DEFAULT 'draft',
    updated_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE generated_documents (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    template_id UUID REFERENCES document_templates(id) ON DELETE SET NULL,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    customer_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    filled_data JSONB,
    pdf_path TEXT,
    generated_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== TRIGGERY =====

CREATE TRIGGER document_templates_updated_at BEFORE UPDATE ON document_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ===== INDEXY =====

CREATE INDEX idx_document_templates_type ON document_templates(type);
CREATE INDEX idx_document_templates_status ON document_templates(status);
CREATE INDEX idx_generated_documents_template ON generated_documents(template_id);
CREATE INDEX idx_generated_documents_booking ON generated_documents(booking_id);
CREATE INDEX idx_generated_documents_customer ON generated_documents(customer_id);
CREATE INDEX idx_generated_documents_created ON generated_documents(created_at DESC);

-- ===== RLS =====

ALTER TABLE document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;

-- Šablony: veřejné čtení aktivních
CREATE POLICY "Anyone can view active document templates" ON document_templates
    FOR SELECT USING (status = 'active');

-- Generované dokumenty: zákazník vidí své
CREATE POLICY "Users can view own generated documents" ON generated_documents
    FOR SELECT USING (auth.uid() = customer_id);

COMMENT ON TABLE document_templates IS 'Šablony dokumentů — smlouvy, faktury, protokoly, VOP, GDPR';
COMMENT ON TABLE generated_documents IS 'Vygenerované dokumenty z šablon pro konkrétní rezervace';

-- ====== 009: CMS ======
-- MotoGo24: CMS — Content Management System
-- Proměnné, stránky, promo kódy, feature flags

CREATE TABLE cms_variables (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value JSONB NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('pricing', 'content', 'features', 'seo', 'promo')),
    description TEXT,
    updated_by UUID,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE cms_pages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    content TEXT,
    meta_description TEXT,
    og_image TEXT,
    published BOOLEAN DEFAULT false,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE promo_codes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('percent', 'fixed')),
    value NUMERIC(10,2) NOT NULL,
    valid_from DATE,
    valid_to DATE,
    max_uses INT,
    used_count INT DEFAULT 0,
    min_order_amount NUMERIC(10,2),
    applicable_motos UUID[],
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE feature_flags (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    enabled BOOLEAN DEFAULT false,
    description TEXT,
    conditions JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== TRIGGERY =====

CREATE TRIGGER cms_pages_updated_at BEFORE UPDATE ON cms_pages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ===== INDEXY =====

CREATE INDEX idx_cms_variables_key ON cms_variables(key);
CREATE INDEX idx_cms_variables_category ON cms_variables(category);
CREATE INDEX idx_cms_pages_slug ON cms_pages(slug);
CREATE INDEX idx_cms_pages_published ON cms_pages(published) WHERE published = true;
CREATE INDEX idx_promo_codes_code ON promo_codes(code);
CREATE INDEX idx_promo_codes_active ON promo_codes(active) WHERE active = true;
CREATE INDEX idx_feature_flags_key ON feature_flags(key);

-- ===== RLS =====

ALTER TABLE cms_variables ENABLE ROW LEVEL SECURITY;
ALTER TABLE cms_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

-- CMS: veřejné čtení
CREATE POLICY "Anyone can view CMS variables" ON cms_variables
    FOR SELECT USING (true);

CREATE POLICY "Anyone can view published CMS pages" ON cms_pages
    FOR SELECT USING (published = true);

CREATE POLICY "Anyone can view active promo codes" ON promo_codes
    FOR SELECT USING (active = true);

CREATE POLICY "Anyone can view feature flags" ON feature_flags
    FOR SELECT USING (true);

COMMENT ON TABLE cms_variables IS 'CMS proměnné — ceny, obsah, featury, SEO, promo nastavení';
COMMENT ON TABLE cms_pages IS 'CMS stránky — statický obsah webu';
COMMENT ON TABLE promo_codes IS 'Promo kódy — procenta nebo fixní slevy';
COMMENT ON TABLE feature_flags IS 'Feature flags — zapínání/vypínání funkcí v aplikaci';

-- ====== 010: Analytics ======
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

-- ====== 011: Notifications ======
-- MotoGo24: Notifications & Automation
-- Notifikační pravidla, log odeslaných notifikací, automatizace

CREATE TABLE notification_rules (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('mileage', 'date', 'booking_status', 'stock_level', 'sos')),
    conditions JSONB NOT NULL DEFAULT '{}',
    actions JSONB NOT NULL DEFAULT '{}',
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE notification_log (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    rule_id UUID REFERENCES notification_rules(id) ON DELETE SET NULL,
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('admin', 'customer')),
    recipient_id UUID,
    channel TEXT NOT NULL CHECK (channel IN ('email', 'sms', 'push', 'webhook')),
    content TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('sent', 'failed', 'pending')) DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE automation_rules (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    event TEXT NOT NULL CHECK (event IN ('booking_created', 'booking_paid', 'booking_cancelled', 'sos_reported', 'stock_low', 'service_due')),
    conditions JSONB DEFAULT '{}',
    actions JSONB NOT NULL DEFAULT '{}',
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== INDEXY =====

CREATE INDEX idx_notification_rules_trigger ON notification_rules(trigger_type);
CREATE INDEX idx_notification_rules_enabled ON notification_rules(enabled) WHERE enabled = true;
CREATE INDEX idx_notification_log_rule ON notification_log(rule_id);
CREATE INDEX idx_notification_log_recipient ON notification_log(recipient_id);
CREATE INDEX idx_notification_log_status ON notification_log(status);
CREATE INDEX idx_notification_log_created ON notification_log(created_at DESC);
CREATE INDEX idx_automation_rules_event ON automation_rules(event);
CREATE INDEX idx_automation_rules_enabled ON automation_rules(enabled) WHERE enabled = true;

-- ===== RLS =====

ALTER TABLE notification_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_rules ENABLE ROW LEVEL SECURITY;

-- Admin-only (rozšíří 013)
CREATE POLICY "Authenticated can view notification rules" ON notification_rules
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view notification log" ON notification_log
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated can view automation rules" ON automation_rules
    FOR SELECT USING (auth.uid() IS NOT NULL);

COMMENT ON TABLE notification_rules IS 'Pravidla pro automatické notifikace — servis, stock, SOS';
COMMENT ON TABLE notification_log IS 'Log odeslaných notifikací — email, SMS, push, webhook';
COMMENT ON TABLE automation_rules IS 'Automatizační pravidla — akce na události v systému';

-- ====== 012: AI Integration ======
-- MotoGo24: AI Integration
-- Konverzace s AI asistentem, logy, akce spuštěné AI

CREATE TABLE ai_conversations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    admin_id UUID,
    messages JSONB DEFAULT '[]',
    context_page TEXT,
    model TEXT DEFAULT 'claude-sonnet-4-5-20250929',
    total_tokens INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ai_logs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    admin_id UUID,
    prompt TEXT NOT NULL,
    response TEXT,
    tokens_used INT DEFAULT 0,
    model TEXT,
    latency_ms INT,
    action_taken JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ai_actions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id UUID REFERENCES ai_conversations(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('create_booking', 'update_price', 'schedule_service', 'send_message', 'generate_report', 'block_moto', 'approve_order')),
    action_data JSONB NOT NULL DEFAULT '{}',
    status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'executed', 'rejected')) DEFAULT 'pending',
    approved_by UUID,
    executed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== TRIGGERY =====

CREATE TRIGGER ai_conversations_updated_at BEFORE UPDATE ON ai_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ===== INDEXY =====

CREATE INDEX idx_ai_conversations_admin ON ai_conversations(admin_id);
CREATE INDEX idx_ai_conversations_created ON ai_conversations(created_at DESC);
CREATE INDEX idx_ai_logs_admin ON ai_logs(admin_id);
CREATE INDEX idx_ai_logs_created ON ai_logs(created_at DESC);
CREATE INDEX idx_ai_actions_conversation ON ai_actions(conversation_id);
CREATE INDEX idx_ai_actions_status ON ai_actions(status);
CREATE INDEX idx_ai_actions_type ON ai_actions(action_type);

-- ===== RLS =====

ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_actions ENABLE ROW LEVEL SECURITY;

-- Admin vidí své konverzace
CREATE POLICY "Admins view own AI conversations" ON ai_conversations
    FOR SELECT USING (auth.uid() = admin_id);

CREATE POLICY "Admins create own AI conversations" ON ai_conversations
    FOR INSERT WITH CHECK (auth.uid() = admin_id);

CREATE POLICY "Admins update own AI conversations" ON ai_conversations
    FOR UPDATE USING (auth.uid() = admin_id);

CREATE POLICY "Admins view own AI logs" ON ai_logs
    FOR SELECT USING (auth.uid() = admin_id);

CREATE POLICY "Admins view own AI actions" ON ai_actions
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM ai_conversations WHERE ai_conversations.id = ai_actions.conversation_id AND ai_conversations.admin_id = auth.uid()
    ));

COMMENT ON TABLE ai_conversations IS 'Konverzace s AI asistentem v admin panelu';
COMMENT ON TABLE ai_logs IS 'Logy AI volání — prompt, response, tokeny, latence';
COMMENT ON TABLE ai_actions IS 'Akce navržené AI — booking, cena, servis, zpráva, report';

-- ====== 013: Admin Roles ======
-- MotoGo24: Admin Roles & Permissions
-- Role, audit log, admin RLS policy na VŠECHNY tabulky

CREATE TYPE admin_role AS ENUM ('superadmin', 'manager', 'operator', 'viewer');

CREATE TABLE admin_users (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    role admin_role DEFAULT 'viewer',
    branch_access UUID[] DEFAULT '{}',
    permissions JSONB DEFAULT '{}',
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE admin_audit_log (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    admin_id UUID,
    action TEXT NOT NULL,
    entity_type TEXT,
    entity_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== TRIGGERY =====

CREATE TRIGGER admin_users_updated_at BEFORE UPDATE ON admin_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ===== FUNKCE =====

CREATE OR REPLACE FUNCTION is_admin(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM admin_users WHERE id = p_user_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION check_admin_permission(p_user_id UUID, p_permission TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_role admin_role;
    v_perms JSONB;
BEGIN
    SELECT role, permissions INTO v_role, v_perms
    FROM admin_users WHERE id = p_user_id;

    IF NOT FOUND THEN RETURN false; END IF;
    IF v_role = 'superadmin' THEN RETURN true; END IF;
    IF v_role = 'manager' THEN RETURN true; END IF;

    RETURN COALESCE((v_perms->>p_permission)::BOOLEAN, false);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ===== INDEXY =====

CREATE INDEX idx_admin_users_role ON admin_users(role);
CREATE INDEX idx_admin_audit_log_admin ON admin_audit_log(admin_id);
CREATE INDEX idx_admin_audit_log_entity ON admin_audit_log(entity_type, entity_id);
CREATE INDEX idx_admin_audit_log_created ON admin_audit_log(created_at DESC);

-- ===== RLS na admin tabulky =====

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view admin users" ON admin_users
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users au WHERE au.id = auth.uid() AND au.role IN ('superadmin', 'manager'))
    );

CREATE POLICY "Admin can view own record" ON admin_users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Superadmin can manage admin users" ON admin_users
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users au WHERE au.id = auth.uid() AND au.role = 'superadmin')
    );

CREATE POLICY "Admins can view audit log" ON admin_audit_log
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users au WHERE au.id = auth.uid())
    );

-- ═══════════════════════════════════════════════════════════
-- ADMIN RLS POLICIES NA VŠECHNY EXISTUJÍCÍ TABULKY
-- Pattern: admin vidí data dle branch_access nebo superadmin vidí vše
-- ═══════════════════════════════════════════════════════════

-- ── BOOKINGS ──
DROP POLICY IF EXISTS "Users can view own bookings" ON bookings;
CREATE POLICY "Users and admins can view bookings" ON bookings
    FOR SELECT USING (
        auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR bookings.branch_id = ANY(admin_users.branch_access)
        ))
    );

DROP POLICY IF EXISTS "Users can update own pending/active bookings" ON bookings;
CREATE POLICY "Users and admins can update bookings" ON bookings
    FOR UPDATE USING (
        (auth.uid() = user_id AND status IN ('pending', 'active'))
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR bookings.branch_id = ANY(admin_users.branch_access)
        ))
    );

CREATE POLICY "Admins can insert bookings" ON bookings
    FOR INSERT WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

CREATE POLICY "Admins can delete bookings" ON bookings
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── PROFILES ──
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users and admins can view profiles" ON profiles
    FOR SELECT USING (
        auth.uid() = id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users and admins can update profiles" ON profiles
    FOR UPDATE USING (
        auth.uid() = id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── DOCUMENTS ──
DROP POLICY IF EXISTS "Users can view own documents" ON documents;
CREATE POLICY "Users and admins can view documents" ON documents
    FOR SELECT USING (
        auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR EXISTS (
                SELECT 1 FROM bookings b2 JOIN admin_users au ON au.id = auth.uid() WHERE b2.id = documents.booking_id AND b2.branch_id = ANY(au.branch_access)
            )
        ))
    );

DROP POLICY IF EXISTS "Users can upload own documents" ON documents;
CREATE POLICY "Users and admins can upload documents" ON documents
    FOR INSERT WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── REVIEWS ──
DROP POLICY IF EXISTS "Anyone can view reviews" ON reviews;
CREATE POLICY "Anyone and admins can view reviews" ON reviews
    FOR SELECT USING (true);

CREATE POLICY "Admins can manage reviews" ON reviews
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── MOTORCYCLES ──
DROP POLICY IF EXISTS "Anyone can view motorcycles" ON motorcycles;
CREATE POLICY "Anyone can view motorcycles with admin write" ON motorcycles
    FOR SELECT USING (true);

CREATE POLICY "Admins can manage motorcycles" ON motorcycles
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR motorcycles.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── BRANCHES ──
DROP POLICY IF EXISTS "Anyone can view branches" ON branches;
CREATE POLICY "Anyone can view branches with admin write" ON branches
    FOR SELECT USING (true);

CREATE POLICY "Admins can manage branches" ON branches
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role = 'superadmin')
    );

-- ── SOS_INCIDENTS ──
DROP POLICY IF EXISTS "Users manage own SOS incidents" ON sos_incidents;
CREATE POLICY "Users and admins can view SOS incidents" ON sos_incidents
    FOR ALL USING (
        auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR EXISTS (
                SELECT 1 FROM bookings b2 JOIN admin_users au ON au.id = auth.uid() WHERE b2.id = sos_incidents.booking_id AND b2.branch_id = ANY(au.branch_access)
            )
        ))
    );

-- ── SOS_TIMELINE ──
DROP POLICY IF EXISTS "Users view own SOS timeline" ON sos_timeline;
CREATE POLICY "Users and admins can view SOS timeline" ON sos_timeline
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM sos_incidents WHERE sos_incidents.id = sos_timeline.incident_id AND sos_incidents.user_id = auth.uid()
        )
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

CREATE POLICY "Admins can insert SOS timeline" ON sos_timeline
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── INVENTORY ──
DROP POLICY IF EXISTS "Authenticated can view inventory" ON inventory;
CREATE POLICY "Admins can manage inventory" ON inventory
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR inventory.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── INVENTORY_MOVEMENTS ──
DROP POLICY IF EXISTS "Authenticated can view inventory movements" ON inventory_movements;
CREATE POLICY "Admins can manage inventory movements" ON inventory_movements
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── PURCHASE_ORDERS ──
DROP POLICY IF EXISTS "Authenticated can view purchase orders" ON purchase_orders;
CREATE POLICY "Admins can manage purchase orders" ON purchase_orders
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager', 'operator'))
    );

-- ── PURCHASE_ORDER_ITEMS ──
DROP POLICY IF EXISTS "Authenticated can view purchase order items" ON purchase_order_items;
CREATE POLICY "Admins can manage purchase order items" ON purchase_order_items
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── MAINTENANCE_LOG ──
DROP POLICY IF EXISTS "Authenticated can view maintenance log" ON maintenance_log;
CREATE POLICY "Admins can manage maintenance log" ON maintenance_log
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── MAINTENANCE_SCHEDULES ──
DROP POLICY IF EXISTS "Authenticated can view maintenance schedules" ON maintenance_schedules;
CREATE POLICY "Admins can manage maintenance schedules" ON maintenance_schedules
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── MESSAGE_THREADS ──
DROP POLICY IF EXISTS "Users can view own message threads" ON message_threads;
CREATE POLICY "Users and admins can view message threads" ON message_threads
    FOR SELECT USING (
        auth.uid() = customer_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

CREATE POLICY "Admins can manage message threads" ON message_threads
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── MESSAGES ──
DROP POLICY IF EXISTS "Users can view own messages" ON messages;
DROP POLICY IF EXISTS "Users can send messages" ON messages;
CREATE POLICY "Users and admins can view messages" ON messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM message_threads WHERE message_threads.id = messages.thread_id AND message_threads.customer_id = auth.uid()
        )
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

CREATE POLICY "Users and admins can send messages" ON messages
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM message_threads WHERE message_threads.id = messages.thread_id AND message_threads.customer_id = auth.uid()
        )
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── ACCOUNTING_ENTRIES ──
DROP POLICY IF EXISTS "Authenticated can view accounting entries" ON accounting_entries;
CREATE POLICY "Admins can manage accounting entries" ON accounting_entries
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR accounting_entries.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── INVOICES ──
CREATE POLICY "Admins can manage invoices" ON invoices
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── TAX_RECORDS ──
DROP POLICY IF EXISTS "Authenticated can view tax records" ON tax_records;
CREATE POLICY "Admins can manage tax records" ON tax_records
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── CASH_REGISTER ──
DROP POLICY IF EXISTS "Authenticated can view cash register" ON cash_register;
CREATE POLICY "Admins can manage cash register" ON cash_register
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR cash_register.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── GENERATED_DOCUMENTS ──
DROP POLICY IF EXISTS "Users can view own generated documents" ON generated_documents;
CREATE POLICY "Users and admins can view generated documents" ON generated_documents
    FOR SELECT USING (
        auth.uid() = customer_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

CREATE POLICY "Admins can manage generated documents" ON generated_documents
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── DOCUMENT_TEMPLATES ──
DROP POLICY IF EXISTS "Anyone can view active document templates" ON document_templates;
CREATE POLICY "Anyone can view active templates and admins all" ON document_templates
    FOR SELECT USING (
        status = 'active'
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

CREATE POLICY "Admins can manage document templates" ON document_templates
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── CMS_VARIABLES ──
CREATE POLICY "Admins can manage CMS variables" ON cms_variables
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── CMS_PAGES ──
CREATE POLICY "Admins can manage CMS pages" ON cms_pages
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── PROMO_CODES ──
CREATE POLICY "Admins can manage promo codes" ON promo_codes
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── FEATURE_FLAGS ──
CREATE POLICY "Admins can manage feature flags" ON feature_flags
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role = 'superadmin')
    );

-- ── NOTIFICATION_LOG ──
DROP POLICY IF EXISTS "Authenticated can view notification log" ON notification_log;
CREATE POLICY "Admins can manage notification log" ON notification_log
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── NOTIFICATION_RULES ──
DROP POLICY IF EXISTS "Authenticated can view notification rules" ON notification_rules;
CREATE POLICY "Admins can manage notification rules" ON notification_rules
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── AUTOMATION_RULES ──
DROP POLICY IF EXISTS "Authenticated can view automation rules" ON automation_rules;
CREATE POLICY "Admins can manage automation rules" ON automation_rules
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── AI_CONVERSATIONS ──
DROP POLICY IF EXISTS "Admins view own AI conversations" ON ai_conversations;
DROP POLICY IF EXISTS "Admins create own AI conversations" ON ai_conversations;
DROP POLICY IF EXISTS "Admins update own AI conversations" ON ai_conversations;
CREATE POLICY "Admins can manage AI conversations" ON ai_conversations
    FOR ALL USING (
        auth.uid() = admin_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role = 'superadmin')
    );

-- ── AI_LOGS ──
DROP POLICY IF EXISTS "Admins view own AI logs" ON ai_logs;
CREATE POLICY "Admins can view AI logs" ON ai_logs
    FOR SELECT USING (
        auth.uid() = admin_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role = 'superadmin')
    );

-- ── AI_ACTIONS ──
DROP POLICY IF EXISTS "Admins view own AI actions" ON ai_actions;
CREATE POLICY "Admins can manage AI actions" ON ai_actions
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── PRICING_RULES ──
CREATE POLICY "Admins can manage pricing rules" ON pricing_rules
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── EXTRAS_CATALOG ──
CREATE POLICY "Admins can manage extras catalog" ON extras_catalog
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR extras_catalog.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── BOOKING_EXTRAS ──
CREATE POLICY "Admins can manage booking extras" ON booking_extras
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── DAILY_STATS ──
DROP POLICY IF EXISTS "Authenticated can view daily stats" ON daily_stats;
CREATE POLICY "Admins can manage daily stats" ON daily_stats
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR daily_stats.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── MOTO_PERFORMANCE ──
DROP POLICY IF EXISTS "Authenticated can view moto performance" ON moto_performance;
CREATE POLICY "Admins can view moto performance" ON moto_performance
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ── BRANCH_PERFORMANCE ──
DROP POLICY IF EXISTS "Authenticated can view branch performance" ON branch_performance;
CREATE POLICY "Admins can view branch performance" ON branch_performance
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR branch_performance.branch_id = ANY(admin_users.branch_access)
        ))
    );

-- ── PREDICTIONS ──
DROP POLICY IF EXISTS "Authenticated can view predictions" ON predictions;
CREATE POLICY "Admins can view predictions" ON predictions
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager'))
    );

-- ── SUPPLIERS ──
DROP POLICY IF EXISTS "Authenticated can view suppliers" ON suppliers;
CREATE POLICY "Admins can manage suppliers" ON suppliers
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('superadmin', 'manager', 'operator'))
    );

COMMENT ON TABLE admin_users IS 'Admin uživatelé — role, oprávnění, přístup k pobočkám';
COMMENT ON TABLE admin_audit_log IS 'Audit log adminských akcí — kdo, co, kdy, odkud';

-- ====== SEED DATA ======
-- ═══════════════════════════════════════════════════════════
-- MotoGo24 — SEED DATA
-- Produkční seed s reálnými daty z motos.js + motos-extra.js
-- ═══════════════════════════════════════════════════════════

-- ===== 1. POBOČKY =====

INSERT INTO branches (id, name, address, city, zip, coordinates, phone, email) VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'MotoGo24 Mezná',
    'Mezná 9',
    'Mezná',
    '393 01',
    POINT(15.2245, 49.4314),
    '+420774256271',
    'mezna@motogo24.cz'
),
(
    '22222222-2222-2222-2222-222222222222',
    'MotoGo24 Brno',
    'Vídeňská 42',
    'Brno',
    '639 00',
    POINT(16.6068, 49.1951),
    '+420774256271',
    'brno@motogo24.cz'
);

-- ===== 2. MOTORKY (z motos.js + motos-extra.js) =====

INSERT INTO motorcycles (id, branch_id, model, category, license_required, power_kw, engine_cc, weight_kg, seat_height_mm, fuel_tank_l, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend, image_url, description, features, year, deposit_amount, status) VALUES
-- BMW R 1200 GS Adventure
(
    'a0000001-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'BMW R 1200 GS Adventure',
    'cestovni',
    'A',
    92, 1254, 268, 850, 30.0,
    4208, 3788, 3367, 3788, 4208, 4882, 4629,
    3788, 4629,
    'https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800&q=85&auto=format&fit=crop',
    'Legenda mezi adventure motorkami. Ideální pro dlouhé roadtripy po silnici i lehkém terénu. Boxer motor s charakteristickým zvukem, nádrž 30 L a prémiové vybavení z ní dělají perfektního společníka na každý výlet.',
    ARRAY['Cestovní enduro – prémiová třída','Dlouhé trasy, roadtripy, přejezdy','Jízda ve dvou (spolujezdec OK)','Silnice + lehký terén','Velcí jezdci 175–200 cm'],
    2023, 5000, 'active'
),
-- Jawa RVM 500 Adventure
(
    'a0000001-0000-0000-0000-000000000002',
    '11111111-1111-1111-1111-111111111111',
    'Jawa RVM 500 Adventure',
    'cestovni',
    'A2',
    35, 500, 195, 810, 18.0,
    1986, 1788, 1589, 1788, 1986, 2383, 2185,
    1788, 2185,
    'https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=800&q=85&auto=format&fit=crop',
    'Moderní česká legenda v kategorii A2. Výborný poměr ceny a kvality. Díky omezení na 35 kW vhodná pro A2 průkaz. Pohodlná i na delší výlety, přívětivá pro menší jezdce.',
    ARRAY['Cestovní enduro – kategorie A2','Pro začátečníky i pokročilé','Menší a střední jezdci','Silnice + lehký terén','Výborná cena/výkon'],
    2023, 5000, 'active'
),
-- Benelli TRK 702 X
(
    'a0000001-0000-0000-0000-000000000003',
    '11111111-1111-1111-1111-111111111111',
    'Benelli TRK 702 X',
    'cestovni',
    'A2',
    35, 702, 215, 830, 20.0,
    2951, 2725, 2422, 2725, 2892, 3541, 3331,
    2725, 3331,
    'https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&q=85&auto=format&fit=crop',
    'Italský charakter a moderní crossover design. TRK 702X je adventure motorka pro vyšší jezdce kategorie A2 se solidní výbavou. Vhodná na silnici i nezpevněné cesty.',
    ARRAY['Crossover adventure – A2 kategorie','Vyšší jezdci 175–195 cm','Delší cesty a výlety','Silnice i nezpevněno','Italský design'],
    2022, 5000, 'active'
),
-- CF MOTO 800 MT
(
    'a0000001-0000-0000-0000-000000000004',
    '11111111-1111-1111-1111-111111111111',
    'CF MOTO 800 MT',
    'cestovni',
    'A',
    67, 800, 221, 835, 18.5,
    3941, 3663, 3256, 3663, 3892, 4729, 4476,
    3663, 4476,
    'https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=800&q=85&auto=format&fit=crop',
    'Moderní adventure tourer s výkonným dvojválcem. Skvělá aerodynamika, velký nádrž a pohodlná ergonomie. Výborná volba pro dlouhé trasy i jízdu ve dvou.',
    ARRAY['Adventure tourer','Dlouhé roadtripy','Jízda ve dvou (spolujezdec OK)','Silnice + lehký terén','Výborný poměr cena/výkon'],
    2023, 5000, 'active'
),
-- Yamaha Niken GT
(
    'a0000001-0000-0000-0000-000000000005',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha Niken GT',
    'cestovni',
    'A',
    84, 847, 263, 820, 18.0,
    3931, 3538, 3144, 3538, 3931, 4717, 4252,
    3538, 4252,
    'photos/yamaha-niken_1.jpg',
    'Unikátní tříkolová motorka s předními dvěma koly pro maximální stabilitu. Niken GT je revoluční stroj pro dobrodruhy, kteří chtějí zažít něco zcela jiného. Výborná stabilita v zatáčkách, pohodlné GT vybavení.',
    ARRAY['Tříkolová – unikátní zážitek','Extrémní stabilita v zatáčkách','GT výbava – vyhřívání, TFT displej','Dlouhé trasy','Pro zkušené jezdce'],
    2021, 5000, 'active'
),
-- Yamaha XT 660 X
(
    'a0000001-0000-0000-0000-000000000006',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha XT 660 X',
    'supermoto',
    'A2',
    35, 659, 179, 895, 15.0,
    1986, 1788, 1589, 1788, 1986, 2383, 2185,
    1788, 2185,
    'photos/yamaha-xt660_1.jpg',
    'Legendární supermoto s jednoválcovým motorem. XT 660 X je ikonou mezi supermoto motorkami – lehká, agilní, perfektní pro město i silnici. Ideální pro jezdce A2 kategorie.',
    ARRAY['Supermoto – město i silnice','Lehká a agilní','Kategorie A2','Průjezd hustou zástavbou','Sportovní styl'],
    2018, 5000, 'active'
),
-- Kawasaki Z 900
(
    'a0000001-0000-0000-0000-000000000007',
    '11111111-1111-1111-1111-111111111111',
    'Kawasaki Z 900',
    'naked',
    'A',
    95, 948, 193, 795, 17.0,
    3514, 3163, 2811, 3163, 3514, 4217, 3865,
    3163, 3865,
    'photos/kawasaki-z900_1.jpg',
    'Čtyřválcový naked bike plný adrenalinu. Kawasaki Z 900 nabízí brutální výkon, ostrý design a moderní elektroniku. Perfektní volba pro jezdce, kteří chtějí výkon a styl v jednom.',
    ARRAY['Naked bike – sportovní jízda','Čtyřválcový motor – brutální výkon','Moderní elektronika','Styl a výkon','Pro zkušené jezdce'],
    2022, 5000, 'active'
),
-- Yamaha MT-09
(
    'a0000001-0000-0000-0000-000000000008',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha MT-09',
    'naked',
    'A',
    87, 847, 193, 820, 14.0,
    3097, 2788, 2478, 2788, 3097, 3717, 3407,
    2788, 3407,
    'photos/yamaha-mt09_1.jpg',
    'Trojválcový naked bike se zuřivým charakterem. Yamaha MT-09 je "Dark Side of Japan" – agresivní, zábavný a nepředvídatelný. Výborná volba pro jezdce, kteří chtějí maximální zábavu na silnici.',
    ARRAY['Naked bike – maximální zábava','Trojválcový motor – unikátní charakter','Agresivní výkon','Lehká a agilní','Dark Side of Japan'],
    2017, 5000, 'active'
),
-- Yamaha XTZ 1200 Super Ténéré
(
    'a0000001-0000-0000-0000-000000000009',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha XTZ 1200 Super Ténéré',
    'cestovni',
    'A',
    76, 1199, 261, 845, 23.0,
    4417, 3975, 3533, 3975, 4417, 5300, 4858,
    3975, 4858,
    'photos/yamaha-tenere_1.jpg',
    'Rallye legenda pro silnici. Yamaha Super Ténéré je inspirována vítězi Dakaru – výkonný dvojválec, obří nádrž a výborná ergonomie pro extrémně dlouhé trasy. Dokonalý cestovní partner.',
    ARRAY['Rallye adventure – inspirace Dakarem','Obrovský dojezd','Extrémně pohodlná','Jízda ve dvou','Silnice + terén'],
    2019, 5000, 'active'
),
-- Ducati Multistrada 1200 ABS
(
    'a0000001-0000-0000-0000-000000000010',
    '11111111-1111-1111-1111-111111111111',
    'Ducati Multistrada 1200 ABS',
    'cestovni',
    'A',
    104, 1198, 229, 820, 20.0,
    3486, 3138, 2789, 3138, 3486, 4183, 3835,
    3138, 3835,
    'photos/ducati-multistrada_1.jpg',
    'Italská vášeň v podobě adventure motorky. Ducati Multistrada 1200 nabízí brutální výkon L-twin motoru, prémiové elektronické systémy a charakteristický italský zvuk. Pro milovníky Ducati.',
    ARRAY['Italský L-twin – unikátní zvuk','Prémiová elektronika – 4 jízdní režimy','Silnice i terén','Jízda ve dvou','Pro zkušené jezdce'],
    2015, 5000, 'active'
),
-- KTM 1290 Super Adventure
(
    'a0000001-0000-0000-0000-000000000011',
    '11111111-1111-1111-1111-111111111111',
    'KTM 1290 Super Adventure',
    'cestovni',
    'A',
    118, 1301, 218, 850, 23.0,
    4625, 4163, 3700, 4163, 4625, 5550, 5088,
    4163, 5088,
    'photos/ktm-1290_1.jpg',
    'Ready to Race v adventure světě. KTM 1290 Super Adventure je nejextrémnější adventure motorka v naší flotile. Výkonný V-twin, prémiová WP elektronika a oranzové barvy KTM. Pro skutečné dobrodruhy.',
    ARRAY['Nejvýkonnější adventure v nabídce','V-twin 160 koní – extrémní výkon','WP elektronika – terén i silnice','Prémiové vybavení','Pouze pro zkušené'],
    2017, 5000, 'active'
),
-- Yamaha PW 50
(
    'a0000001-0000-0000-0000-000000000012',
    '11111111-1111-1111-1111-111111111111',
    'Yamaha PW 50',
    'detske',
    'A1',
    1, 49, 25, 485, 0,
    1333, 1200, 1067, 1200, 1333, 1600, 1467,
    1200, 1467,
    'photos/yamaha-pw50_1.jpg',
    'Malý pomocník pro velké začátky. Yamaha PW 50 je legendární dětská motorka pro první kroky v motosportu. Automatická převodovka, nízké sedlo a maximálních 50 ccm jsou ideální pro děti od 3 let.',
    ARRAY['Dětská motorka – od 3 let','Automatická převodovka','Nízké sedlo – 485 mm','Omezovač plynu pro rodiče','Legendární volba pro začátky'],
    2016, 2000, 'active'
),
-- KTM SX 65
(
    'a0000001-0000-0000-0000-000000000013',
    '11111111-1111-1111-1111-111111111111',
    'KTM SX 65',
    'detske',
    'A1',
    8, 65, 49, 670, 0,
    1000, 1000, 1000, 1000, 1200, 1200, 1200,
    1000, 1200,
    'photos/ktm-sx65_1.jpg',
    'Závodní motokros pro mladé piloty. KTM SX 65 je skutečná závodní motorka v malém provedení – pro děti 7–12 let. Výkonný dvoutaktní motor, závodní podvozek a oranžové KTM barvy.',
    ARRAY['Závodní motokros pro děti','Dvoutaktní motor – závodní výkon','Věk 7–12 let','Uzavřené tratě / areály','Výchozí bod závodní kariéry'],
    2020, 2000, 'active'
),
-- Triumph Tiger 1200 Explorer
(
    'a0000001-0000-0000-0000-000000000014',
    '11111111-1111-1111-1111-111111111111',
    'Triumph Tiger 1200 Explorer',
    'cestovni',
    'A',
    96, 1215, 259, 810, 20.0,
    4208, 3788, 3367, 3788, 4208, 5050, 4629,
    3788, 4629,
    'photos/triumph-tiger_1.jpg',
    'Britský elegán pro světové dobrodružství. Triumph Tiger 1200 Explorer je prémiová adventure motorka s trojválcovým motorem, bohatou výbavou a elegantním britským designem. Ideální pro dlouhé transcontinentální jízdy.',
    ARRAY['Britský trojválec – unikátní charakter','Prémiové GT vybavení','Transcontinentální cestování','Jízda ve dvou','Elegantní design'],
    2018, 5000, 'active'
);

-- ===== 3. EXTRAS KATALOG =====

INSERT INTO extras_catalog (id, name, category, price_per_day, branch_id, available) VALUES
('e0000001-0000-0000-0000-000000000001', 'Helma přilba L', 'ochranné', 150, '11111111-1111-1111-1111-111111111111', 5),
('e0000001-0000-0000-0000-000000000002', 'Helma přilba XL', 'ochranné', 150, '11111111-1111-1111-1111-111111111111', 5),
('e0000001-0000-0000-0000-000000000003', 'Bunda S', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000004', 'Bunda M', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000005', 'Bunda L', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000006', 'Bunda XL', 'ochranné', 100, '11111111-1111-1111-1111-111111111111', 3),
('e0000001-0000-0000-0000-000000000007', 'Rukavice', 'ochranné', 50, '11111111-1111-1111-1111-111111111111', 6),
('e0000001-0000-0000-0000-000000000008', 'Boční kufry pár', 'zavazadla', 200, '11111111-1111-1111-1111-111111111111', 4),
('e0000001-0000-0000-0000-000000000009', 'Top case', 'zavazadla', 100, '11111111-1111-1111-1111-111111111111', 4),
('e0000001-0000-0000-0000-000000000010', 'GPS navigace', 'navigace', 150, '11111111-1111-1111-1111-111111111111', 3),
-- Brno duplicity
('e0000001-0000-0000-0000-000000000011', 'Helma přilba L', 'ochranné', 150, '22222222-2222-2222-2222-222222222222', 3),
('e0000001-0000-0000-0000-000000000012', 'Helma přilba XL', 'ochranné', 150, '22222222-2222-2222-2222-222222222222', 3),
('e0000001-0000-0000-0000-000000000013', 'Bunda M', 'ochranné', 100, '22222222-2222-2222-2222-222222222222', 2),
('e0000001-0000-0000-0000-000000000014', 'Bunda L', 'ochranné', 100, '22222222-2222-2222-2222-222222222222', 2),
('e0000001-0000-0000-0000-000000000015', 'Rukavice', 'ochranné', 50, '22222222-2222-2222-2222-222222222222', 4),
('e0000001-0000-0000-0000-000000000016', 'GPS navigace', 'navigace', 150, '22222222-2222-2222-2222-222222222222', 2);

-- ===== 4. PRICING RULES =====

INSERT INTO pricing_rules (name, type, modifier, valid_from, valid_to, min_days, promo_code, active) VALUES
-- Sezóna duben–září: +15%
('Hlavní sezóna (duben–září)', 'seasonal', 1.15, '2026-04-01', '2026-09-30', NULL, NULL, true),
-- Long-term slevy
('7+ dní sleva 10%', 'long_term', 0.90, NULL, NULL, 7, NULL, true),
('14+ dní sleva 15%', 'long_term', 0.85, NULL, NULL, 14, NULL, true),
-- Promo kód
('PRVNIJIZDA – 20% sleva', 'promo', 0.80, '2026-01-01', '2026-12-31', NULL, 'PRVNIJIZDA', true);

-- ===== 5. PROMO KÓDY =====

INSERT INTO promo_codes (code, type, value, valid_from, valid_to, max_uses, active) VALUES
('PRVNIJIZDA', 'percent', 20, '2026-01-01', '2026-12-31', 100, true),
('MOTO10', 'percent', 10, '2026-01-01', '2026-12-31', 200, true),
('MOTO20', 'percent', 20, '2026-01-01', '2026-12-31', 50, true),
('JARO25', 'percent', 25, '2026-03-01', '2026-05-31', 30, true);

-- ===== 6. ADMIN SUPERADMIN =====

-- Insert admin user into auth.users (Supabase manages this, but we seed it)
-- NOTE: In production, create the user via Supabase Auth UI/API first,
-- then INSERT into admin_users only. This seed assumes the user already exists.

-- Vytvoření admina: admin@motogo24.cz
-- Heslo se nastavuje přes Supabase Auth, zde jen reference
DO $$
DECLARE
    v_admin_id UUID := 'ad000001-0000-0000-0000-000000000001';
BEGIN
    -- Pokus o INSERT do auth.users (funguje jen s service_role key)
    -- V produkci se admin vytváří přes Supabase Dashboard
    BEGIN
        INSERT INTO auth.users (
            id,
            instance_id,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            role,
            aud,
            created_at,
            updated_at
        ) VALUES (
            v_admin_id,
            '00000000-0000-0000-0000-000000000000',
            'admin@motogo24.cz',
            crypt('MotoGo24Admin!2026', gen_salt('bf')),
            NOW(),
            '{"provider": "email", "providers": ["email"]}'::jsonb,
            '{"full_name": "MotoGo24 Admin"}'::jsonb,
            'authenticated',
            'authenticated',
            NOW(),
            NOW()
        );
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'auth.users INSERT skipped (user may already exist or insufficient permissions)';
    END;

    -- Profil
    BEGIN
        INSERT INTO profiles (id, email, full_name, phone, language)
        VALUES (v_admin_id, 'admin@motogo24.cz', 'MotoGo24 Admin', '+420774256271', 'cs');
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'Profile already exists';
    END;

    -- Admin role
    INSERT INTO admin_users (id, role, branch_access, permissions)
    VALUES (
        v_admin_id,
        'superadmin',
        ARRAY['11111111-1111-1111-1111-111111111111'::UUID, '22222222-2222-2222-2222-222222222222'::UUID],
        '{"all": true}'::jsonb
    )
    ON CONFLICT (id) DO UPDATE SET role = 'superadmin', branch_access = EXCLUDED.branch_access;
END;
$$;

-- ===== 7. CMS VARIABLES =====

INSERT INTO cms_variables (key, value, category, description) VALUES
('company_name', '"MotoGo24 s.r.o."', 'content', 'Název firmy'),
('company_phone', '"+420774256271"', 'content', 'Hlavní telefon'),
('company_email', '"info@motogo24.cz"', 'content', 'Hlavní e-mail'),
('company_web', '"https://motogo24.cz"', 'content', 'Webová stránka'),
('default_deposit', '5000', 'pricing', 'Výchozí záloha v CZK'),
('season_start', '"2026-04-01"', 'pricing', 'Začátek hlavní sezóny'),
('season_end', '"2026-09-30"', 'pricing', 'Konec hlavní sezóny'),
('delivery_price_per_km', '15', 'pricing', 'Cena za km přistavení'),
('min_rental_days', '1', 'pricing', 'Minimální délka pronájmu'),
('max_rental_days', '30', 'pricing', 'Maximální délka pronájmu');

-- ===== 8. FEATURE FLAGS =====

INSERT INTO feature_flags (key, enabled, description) VALUES
('ai_assistant', true, 'AI asistent v admin panelu'),
('online_payments', true, 'Online platby (Stripe)'),
('document_scanner', true, 'Skenování dokladů v appce'),
('push_notifications', true, 'Push notifikace'),
('whatsapp_integration', false, 'WhatsApp integrace'),
('multi_language', true, 'Vícejazyčná podpora (CZ/EN/DE)'),
('sos_system', true, 'SOS systém pro zákazníky'),
('delivery_service', true, 'Přistavení motorky');

-- ===== 9. NOTIFICATION RULES =====

INSERT INTO notification_rules (name, trigger_type, conditions, actions, enabled) VALUES
('Servis za 500 km', 'mileage', '{"threshold_km": 500}', '{"notify": "admin", "channel": "email", "template": "service_due"}', true),
('Booking potvrzení', 'booking_status', '{"status": "active"}', '{"notify": "customer", "channel": "email", "template": "booking_confirmed"}', true),
('SOS alert', 'sos', '{"types": ["accident_major", "theft"]}', '{"notify": "admin", "channel": "sms", "template": "sos_alert", "phone": "+420774256271"}', true),
('Nízký sklad', 'stock_level', '{"below_min": true}', '{"notify": "admin", "channel": "email", "template": "low_stock"}', true);

-- ===== 10. DOCUMENT TEMPLATES =====

INSERT INTO document_templates (type, name, html_content, variables, version, status) VALUES
('smlouva', 'Nájemní smlouva – standard', '<h1>Nájemní smlouva</h1><p>Pronajímatel: {{company_name}}</p><p>Nájemce: {{customer_name}}</p><p>Předmět: {{moto_model}}</p><p>Období: {{start_date}} – {{end_date}}</p><p>Cena: {{total_price}} CZK</p>', '["company_name","customer_name","moto_model","start_date","end_date","total_price"]', 1, 'active'),
('protokol', 'Předávací protokol', '<h1>Předávací protokol</h1><p>Motorka: {{moto_model}}</p><p>Stav km: {{mileage}}</p><p>Stav paliva: {{fuel_level}}</p><p>Poznámky: {{notes}}</p>', '["moto_model","mileage","fuel_level","notes"]', 1, 'active'),
('vop', 'Všeobecné obchodní podmínky', '<h1>VOP MotoGo24</h1><p>Platné od 1.1.2026</p>', '[]', 1, 'active');
