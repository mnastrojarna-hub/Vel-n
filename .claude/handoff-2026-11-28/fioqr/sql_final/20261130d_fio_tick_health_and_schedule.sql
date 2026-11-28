-- =============================================================================
-- 2026-11-30d: Fio synchronizace každou MINUTU + hlídání v SQL (výpadek, platnost tokenu)
--
-- Zadání majitele 2026-11-27: synchronizace každou minutu („pokud by to nespamovalo“) + upozornění
-- před vypršením API tokenu.
--
-- Potřebuje 20261130a1/a2 (fio_sync_state, _fio_ops_mail) a 20261130b2 (expire_bank_payment_requests).
--   1) fio_health_alerts(): (a) synchronizace neběží > 20 min (cron jede, edge funkce neodpovídá)
--      → e-mail 1× za 24 h; (b) platnost tokenu — 30 / 14 / 7 / 3 / 1 / 0 dní předem, každý práh JEDNOU,
--      jen 8–20 h. Běží v SQL uvnitř fio_sync_tick → funguje i když je edge funkce rozbitá / token mrtvý.
--      Před prvním úspěšným během a bez zadaného data platnosti nehlásí nic (žádný šum před spuštěním).
--   2) fio_sync_tick(): aktuální tělo + vypršení požadavků na platbu + hlídání + timeout volání 55 s
--      (dosud výchozí timeout pg_net — odpověď delšího běhu se zahazovala).
--   3) cron 'fio-bank-sync': */5 → každou minutu.
-- Proč to nespamuje: Fio limit = 1 dotaz / 30 s na token → 1 dotaz za 60 s je v limitu (HTTP 409 edge
-- funkce tiše přeskočí); prázdný běh nezapisuje nic do debug_log (jen 1 UPDATE řádku fio_sync_state);
-- selhání se loguje a hlásí jen při ZMĚNĚ stavu; e-maily jen při události u konkrétní platby; souběh
-- běhů hlídá zámek (fio_sync_begin).
--
-- NÁVRAT na 5 minut (kdykoli, bez dalších změn — SQL editor):
--   SELECT cron.unschedule('fio-bank-sync');
--   SELECT cron.schedule('fio-bank-sync', '*/5 * * * *', $cron$ SELECT public.fio_sync_tick(); $cron$);
-- Idempotentní. STATE soubory: 3 (RPC), 5 (cron), 6.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fio_health_alerts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s fio_sync_state%ROWTYPE;
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_hour  integer := EXTRACT(hour FROM now() AT TIME ZONE 'Europe/Prague')::integer;
  v_d integer; v_t integer; v_how text;
