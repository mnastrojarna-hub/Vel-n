-- 2026-09-28 (rozhodnutí majitele): diagnostika pobočky — v DB se drží JEN POSLEDNÍ report každé jednotky, historie se
-- nezálohuje (Velín zobrazuje jen aktuální protokol; 7denní historie sítě je uvnitř každého reportu v `report.netlog`).
-- Změna proti 20260910e_kiosk_log_guards.sql: LIMIT 30 → 1 v úklidu po INSERTu + jednorázové promazání starších.
-- Ostatní beze změny (auth, limit 512 KiB, rate limit 30 s, insert_failed). Idempotentní.

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
  -- Jen poslední report na zařízení (2026-09-28; dřív 30)
  DELETE FROM public.kiosk_diagnostics d WHERE d.device_id = p_device_id AND d.id <> v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  -- Detail chyby patří do logu DB, ne k zařízení (uniklý token = průzkum schématu).
  RAISE WARNING 'kiosk_report_diagnostics(%) selhalo: %', p_device_id, SQLERRM;
  RETURN jsonb_build_object('ok', false, 'error', 'insert_failed');
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) IS
  'Report diagnostiky RPi → kiosk_diagnostics (JEN poslední na zařízení — 2026-09-28). Auth device_id+token. Chyby: unauthorized, report_too_large (>512 KiB), rate_limited (<30 s), insert_failed.';

-- Jednorázový úklid: ponechat jen nejnovější report každého zařízení.
DELETE FROM public.kiosk_diagnostics d
 USING (
   SELECT id, row_number() OVER (PARTITION BY device_id ORDER BY created_at DESC, id DESC) AS rn
     FROM public.kiosk_diagnostics
 ) x
 WHERE x.id = d.id AND x.rn > 1;
