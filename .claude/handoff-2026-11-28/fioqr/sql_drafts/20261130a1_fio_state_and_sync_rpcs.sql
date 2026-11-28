-- =============================================================================
-- NÁVRH (DRAFT, není v repu) 2026-11-30a1 (část 1/2): Fio banka — stav synchronizace, rozšíření pohybů,
-- ruční párování / ignorování z Velína, hlídání platnosti tokenu.
--
-- Zadání majitele 2026-11-27: obrazovka „Banka“ ve Velínu (pohyby, nespárované platby),
-- upozornění před vypršením API tokenu. Navazuje na 20260829_fio_bank_sync.sql a
-- 20260830_fio_payment_orders.sql. Idempotentní, NEmaže data, bez tajných hodnot
-- (tokeny zůstávají jen v Supabase Edge secrets FIO_API_TOKEN / FIO_PAYMENT_TOKEN).
--
-- Obsah:
--   1) fio_transactions: nové sloupce (objednávka, požadavek, surová data, ruční cíl, vyřízení)
--      + stavy confirmed_order / confirmed_change / ignored
--   2) fio_sync_state: jednořádkový stav synchronizace (poslední úspěch, chyba, zámek běhu,
--      účet tokenu, platnost tokenů) — admin jen čte, zapisují RPC
--   3) _fio_ops_mail, fio_sync_begin, fio_sync_end — volá edge fio-sync (service_role)
--   (část 2/2 = 20261130a2: admin RPC s auditem, indexy VS, realtime)
--   + RLS fio_transactions / fio_payment_orders: admin jen SELECT (dosud FOR ALL)
-- STATE soubory: 1 (tabulky), 2 (sloupce), 3 (RPC), 5 (RLS, realtime), 6 (changelog).
-- =============================================================================

-- ── 1) fio_transactions ──────────────────────────────────────────────────────
ALTER TABLE public.fio_transactions
  ADD COLUMN IF NOT EXISTS order_id             uuid REFERENCES public.shop_orders(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS request_id           uuid,          -- bank_payment_requests.id (FK přidá 20261130b)
  ADD COLUMN IF NOT EXISTS raw                  jsonb,         -- celý pohyb z Fio (všechny column*), pro detail ve Velínu
  ADD COLUMN IF NOT EXISTS manual_target_type   text,          -- ruční párování z Velína: booking | surcharge | order | request
  ADD COLUMN IF NOT EXISTS manual_target_id     uuid,
  ADD COLUMN IF NOT EXISTS manual_accept_amount boolean NOT NULL DEFAULT false,  -- obsluha přijala i nižší částku
  ADD COLUMN IF NOT EXISTS resolved_by          uuid,          -- admin, který pohyb ručně spároval / ignoroval
  ADD COLUMN IF NOT EXISTS resolved_at          timestamptz,
  ADD COLUMN IF NOT EXISTS resolution_note      text;

ALTER TABLE public.fio_transactions DROP CONSTRAINT IF EXISTS fio_transactions_manual_target_check;
ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_manual_target_check
  CHECK (manual_target_type IS NULL OR manual_target_type IN ('booking','surcharge','order','request'));

ALTER TABLE public.fio_transactions DROP CONSTRAINT IF EXISTS fio_transactions_status_check;
ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_status_check
  CHECK (status IN ('new','outgoing','confirmed_booking','confirmed_surcharge','confirmed_order','confirmed_change',
                    'already_paid','no_match','amount_mismatch','needs_review','error','ignored'));

CREATE INDEX IF NOT EXISTS idx_fio_transactions_date ON public.fio_transactions (tx_date DESC, fio_id DESC);

-- Admin Velínu pohyby a platební příkazy jen ČTE. Dosud FOR ALL USING (is_admin()) dovolovalo adminovi
-- přímý UPDATE/DELETE bez auditu (Velín tyto tabulky dosud nepoužíval) → nově jen SELECT; změny stavu
-- jdou výhradně přes auditované RPC níže a přes edge funkce (service_role, RLS se jich netýká).
DROP POLICY IF EXISTS fio_transactions_admin ON public.fio_transactions;
DROP POLICY IF EXISTS fio_transactions_admin_select ON public.fio_transactions;
CREATE POLICY fio_transactions_admin_select ON public.fio_transactions FOR SELECT USING (public.is_admin());
DROP POLICY IF EXISTS fio_payment_orders_admin ON public.fio_payment_orders;
DROP POLICY IF EXISTS fio_payment_orders_admin_select ON public.fio_payment_orders;
CREATE POLICY fio_payment_orders_admin_select ON public.fio_payment_orders FOR SELECT USING (public.is_admin());

-- ── 2) fio_sync_state ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fio_sync_state (
  id                         smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  last_run_at                timestamptz,           -- poslední spuštění edge fio-sync
  last_ok_at                 timestamptz,           -- poslední úspěšná odpověď Fio API
  last_error                 text,                  -- missing_fio_token | fio_http_500 | bad_response | insert_failed | account_mismatch …
  last_error_at              timestamptz,
  last_http_status           integer,
  consecutive_failures       integer NOT NULL DEFAULT 0,
  failure_alert_at           timestamptz,           -- kdy šel mail „synchronizace selhává“ (1× na výpadek + připomenutí po 24 h)
  stale_alert_at             timestamptz,           -- kdy šel mail „synchronizace neběží“ (hlídá fio_sync_tick v SQL)
  lease_until                timestamptz,           -- zámek běhu (nejvýš jeden běh najednou)
  account_iban               text,                  -- IBAN účtu, ke kterému token patří (z odpovědi Fio)
  id_last_download           bigint,
  last_reconcile_on          date,                  -- den poslední kontroly „periods“ (pojistka proti ztracenému pohybu)
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
-- zápis jen přes SECURITY DEFINER funkce níže (edge = service_role, Velín = admin RPC)

-- ── 3) Funkce pro edge fio-sync ──────────────────────────────────────────────
-- Provozní e-mail na info@ (vzor auto_cancel_expired_pending: URL + klíč z app_settings, pg_net).
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

