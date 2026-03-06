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