BEGIN
  SELECT * INTO s FROM fio_sync_state WHERE id = 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  -- (a) synchronizace neběží: už někdy fungovala, ale poslední úspěch je starší než 20 minut a
  --     edge funkce sama chybu nehlásí (failure_alert_at = její vlastní upozornění) → 1× za 24 h
  IF s.last_ok_at IS NOT NULL AND s.last_ok_at < now() - interval '20 minutes'
     AND s.failure_alert_at IS NULL
     AND (s.stale_alert_at IS NULL OR s.stale_alert_at < now() - interval '24 hours') THEN
    PERFORM _fio_ops_mail('🚨 Fio: synchronizace účtu neběží — platby převodem se nepotvrzují',
      '<p><strong>Poslední úspěšné stažení pohybů z Fio účtu: ' || to_char(s.last_ok_at AT TIME ZONE 'Europe/Prague', 'DD.MM.YYYY HH24:MI')
      || '.</strong> Od té doby se synchronizace nedokončila (edge funkce fio-sync neodpovídá nebo se nespouští).</p>'
      || '<p>Platby QR kódem / převodem se mezitím nepotvrzují samy — potvrzujte je ručně v detailu rezervace. Stav: Velín → Finance → Banka.</p>');
    INSERT INTO debug_log (source, action, component, status, request_data)
    VALUES ('fio-sync', 'sync_stale', 'fio', 'error', jsonb_build_object('last_ok_at', s.last_ok_at, 'last_run_at', s.last_run_at));
    UPDATE fio_sync_state SET stale_alert_at = now() WHERE id = 1;
  END IF;

  -- (b) platnost tokenů (jen 8–20 h Prahy, ať mail nechodí v noci)
  IF v_hour BETWEEN 8 AND 20 THEN
    v_how := CASE WHEN s.token_auto_prolong
      THEN 'Token má zapnuté automatické prodlužování: stačí se přihlásit do internetového bankovnictví / Smartbankingu Fio (platnost se posune o 180 dní) a ve Velínu (Finance → Banka) upravit datum.'
      ELSE 'V internetovém bankovnictví Fio (Nastavení → API) token prodlužte, nebo vystavte nový a vložte ho do Supabase secretu; pak ve Velínu (Finance → Banka) upravte datum. Doporučujeme zapnout automatické prodlužování.' END;

    IF s.token_valid_until IS NOT NULL THEN
      v_d := s.token_valid_until - v_today;
      v_t := CASE WHEN v_d <= 0 THEN 0 WHEN v_d <= 1 THEN 1 WHEN v_d <= 3 THEN 3 WHEN v_d <= 7 THEN 7
                  WHEN v_d <= 14 THEN 14 WHEN v_d <= 30 THEN 30 END;
      IF v_t IS NOT NULL AND (s.token_warned_threshold IS NULL OR v_t < s.token_warned_threshold) THEN
        PERFORM _fio_ops_mail(
          CASE WHEN v_d <= 0 THEN '🚨 Fio: API token pro čtení účtu VYPRŠEL' ELSE '⏳ Fio: API token pro čtení účtu vyprší za ' || v_d || ' dní' END,
          '<p>Token <strong>FIO_API_TOKEN</strong> (stahování pohybů, automatické potvrzování plateb) má platnost do <strong>'
          || to_char(s.token_valid_until, 'DD.MM.YYYY') || '</strong>. Po vypršení se platby QR / převodem přestanou potvrzovat samy.</p><p>' || v_how || '</p>');
        UPDATE fio_sync_state SET token_warned_threshold = v_t WHERE id = 1;
      END IF;
    END IF;

    IF s.pay_token_valid_until IS NOT NULL THEN
      v_d := s.pay_token_valid_until - v_today;
      v_t := CASE WHEN v_d <= 0 THEN 0 WHEN v_d <= 1 THEN 1 WHEN v_d <= 3 THEN 3 WHEN v_d <= 7 THEN 7
                  WHEN v_d <= 14 THEN 14 WHEN v_d <= 30 THEN 30 END;
      IF v_t IS NOT NULL AND (s.pay_token_warned_threshold IS NULL OR v_t < s.pay_token_warned_threshold) THEN
        PERFORM _fio_ops_mail(
          CASE WHEN v_d <= 0 THEN '🚨 Fio: API token pro platební příkazy VYPRŠEL' ELSE '⏳ Fio: API token pro platební příkazy vyprší za ' || v_d || ' dní' END,
          '<p>Token <strong>FIO_PAYMENT_TOKEN</strong> (automatické vratky převodem) má platnost do <strong>'
          || to_char(s.pay_token_valid_until, 'DD.MM.YYYY') || '</strong>. Po vypršení zůstanou vratky na ručním odeslání (Velín je označí „čeká na vrácení“).</p><p>' || v_how || '</p>');
        UPDATE fio_sync_state SET pay_token_warned_threshold = v_t WHERE id = 1;
      END IF;
    END IF;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.fio_health_alerts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_health_alerts() TO service_role;

CREATE OR REPLACE FUNCTION public.fio_sync_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- Údržba a hlídání v SQL — nezávislé na edge funkci (chyba jedné části nezastaví zbytek):
  -- vypršení požadavků na platbu (20261130b2) a upozornění „neběží“ / platnost tokenu.
  BEGIN PERFORM public.expire_bank_payment_requests();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'fio_sync_tick: expire_bank_payment_requests: %', SQLERRM; END;
  BEGIN PERFORM public.fio_health_alerts();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'fio_sync_tick: fio_health_alerts: %', SQLERRM; END;

  SELECT value #>> '{}' INTO v_url FROM public.app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM public.app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'fio_sync_tick: app_settings supabase_url/service_role_key chybí';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/fio-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
END $function$;
REVOKE ALL ON FUNCTION public.fio_sync_tick() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fio_sync_tick() TO service_role;

-- Cron každou minutu (dosud */5). cron.schedule se stejným názvem job přepíše; unschedule je pojistka
-- pro starší pg_cron.
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('fio-bank-sync');
  EXCEPTION WHEN OTHERS THEN NULL; -- job ještě neexistuje
  END;
  PERFORM cron.schedule(
    'fio-bank-sync',
    '* * * * *',
    $cron$ SELECT public.fio_sync_tick(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;
