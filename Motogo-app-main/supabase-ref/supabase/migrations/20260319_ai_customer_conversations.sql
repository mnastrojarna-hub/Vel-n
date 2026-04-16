-- Tabulka pro multi-konverzace zákazníků s AI servisním agentem
-- Frontend: motogo-app-frontend/js/ai-agent-ui.js

CREATE TABLE IF NOT EXISTS ai_customer_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL DEFAULT 'Nová konverzace',
  messages jsonb NOT NULL DEFAULT '[]'::jsonb,
  booking_id uuid REFERENCES bookings(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ai_cust_conv_user ON ai_customer_conversations(user_id);
CREATE INDEX idx_ai_cust_conv_updated ON ai_customer_conversations(updated_at DESC);

ALTER TABLE ai_customer_conversations ENABLE ROW LEVEL SECURITY;

-- Zákazník vidí jen své konverzace
CREATE POLICY ai_cust_conv_own ON ai_customer_conversations
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Admin full access
CREATE POLICY ai_cust_conv_admin ON ai_customer_conversations
  FOR ALL USING (is_admin());

-- Trigger pro updated_at
CREATE TRIGGER trg_ai_cust_conv_updated
  BEFORE UPDATE ON ai_customer_conversations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RPC pro rychlý append zprávy (frontend nemusí stahovat celý JSONB)
CREATE OR REPLACE FUNCTION append_ai_message(
  p_conversation_id uuid,
  p_role text,
  p_content text
) RETURNS void AS $$
BEGIN
  UPDATE ai_customer_conversations
  SET messages = messages || jsonb_build_array(jsonb_build_object(
    'role', p_role,
    'content', p_content,
    'timestamp', now()
  )),
  updated_at = now()
  WHERE id = p_conversation_id AND user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
