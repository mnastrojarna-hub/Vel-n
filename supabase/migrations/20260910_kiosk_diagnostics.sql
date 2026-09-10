-- ============================================================================
-- Samoobslužná pobočka — DIAGNOSTIKA SÍTĚ řídicí jednotky (Raspberry Pi 5)
-- Migrace: 20260910_kiosk_diagnostics.sql  (navazuje na 20260909_kiosk_rpi_controller.sql)
--
-- RPi program (`raspberry/motogo-box`, modul diagnostics.py) umí na požádání provést
-- kompletní diagnostiku sítě (rozhraní, routy, DNS, LTE, internet, spojení s Velínem,
-- dostupnost konfigurovaných modulů, TCP scan LAN + identifikace Waveshare/Shelly, ARP).
-- Spouští se kódem z displeje (lokální `diagnostics.code`), servisním heslem z Velína
-- s účelem `diagnostics` nebo příkazem `diagnostics` z Velína. Report se zobrazí na
-- displeji a odešle sem:
--
--   * branch_service_codes.action   — účel servisního hesla: service (servisní panel = vše)
--                                     | diagnostics (JEN spuštění diagnostiky sítě)
--   * kiosk_commands.command        — nový příkaz 'diagnostics'
--   * kiosk_diagnostics             — reporty diagnostiky (celý JSON + souhrn), RLS admin
--   * RPC kiosk_report_diagnostics  — zařízení uloží report (drží se posledních 30 na zařízení)
--   * RPC kiosk_sync_config         — service_codes nově {h, action, label} (offline cache účelu)
--   * RPC kiosk_resolve_code        — u servisního hesla vrací i 'action'
--
-- Tablety (Flutter kiosk) ignorují nová pole → beze změny chování. Idempotentní.
-- ============================================================================

-- ─── 1) Účel servisního hesla ────────────────────────────────────────────────
ALTER TABLE public.branch_service_codes
  ADD COLUMN IF NOT EXISTS action text NOT NULL DEFAULT 'service';
ALTER TABLE public.branch_service_codes DROP CONSTRAINT IF EXISTS branch_service_codes_action_check;
ALTER TABLE public.branch_service_codes ADD CONSTRAINT branch_service_codes_action_check
  CHECK (action IN ('service', 'diagnostics'));
COMMENT ON COLUMN public.branch_service_codes.action IS
  'Účel hesla: service = servisní panel (otevírání, světla, hudba, restart, diagnostika); '
  'diagnostics = JEN spuštění diagnostiky sítě na RPi řídicí jednotce (nic neotevírá).';

-- ─── 2) kiosk_commands: příkaz diagnostics ───────────────────────────────────
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics'
  ));

