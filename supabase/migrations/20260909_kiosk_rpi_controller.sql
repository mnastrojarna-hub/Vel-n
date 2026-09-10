-- ============================================================================
-- Samoobslužná pobočka — ŘÍDICÍ JEDNOTKA Raspberry Pi 5 (autonomní pobočka Brno)
-- Migrace: 20260909_kiosk_rpi_controller.sql  (navazuje na 0628/0629/0630)
--
-- Tablet (Flutter kiosk) nahrazuje na 9zónové pobočce Brno Raspberry Pi 5
-- (program `raspberry/motogo-box`): zámky/světla/audio přes Modbus TCP
-- (Waveshare WAV645 + 2× WAV617), signalizace přes Shelly Pro RGBWW PM (HTTP RPC),
-- dveřní NC kontakty, stavový automat per zóna. Identita, auth (device_id +
-- device_token), příkazy, audit i logy zůstávají 1:1 jako u tabletu — přidává se:
--
--   * branch_kiosk_config.hardware jsonb — HW mapa pobočky (devices/timings/polling/
--                                          contacts/security/audio/signal) spravovaná z Velína
--   * branch_doors.hw jsonb            — HW mapa jedné zóny (zámek/kontakt/světlo/audio/červená/zelená)
--   * kiosk_devices.status/status_at   — poslední snapshot stavu řídicí jednotky (zóny, moduly, LTE…)
--   * kiosk_commands.command           — nové příkazy light_on/light_off/set_signal/zone_test/
--                                        audio_test/all_off/reboot/sync_config/update_software
--   * RPC kiosk_sync_config            — konfigurace + dveře + HMAC hashe kódů pro offline ověření
--                                        (PIN se do zařízení NIKDY neposílá v čistém textu)
--   * RPC kiosk_report_status          — zařízení hlásí snapshot stavu
--
-- kiosk_heartbeat / kiosk_resolve_code / kiosk_sync_codes se NEMĚNÍ (tablety fungují dál).
-- HMAC: pgcrypto je na Supabase ve schématu `extensions` → `extensions.hmac(...)`,
-- `SET search_path = public, extensions` (viz 20260816b_admin_create_customer_gen_salt_fix.sql).
-- Idempotentní — bezpečné spustit opakovaně.
-- ============================================================================

-- ─── 1) HW mapa pobočky (Velín přepisuje výchozí config/brno-9zone.yaml) ─────
ALTER TABLE public.branch_kiosk_config
  ADD COLUMN IF NOT EXISTS hardware jsonb NOT NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN public.branch_kiosk_config.hardware IS
  'HW mapa pobočky pro řídicí jednotku RPi (motogo_box). Top-level klíče přepisují lokální YAML: '
  'devices {name:{type:wav645|wav617|shelly_rgbww, host, port, unit_id}}, '
  'timings {lock_pulse_ms, door_open_timeout_s, door_close_debounce_ms, light_after_close_s, music_after_close_s, maximum_session_s, forced_open_debounce_ms, pin_entry_timeout_s, overtime_alert_minutes[]}, '
  'polling {door_input_poll_ms, software_debounce_ms, modbus_timeout_ms, retry_delays_ms[], device_offline_after_failures}, '
  'contacts {closed_level}, security {maximum_failed_attempts, attempt_window_minutes, lockout_minutes, pin_length, mask_pin_on_screen, service_token_minutes}, '
  'audio {volume, fade_in_ms, fade_out_ms, selector_settle_ms, selector_on_ms, device, shuffle}, '
  'signal {brightness, blink_ms, pulse_ms, transition_s}. Klíč zones sem NEPATŘÍ (zóny = branch_doors.hw). {} = použít lokální výchozí mapu.';

-- ─── 2) HW mapa jedné zóny (dveří) ───────────────────────────────────────────
ALTER TABLE public.branch_doors
  ADD COLUMN IF NOT EXISTS hw jsonb NOT NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN public.branch_doors.hw IS
  'HW mapa zóny pro řídicí jednotku RPi: {zone:int, lock:{dev,coil}, contact:{dev,input}, light:{dev,coil}, '
  'audio:{dev,coil}, red:{dev,light}, green:{dev,light}, closed_level?:0|1}. dev = klíč z branch_kiosk_config.hardware.devices '
  '(zámek/světlo/audio = relé Waveshare, contact = vstup WAV617, red/green = Shelly light id 0–4). '
  '{} = dveře bez HW zóny (tabletový režim přes relay_url/light_url).';

