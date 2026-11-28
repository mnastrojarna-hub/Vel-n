-- =============================================================================
-- 2026-11-30a2 (část 2/3): Fio banka — RPC pro edge funkci fio-sync (jen service_role)
--
-- Potřebuje 20261130a1 (fio_sync_state, nové sloupce fio_transactions, _fio_ops_mail).
--   fio_sync_begin()          zámek běhu (nejvýš jeden běh najednou; po pádu sám vyprší) + zda má běh
--                             místo „od posledního stažení“ stáhnout pohyby za období (pojistka proti
--                             ztracenému pohybu: 1× denně a po každém neplatném / neuloženém stažení)
--   fio_sync_end()            výsledek běhu; do debug_log a na e-mail jde JEN změna stavu
--                             (první chyba, 3. chyba v řadě = upozornění, obnovení) — prázdný ani
--                             opakovaně chybující běh nic neloguje; hlídá i účet, ke kterému token patří
--   fio_claim_transactions()  vezme pohyby ke zpracování tak, aby je nedostal souběžný běh
-- EXISTENCÍ fio_sync_begin se v edge funkci fio-sync zapíná nové chování (zámek, opakování chyb,
-- sčítání částečných plateb, hlášení duplicit, obnovení rezervace po pozdní platbě, párování
-- objednávek e-shopu). Bez ní funkce běží přesně jako dřív.
-- Idempotentní. STATE soubory: 3 (RPC), 6.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fio_sync_begin(p_lease_seconds integer DEFAULT 180)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s fio_sync_state%ROWTYPE; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_tries integer; v_due boolean; v_from date;
BEGIN
  UPDATE fio_sync_state
     SET lease_until = now() + make_interval(secs => GREATEST(30, LEAST(COALESCE(p_lease_seconds, 180), 600))),
         last_run_at = now(), updated_at = now()
   WHERE id = 1 AND (lease_until IS NULL OR lease_until < now())
   RETURNING * INTO s;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('acquired', false);
  END IF;
  -- Stažení za období („periods“ — nezávislé na zarážce banky): když čeká dohledání (reconcile_since),
  -- jinak 1× denně po 3:00 Prahy, až po prvním úspěšném běhu. Nejvýš 3 pokusy denně, pak zase „last“
  -- (aby vadné období nezablokovalo běžné stahování).
  v_tries := CASE WHEN s.reconcile_try_on = v_today THEN COALESCE(s.reconcile_tries, 0) ELSE 0 END;
  v_due := v_tries < 3 AND (
    s.reconcile_since IS NOT NULL
    OR (s.last_ok_at IS NOT NULL AND s.last_reconcile_on IS DISTINCT FROM v_today
        AND EXTRACT(hour FROM now() AT TIME ZONE 'Europe/Prague') >= 3));
  IF v_due THEN
    UPDATE fio_sync_state SET reconcile_tries = v_tries + 1, reconcile_try_on = v_today WHERE id = 1;
  END IF;
  v_from := LEAST(v_today - 5, COALESCE((s.reconcile_since AT TIME ZONE 'Europe/Prague')::date - 1, v_today - 5));
  v_from := GREATEST(v_from, v_today - 60, COALESCE((s.first_ok_at AT TIME ZONE 'Europe/Prague')::date, v_today - 60));
  RETURN jsonb_build_object('acquired', true, 'reconcile_due', v_due,
    'reconcile_from', LEAST(v_from, v_today)::text, 'reconcile_to', v_today::text,
    'id_last_download', s.id_last_download);