-- ─── 3) Reporty diagnostiky ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.kiosk_diagnostics (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id    uuid NOT NULL REFERENCES public.kiosk_devices(id) ON DELETE CASCADE,
  branch_id    uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  report_id    text,                                   -- id běhu z RPi (report.id)
  source       text,                                   -- local_code | service_code | service_panel | velin
  ok           boolean,
  problems     jsonb NOT NULL DEFAULT '[]'::jsonb,     -- summary.problems (texty)
  summary      jsonb NOT NULL DEFAULT '{}'::jsonb,     -- {ok, problems[], hosts, internet, lte, devices_ok, devices_total}
  report       jsonb NOT NULL DEFAULT '{}'::jsonb,     -- celý report (system/interfaces/lte/internet/supabase/devices/lan/arp/steps)
  app_version  text,
  started_at   timestamptz,
  finished_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kiosk_diagnostics_branch ON public.kiosk_diagnostics(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_kiosk_diagnostics_device ON public.kiosk_diagnostics(device_id, created_at DESC);
COMMENT ON TABLE public.kiosk_diagnostics IS
  'Reporty diagnostiky sítě z RPi řídicích jednotek (RPC kiosk_report_diagnostics). Velín: blok „Diagnostika sítě" v záložce Samoobsluha.';

ALTER TABLE public.kiosk_diagnostics ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kiosk_diagnostics_admin ON public.kiosk_diagnostics;
CREATE POLICY kiosk_diagnostics_admin ON public.kiosk_diagnostics FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ─── 4) RPC: zařízení uloží report ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_report_diagnostics(p_device_id uuid, p_device_token uuid, p_report jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_id uuid; v_summary jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  v_summary := coalesce(p_report->'summary', '{}'::jsonb);
  INSERT INTO public.kiosk_diagnostics(device_id, branch_id, report_id, source, ok, problems, summary, report, app_version, started_at, finished_at)
  VALUES (p_device_id, v_bid, p_report->>'id', p_report->>'source',
          CASE WHEN v_summary ? 'ok' THEN (v_summary->>'ok')::boolean ELSE NULL END,
          coalesce(v_summary->'problems', '[]'::jsonb), v_summary, coalesce(p_report, '{}'::jsonb),
          p_report->>'version',
          NULLIF(p_report->>'ts', '')::timestamptz, NULLIF(p_report->>'finished_at', '')::timestamptz)
  RETURNING id INTO v_id;
  -- držet jen posledních 30 reportů na zařízení (report může mít stovky kB)
  DELETE FROM public.kiosk_diagnostics d
   WHERE d.device_id = p_device_id
     AND d.id NOT IN (SELECT id FROM public.kiosk_diagnostics WHERE device_id = p_device_id ORDER BY created_at DESC LIMIT 30);
  RETURN jsonb_build_object('ok', true, 'id', v_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_report_diagnostics(uuid, uuid, jsonb) IS
  'RPi řídicí jednotka: uloží report diagnostiky sítě do kiosk_diagnostics (posledních 30 na zařízení). Auth device_id+token.';

-- ─── 5) kiosk_sync_config: service_codes nesou účel (action) a popisek ──────
CREATE OR REPLACE FUNCTION public.kiosk_sync_config(p_device_id uuid, p_device_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_key bytea; v_doors jsonb; v_services jsonb; v_codes jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;
  v_key := convert_to(p_device_token::text, 'UTF8');

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'door_kind', d.door_kind, 'box_number', d.box_number, 'label', d.label,
    'hw', coalesce(d.hw, '{}'::jsonb), 'relay_url', d.relay_url, 'light_url', d.light_url,
    'sort_order', d.sort_order)
    ORDER BY d.sort_order, coalesce(d.box_number, 9999), d.created_at), '[]'::jsonb)
  INTO v_doors FROM public.branch_doors d WHERE d.branch_id = v_bid AND d.is_active;

  -- servisní hesla — jen hashe + účel (service | diagnostics) + popisek
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || s.code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'action', coalesce(s.action, 'service'), 'label', s.label)
    ORDER BY s.created_at), '[]'::jsonb)
  INTO v_services FROM public.branch_service_codes s WHERE s.branch_id = v_bid AND s.is_active;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || bdc.door_code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'kind', bdc.code_type, 'booking_id', bdc.booking_id,
    'valid_from', bdc.valid_from, 'valid_until', bdc.valid_until,
    'door_id', d.id,
    'box_number', CASE WHEN bdc.code_type = 'motorcycle' THEN coalesce(d.box_number, m.box_number) ELSE d.box_number END)
    ORDER BY bdc.valid_until DESC NULLS LAST, bdc.updated_at DESC), '[]'::jsonb)
  INTO v_codes
  FROM public.branch_door_codes bdc
  LEFT JOIN public.motorcycles m ON m.id = bdc.moto_id
  LEFT JOIN public.branch_doors d ON d.branch_id = v_bid AND d.is_active AND (
        (bdc.code_type = 'accessories' AND d.door_kind = 'accessories')
     OR (bdc.code_type = 'motorcycle'  AND d.door_kind = 'motorcycle' AND d.box_number = m.box_number))
  WHERE bdc.branch_id = v_bid AND bdc.is_active = true AND bdc.sent_to_customer = true
    AND bdc.door_code IS NOT NULL AND bdc.door_code <> ''
    AND (bdc.valid_until IS NULL OR bdc.valid_until >= now() - interval '1 day');

  RETURN jsonb_build_object(
    'ok', true, 'synced_at', now(), 'branch_name', v_branch.name,
    'hardware', coalesce(v_cfg.hardware, '{}'::jsonb),
    'timings', jsonb_build_object(
      'door_open_seconds', COALESCE(v_cfg.door_open_seconds, 8),
      'light_seconds',     COALESCE(v_cfg.light_seconds, 120),
      'music_seconds',     COALESCE(v_cfg.music_seconds, 90)),
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'power_status_url', v_cfg.power_status_url,
    'power_poll_seconds', COALESCE(v_cfg.power_poll_seconds, 60),
    'doors', v_doors, 'service_codes', v_services, 'codes', v_codes
  );
