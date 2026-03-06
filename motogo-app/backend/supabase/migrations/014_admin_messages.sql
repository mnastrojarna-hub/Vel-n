-- =====================================================
-- MotoGo24: Admin Messages (Zprávy z velínu / centrály)
-- Migration 014 – tabulka admin_messages + RLS + trigger
-- + funkce pro odesílání zpráv z admin panelu
-- + automatické odpovědi na SOS incidenty
-- =====================================================

-- ===== 1. TABULKA =====

CREATE TABLE admin_messages (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    incident_id UUID REFERENCES sos_incidents(id) ON DELETE SET NULL,
    booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
    type TEXT NOT NULL DEFAULT 'info'
        CHECK (type IN (
            'sos_response',         -- obecná odpověď na SOS
            'accident_response',    -- reakce na nahlášení nehody
            'replacement',          -- vezeme náhradní motorku
            'tow',                  -- volali jsme odtah
            'info',                 -- obecná informace
            'thanks'                -- poděkování za nahlášení
        )),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    read BOOLEAN DEFAULT false,
    sent_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ===== 2. INDEXY =====

CREATE INDEX idx_admin_messages_user ON admin_messages(user_id);
CREATE INDEX idx_admin_messages_user_unread ON admin_messages(user_id, read)
    WHERE read = false;
CREATE INDEX idx_admin_messages_incident ON admin_messages(incident_id)
    WHERE incident_id IS NOT NULL;
CREATE INDEX idx_admin_messages_created ON admin_messages(created_at DESC);

-- ===== 3. RLS (Row Level Security) =====

ALTER TABLE admin_messages ENABLE ROW LEVEL SECURITY;

-- Zákazník vidí a může označit jako přečtené POUZE své zprávy
CREATE POLICY "Users can view own admin messages" ON admin_messages
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can mark own messages as read" ON admin_messages
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Admin může vše (vkládat, číst, upravovat, mazat)
CREATE POLICY "Admins can manage all admin messages" ON admin_messages
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid())
    );

-- ===== 4. REALTIME – zapnout pro Supabase Realtime =====
-- (Nutné pro okamžité doručování notifikací do appky)

ALTER PUBLICATION supabase_realtime ADD TABLE admin_messages;

-- ===== 5. FUNKCE: Odeslání zprávy zákazníkovi z admin panelu =====

CREATE OR REPLACE FUNCTION send_admin_message(
    p_user_id UUID,
    p_title TEXT,
    p_message TEXT,
    p_type TEXT DEFAULT 'info',
    p_incident_id UUID DEFAULT NULL,
    p_booking_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_msg_id UUID;
BEGIN
    -- Ověř, že volající je admin
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid()) THEN
        RAISE EXCEPTION 'Přístup odepřen – pouze admin';
    END IF;

    INSERT INTO admin_messages (user_id, title, message, type, incident_id, booking_id, sent_by)
    VALUES (p_user_id, p_title, p_message, p_type, p_incident_id, p_booking_id, auth.uid())
    RETURNING id INTO v_msg_id;

    -- Zapiš do audit logu
    INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, new_data)
    VALUES (
        auth.uid(),
        'send_admin_message',
        'admin_messages',
        v_msg_id,
        jsonb_build_object(
            'user_id', p_user_id,
            'title', p_title,
            'type', p_type,
            'incident_id', p_incident_id
        )
    );

    RETURN v_msg_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== 6. FUNKCE: Automatická odpověď na SOS incident =====
-- Volá se z admin panelu nebo automaticky při změně stavu SOS

CREATE OR REPLACE FUNCTION auto_reply_sos(
    p_incident_id UUID,
    p_reply_type TEXT DEFAULT 'sos_response'
) RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_sos_type TEXT;
    v_title TEXT;
    v_message TEXT;
