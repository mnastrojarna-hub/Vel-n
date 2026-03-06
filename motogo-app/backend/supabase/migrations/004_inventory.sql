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
