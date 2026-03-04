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
            OR bookings.branch_id = ANY(branch_access)
        ))
    );

DROP POLICY IF EXISTS "Users can update own pending/active bookings" ON bookings;
CREATE POLICY "Users and admins can update bookings" ON bookings
    FOR UPDATE USING (
        (auth.uid() = user_id AND status IN ('pending', 'active'))
        OR EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND (
            role = 'superadmin'
            OR bookings.branch_id = ANY(branch_access)
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
                SELECT 1 FROM bookings WHERE bookings.id = documents.booking_id AND bookings.branch_id = ANY(
                    (SELECT branch_access FROM admin_users WHERE id = auth.uid())
                )
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
            OR motorcycles.branch_id = ANY(branch_access)
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
                SELECT 1 FROM bookings WHERE bookings.id = sos_incidents.booking_id AND bookings.branch_id = ANY(
                    (SELECT branch_access FROM admin_users WHERE id = auth.uid())
                )
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
            OR inventory.branch_id = ANY(branch_access)
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
            OR accounting_entries.branch_id = ANY(branch_access)
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
            OR cash_register.branch_id = ANY(branch_access)
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
            OR extras_catalog.branch_id = ANY(branch_access)
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
            OR daily_stats.branch_id = ANY(branch_access)
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
            OR branch_performance.branch_id = ANY(branch_access)
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
