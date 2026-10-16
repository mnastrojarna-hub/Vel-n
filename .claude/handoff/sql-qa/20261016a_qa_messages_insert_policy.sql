-- =============================================================================
-- 20261016a_qa_messages_insert_policy.sql  — NÁVRH ke schválení (QA brána 2026-10-16), neaplikováno
-- RLS: zákazník smí do svého vlákna vkládat jen zprávy direction='customer'.
--
-- Živě (snapshot 2026-10-15) má public.messages tři INSERT cesty:
--   • messages_admin               FOR ALL  USING is_admin()                     (Velín)
--   • messages_customer_insert     FOR INSERT WITH CHECK direction='customer' AND vlastní vlákno (appka)
--   • "Users and admins can send messages"  FOR INSERT WITH CHECK vlastní vlákno OR admin_users — BEZ
--     podmínky na direction → zákazník může do svého vlákna vložit i direction='admin'/'outbound'.
--     Velín → Zprávy → Hodnocení by takovou zprávu bral jako odpověď týmu (nízké hodnocení „vyřízeno“,
--     zmizí z odznaku) a trigger trg_bridge_admin_message by ji přeposlal jako zprávu od MotoGo24.
-- Appka vkládá jen direction='customer' (messages_provider.dart), Velín přes is_admin(), edge funkce
-- service_role → po odebrání staré politiky nic nepřestane fungovat.
--
-- Bezpečnost: politika se odebere JEN když existují obě náhradní politiky (messages_admin a
-- messages_customer_insert s podmínkou direction='customer'); jinak NOTICE a beze změny.
-- Idempotentní (DROP POLICY IF EXISTS). Bez BEGIN/COMMIT (deploy-sql.yml = 1 transakce na soubor).
-- Po aplikaci: SUPABASE_BACKEND_STATE_5.md (řádek messages) + changelog STATE_6.
-- =============================================================================
DO $$
DECLARE
  v_admin boolean;
  v_cust  boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'messages'
                  AND policyname = 'messages_admin' AND cmd = 'ALL')
    INTO v_admin;
  SELECT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'messages'
                  AND policyname = 'messages_customer_insert' AND cmd = 'INSERT'
                  AND with_check ILIKE '%direction%customer%')
    INTO v_cust;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'messages'
                  AND policyname = 'Users and admins can send messages') THEN
    RAISE NOTICE 'messages: politika "Users and admins can send messages" už neexistuje – beze změny';
  ELSIF v_admin AND v_cust THEN
    DROP POLICY "Users and admins can send messages" ON public.messages;
    RAISE NOTICE 'messages: odebrána politika "Users and admins can send messages" (zůstává messages_admin + messages_customer_insert)';
  ELSE
    RAISE NOTICE 'messages: chybí náhradní politika (messages_admin=%, messages_customer_insert=%) – beze změny', v_admin, v_cust;
  END IF;
END $$;
