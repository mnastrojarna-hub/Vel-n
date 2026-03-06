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
