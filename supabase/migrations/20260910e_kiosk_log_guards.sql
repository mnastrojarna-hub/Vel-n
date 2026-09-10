-- ============================================================================
-- Samoobslužná pobočka — limity RPC kiosk_log_event / kiosk_log_open, retence kiosk_logs
-- Migrace: 20260910e_kiosk_log_guards.sql (navazuje na 20260630 / 20260628 / 20260910b)
--
-- Nález A38 revize RPi řídicí jednotky (2026-09-10) — uniklý device_token mohl:
--   * kiosk_log_event: bez limitu velikosti detailu a počtu řádků nafouknout kiosk_logs
--     (ověřeno: 5000 × 1 MiB detail = 67 MB bez chyby) → záloha, dotazy Velína, soak rolloutů;
--   * kiosk_log_open: zapsat audit otevření s door_id CIZÍ pobočky do branch_door_events;
--   * kiosk_report_diagnostics vracela zařízení surové SQLERRM (vnitřní informace o DB).
-- Nově:
--   * kiosk_log_event: detail > 64 KiB → {truncated:true, size}; max 120 záznamů / zařízení / minutu
--     (další se tiše zahodí — RPi je posílá přes outbox jako fire-and-forget, nic neopakuje);
--     source / app_version ořez na 100 znaků; index (device_id, created_at) pro rate limit i Velín.
--   * kiosk_log_open: door_id, který nepatří pobočce zařízení (nebo neexistuje) → NULL
--     + detail.door_mismatch=true a původní door_id v detail.door_id; detail > 64 KiB → truncated.
--   * retence kiosk_logs 90 dní: pg_cron 'kiosk-logs-retention' denně 04:15 UTC
--     (branch_door_events = audit, bez retence; kiosk_diagnostics má strop 30 / zařízení).
--   * kiosk_report_diagnostics: chyba INSERTu → {ok:false, error:'insert_failed'} + RAISE WARNING
--     (detail zůstane v logu Postgresu, ne u zařízení).
-- Idempotentní. Tablety i RPi: beze změny protokolu (obě RPC jsou void, návrat diagnostiky má stejný tvar).
-- ============================================================================

-- ─── 1) index pro rate limit + výpis logů zařízení ───────────────────────────
CREATE INDEX IF NOT EXISTS idx_kiosk_logs_device ON public.kiosk_logs(device_id, created_at DESC);