-- ─── 3) Poslední snapshot stavu zařízení ─────────────────────────────────────
ALTER TABLE public.kiosk_devices
  ADD COLUMN IF NOT EXISTS status jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.kiosk_devices
  ADD COLUMN IF NOT EXISTS status_at timestamptz;
COMMENT ON COLUMN public.kiosk_devices.status IS
  'Poslední snapshot stavu řídicí jednotky (RPC kiosk_report_status): {ts, version, uptime_s, ready, branch_name, '
  'internet, config_source:local|remote, config_problems[], modules:{name:bool}, audio:{playing_zone, player_ok}, '
  'health:{lte:{state,operator,rssi,rsrp,reconnects,usb_resets}, sys:{cpu_temp,throttled,disk_free_pct,mem_free_pct,load1,uptime_s}, internet, ts}, '
  'zones:[{zone, door_id, box_number, kind, label, state, door_closed, fault, light, signal, music, session_started_at, booking_id, last_event}], notice}. '
  'U tabletů zůstává {}.';
COMMENT ON COLUMN public.kiosk_devices.status_at IS
  'Čas posledního snapshotu status (kiosk_report_status). NULL = zařízení stav nehlásí (tablet).';

-- ─── 4) kiosk_commands: nové příkazy pro řídicí jednotku ─────────────────────
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    -- stávající (tablet i RPi)
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    -- nové (RPi řídicí jednotka)
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software'
  ));

-- ─── 5) RPC: synchronizace konfigurace + offline cache kódů (HMAC) ───────────
-- Vrací HW mapu pobočky, dveře vč. hw, a kódy JEN jako HMAC-SHA256 hashe
-- klíčované tokenem zařízení: h = hex(hmac(device_id || ':' || code, device_token)).
-- Zařízení si při ověření spočítá stejný hash (pins.hmac_code) → PIN není nikde
-- uložen v čistém textu (SPEC §10). Zákaznické kódy: aktivní + vydané + platnost
-- neskončila déle než před 1 dnem (stejné okno a JOIN na dveře jako kiosk_sync_codes).
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

  -- všechny aktivní dveře pobočky vč. HW mapy zóny (tabletové relay/light URL zůstávají)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'door_kind', d.door_kind, 'box_number', d.box_number, 'label', d.label,
    'hw', coalesce(d.hw, '{}'::jsonb), 'relay_url', d.relay_url, 'light_url', d.light_url,
    'sort_order', d.sort_order)
    ORDER BY d.sort_order, coalesce(d.box_number, 9999), d.created_at), '[]'::jsonb)
  INTO v_doors FROM public.branch_doors d WHERE d.branch_id = v_bid AND d.is_active;

  -- servisní hesla — jen hashe
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || s.code, 'UTF8'), v_key, 'sha256'), 'hex'))
    ORDER BY s.created_at), '[]'::jsonb)
  INTO v_services FROM public.branch_service_codes s WHERE s.branch_id = v_bid AND s.is_active;

  -- zákaznické kódy — hash + druh + platnost + cílové dveře (motorka dle motorcycles.box_number)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'h', encode(extensions.hmac(convert_to(p_device_id::text || ':' || bdc.door_code, 'UTF8'), v_key, 'sha256'), 'hex'),
    'kind', bdc.code_type, 'booking_id', bdc.booking_id,
    'valid_from', bdc.valid_from, 'valid_until', bdc.valid_until,
    -- box_number JEN u kódu k motorce (shodně s kiosk_resolve_code); kód k oblečení má moto_id
    -- vyplněné (trigger) a dveře oblečení box_number NULL → coalesce by offline otevřel kóji motorky
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
REVOKE ALL ON FUNCTION public.kiosk_sync_config(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_sync_config(uuid, uuid) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_sync_config(uuid, uuid) IS
  'RPi řídicí jednotka: HW mapa pobočky + dveře (hw) + offline cache kódů jako HMAC-SHA256 (klíč = device_token). Auth device_id+token.';

-- ─── 6) RPC: zařízení hlásí snapshot stavu ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_report_status(p_device_id uuid, p_device_token uuid, p_status jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, false);
  IF v_bid IS NULL THEN RETURN; END IF;
  UPDATE public.kiosk_devices
     SET status = coalesce(p_status, '{}'::jsonb), status_at = now(), last_seen_at = now()
   WHERE id = p_device_id;
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_status(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_status(uuid, uuid, jsonb) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_report_status(uuid, uuid, jsonb) IS
  'RPi řídicí jednotka: uloží snapshot stavu do kiosk_devices.status/status_at (+ last_seen_at). Auth device_id+token.';
