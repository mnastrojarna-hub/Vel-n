-- 20261112c03_messages_bump_thread.sql
-- =============================================================================
-- Zpráva zákazníka posune konverzaci nahoru ve Velínu → Zprávy.
--
-- Souvisí se zadáním majitele 2026-10-15 („Napiš nám přímo, co máme zlepšit“
-- jde do Velínu). Zákazník nemá na message_threads politiku UPDATE, takže
-- appka po odeslání zprávy (messages_provider.sendMessage → update
-- last_message_at) vlákno NEposune — update tiše nic nezmění. Velín řadí
-- konverzace podle last_message_at, takže zpráva do STARŠÍHO vlákna (např.
-- zpětná vazba do vlákna rezervace) zůstala v seznamu dole.
-- Řešení bez otevírání UPDATE zákazníkům: AFTER INSERT trigger na messages
-- posune last_message_at vlákna jen dopředu, nejdál na „teď“ (budoucí
-- created_at poslaný klientem vlákno nepřipíchne nahoru). Status vlákna se
-- NEMĚNÍ (uzavřené zůstává uzavřené).
-- SECURITY DEFINER, protože zákazník sám UPDATE na vlákno nesmí; funkce mění
-- jen last_message_at vlákna, do kterého zpráva právě prošla RLS INSERT.
-- Chyba triggeru nikdy neshodí odeslání zprávy (EXCEPTION → WARNING).
--
-- Idempotentní (CREATE OR REPLACE, DROP TRIGGER IF EXISTS + CREATE). Nemění
-- politiky messages ani message_threads, trigger trg_bridge_admin_message
-- ani data (žádný backfill).
-- =============================================================================

CREATE OR REPLACE FUNCTION public._messages_bump_thread()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_at timestamptz := LEAST(COALESCE(NEW.created_at, now()), now());
BEGIN
  IF NEW.thread_id IS NULL THEN
    RETURN NULL;
  END IF;
  UPDATE public.message_threads
     SET last_message_at = v_at
   WHERE id = NEW.thread_id
     AND (last_message_at IS NULL OR last_message_at < v_at);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_messages_bump_thread(%): %', NEW.thread_id, SQLERRM;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public._messages_bump_thread() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._messages_bump_thread() IS
  'AFTER INSERT na messages: posune message_threads.last_message_at jen dopředu (nejdál na now()). Zákazník nemá UPDATE na vlákna.';

DROP TRIGGER IF EXISTS trg_messages_bump_thread ON public.messages;
CREATE TRIGGER trg_messages_bump_thread
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public._messages_bump_thread();