-- Začátek běhu: zámek (nejvýš jeden běh) + co má běh udělat navíc.
CREATE OR REPLACE FUNCTION public.fio_sync_begin(p_lease_seconds integer DEFAULT 180)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s fio_sync_state%ROWTYPE; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  UPDATE fio_sync_state
     SET lease_until = now() + make_interval(secs => GREATEST(30, LEAST(COALESCE(p_lease_seconds, 180), 600))),
         last_run_at = now(), updated_at = now()
   WHERE id = 1 AND (lease_until IS NULL OR lease_until < now())
   RETURNING * INTO s;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('acquired', false);
  END IF;
  RETURN jsonb_build_object('acquired', true,
    -- 1× denně (po 3:00 Prahy) se místo „last“ stáhne období posledních dní: pojistka proti pohybu,
    -- který Fio vydalo (zarážka se posunula), ale do fio_transactions se nezapsal
    'reconcile_due', s.last_reconcile_on IS DISTINCT FROM v_today
                     AND EXTRACT(hour FROM now() AT TIME ZONE 'Europe/Prague') >= 3,
    'reconcile_from', (v_today - 5)::text, 'reconcile_to', v_today::text,
    'id_last_download', s.id_last_download);
END $$;
REVOKE ALL ON FUNCTION public.fio_sync_begin(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_sync_begin(integer) TO service_role;

-- Konec běhu: uvolní zámek, zapíše výsledek. Do debug_log a na e-mail jde JEN změna stavu
-- (první chyba, 3. chyba v řadě = upozornění, obnovení) — prázdný ani opakovaně chybující běh nic neloguje.
--   p_ok    : Fio odpovědělo a pohyby jsou uložené (i prázdný výpis)
--   p_error : kód chyby (jen když p_ok = false); 'rate_limited' (HTTP 409) se jako chyba NEpočítá
--   p_info  : { iban, id_last_download, reconciled: bool }
CREATE OR REPLACE FUNCTION public.fio_sync_end(p_ok boolean, p_error text DEFAULT NULL, p_http integer DEFAULT NULL,
                                               p_info jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s fio_sync_state%ROWTYPE; v_live boolean; v_iban text; v_cfg_iban text; v_mismatch boolean := false;
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date; v_why text;
BEGIN
  SELECT * INTO s FROM fio_sync_state WHERE id = 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'no_state'); END IF;
  -- „Ostrý provoz“ = synchronizace už někdy uspěla nebo obsluha zadala platnost tokenu;
  -- před tím se neupozorňuje (token ještě nemusí být nastaven).
  v_live := s.last_ok_at IS NOT NULL OR s.token_valid_until IS NOT NULL;

  IF COALESCE(p_error, '') = 'rate_limited' THEN
    UPDATE fio_sync_state SET lease_until = NULL, updated_at = now() WHERE id = 1;
    RETURN jsonb_build_object('success', true, 'skipped', 'rate_limited');
  END IF;

  IF p_ok THEN
    v_iban := NULLIF(upper(regexp_replace(COALESCE(p_info->>'iban', ''), '\s', '', 'g')), '');
    SELECT NULLIF(upper(regexp_replace(COALESCE(value->>'bank_iban', ''), '\s', '', 'g')), '')
      INTO v_cfg_iban FROM app_settings WHERE key = 'company_info';
    v_mismatch := v_iban IS NOT NULL AND v_cfg_iban IS NOT NULL AND v_iban <> v_cfg_iban;

    IF s.consecutive_failures >= 3 THEN
      INSERT INTO debug_log (source, action, component, status, request_data)
      VALUES ('fio-sync', 'sync_recovered', 'fio', 'ok',
              jsonb_build_object('failures', s.consecutive_failures, 'last_error', s.last_error));
      IF s.failure_alert_at IS NOT NULL THEN
        PERFORM _fio_ops_mail('✅ Fio: synchronizace účtu znovu běží',
          '<p>Stahování pohybů z Fio účtu se obnovilo (předchozí chyba: ' || COALESCE(s.last_error, '—') ||
          ', ' || s.consecutive_failures || ' neúspěšných běhů). Platby přijaté mezitím se zpracují samy.</p>');
      END IF;
    END IF;
    -- token patří k jinému účtu, než na který míří QR kódy (company_info.bank_iban) → 1× denně upozornit
    IF v_mismatch AND (s.last_error IS DISTINCT FROM 'account_mismatch' OR s.last_error_at < now() - interval '24 hours') THEN
      INSERT INTO debug_log (source, action, component, status, request_data)
      VALUES ('fio-sync', 'account_mismatch', 'fio', 'error', jsonb_build_object('token_iban', v_iban, 'company_iban', v_cfg_iban));
      PERFORM _fio_ops_mail('⚠️ Fio: token patří k jinému účtu než firemní účet v nastavení',
        '<p>API token čte účet <strong>' || v_iban || '</strong>, ale zákazníci platí QR kódem na <strong>' || v_cfg_iban ||
        '</strong> (Velín → Státní správa → Firemní údaje). Platby se proto nespárují. Opravte číslo účtu, nebo vystavte token k správnému účtu.</p>');
    END IF;
    UPDATE fio_sync_state SET
      last_ok_at = now(), consecutive_failures = 0, failure_alert_at = NULL, stale_alert_at = NULL, lease_until = NULL,
      last_http_status = COALESCE(p_http, 200),
      last_error    = CASE WHEN v_mismatch THEN 'account_mismatch' ELSE NULL END,
      last_error_at = CASE WHEN v_mismatch THEN (CASE WHEN s.last_error = 'account_mismatch' AND s.last_error_at >= now() - interval '24 hours'
                                                        THEN s.last_error_at ELSE now() END) ELSE NULL END,
      account_iban = COALESCE(v_iban, account_iban),
      id_last_download = COALESCE(NULLIF(p_info->>'id_last_download', '')::bigint, id_last_download),
      last_reconcile_on = CASE WHEN COALESCE((p_info->>'reconciled')::boolean, false) THEN v_today ELSE last_reconcile_on END,
      updated_at = now()
    WHERE id = 1;
    RETURN jsonb_build_object('success', true);
  END IF;

  -- chyba
  IF s.consecutive_failures = 0 THEN   -- první chyba v řadě → jeden řádek logu
    INSERT INTO debug_log (source, action, component, status, request_data, error_message)
    VALUES ('fio-sync', 'sync_failing', 'fio', 'error', jsonb_build_object('http_status', p_http), COALESCE(p_error, 'unknown'));
  END IF;
  IF v_live AND s.consecutive_failures + 1 >= 3
     AND (s.failure_alert_at IS NULL OR s.failure_alert_at < now() - interval '24 hours') THEN
    v_why := CASE
      WHEN p_error = 'missing_fio_token' THEN 'V Supabase chybí secret FIO_API_TOKEN.'
      WHEN p_http = 500 THEN 'Fio API vrací chybu 500 — podle dokumentace banky to znamená NEPLATNÝ nebo VYPRŠELÝ token. '
        || 'V internetovém bankovnictví Fio (Nastavení → API) vystavte nový token „Sledování účtu“ a vložte ho do Supabase secretu FIO_API_TOKEN; '
        || 'pak ve Velínu (Finance → Banka) zadejte nové datum platnosti.'
      ELSE 'Chyba: ' || COALESCE(p_error, 'neznámá') || COALESCE(' (HTTP ' || p_http || ')', '') || '.' END;
    PERFORM _fio_ops_mail('🚨 Fio: synchronizace účtu selhává — platby převodem se nepotvrzují',
      '<p><strong>Stahování pohybů z Fio účtu selhalo ' || (s.consecutive_failures + 1) || '× po sobě.</strong> ' || v_why || '</p>'
      || '<p>Dokud se to neopraví, platby QR kódem / převodem se nepotvrdí samy — potvrzujte je ručně v detailu rezervace. '
      || 'Po opravě se nezpracované platby dotáhnou automaticky.</p>');
    UPDATE fio_sync_state SET failure_alert_at = now() WHERE id = 1;
  END IF;
  UPDATE fio_sync_state SET
    consecutive_failures = consecutive_failures + 1, last_error = COALESCE(p_error, 'unknown'), last_error_at = now(),
    last_http_status = p_http, lease_until = NULL, updated_at = now()
  WHERE id = 1;
  RETURN jsonb_build_object('success', true, 'failures', s.consecutive_failures + 1);
END $$;
REVOKE ALL ON FUNCTION public.fio_sync_end(boolean, text, integer, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_sync_end(boolean, text, integer, jsonb) TO service_role;