END; $$;
COMMENT ON FUNCTION public.kiosk_sync_config(uuid, uuid) IS
  'RPi řídicí jednotka: HW mapa pobočky + dveře (hw) + offline cache kódů jako HMAC-SHA256 (klíč = device_token); service_codes {h, action, label}. Auth device_id+token.';

-- ─── 6) kiosk_resolve_code: servisní heslo vrací i účel (action) ─────────────
-- Jinak 1:1 s 20260628 (tablety: pole 'action' ignorují; 'diagnostics' heslo na tabletu
-- otevře servisní výběr dveří jako dřív — tablet diagnostiku neumí).
CREATE OR REPLACE FUNCTION public.kiosk_resolve_code(
  p_device_id uuid, p_device_token uuid, p_code text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE; v_svc public.branch_service_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
BEGIN
  IF v_code = '' THEN RETURN jsonb_build_object('ok',false,'error','missing_inputs'); END IF;
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;

  -- 1) servisní heslo → seznam všech aktivních dveří (app se zeptá které) + účel hesla
  SELECT * INTO v_svc FROM public.branch_service_codes s
   WHERE s.branch_id=v_bid AND s.is_active AND s.code=v_code ORDER BY s.created_at LIMIT 1;
  IF FOUND THEN
    SELECT coalesce(jsonb_agg(d ORDER BY d.ord),'[]'::jsonb) INTO v_doors FROM (
      SELECT bd.id,bd.door_kind,bd.box_number,bd.label,bd.relay_url,bd.light_url,coalesce(bd.box_number,9999) AS ord
        FROM public.branch_doors bd WHERE bd.branch_id=v_bid AND bd.is_active) d;
    RETURN jsonb_build_object('ok',true,'kind','service','action',coalesce(v_svc.action,'service'),'label',v_svc.label,
      'branch_id',v_bid,'branch_name',v_branch.name,
      'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
      'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),'doors',v_doors);
  END IF;

  -- 2) zákaznický kód (branch_door_codes) — aktivní, vydaný, v platnosti, této pobočky
  SELECT * INTO v_dc FROM public.branch_door_codes bdc
   WHERE bdc.branch_id=v_bid AND bdc.door_code=v_code AND bdc.is_active=true AND bdc.sent_to_customer=true
     AND (bdc.valid_from IS NULL OR bdc.valid_from<=now()) AND (bdc.valid_until IS NULL OR bdc.valid_until>=now())
   ORDER BY bdc.updated_at DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','invalid_code'); END IF;

  IF v_dc.code_type='accessories' THEN
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='accessories' AND is_active LIMIT 1;
  ELSE
    SELECT box_number INTO v_box FROM public.motorcycles WHERE id=v_dc.moto_id;
    SELECT * INTO v_door FROM public.branch_doors WHERE branch_id=v_bid AND door_kind='motorcycle' AND box_number=v_box AND is_active LIMIT 1;
  END IF;

  RETURN jsonb_build_object('ok',true,'kind',v_dc.code_type,'branch_id',v_bid,'branch_name',v_branch.name,
    'booking_id',v_dc.booking_id,'box_number',coalesce(v_door.box_number,v_box),
    'music_on_url',v_cfg.music_on_url,'music_off_url',v_cfg.music_off_url,'music_seconds',COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds',COALESCE(v_cfg.door_open_seconds,8),'light_seconds',COALESCE(v_cfg.light_seconds,120),
    'door',CASE WHEN v_door.id IS NULL THEN NULL ELSE jsonb_build_object('id',v_door.id,'door_kind',v_door.door_kind,
      'box_number',v_door.box_number,'label',v_door.label,'relay_url',v_door.relay_url,'light_url',v_door.light_url) END,
    'door_configured',(v_door.id IS NOT NULL));
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_resolve_code(uuid, uuid, text) TO anon, authenticated, service_role;
