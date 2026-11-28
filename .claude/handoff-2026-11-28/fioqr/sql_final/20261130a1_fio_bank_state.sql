-- =============================================================================
-- 2026-11-30a1 (část 1/3): Fio banka — rozšíření pohybů a stav synchronizace
--
-- Zadání majitele 2026-11-27: obrazovka „Banka“ ve Velínu (pohyby, nespárované platby), párování
-- plateb objednávek e-shopu a dárkových poukazů, upozornění před vypršením API tokenu.
-- Navazuje na 20260829_fio_bank_sync.sql a 20260830_fio_payment_orders.sql.
-- Idempotentní, NEmaže data, bez tajných hodnot (tokeny zůstávají jen v Supabase Edge secrets
-- FIO_API_TOKEN / FIO_PAYMENT_TOKEN).
--
-- Obsah:
--   1) fio_transactions: nové sloupce (objednávka, požadavek, cíl a důvod rozhodnutí, surová data,
--      ruční spárování, úkol pro obsluhu, opakování při chybě, zámek řádku) + nové stavy
--      confirmed_order / confirmed_change / ignored
--   2) admin Velínu pohyby a platební příkazy jen ČTE (dosud FOR ALL) — změny jen přes auditované RPC
--   3) fio_sync_state: jednořádkový stav synchronizace (poslední úspěch, chyba, zámek běhu, účet
--      tokenu, platnost tokenů) — admin jen čte
--   4) _fio_ops_mail: provozní e-mail na info@ z SQL
-- TÍMTO SOUBOREM SE ZAPÍNÁ nové chování edge funkce fio-sync (pozná ho podle RPC z části 2/3):
-- do té doby funkce běží přesně jako dřív.
-- STATE soubory: 1 (tabulky), 2 (sloupce), 3 (RPC), 5 (RLS), 6 (changelog).
-- =============================================================================