BEGIN
    -- Načti incident
    SELECT user_id, type::TEXT INTO v_user_id, v_sos_type
    FROM sos_incidents WHERE id = p_incident_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Incident nenalezen';
    END IF;

    -- Zvol text podle typu odpovědi
    CASE p_reply_type
        WHEN 'thanks' THEN
            CASE v_sos_type
                WHEN 'accident_minor' THEN
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Děkujeme za nahlášení drobné nehody. Šťastnou cestu! Pokud budete potřebovat cokoliv dalšího, neváhejte nás kontaktovat.';
                WHEN 'accident_major' THEN
                    v_title := 'Přijali jsme vaše hlášení';
                    v_message := 'Vaše hlášení vážné nehody bylo přijato. Náš tým se tím okamžitě zabývá. Zůstaňte v bezpečí a čekejte na další instrukce.';
                WHEN 'breakdown_minor' THEN
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Děkujeme za nahlášení poruchy. Šťastnou cestu! Závadu prověříme při nejbližším servisu.';
                WHEN 'breakdown_major' THEN
                    v_title := 'Přijali jsme vaše hlášení';
                    v_message := 'Vaše hlášení poruchy bylo přijato. Pracujeme na řešení. Prosím vyčkejte na místě.';
                WHEN 'theft' THEN
                    v_title := 'Hlášení krádeže přijato';
                    v_message := 'Vaše hlášení krádeže bylo přijato. Kontaktovali jsme Policii ČR. Prosím volejte také 158. Ozveme se co nejdříve.';
                ELSE
                    v_title := 'Děkujeme za nahlášení';
                    v_message := 'Vaše hlášení bylo přijato. Děkujeme a šťastnou cestu!';
            END CASE;
        WHEN 'replacement' THEN
            v_title := 'Vezeme vám náhradní motorku';
            v_message := 'Vydržte! Vezeme vám náhradní motorku. Budeme u vás co nejdříve. Sledujte prosím telefon pro další informace.';
        WHEN 'tow' THEN
            v_title := 'Odtahová služba na cestě';
            v_message := 'Zavolali jsme vám odtahovou službu. Prosím vyčkejte na místě. Řidič vás bude kontaktovat telefonicky.';
        ELSE
            v_title := 'Zpráva z MotoGo24';
            v_message := 'Vaše hlášení bylo přijato. Děkujeme za informaci.';
    END CASE;

    -- Vlož zprávu
    RETURN send_admin_message(
        v_user_id,
        v_title,
        v_message,
        p_reply_type,
        p_incident_id,
        NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===== 7. TRIGGER: Automatická odpověď při vytvoření SOS incidentu =====
-- Pošle automatické poděkování zákazníkovi

CREATE OR REPLACE FUNCTION trigger_sos_auto_reply()
RETURNS TRIGGER AS $$
BEGIN
    -- Vložit zprávu přímo (bez admin auth check)
    INSERT INTO admin_messages (user_id, title, message, type, incident_id)
    VALUES (
        NEW.user_id,
        CASE NEW.type::TEXT
            WHEN 'accident_minor' THEN 'Děkujeme za nahlášení drobné nehody'
            WHEN 'accident_major' THEN 'Přijali jsme hlášení vážné nehody'
            WHEN 'breakdown_minor' THEN 'Děkujeme za nahlášení poruchy'
            WHEN 'breakdown_major' THEN 'Přijali jsme hlášení poruchy'
            WHEN 'theft' THEN 'Hlášení krádeže přijato'
            ELSE 'Vaše hlášení bylo přijato'
        END,
        CASE NEW.type::TEXT
            WHEN 'accident_minor' THEN 'Děkujeme za nahlášení. Šťastnou cestu! Pokud potřebujete pomoc, kontaktujte nás na +420 774 256 271.'
            WHEN 'accident_major' THEN 'Vaše hlášení bylo přijato. Náš tým se tím zabývá. Zůstaňte v bezpečí, brzy se ozveme.'
            WHEN 'breakdown_minor' THEN 'Děkujeme za nahlášení poruchy. Šťastnou cestu! Závadu zkontrolujeme.'
            WHEN 'breakdown_major' THEN 'Vaše hlášení poruchy bylo přijato. Pracujeme na řešení – prosím vyčkejte na místě.'
            WHEN 'theft' THEN 'Hlášení krádeže přijato. Kontaktujte prosím také Policii ČR na 158. Ozveme se co nejdříve.'
            ELSE 'Děkujeme za nahlášení. Ozveme se co nejdříve.'
        END,
        'thanks',
        NEW.id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER sos_auto_reply_on_create
    AFTER INSERT ON sos_incidents
    FOR EACH ROW
    EXECUTE FUNCTION trigger_sos_auto_reply();

-- ===== 8. KOMENTÁŘE =====

COMMENT ON TABLE admin_messages IS 'Zprávy z centrály (velínu) pro zákazníky – reakce na SOS, informace, oznámení';
COMMENT ON FUNCTION send_admin_message IS 'RPC: Admin odešle zprávu zákazníkovi (loguje se do audit logu)';
COMMENT ON FUNCTION auto_reply_sos IS 'RPC: Automatická odpověď na SOS incident podle typu';
COMMENT ON FUNCTION trigger_sos_auto_reply IS 'Trigger: Automatické poděkování při vytvoření SOS incidentu';
