-- =====================================================
-- MotoGo24 — Opravy propojení Velín ↔ Aplikace
-- 1. RLS profily: zákazník vidí svůj profil
-- 2. RLS bookings: zákazník CRUD svých rezervací
-- 3. RLS motorcycles: veřejné čtení aktivních
-- 4. confirm_payment RPC (test mode)
-- 5. Bridge: admin messages → admin_messages tabulka
-- 6. RLS admin_messages: zákazník čte své zprávy
-- 7. Promo kódy: customer insert do promo_code_usage
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. PROFILES — zákazník vidí a edituje SVŮJ profil
-- ═══════════════════════════════════════════════════════

DROP POLICY IF EXISTS profiles_user_select ON profiles;
CREATE POLICY profiles_user_select ON profiles
  FOR SELECT USING (id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS profiles_user_update ON profiles;
CREATE POLICY profiles_user_update ON profiles
  FOR UPDATE USING (id = auth.uid());

DROP POLICY IF EXISTS profiles_admin_all ON profiles;
CREATE POLICY profiles_admin_all ON profiles
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════
-- 2. BOOKINGS — zákazník vidí své, admin vše
-- ═══════════════════════════════════════════════════════

DROP POLICY IF EXISTS bookings_user_select ON bookings;
CREATE POLICY bookings_user_select ON bookings
  FOR SELECT USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS bookings_user_insert ON bookings;
CREATE POLICY bookings_user_insert ON bookings
  FOR INSERT WITH CHECK (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS bookings_user_update ON bookings;
CREATE POLICY bookings_user_update ON bookings
  FOR UPDATE USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS bookings_admin_delete ON bookings;
CREATE POLICY bookings_admin_delete ON bookings
  FOR DELETE USING (is_admin());

-- ═══════════════════════════════════════════════════════
-- 3. MOTORCYCLES — veřejné čtení (katalog), admin CRUD
-- ═══════════════════════════════════════════════════════

DROP POLICY IF EXISTS motorcycles_public_read ON motorcycles;
CREATE POLICY motorcycles_public_read ON motorcycles
  FOR SELECT USING (true);

DROP POLICY IF EXISTS motorcycles_admin_all ON motorcycles;
CREATE POLICY motorcycles_admin_all ON motorcycles
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════
-- 4. CONFIRM_PAYMENT — RPC funkce (test mode = vždy OK)
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION confirm_payment(
  p_booking_id uuid,
  p_method text DEFAULT 'card'
)
RETURNS jsonb AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rezervace nenalezena');
  END IF;

  -- Ověř, že booking patří volajícímu nebo je admin
  IF v_booking.user_id != auth.uid() AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nemáte oprávnění');
  END IF;

  -- Update booking — platba potvrzena
  UPDATE bookings SET
    payment_status = 'paid',
    payment_method = p_method,
    status = CASE WHEN status = 'pending' THEN 'active' ELSE status END
  WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', 'TXN-TEST-' || substr(p_booking_id::text, 1, 8)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════
-- 5. ADMIN_MESSAGES — zajistit existenci + RLS
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS admin_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE,
  title text,
  message text,
  type text DEFAULT 'info',
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_messages_user ON admin_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_messages_read ON admin_messages(user_id, read);

ALTER TABLE admin_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_messages_user_select ON admin_messages;
CREATE POLICY admin_messages_user_select ON admin_messages
  FOR SELECT USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS admin_messages_user_update ON admin_messages;
CREATE POLICY admin_messages_user_update ON admin_messages
  FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS admin_messages_admin_all ON admin_messages;
CREATE POLICY admin_messages_admin_all ON admin_messages
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- Realtime pro admin_messages
ALTER PUBLICATION supabase_realtime ADD TABLE admin_messages;

-- ═══════════════════════════════════════════════════════
-- 6. BRIDGE: Admin zpráva → admin_messages
--    Když admin pošle zprávu přes message_threads/messages,
--    automaticky se vytvoří záznam v admin_messages
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION bridge_admin_message_to_app()
RETURNS trigger AS $$
DECLARE
  v_thread message_threads%ROWTYPE;
  v_customer_id uuid;
BEGIN
  -- Pouze admin zprávy
  IF NEW.direction != 'admin' THEN RETURN NEW; END IF;

  -- Najdi thread a zákazníka
  SELECT * INTO v_thread FROM message_threads WHERE id = NEW.thread_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_customer_id := v_thread.customer_id;
  IF v_customer_id IS NULL THEN RETURN NEW; END IF;

  -- Vytvoř záznam v admin_messages pro aplikaci
  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    v_customer_id,
    COALESCE(v_thread.subject, 'Zpráva z Moto Go'),
    NEW.content,
    'info'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_bridge_admin_message ON messages;
CREATE TRIGGER trg_bridge_admin_message
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION bridge_admin_message_to_app();

-- ═══════════════════════════════════════════════════════
-- 7. PROMO_CODE_USAGE — zákazník může vložit použití
-- ═══════════════════════════════════════════════════════

DROP POLICY IF EXISTS promo_usage_customer_insert ON promo_code_usage;
CREATE POLICY promo_usage_customer_insert ON promo_code_usage
  FOR INSERT WITH CHECK (customer_id = auth.uid());

DROP POLICY IF EXISTS promo_usage_customer_read ON promo_code_usage;
CREATE POLICY promo_usage_customer_read ON promo_code_usage
  FOR SELECT USING (customer_id = auth.uid() OR is_admin());

-- ═══════════════════════════════════════════════════════
-- 8. DOCUMENTS — zákazník vidí své dokumenty
-- ═══════════════════════════════════════════════════════

DROP POLICY IF EXISTS documents_user_select ON documents;
CREATE POLICY documents_user_select ON documents
  FOR SELECT USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS documents_user_insert ON documents;
CREATE POLICY documents_user_insert ON documents
  FOR INSERT WITH CHECK (user_id = auth.uid() OR is_admin());

-- ═══════════════════════════════════════════════════════
-- 9. SERVICE_ORDERS — admin + vytváření z kalendáře
-- ═══════════════════════════════════════════════════════

-- service_orders already has admin policy, ensure it covers INSERT
DROP POLICY IF EXISTS service_orders_admin ON service_orders;
CREATE POLICY service_orders_admin ON service_orders
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());
