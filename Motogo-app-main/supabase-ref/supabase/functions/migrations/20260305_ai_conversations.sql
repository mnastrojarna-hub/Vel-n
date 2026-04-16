-- =====================================================
-- MotoGo24 Velín — AI Conversations tabulka
-- Ukládá konverzace s AI Copilotem
-- ZÁVISÍ NA: 20260305_000_base_tables.sql
-- =====================================================

CREATE TABLE IF NOT EXISTS ai_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid REFERENCES admin_users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  title text NOT NULL DEFAULT 'Nová konverzace',
  messages jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_conversations_admin ON ai_conversations(admin_id);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_updated ON ai_conversations(updated_at DESC);

ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;

-- Každý admin vidí jen své konverzace
DROP POLICY IF EXISTS ai_conversations_own ON ai_conversations;
CREATE POLICY ai_conversations_own ON ai_conversations
  FOR ALL USING (admin_id = auth.uid() OR is_superadmin())
  WITH CHECK (admin_id = auth.uid());

DROP TRIGGER IF EXISTS trg_ai_conversations_updated ON ai_conversations;
CREATE TRIGGER trg_ai_conversations_updated
  BEFORE UPDATE ON ai_conversations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
