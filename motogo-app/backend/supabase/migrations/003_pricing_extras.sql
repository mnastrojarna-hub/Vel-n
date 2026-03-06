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
