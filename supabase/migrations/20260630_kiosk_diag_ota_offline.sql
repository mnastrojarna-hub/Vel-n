-- ============================================================================
-- Samoobslužná pobočka — vzdálená diagnostika + OTA + offline cache + restart
-- Migrace: 20260630_kiosk_diag_ota_offline.sql  (navazuje na 0628/0629)
--
--   * kiosk_logs           — chyby/pády/události z kiosku (vzdálená diagnostika)
--   * RPC kiosk_log_event  — kiosk hlásí log (token-auth)
--   * RPC kiosk_sync_codes — offline cache: tablet si stáhne aktivní kódy + dveře
--   * kiosk_commands       — nový příkaz 'restart'
--   * kiosk_heartbeat      — vrací i info o nejnovější verzi appky (OTA) z app_settings
--
-- OTA verzi spravuje app_settings key='kiosk_app' = {version_code, version_name, apk_url, mandatory, notes}.
-- Idempotentní.
-- ============================================================================

-- ─── Diagnostické logy z kiosku ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.kiosk_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   uuid REFERENCES public.kiosk_devices(id) ON DELETE CASCADE,
  branch_id   uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  level       text NOT NULL DEFAULT 'info' CHECK (level IN ('info','warn','error','crash')),
  source      text,                 -- relay / camera / power / rpc / flutter / platform …
  message     text,
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  app_version text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kiosk_logs_branch ON public.kiosk_logs(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_kiosk_logs_level ON public.kiosk_logs(level, created_at DESC);

ALTER TABLE public.kiosk_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kiosk_logs_admin ON public.kiosk_logs;
CREATE POLICY kiosk_logs_admin ON public.kiosk_logs FOR SELECT USING (is_admin());

-- ─── kiosk_commands: nový příkaz restart ────────────────────────────────────
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN ('open_door','music_on','music_off','identify','reload','camera_control','http_get','restart'));

-- ─── RPC: kiosk hlásí log/chybu ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_log_event(
  p_device_id uuid, p_device_token uuid,
  p_level text, p_source text, p_message text,
  p_detail jsonb DEFAULT '{}'::jsonb, p_app_version text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN; END IF;
  INSERT INTO public.kiosk_logs(device_id, branch_id, level, source, message, detail, app_version)
  VALUES (p_device_id, v_bid,
          COALESCE(NULLIF(p_level,''),'info'), p_source, left(coalesce(p_message,''), 4000),
          coalesce(p_detail,'{}'::jsonb), p_app_version);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_log_event(uuid, uuid, text, text, text, jsonb, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_log_event(uuid, uuid, text, text, text, jsonb, text) TO anon, authenticated, service_role;

-- ─── RPC: offline cache — aktivní kódy + mapování dveří pro celou pobočku ────
-- Tablet si to periodicky stáhne; při výpadku internetu ověřuje kódy lokálně.
CREATE OR REPLACE FUNCTION public.kiosk_sync_codes(p_device_id uuid, p_device_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_bid uuid; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_doors jsonb; v_services jsonb; v_codes jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'door_kind', door_kind, 'box_number', box_number,
    'label', label, 'relay_url', relay_url, 'light_url', light_url)), '[]'::jsonb)
  INTO v_doors FROM public.branch_doors WHERE branch_id = v_bid AND is_active;

  SELECT coalesce(jsonb_agg(code), '[]'::jsonb) INTO v_services
  FROM public.branch_service_codes WHERE branch_id = v_bid AND is_active;

  -- Aktivní zákaznické kódy + ke kterým dveřím patří (relay/light pro offline otevření)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'code', bdc.door_code, 'kind', bdc.code_type, 'booking_id', bdc.booking_id,
    'valid_from', bdc.valid_from, 'valid_until', bdc.valid_until,
    'door_id', d.id, 'box_number', d.box_number, 'label', d.label,
    'relay_url', d.relay_url, 'light_url', d.light_url)), '[]'::jsonb)
  INTO v_codes
  FROM public.branch_door_codes bdc
  LEFT JOIN public.motorcycles m ON m.id = bdc.moto_id
  LEFT JOIN public.branch_doors d ON d.branch_id = v_bid AND d.is_active AND (
        (bdc.code_type = 'accessories' AND d.door_kind = 'accessories')
     OR (bdc.code_type = 'motorcycle'  AND d.door_kind = 'motorcycle' AND d.box_number = m.box_number))
  WHERE bdc.branch_id = v_bid AND bdc.is_active = true AND bdc.sent_to_customer = true
    AND (bdc.valid_until IS NULL OR bdc.valid_until >= now() - interval '1 day');

  RETURN jsonb_build_object(
    'ok', true, 'synced_at', now(),
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'music_seconds', COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds', COALESCE(v_cfg.door_open_seconds,8),
    'light_seconds', COALESCE(v_cfg.light_seconds,120),
    'doors', v_doors, 'service_codes', v_services, 'codes', v_codes
  );
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_sync_codes(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_sync_codes(uuid, uuid) TO anon, authenticated, service_role;

-- ─── kiosk_heartbeat rozšířen o OTA info (nejnovější verze appky) ────────────
CREATE OR REPLACE FUNCTION public.kiosk_heartbeat(
  p_device_id uuid, p_device_token uuid,
  p_app_version text DEFAULT NULL, p_platform text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE; v_bid uuid; v_app jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  UPDATE public.kiosk_devices
     SET last_seen_at = now(),
         app_version = COALESCE(p_app_version, app_version),
         platform    = COALESCE(p_platform, platform)
   WHERE id = p_device_id;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;
  SELECT value INTO v_app FROM public.app_settings WHERE key = 'kiosk_app';
  RETURN jsonb_build_object(
    'ok', true, 'branch_id', v_bid, 'branch_name', v_branch.name,
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'music_seconds', COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds', COALESCE(v_cfg.door_open_seconds,8),
    'light_seconds', COALESCE(v_cfg.light_seconds,120),
    'power_status_url', v_cfg.power_status_url,
    'power_poll_seconds', COALESCE(v_cfg.power_poll_seconds,60),
    'update', v_app
  );
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_heartbeat(uuid, uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_heartbeat(uuid, uuid, text, text) TO anon, authenticated, service_role;