-- ─── 2) kiosk_log_event: limit velikosti detailu + rate limit ────────────────
CREATE OR REPLACE FUNCTION public.kiosk_log_event(
  p_device_id uuid, p_device_token uuid,
  p_level text, p_source text, p_message text,
  p_detail jsonb DEFAULT '{}'::jsonb, p_app_version text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_detail jsonb; v_recent int;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN; END IF;
  -- Rate limit: max 120 záznamů / zařízení / minutu (bouře událostí, uniklý token) → další se tiše zahodí.
  SELECT count(*) INTO v_recent FROM public.kiosk_logs
   WHERE device_id = p_device_id AND created_at > now() - interval '1 minute';
  IF v_recent >= 120 THEN RETURN; END IF;
  v_detail := coalesce(p_detail, '{}'::jsonb);
  IF pg_column_size(v_detail) > 65536 THEN   -- 64 KiB: detail události má stovky bajtů
    v_detail := jsonb_build_object('truncated', true, 'size', pg_column_size(v_detail));
  END IF;
  INSERT INTO public.kiosk_logs(device_id, branch_id, level, source, message, detail, app_version)
  VALUES (p_device_id, v_bid,
          COALESCE(NULLIF(p_level,''),'info'), left(p_source, 100), left(coalesce(p_message,''), 4000),
          v_detail, left(p_app_version, 100));
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_log_event(uuid, uuid, text, text, text, jsonb, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_log_event(uuid, uuid, text, text, text, jsonb, text) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_log_event(uuid, uuid, text, text, text, jsonb, text) IS
  'Log/událost zařízení → kiosk_logs. Auth device_id+token (špatný = no-op). Detail > 64 KiB → {truncated,size}; max 120 záznamů/zařízení/min (další zahozeny). Retence 90 dní (cron kiosk-logs-retention).';

-- ─── 3) kiosk_log_open: door_id musí patřit pobočce zařízení ─────────────────
CREATE OR REPLACE FUNCTION public.kiosk_log_open(
  p_device_id uuid, p_device_token uuid, p_door_id uuid,
  p_kind text, p_booking_id uuid, p_success boolean, p_detail jsonb DEFAULT '{}'::jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_door uuid; v_detail jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  v_detail := coalesce(p_detail, '{}'::jsonb);
  IF pg_column_size(v_detail) > 65536 THEN
    v_detail := jsonb_build_object('truncated', true, 'size', pg_column_size(v_detail));
  END IF;
  -- Dveře cizí pobočky (nebo neexistující) se do auditu nepropíší — zůstane stopa v detailu.
  v_door := p_door_id;
  IF v_door IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.branch_doors WHERE id = v_door AND branch_id = v_bid) THEN
    v_door := NULL;
    v_detail := v_detail || jsonb_build_object('door_mismatch', true, 'door_id', p_door_id);
  END IF;
  INSERT INTO public.branch_door_events(branch_id, device_id, door_id, kind, booking_id, success, detail)
  VALUES (v_bid, p_device_id, v_door, left(p_kind, 40), p_booking_id, coalesce(p_success,true), v_detail);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_log_open(uuid, uuid, uuid, text, uuid, boolean, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_log_open(uuid, uuid, uuid, text, uuid, boolean, jsonb) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_log_open(uuid, uuid, uuid, text, uuid, boolean, jsonb) IS
  'Audit otevření → branch_door_events. Auth device_id+token. door_id mimo pobočku zařízení → NULL + detail.door_mismatch; detail > 64 KiB → {truncated,size}.';

-- ─── 4) kiosk_report_diagnostics: bez SQLERRM směrem k zařízení ──────────────
CREATE OR REPLACE FUNCTION public.kiosk_report_diagnostics(p_device_id uuid, p_device_token uuid, p_report jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_id uuid; v_summary jsonb; v_last timestamptz;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  IF pg_column_size(p_report) > 524288 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'report_too_large');
  END IF;
  SELECT max(created_at) INTO v_last FROM public.kiosk_diagnostics WHERE device_id = p_device_id;
  IF v_last IS NOT NULL AND v_last > now() - interval '30 seconds' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited');
  END IF;
  v_summary := coalesce(p_report->'summary', '{}'::jsonb);
  INSERT INTO public.kiosk_diagnostics(device_id, branch_id, report_id, source, ok, problems, summary, report, app_version, started_at, finished_at)
  VALUES (p_device_id, v_bid, p_report->>'id', p_report->>'source',
          CASE WHEN v_summary ? 'ok' THEN (v_summary->>'ok')::boolean ELSE NULL END,
          coalesce(v_summary->'problems', '[]'::jsonb), v_summary, coalesce(p_report, '{}'::jsonb),
          p_report->>'version',
          NULLIF(p_report->>'ts', '')::timestamptz, NULLIF(p_report->>'finished_at', '')::timestamptz)
  RETURNING id INTO v_id;
  DELETE FROM public.kiosk_diagnostics d
   WHERE d.device_id = p_device_id
     AND d.id NOT IN (SELECT id FROM public.kiosk_diagnostics WHERE device_id = p_device_id ORDER BY created_at DESC LIMIT 30);
  RETURN jsonb_build_object('ok', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  -- Detail chyby patří do logu DB, ne k zařízení (uniklý token = průzkum schématu).
  RAISE WARNING 'kiosk_report_diagnostics(%) selhalo: %', p_device_id, SQLERRM;
  RETURN jsonb_build_object('ok', false, 'error', 'insert_failed');
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) IS
  'Report diagnostiky RPi → kiosk_diagnostics (posledních 30 / zařízení). Auth device_id+token. Chyby: unauthorized, report_too_large (>512 KiB), rate_limited (<30 s), insert_failed.';

-- ─── 5) retence kiosk_logs (90 dní), denně 04:15 UTC ─────────────────────────
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('kiosk-logs-retention');
  EXCEPTION WHEN OTHERS THEN NULL; -- job ještě neexistuje
  END;
  PERFORM cron.schedule('kiosk-logs-retention', '15 4 * * *',
    $cron$ DELETE FROM public.kiosk_logs WHERE created_at < now() - interval '90 days'; $cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule kiosk-logs-retention selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;
