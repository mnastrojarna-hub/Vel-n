-- ============================================================================
-- Samoobslužná pobočka (AlzaBox na motorky) — kiosk backend
-- Migrace: 20260628_selfservice_kiosk.sql
--
-- Model:
--   * pobočka má unikátní branch_code (už existuje) + branch_kiosk_config (hudba, časování)
--   * KAŽDÝ tablet = řádek v kiosk_devices s unikátním id + device_token (per-app identita)
--   * branch_doors  — mapování dveří → Shelly relé/světlo (LAN)
--   * branch_service_codes — servisní hesla (otevírají vše)
--   * kiosk_commands — REALTIME fronta vzdálených příkazů z Velína (otevři dveře, hudba…)
--   * branch_door_events — audit
--
-- Auth kiosku: (device_id + device_token). Kiosk čte/zapisuje VÝHRADNĚ přes
-- SECURITY DEFINER RPC (kiosk_heartbeat / kiosk_resolve_code / kiosk_log_open /
-- kiosk_complete_command). Vzdálené ovládání jde přes Realtime na kiosk_commands.
--
-- Pozn.: fyzické "číslo dveří" motorky = motorcycles.box_number (už existuje).
--        Dveře k oblečení = JEDNY sdílené per pobočka (door_kind='accessories').
--        Idempotentní — bezpečné spustit i nad částečně aplikovaným stavem.
-- ============================================================================

-- ─── 1) Konfigurace kiosku per pobočka (bez tokenu — token je per zařízení) ──
CREATE TABLE IF NOT EXISTS public.branch_kiosk_config (
  branch_id        uuid PRIMARY KEY REFERENCES public.branches(id) ON DELETE CASCADE,
  music_on_url     text,        -- HTTP (GET) spuštění hudby na celé pobočce
  music_off_url    text,        -- HTTP (GET) zastavení hudby (volitelné)
  relay_base_url   text,        -- volitelný základ URL pro relé na LAN (informativní)
  door_open_seconds  integer NOT NULL DEFAULT 8,
  light_seconds      integer NOT NULL DEFAULT 120,
  music_seconds      integer NOT NULL DEFAULT 90,
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
-- migrace ze starší verze, kde byl token na pobočce
ALTER TABLE public.branch_kiosk_config DROP COLUMN IF EXISTS kiosk_token;

-- ─── 2) Zařízení (tablety) — unikátní identita per app ───────────────────────
CREATE TABLE IF NOT EXISTS public.kiosk_devices (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),  -- UNIKÁTNÍ identifikátor zařízení
  branch_id     uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  name          text,                                        -- popis ("Brno — hlavní vchod")
  device_token  uuid NOT NULL DEFAULT gen_random_uuid(),     -- tajný párovací token
  platform      text,
  app_version   text,
  last_seen_at  timestamptz,                                 -- heartbeat (online stav)
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kiosk_devices_branch ON public.kiosk_devices(branch_id);

-- ─── 3) Mapování dveří → relé/světlo ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_doors (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  door_kind   text NOT NULL CHECK (door_kind IN ('motorcycle','accessories')),
  box_number  integer,
  label       text,
  relay_url   text,
  light_url   text,
  is_active   boolean NOT NULL DEFAULT true,
  sort_order  integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_branch_doors_moto
  ON public.branch_doors(branch_id, box_number) WHERE door_kind = 'motorcycle';
CREATE UNIQUE INDEX IF NOT EXISTS uq_branch_doors_acc
  ON public.branch_doors(branch_id) WHERE door_kind = 'accessories';
CREATE INDEX IF NOT EXISTS idx_branch_doors_branch ON public.branch_doors(branch_id);

-- ─── 4) Servisní hesla ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_service_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  code        text NOT NULL,
  label       text,
  is_active   boolean NOT NULL DEFAULT true,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_branch_service_codes
  ON public.branch_service_codes(branch_id, code) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_branch_service_codes_branch ON public.branch_service_codes(branch_id);

