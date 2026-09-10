-- ============================================================================
-- Samoobslužná pobočka — expirace starých příkazů + limity RPC řídicí jednotky
-- Migrace: 20260910b_kiosk_commands_ttl.sql (navazuje na 20260909 / 20260910)
--
-- Nálezy revize RPi řídicí jednotky (2026-09-10):
--   * kiosk_fetch_commands vracela KAŽDÝ pending příkaz bez ohledu na stáří → po výpadku LTE /
--     rebootu se prováděly hodiny staré příkazy (open_door!) bez dozoru. Nově se pending příkazy
--     starší než 10 minut označí 'expired' a nevrátí; vrácené řádky nesou created_at.
--   * kiosk_report_diagnostics / kiosk_report_status bez limitu velikosti → ochrana proti nafouknutí
--     tabulky/zálohy z uniklého device_tokenu: report max 512 KiB, status max 256 KiB,
--     diagnostika max 1 report za 30 s na zařízení.
-- Idempotentní. Tablety: beze změny chování (příkazy z Velína se provádějí do 10 min).
-- ============================================================================

-- ─── 1) kiosk_fetch_commands: expirace pending příkazů starších než 10 minut ─
CREATE OR REPLACE FUNCTION public.kiosk_fetch_commands(p_device_id uuid, p_device_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_rows jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  -- Příkaz, který zařízení nevyzvedlo do 10 minut (offline, reboot), se NESMÍ provést později bez dozoru.
  UPDATE public.kiosk_commands
     SET status = 'expired', executed_at = now(),
         result = coalesce(result, '{}'::jsonb) || jsonb_build_object('error', 'expired', 'message', 'Zařízení příkaz nevyzvedlo do 10 minut.')
   WHERE device_id = p_device_id AND status = 'pending' AND created_at < now() - interval '10 minutes';
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'command', command, 'params', params, 'created_at', created_at)
                            ORDER BY created_at), '[]'::jsonb)
    INTO v_rows
    FROM public.kiosk_commands
   WHERE device_id = p_device_id AND status = 'pending';
  RETURN jsonb_build_object('ok', true, 'commands', v_rows);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_fetch_commands(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_fetch_commands(uuid, uuid) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_fetch_commands(uuid, uuid) IS
  'Čekající příkazy zařízení (+created_at); pending starší než 10 min se označí expired a nevrátí. Auth device_id+token.';

-- ─── 2) kiosk_report_diagnostics: limit velikosti + rate limit ───────────────
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
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) TO anon, authenticated, service_role;

-- ─── 3) kiosk_report_status: limit velikosti snapshotu ───────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_report_status(p_device_id uuid, p_device_token uuid, p_status jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN; END IF;
  IF pg_column_size(p_status) > 262144 THEN RETURN; END IF;   -- 256 KiB: snapshot má jednotky kB
  UPDATE public.kiosk_devices
     SET status = coalesce(p_status, '{}'::jsonb), status_at = now(), last_seen_at = now()
   WHERE id = p_device_id;
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_status(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_status(uuid, uuid, jsonb) TO anon, authenticated, service_role;
