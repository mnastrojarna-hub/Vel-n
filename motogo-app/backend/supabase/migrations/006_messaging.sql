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