-- ─── 5) Realtime fronta vzdálených příkazů (Velín → kiosk) ───────────────────
CREATE TABLE IF NOT EXISTS public.kiosk_commands (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   uuid NOT NULL REFERENCES public.kiosk_devices(id) ON DELETE CASCADE,
  branch_id   uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  command     text NOT NULL CHECK (command IN ('open_door','music_on','music_off','identify','reload')),
  params      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- např. {relay_url, light_url, label}
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','done','failed','expired')),
  result      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  executed_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_kiosk_commands_device ON public.kiosk_commands(device_id, status, created_at DESC);

-- ─── 6) Audit otevření ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_door_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  device_id   uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL,
  door_id     uuid REFERENCES public.branch_doors(id) ON DELETE SET NULL,
  kind        text,
  booking_id  uuid,
  code_masked text,
  success     boolean NOT NULL DEFAULT true,
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.branch_door_events ADD COLUMN IF NOT EXISTS device_id uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_branch_door_events_branch ON public.branch_door_events(branch_id, created_at DESC);

-- ─── updated_at triggery ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_branch_kiosk_config_touch ON public.branch_kiosk_config;
CREATE TRIGGER trg_branch_kiosk_config_touch BEFORE UPDATE ON public.branch_kiosk_config
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_kiosk_devices_touch ON public.kiosk_devices;
CREATE TRIGGER trg_kiosk_devices_touch BEFORE UPDATE ON public.kiosk_devices
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_branch_doors_touch ON public.branch_doors;
CREATE TRIGGER trg_branch_doors_touch BEFORE UPDATE ON public.branch_doors
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_branch_service_codes_touch ON public.branch_service_codes;
CREATE TRIGGER trg_branch_service_codes_touch BEFORE UPDATE ON public.branch_service_codes
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ─── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.branch_kiosk_config   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kiosk_devices         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_doors          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_service_codes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kiosk_commands        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_door_events    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS branch_kiosk_config_admin ON public.branch_kiosk_config;
CREATE POLICY branch_kiosk_config_admin ON public.branch_kiosk_config FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS kiosk_devices_admin ON public.kiosk_devices;
CREATE POLICY kiosk_devices_admin ON public.kiosk_devices FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_doors_admin ON public.branch_doors;
CREATE POLICY branch_doors_admin ON public.branch_doors FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_service_codes_admin ON public.branch_service_codes;
CREATE POLICY branch_service_codes_admin ON public.branch_service_codes FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS kiosk_commands_admin ON public.kiosk_commands;
CREATE POLICY kiosk_commands_admin ON public.kiosk_commands FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS branch_door_events_admin ON public.branch_door_events;
CREATE POLICY branch_door_events_admin ON public.branch_door_events FOR SELECT USING (is_admin());

-- ─── Realtime: Broadcast z DB při novém příkazu ─────────────────────────────
-- Kiosk běží pod anon klíčem → nemůže číst admin-only kiosk_commands přes
-- postgres_changes. Místo toho po vložení příkazu pošleme NEVEŘEJNĚ neuhodnutelný
-- broadcast na topic 'kiosk:<device_id>' (jen probuzení, bez citlivých dat);
-- kiosk si pak příkazy bezpečně stáhne přes token-ověřenou RPC kiosk_fetch_commands.
CREATE OR REPLACE FUNCTION public.kiosk_command_broadcast()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    PERFORM realtime.send(jsonb_build_object('id', NEW.id), 'cmd', 'kiosk:' || NEW.device_id::text, false);
  EXCEPTION WHEN undefined_function THEN NULL; WHEN undefined_table THEN NULL; WHEN others THEN NULL;
  END;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_kiosk_command_broadcast ON public.kiosk_commands;
CREATE TRIGGER trg_kiosk_command_broadcast AFTER INSERT ON public.kiosk_commands
  FOR EACH ROW WHEN (NEW.status = 'pending') EXECUTE FUNCTION public.kiosk_command_broadcast();