END $$;
REVOKE ALL ON FUNCTION public.fio_sync_begin(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_sync_begin(integer) TO service_role;

--   p_ok    : true = banka odpověděla a pohyby jsou uložené (i prázdný výpis); false = chyba
--   p_error : kód chyby (jen když p_ok není true); 'rate_limited' (HTTP 409) se jako chyba NEpočítá
--   p_info  : { iban, id_last_download, reconcile: běh byl „periods“, reconciled: období staženo a
--               uloženo, recover: pohyby mohly propadnout → příští běh stáhne období }
CREATE OR REPLACE FUNCTION public.fio_sync_end(p_ok boolean, p_error text DEFAULT NULL, p_http integer DEFAULT NULL,
                                               p_info jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s fio_sync_state%ROWTYPE; v_live boolean; v_iban text; v_cfg_iban text; v_mismatch boolean := false;
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date; v_why text;
  v_info jsonb := COALESCE(p_info, '{}'::jsonb);
  v_reconciled boolean := COALESCE((v_info->>'reconciled')::boolean, false);
BEGIN
  SELECT * INTO s FROM fio_sync_state WHERE id = 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'no_state'); END IF;
  -- „Ostrý provoz“ = synchronizace už někdy uspěla nebo obsluha zadala platnost tokenu;
  -- před tím se neupozorňuje (token ještě nemusí být nastaven).
  v_live := s.last_ok_at IS NOT NULL OR s.token_valid_until IS NOT NULL;

  IF COALESCE(p_error, '') = 'rate_limited' THEN
    UPDATE fio_sync_state SET lease_until = NULL, updated_at = now(),
           reconcile_tries = CASE WHEN COALESCE((v_info->>'reconcile')::boolean, false) THEN GREATEST(reconcile_tries - 1, 0) ELSE reconcile_tries END
     WHERE id = 1;
    RETURN jsonb_build_object('success', true, 'skipped', 'rate_limited');
  END IF;

  IF p_ok IS TRUE THEN
    v_iban := NULLIF(upper(regexp_replace(COALESCE(v_info->>'iban', ''), '\s', '', 'g')), '');
    SELECT NULLIF(upper(regexp_replace(COALESCE(value->>'bank_iban', ''), '\s', '', 'g')), '')
      INTO v_cfg_iban FROM app_settings WHERE key = 'company_info';
    v_mismatch := v_iban IS NOT NULL AND v_cfg_iban IS NOT NULL AND v_iban <> v_cfg_iban;

    IF s.consecutive_failures >= 1 THEN
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
      last_ok_at = now(), first_ok_at = COALESCE(first_ok_at, now()),
      consecutive_failures = 0, failure_alert_at = NULL, stale_alert_at = NULL, lease_until = NULL,
      last_http_status = COALESCE(p_http, 200),
      last_error    = CASE WHEN v_mismatch THEN 'account_mismatch' ELSE NULL END,
      last_error_at = CASE WHEN v_mismatch THEN (CASE WHEN s.last_error = 'account_mismatch' AND s.last_error_at >= now() - interval '24 hours'
                                                        THEN s.last_error_at ELSE now() END) ELSE NULL END,
      account_iban = COALESCE(v_iban, account_iban),
      id_last_download = COALESCE(NULLIF(v_info->>'id_last_download', '')::bigint, id_last_download),
      last_reconcile_on = CASE WHEN v_reconciled THEN v_today ELSE last_reconcile_on END,
      -- období staženo → dohledání hotovo; po delším výpadku (3+ chyb) si první úspěšný běh „last“
      -- vyžádá dohledání od posledního úspěchu (nový token může mít jinou zarážku)
      reconcile_since = CASE WHEN v_reconciled THEN NULL
                             WHEN s.consecutive_failures >= 3 THEN COALESCE(reconcile_since, s.last_ok_at, now())
                             ELSE reconcile_since END,
      reconcile_tries = CASE WHEN v_reconciled THEN 0 ELSE reconcile_tries END,
      updated_at = now()
    WHERE id = 1;
    RETURN jsonb_build_object('success', true);
  END IF;

  -- chyba
  IF s.consecutive_failures = 0 THEN   -- první chyba v řadě → jeden řádek logu
    INSERT INTO debug_log (source, action, component, status, request_data, error_message)
    VALUES ('fio-sync', 'sync_failing', 'fio', 'error',
            jsonb_build_object('http_status', p_http, 'detail', left(COALESCE(v_info->>'detail', ''), 300)), COALESCE(p_error, 'unknown'));
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
    last_http_status = p_http, lease_until = NULL, updated_at = now(),
    reconcile_since = CASE WHEN COALESCE((v_info->>'recover')::boolean, false) THEN COALESCE(reconcile_since, now()) ELSE reconcile_since END
  WHERE id = 1;
  RETURN jsonb_build_object('success', true, 'failures', s.consecutive_failures + 1);
END $$;
REVOKE ALL ON FUNCTION public.fio_sync_end(boolean, text, integer, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_sync_end(boolean, text, integer, jsonb) TO service_role;

-- Pohyby ke zpracování: příchozí ve stavu 'new' (a staré 'error' z doby před touto změnou — ty se dřív
-- neopakovaly ani nehlásily), které právě nezpracovává jiný běh. Zámek řádku na p_claim_seconds;
-- po zpracování ho edge funkce uvolní (claimed_until = NULL), po pádu vyprší sám.
CREATE OR REPLACE FUNCTION public.fio_claim_transactions(p_limit integer DEFAULT 1, p_fio_id bigint DEFAULT NULL,
                                                         p_claim_seconds integer DEFAULT 150)
RETURNS SETOF public.fio_transactions LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  UPDATE fio_transactions t
     SET claimed_until = now() + make_interval(secs => GREATEST(30, LEAST(COALESCE(p_claim_seconds, 150), 900)))
   WHERE t.fio_id IN (
     SELECT f.fio_id FROM fio_transactions f
      WHERE f.amount > 0
        AND (f.status = 'new' OR (f.status = 'error' AND f.attempts = 0))
        AND (f.claimed_until IS NULL OR f.claimed_until < now())
        AND (p_fio_id IS NULL OR f.fio_id = p_fio_id)
      ORDER BY f.fio_id
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 1), 50))
      FOR UPDATE SKIP LOCKED)
  RETURNING t.*;
END $$;
REVOKE ALL ON FUNCTION public.fio_claim_transactions(integer, bigint, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_claim_transactions(integer, bigint, integer) TO service_role;
