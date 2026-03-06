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