-- ─── Interní helper: ověř zařízení, vrať branch_id (+ touch last_seen) ───────
CREATE OR REPLACE FUNCTION public.kiosk_device_branch(
  p_device_id uuid, p_device_token uuid, p_touch boolean DEFAULT false
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_branch uuid;
BEGIN
  SELECT branch_id INTO v_branch FROM public.kiosk_devices
   WHERE id = p_device_id AND device_token = p_device_token AND is_active = true;
  IF v_branch IS NULL THEN RETURN NULL; END IF;
  IF p_touch THEN
    UPDATE public.kiosk_devices SET last_seen_at = now() WHERE id = p_device_id;
  END IF;
  RETURN v_branch;
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_device_branch(uuid, uuid, boolean) FROM public;

-- ─── RPC: heartbeat (online stav + verze + konfigurace pobočky) ──────────────
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
    'light_seconds', COALESCE(v_cfg.light_seconds,120)
  );
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_heartbeat(uuid, uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_heartbeat(uuid, uuid, text, text) TO anon, authenticated, service_role;

-- ─── RPC: ověření kódu (servis → zákaznický kód → invalid) ──────────────────
DROP FUNCTION IF EXISTS public.kiosk_resolve_code(text, uuid, text);
CREATE OR REPLACE FUNCTION public.kiosk_resolve_code(
  p_device_id uuid, p_device_token uuid, p_code text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_bid uuid; v_branch public.branches%ROWTYPE; v_cfg public.branch_kiosk_config%ROWTYPE;
  v_door public.branch_doors%ROWTYPE; v_dc public.branch_door_codes%ROWTYPE;
  v_box integer; v_doors jsonb; v_code text := btrim(coalesce(p_code,''));
BEGIN
  IF v_code = '' THEN RETURN jsonb_build_object('ok',false,'error','missing_inputs'); END IF;
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthorized'); END IF;
  SELECT * INTO v_branch FROM public.branches WHERE id = v_bid;
  SELECT * INTO v_cfg FROM public.branch_kiosk_config WHERE branch_id = v_bid;

  -- 1) servisní heslo → seznam všech aktivních dveří (app se zeptá které)
  IF EXISTS (SELECT 1 FROM public.branch_service_codes s WHERE s.branch_id=v_bid AND s.is_active AND s.code=v_code) THEN
    SELECT coalesce(jsonb_agg(d ORDER BY d.ord),'[]'::jsonb) INTO v_doors FROM (
      SELECT bd.id,bd.door_kind,bd.box_number,bd.label,bd.relay_url,bd.light_url,coalesce(bd.box_number,9999) AS ord
        FROM public.branch_doors bd WHERE bd.branch_id=v_bid AND bd.is_active) d;
    RETURN jsonb_build_object('ok',true,'kind','service','branch_id',v_bid,'branch_name',v_branch.name,
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

-- ─── RPC: audit otevření ────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.kiosk_log_open(text, uuid, uuid, text, uuid, boolean, jsonb);
CREATE OR REPLACE FUNCTION public.kiosk_log_open(
  p_device_id uuid, p_device_token uuid, p_door_id uuid,
  p_kind text, p_booking_id uuid, p_success boolean, p_detail jsonb DEFAULT '{}'::jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  INSERT INTO public.branch_door_events(branch_id, device_id, door_id, kind, booking_id, success, detail)
  VALUES (v_bid, p_device_id, p_door_id, p_kind, p_booking_id, coalesce(p_success,true), coalesce(p_detail,'{}'::jsonb));
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_log_open(uuid, uuid, uuid, text, uuid, boolean, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_log_open(uuid, uuid, uuid, text, uuid, boolean, jsonb) TO anon, authenticated, service_role;

-- ─── RPC: dokončení vzdáleného příkazu (kiosk hlásí výsledek) ────────────────
CREATE OR REPLACE FUNCTION public.kiosk_complete_command(
  p_device_id uuid, p_device_token uuid, p_command_id uuid,
  p_success boolean, p_result jsonb DEFAULT '{}'::jsonb
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN; END IF;
  UPDATE public.kiosk_commands
     SET status = CASE WHEN p_success THEN 'done' ELSE 'failed' END,
         result = coalesce(p_result,'{}'::jsonb), executed_at = now()
   WHERE id = p_command_id AND device_id = p_device_id;
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_complete_command(uuid, uuid, uuid, boolean, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_complete_command(uuid, uuid, uuid, boolean, jsonb) TO anon, authenticated, service_role;

-- ─── RPC: stažení čekajících vzdálených příkazů (token-auth) ─────────────────
CREATE OR REPLACE FUNCTION public.kiosk_fetch_commands(p_device_id uuid, p_device_token uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_bid uuid; v_rows jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'command', command, 'params', params) ORDER BY created_at), '[]'::jsonb)
    INTO v_rows
    FROM public.kiosk_commands
   WHERE device_id = p_device_id AND status = 'pending';
  RETURN jsonb_build_object('ok', true, 'commands', v_rows);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_fetch_commands(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_fetch_commands(uuid, uuid) TO anon, authenticated, service_role;
