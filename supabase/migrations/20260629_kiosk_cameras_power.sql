-- ============================================================================
-- Samoobslužná pobočka — KAMERY + stav SOLÁRNÍ (ostrovní) elektrárny
-- Migrace: 20260629_kiosk_cameras_power.sql  (navazuje na 20260628_selfservice_kiosk.sql)
--
-- Přidává:
--   * branch_cameras       — kamery pobočky (náhled ve Velíně, ovládání přes tablet/LAN)
--   * branch_power_status  — poslední stav ostrovního FV systému (SoC, PV, zátěž…)
--   * config: power_status_url + power_poll_seconds (tablet stahuje z měniče na LAN)
--   * RPC kiosk_report_power (tablet hlásí stav energie), rozšířené kiosk_heartbeat
--   * kiosk_commands: nové příkazy 'camera_control' a 'http_get' (ovládání přes tablet)
--
-- Idempotentní.
-- ============================================================================

-- ─── config: odkud tablet stahuje stav elektrárny ───────────────────────────
ALTER TABLE public.branch_kiosk_config ADD COLUMN IF NOT EXISTS power_status_url text;
ALTER TABLE public.branch_kiosk_config ADD COLUMN IF NOT EXISTS power_poll_seconds integer NOT NULL DEFAULT 60;

-- ─── Kamery ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_cameras (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id    uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  name         text,
  kind         text NOT NULL DEFAULT 'snapshot' CHECK (kind IN ('snapshot','mjpeg','hls','iframe')),
  stream_url   text,        -- HLS/MJPEG/iframe URL pro živý náhled (reachable z Velína)
  snapshot_url text,        -- JPEG snapshot (auto-refresh) — nejkompatibilnější náhled
  control_url  text,        -- HTTP akce (PTZ preset / relé) — volá se přes tablet (LAN)
  sort_order   integer NOT NULL DEFAULT 0,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_branch_cameras_branch ON public.branch_cameras(branch_id);

-- ─── Stav ostrovní FV elektrárny (poslední snímek) ──────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_power_status (
  branch_id        uuid PRIMARY KEY REFERENCES public.branches(id) ON DELETE CASCADE,
  source           text,
  battery_soc      numeric(5,1),    -- %
  battery_voltage  numeric(6,2),    -- V
  battery_power_w  numeric(10,1),   -- W (+ nabíjení / − vybíjení)
  pv_power_w       numeric(10,1),   -- W z panelů
  load_power_w     numeric(10,1),   -- W spotřeba
  grid_present     boolean,         -- je síť/generátor připojen
  generator_on     boolean,
  raw              jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- ─── updated_at trigger pro kamery ──────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_branch_cameras_touch ON public.branch_cameras;
CREATE TRIGGER trg_branch_cameras_touch BEFORE UPDATE ON public.branch_cameras
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ─── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.branch_cameras      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_power_status ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS branch_cameras_admin ON public.branch_cameras;
CREATE POLICY branch_cameras_admin ON public.branch_cameras FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_power_status_admin ON public.branch_power_status;
CREATE POLICY branch_power_status_admin ON public.branch_power_status FOR SELECT USING (is_admin());

-- ─── kiosk_commands: nové typy příkazů ──────────────────────────────────────
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN ('open_door','music_on','music_off','identify','reload','camera_control','http_get'));

-- ─── Pomocné: bezpečné čtení čísla/boolu z jsonb dle více možných klíčů ──────
CREATE OR REPLACE FUNCTION public.kiosk_jnum(p jsonb, VARIADIC keys text[])
RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text;
BEGIN
  FOREACH k IN ARRAY keys LOOP
    IF p ? k AND (p->>k) IS NOT NULL THEN
      BEGIN RETURN (p->>k)::numeric; EXCEPTION WHEN others THEN NULL; END;
    END IF;
  END LOOP;
  RETURN NULL;
END; $$;

CREATE OR REPLACE FUNCTION public.kiosk_jbool(p jsonb, VARIADIC keys text[])
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text; v text;
BEGIN
  FOREACH k IN ARRAY keys LOOP
    IF p ? k AND (p->>k) IS NOT NULL THEN
      v := lower(p->>k);
      IF v IN ('true','1','on','yes') THEN RETURN true; END IF;
      IF v IN ('false','0','off','no') THEN RETURN false; END IF;
    END IF;
  END LOOP;
  RETURN NULL;
END; $$;

-- ─── RPC: tablet hlásí stav energie (mapuje běžné klíče, ukládá i raw) ───────
CREATE OR REPLACE FUNCTION public.kiosk_report_power(
  p_device_id uuid, p_device_token uuid, p_payload jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  INSERT INTO public.branch_power_status AS bps
    (branch_id, source, battery_soc, battery_voltage, battery_power_w, pv_power_w, load_power_w,
     grid_present, generator_on, raw, updated_at)
  VALUES (
    v_bid, 'tablet',
    public.kiosk_jnum(p_payload, 'battery_soc','soc','SOC','stateOfCharge'),
    public.kiosk_jnum(p_payload, 'battery_voltage','batteryVoltage','vBat','battery_v'),
    public.kiosk_jnum(p_payload, 'battery_power_w','batteryPower','pBat','battery_w'),
    public.kiosk_jnum(p_payload, 'pv_power_w','pvPower','pv_w','solar_w','pPv'),
    public.kiosk_jnum(p_payload, 'load_power_w','loadPower','load_w','consumption_w','pLoad'),
    public.kiosk_jbool(p_payload, 'grid_present','gridPresent','grid','mains'),
    public.kiosk_jbool(p_payload, 'generator_on','generatorOn','generator','genset'),
    coalesce(p_payload, '{}'::jsonb), now()
  )
  ON CONFLICT (branch_id) DO UPDATE SET
    source = 'tablet',
    battery_soc = EXCLUDED.battery_soc, battery_voltage = EXCLUDED.battery_voltage,
    battery_power_w = EXCLUDED.battery_power_w, pv_power_w = EXCLUDED.pv_power_w,
    load_power_w = EXCLUDED.load_power_w, grid_present = EXCLUDED.grid_present,
    generator_on = EXCLUDED.generator_on, raw = EXCLUDED.raw, updated_at = now();
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_report_power(uuid, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_report_power(uuid, uuid, jsonb) TO anon, authenticated, service_role;

-- ─── kiosk_heartbeat rozšířen o power_status_url + power_poll_seconds ────────
CREATE OR REPLACE FUNCTION public.kiosk_heartbeat(
  p_device_id uuid, p_device_token uuid,
  p_app_version text DEFAULT NULL, p_platform text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE; v_bid uuid;
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
  RETURN jsonb_build_object(
    'ok', true, 'branch_id', v_bid, 'branch_name', v_branch.name,
    'music_on_url', v_cfg.music_on_url, 'music_off_url', v_cfg.music_off_url,
    'music_seconds', COALESCE(v_cfg.music_seconds,90),
    'door_open_seconds', COALESCE(v_cfg.door_open_seconds,8),
    'light_seconds', COALESCE(v_cfg.light_seconds,120),
    'power_status_url', v_cfg.power_status_url,
    'power_poll_seconds', COALESCE(v_cfg.power_poll_seconds,60)
  );
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_heartbeat(uuid, uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_heartbeat(uuid, uuid, text, text) TO anon, authenticated, service_role;