-- ── 1) fio_transactions ──────────────────────────────────────────────────────
ALTER TABLE public.fio_transactions
  ADD COLUMN IF NOT EXISTS order_id             uuid REFERENCES public.shop_orders(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS request_id           uuid,          -- bank_payment_requests.id (FK přidá 20261130b1)
  ADD COLUMN IF NOT EXISTS target_type          text,          -- s čím se pohyb spároval: booking | surcharge | order | request
  ADD COLUMN IF NOT EXISTS reason_code          text,          -- strojový důvod rozhodnutí (underpaid, duplicate, late_cancelled…)
  ADD COLUMN IF NOT EXISTS expected_amount      numeric(12,2), -- částka, kterou cíl čekal
  ADD COLUMN IF NOT EXISTS raw                  jsonb,         -- celý pohyb z Fio (všechny column*), pro detail ve Velínu
  ADD COLUMN IF NOT EXISTS manual_target_type   text,          -- ruční spárování z Velína: booking | surcharge | order | request
  ADD COLUMN IF NOT EXISTS manual_target_id     uuid,
  ADD COLUMN IF NOT EXISTS manual_accept_amount boolean NOT NULL DEFAULT false,  -- obsluha přijala i nižší částku
  ADD COLUMN IF NOT EXISTS followup             text,          -- otevřený úkol u POTVRZENÉHO pohybu: overpaid (vrátit přeplatek)
  ADD COLUMN IF NOT EXISTS followup_done_at     timestamptz,
  ADD COLUMN IF NOT EXISTS resolved_by          uuid,          -- admin, který pohyb naposledy ručně řešil
  ADD COLUMN IF NOT EXISTS resolved_at          timestamptz,
  ADD COLUMN IF NOT EXISTS resolution_note      text,
  ADD COLUMN IF NOT EXISTS attempts             integer NOT NULL DEFAULT 0,      -- pokusy o zpracování po chybě
  ADD COLUMN IF NOT EXISTS first_error_at       timestamptz,
  ADD COLUMN IF NOT EXISTS claimed_until        timestamptz;   -- pohyb právě zpracovává jeden běh (fio_claim_transactions)

ALTER TABLE public.fio_transactions DROP CONSTRAINT IF EXISTS fio_transactions_manual_target_check;
ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_manual_target_check
  CHECK (manual_target_type IS NULL OR manual_target_type IN ('booking','surcharge','order','request'));
ALTER TABLE public.fio_transactions DROP CONSTRAINT IF EXISTS fio_transactions_target_type_check;
ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_target_type_check
  CHECK (target_type IS NULL OR target_type IN ('booking','surcharge','order','request'));
ALTER TABLE public.fio_transactions DROP CONSTRAINT IF EXISTS fio_transactions_followup_check;
ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_followup_check
  CHECK (followup IS NULL OR followup IN ('overpaid'));

ALTER TABLE public.fio_transactions DROP CONSTRAINT IF EXISTS fio_transactions_status_check;
ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_status_check
  CHECK (status IN ('new','outgoing','confirmed_booking','confirmed_surcharge','confirmed_order','confirmed_change',
                    'already_paid','no_match','amount_mismatch','needs_review','error','ignored'));

CREATE INDEX IF NOT EXISTS idx_fio_transactions_date ON public.fio_transactions (tx_date DESC, fio_id DESC);
CREATE INDEX IF NOT EXISTS idx_fio_transactions_followup ON public.fio_transactions (fio_id) WHERE followup IS NOT NULL AND followup_done_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fio_transactions_order ON public.fio_transactions (order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fio_transactions_booking ON public.fio_transactions (booking_id) WHERE booking_id IS NOT NULL;

-- ── 2) Admin Velínu pohyby a platební příkazy jen ČTE ────────────────────────
-- Dosud FOR ALL USING (is_admin()) dovolovalo adminovi přímý UPDATE/DELETE bez auditu (Velín tyto
-- tabulky dosud nepoužíval) → nově jen SELECT; změny stavu jdou výhradně přes auditované RPC
-- (20261130a3) a přes edge funkce (service_role, RLS se jich netýká).
DROP POLICY IF EXISTS fio_transactions_admin ON public.fio_transactions;
DROP POLICY IF EXISTS fio_transactions_admin_select ON public.fio_transactions;
CREATE POLICY fio_transactions_admin_select ON public.fio_transactions FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS fio_payment_orders_admin ON public.fio_payment_orders;
DROP POLICY IF EXISTS fio_payment_orders_admin_select ON public.fio_payment_orders;
CREATE POLICY fio_payment_orders_admin_select ON public.fio_payment_orders FOR SELECT USING (public.is_admin());
REVOKE ALL ON public.fio_transactions, public.fio_payment_orders FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.fio_transactions, public.fio_payment_orders FROM authenticated;
GRANT SELECT ON public.fio_transactions, public.fio_payment_orders TO authenticated;

-- ── 3) fio_sync_state ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fio_sync_state (
  id                         smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  last_run_at                timestamptz,           -- poslední spuštění edge fio-sync
  last_ok_at                 timestamptz,           -- poslední úspěšná odpověď Fio API
  first_ok_at                timestamptz,           -- první úspěch (kontrola „periods“ nesahá před start provozu)
  last_error                 text,                  -- missing_fio_token | fio_http_500 | bad_response | insert_failed | account_mismatch | exception
  last_error_at              timestamptz,
  last_http_status           integer,
  consecutive_failures       integer NOT NULL DEFAULT 0,
  failure_alert_at           timestamptz,           -- kdy šel mail „synchronizace selhává“ (1× na výpadek + připomenutí po 24 h)
  stale_alert_at             timestamptz,           -- kdy šel mail „synchronizace neběží“ (hlídá fio_sync_tick v SQL)
  lease_until                timestamptz,           -- zámek běhu (nejvýš jeden běh najednou)
  account_iban               text,                  -- IBAN účtu, ke kterému token patří (z odpovědi Fio)
  id_last_download           bigint,
  last_reconcile_on          date,                  -- den poslední kontroly „periods“ (pojistka proti ztracenému pohybu)
  reconcile_since            timestamptz,           -- od kdy je potřeba pohyby dohledat (po neplatné odpovědi / neuloženém řádku / výpadku)
  reconcile_tries            integer NOT NULL DEFAULT 0,
  reconcile_try_on           date,
  token_valid_until          date,                  -- platnost FIO_API_TOKEN (zadává obsluha — Fio API ji neumí vrátit)
  pay_token_valid_until      date,                  -- platnost FIO_PAYMENT_TOKEN (NULL = není / stejný token)
  token_auto_prolong         boolean NOT NULL DEFAULT false,
  token_warned_threshold     integer,               -- poslední odeslaný práh (30/14/7/3/1/0) pro token_valid_until
  pay_token_warned_threshold integer,
  updated_at                 timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.fio_sync_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.fio_sync_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fio_sync_state_admin_select ON public.fio_sync_state;
CREATE POLICY fio_sync_state_admin_select ON public.fio_sync_state FOR SELECT USING (public.is_admin());
REVOKE ALL ON public.fio_sync_state FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.fio_sync_state FROM authenticated;
GRANT SELECT ON public.fio_sync_state TO authenticated;
-- zápis jen přes SECURITY DEFINER funkce (edge = service_role, Velín = admin RPC)

-- ── 4) Provozní e-mail na info@ ──────────────────────────────────────────────
-- (vzor auto_cancel_expired_pending: URL + klíč z app_settings, pg_net)
CREATE OR REPLACE FUNCTION public._fio_ops_mail(p_subject text, p_html text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_url text; v_key text;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF COALESCE(v_url, '') = '' OR COALESCE(v_key, '') = '' THEN
    RAISE WARNING '_fio_ops_mail: app_settings supabase_url/service_role_key chybí';
    RETURN;
  END IF;
  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-email',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body    := jsonb_build_object('to', 'info@motogo24.cz', 'subject', p_subject, 'raw_html', p_html));
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_fio_ops_mail: %', SQLERRM;
END $$;
REVOKE ALL ON FUNCTION public._fio_ops_mail(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._fio_ops_mail(text, text) TO service_role;
