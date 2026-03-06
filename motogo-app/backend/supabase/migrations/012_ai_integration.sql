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
