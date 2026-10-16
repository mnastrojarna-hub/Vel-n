-- 20261015c_messages_bump_thread.sql
-- =============================================================================
-- NÁVRH (čeká na schválení majitelem — CLAUDE.md pravidlo 3). VOLITELNÉ —
-- záložka Hodnocení i appka fungují i bez něj.
--
-- Problém (existuje už dnes, ověřeno snapshotem 2026-10-10): zákazník nemá na
-- message_threads politiku UPDATE, takže appka po odeslání zprávy
-- (messages_provider.sendMessage → update last_message_at) vlákno NEposune —
-- update tiše nic nezmění. Velín → Chat řadí konverzace podle last_message_at,
-- takže zákazníkova zpráva do STARŠÍHO vlákna (např. „co máme zlepšit“ do
-- vlákna rezervace) zůstane v seznamu dole (vidět je jen díky odznaku nepřečtených).
-- Řešení bez otevírání UPDATE zákazníkům: AFTER INSERT trigger na messages
-- posune last_message_at vlákna (jen dopředu, GREATEST). Status vlákna se
-- NEMĚNÍ (uzavřené zůstává uzavřené — beze změny chování Velína).
-- SECURITY DEFINER, protože zákazník sám UPDATE na vlákno nesmí; funkce mění
-- jen last_message_at vlákna, do kterého zpráva právě prošla RLS INSERT.
-- Chyba triggeru nikdy neshodí odeslání zprávy (EXCEPTION → WARNING).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._messages_bump_thread()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.message_threads
     SET last_message_at = GREATEST(COALESCE(last_message_at, '-infinity'::timestamptz), COALESCE(NEW.created_at, now()))
   WHERE id = NEW.thread_id
     AND (last_message_at IS NULL OR last_message_at < COALESCE(NEW.created_at, now()));
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_messages_bump_thread(%): %', NEW.thread_id, SQLERRM;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._messages_bump_thread() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._messages_bump_thread() IS
  'AFTER INSERT na messages: posune message_threads.last_message_at (jen dopředu). Zákazník nemá UPDATE na vlákna.';

DROP TRIGGER IF EXISTS trg_messages_bump_thread ON public.messages;
CREATE TRIGGER trg_messages_bump_thread
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public._messages_bump_thread();

-- STATE po schválení: STATE_4 (trigger), STATE_5 (pozn. k message_threads RLS:
-- zákazník UPDATE NEMÁ — STATE_5 řádek „customer SELECT/UPDATE/INSERT“ opravit), STATE_6.
