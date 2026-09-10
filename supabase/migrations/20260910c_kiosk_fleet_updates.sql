-- ============================================================================
-- Samoobslužná pobočka — HROMADNÁ AKTUALIZACE řídicích jednotek z Velína (software + OS)
-- Migrace: 20260910c_kiosk_fleet_updates.sql (navazuje na 20260910b_kiosk_commands_ttl.sql)
--
-- Zadání (2026-09-10): Velín rozešle „aktualizuj se" všem RPi jednotkám a ohlídá výsledek
-- (box hlásí verzi v heartbeatu jako "<verze>+<git sha7>"). Pojistky:
--   1) NIKDY slepě při každém pushi — vědomě tlačítkem, nebo automaticky v noci (nightly_hour,
--      výchozí 03:00 Prahy); box sám odloží restart programu, dokud je v kóji zákazník (wait_idle_s).
--   2) Postupně: nejdřív JEDNA jednotka (kanárek) → soak (soak_minutes bez chyb v kiosk_logs) → zbytek.
--   3) OS (Debian): bezpečnostní záplaty dělá unattended-upgrades na boxu; `apt full-upgrade`
--      (+ restart po jádru) rozesílá Velín příkazem `update_system` (stejný postup, kind='system').
--
--   * kiosk_releases         — releasy (commit v main měnící raspberry/motogo-box/**; plní Action release-motogo-box)
--   * kiosk_fleet_settings   — singleton (id=true): noční automatika, kanárek, soak, čekání na klid, OS aktualizace
--   * kiosk_rollouts         — jeden rollout: canary → soak → rollout → done | failed | cancelled
--   * kiosk_rollout_devices  — stav každé jednotky v rolloutu
--   * kiosk_commands.command — nový příkaz 'update_system'
--   * RPC kiosk_version_matches / kiosk_rollout_start / kiosk_rollout_cancel / kiosk_rollout_tick (+ interní helpery)
--   * pg_cron 'kiosk-fleet-update-tick' každých 5 min → kiosk_rollout_tick()
-- Žádné volání ven (příkazy vyzvedne box přes realtime broadcast + polling). Idempotentní.
-- ============================================================================

-- ─── 1) Shoda hlášené verze boxu s commitem release ─────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_version_matches(p_app_version text, p_commit text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT x.s ~ '^[0-9a-f]{7,40}$' AND coalesce(p_commit, '') LIKE x.s || '%'
    FROM (SELECT split_part(coalesce(p_app_version, ''), '+', 2) AS s) x
$$;
REVOKE ALL ON FUNCTION public.kiosk_version_matches(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_version_matches(text, text) TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_version_matches(text, text) IS
  'TRUE když app_version "<verze>+<sha7+>" odpovídá plnému commitu (prefix, min. 7 znaků).';

-- ─── 2) Tabulky ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.kiosk_releases (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commit        text NOT NULL UNIQUE CHECK (commit ~ '^[0-9a-f]{40}$'),
  version       text NOT NULL,                       -- __version__ z motogo_box/__init__.py
  message       text, author text, committed_at timestamptz, files_changed int,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kiosk_releases_created ON public.kiosk_releases(created_at DESC);
COMMENT ON TABLE public.kiosk_releases IS
  'Releasy RPi programu (commit v main měnící raspberry/motogo-box/**). Plní GitHub Action release-motogo-box.';

CREATE TABLE IF NOT EXISTS public.kiosk_fleet_settings (
  id                 boolean PRIMARY KEY DEFAULT true CHECK (id),
  nightly_enabled    boolean NOT NULL DEFAULT false,
  nightly_hour       int NOT NULL DEFAULT 3 CHECK (nightly_hour BETWEEN 0 AND 23),
  canary_device_id   uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL,
  soak_minutes       int NOT NULL DEFAULT 180 CHECK (soak_minutes BETWEEN 5 AND 1440),
  wait_idle_s        int NOT NULL DEFAULT 1800 CHECK (wait_idle_s BETWEEN 0 AND 14400),
  system_enabled     boolean NOT NULL DEFAULT false,
  system_every_days  int NOT NULL DEFAULT 28 CHECK (system_every_days BETWEEN 1 AND 365),
  system_auto_reboot boolean NOT NULL DEFAULT true,
  last_nightly_date  date, last_system_date date,
  updated_at         timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.kiosk_fleet_settings(id) VALUES (true) ON CONFLICT DO NOTHING;
COMMENT ON TABLE public.kiosk_fleet_settings IS
  'Singleton (id=true): noční automatika aktualizací, výchozí kanárek, soak, čekání na klid, OS aktualizace každých N dní.';

CREATE TABLE IF NOT EXISTS public.kiosk_rollouts (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind               text NOT NULL CHECK (kind IN ('software','system')),
  mode               text NOT NULL CHECK (mode IN ('manual','nightly')),
  status             text NOT NULL CHECK (status IN ('canary','soak','rollout','done','failed','cancelled')),
  release_id         uuid REFERENCES public.kiosk_releases(id) ON DELETE SET NULL,
  target_commit      text,
  canary_device_id   uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL,
  soak_minutes       int NOT NULL, wait_idle_s int NOT NULL,
  auto_reboot        boolean NOT NULL DEFAULT false,
  created_by         uuid,
  created_at         timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  canary_started_at  timestamptz, canary_done_at timestamptz, soak_until timestamptz,
  rollout_started_at timestamptz, finished_at timestamptz,
  error              text,
  result             jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {updated, failed, offline, skipped, total, errors[], offline_ids[]}
  note               text
);
CREATE INDEX IF NOT EXISTS idx_kiosk_rollouts_active ON public.kiosk_rollouts(status) WHERE status IN ('canary','soak','rollout');
COMMENT ON TABLE public.kiosk_rollouts IS
  'Hromadná aktualizace jednotek: canary (čeká na kanárka) → soak (sledování chyb) → rollout (zbytek) → done/failed/cancelled.';

CREATE TABLE IF NOT EXISTS public.kiosk_rollout_devices (
  rollout_id     uuid NOT NULL REFERENCES public.kiosk_rollouts(id) ON DELETE CASCADE,
  device_id      uuid NOT NULL REFERENCES public.kiosk_devices(id) ON DELETE CASCADE,
  role           text NOT NULL CHECK (role IN ('canary','fleet')),
  status         text NOT NULL CHECK (status IN ('pending','commanded','updated','failed','offline','skipped')),
  command_id     uuid, commanded_at timestamptz,
  version_before text, version_after text,
  detail         jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (rollout_id, device_id)
);
COMMENT ON TABLE public.kiosk_rollout_devices IS 'Stav každé řídicí jednotky v rolloutu (role canary/fleet).';

ALTER TABLE public.kiosk_releases        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kiosk_fleet_settings  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kiosk_rollouts        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kiosk_rollout_devices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS kiosk_releases_admin ON public.kiosk_releases;
CREATE POLICY kiosk_releases_admin ON public.kiosk_releases FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS kiosk_fleet_settings_admin ON public.kiosk_fleet_settings;
CREATE POLICY kiosk_fleet_settings_admin ON public.kiosk_fleet_settings FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS kiosk_rollouts_admin ON public.kiosk_rollouts;
CREATE POLICY kiosk_rollouts_admin ON public.kiosk_rollouts FOR ALL USING (is_admin()) WITH CHECK (is_admin());
DROP POLICY IF EXISTS kiosk_rollout_devices_admin ON public.kiosk_rollout_devices;
CREATE POLICY kiosk_rollout_devices_admin ON public.kiosk_rollout_devices FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ─── 3) kiosk_commands: příkaz update_system ─────────────────────────────────
ALTER TABLE public.kiosk_commands DROP CONSTRAINT IF EXISTS kiosk_commands_command_check;
ALTER TABLE public.kiosk_commands ADD CONSTRAINT kiosk_commands_command_check
  CHECK (command IN (
    'open_door','music_on','music_off','identify','reload','camera_control','http_get','restart',
    'light_on','light_off','set_signal','zone_test','audio_test','all_off','reboot','sync_config','update_software',
    'diagnostics','update_system'
  ));

-- ─── 4) Interní helpery (REVOKE public — volají se jen z RPC níže) ───────────
CREATE OR REPLACE FUNCTION public.kiosk_rollout_jts(p text) RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN RETURN p::timestamptz; EXCEPTION WHEN OTHERS THEN RETURN NULL; END; $$;

-- Je jednotka aktualizovaná? software = shoda verze s target_commit; system = status.update.last done po p_since.
CREATE OR REPLACE FUNCTION public.kiosk_device_updated(p_rollout public.kiosk_rollouts, p_device public.kiosk_devices, p_since timestamptz)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE v_last jsonb := p_device.status->'update'->'last';
BEGIN
  IF p_rollout.kind = 'software' THEN
    RETURN coalesce(public.kiosk_version_matches(p_device.app_version, p_rollout.target_commit), false);
  END IF;
  RETURN coalesce(v_last->>'kind' = 'system' AND v_last->>'state' = 'done'
                  AND public.kiosk_rollout_jts(v_last->>'finished_at') >= p_since, false);
END; $$;

-- Selhání aktualizace jednotky (text) nebo NULL: status.update.last failed po p_since, nebo příkaz failed/expired.
CREATE OR REPLACE FUNCTION public.kiosk_device_update_error(p_rollout public.kiosk_rollouts, p_device public.kiosk_devices, p_since timestamptz, p_command_id uuid)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_last jsonb := p_device.status->'update'->'last'; v_cmd public.kiosk_commands%ROWTYPE;
BEGIN
  IF coalesce(v_last->>'state' = 'failed' AND coalesce(v_last->>'kind', p_rollout.kind) = p_rollout.kind
              AND public.kiosk_rollout_jts(v_last->>'started_at') >= p_since, false) THEN
    RETURN 'update_failed: ' || left(coalesce(v_last->>'error', '?'), 300);
  END IF;
  IF p_command_id IS NOT NULL THEN
    SELECT * INTO v_cmd FROM public.kiosk_commands WHERE id = p_command_id;
    -- `timeout` = starý controller (před 2026-09-10) čekal na motogo-update jen 120 s a skript běží dál →
    -- není to selhání; rozhodne hlášená verze nebo celkový timeout kanárka/jednotky.
    IF FOUND AND v_cmd.status IN ('failed','expired') AND coalesce(v_cmd.result->>'error', '') <> 'timeout' THEN
      RETURN 'command_' || v_cmd.status || ': ' || left(coalesce(v_cmd.result->>'error', v_cmd.result->>'message', '?'), 300);
    END IF;
  END IF;
  RETURN NULL;
END; $$;

-- Pošle jednotce příkaz rolloutu (update_software / update_system) a označí řádek commanded.
CREATE OR REPLACE FUNCTION public.kiosk_rollout_send_command(p_rollout public.kiosk_rollouts, p_device public.kiosk_devices)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_cmd text; v_params jsonb; v_id uuid;
BEGIN
  IF p_rollout.kind = 'software' THEN
    v_cmd := 'update_software';
    v_params := jsonb_build_object('ref', p_rollout.target_commit, 'rollout_id', p_rollout.id, 'wait_idle_s', p_rollout.wait_idle_s);
  ELSE
    v_cmd := 'update_system';
    v_params := jsonb_build_object('rollout_id', p_rollout.id, 'wait_idle_s', p_rollout.wait_idle_s, 'auto_reboot', p_rollout.auto_reboot);
  END IF;
  INSERT INTO public.kiosk_commands(device_id, branch_id, command, params, created_by)
  VALUES (p_device.id, p_device.branch_id, v_cmd, v_params, p_rollout.created_by) RETURNING id INTO v_id;
  UPDATE public.kiosk_rollout_devices
     SET status = 'commanded', command_id = v_id, commanded_at = now(), version_before = p_device.app_version, updated_at = now()
   WHERE rollout_id = p_rollout.id AND device_id = p_device.id;
  RETURN v_id;
END; $$;

-- Souhrn stavů jednotek → kiosk_rollouts.result
CREATE OR REPLACE FUNCTION public.kiosk_rollout_counts(p_rollout_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'updated',   count(*) FILTER (WHERE status = 'updated'),
    'failed',    count(*) FILTER (WHERE status = 'failed'),
    'offline',   count(*) FILTER (WHERE status = 'offline'),
    'skipped',   count(*) FILTER (WHERE status = 'skipped'),
    'commanded', count(*) FILTER (WHERE status = 'commanded'),
    'pending',   count(*) FILTER (WHERE status = 'pending'),
    'total',     count(*))
  FROM public.kiosk_rollout_devices WHERE rollout_id = p_rollout_id
$$;
REVOKE ALL ON FUNCTION public.kiosk_rollout_jts(text) FROM public;
REVOKE ALL ON FUNCTION public.kiosk_device_updated(public.kiosk_rollouts, public.kiosk_devices, timestamptz) FROM public;
REVOKE ALL ON FUNCTION public.kiosk_device_update_error(public.kiosk_rollouts, public.kiosk_devices, timestamptz, uuid) FROM public;
REVOKE ALL ON FUNCTION public.kiosk_rollout_send_command(public.kiosk_rollouts, public.kiosk_devices) FROM public;
REVOKE ALL ON FUNCTION public.kiosk_rollout_counts(uuid) FROM public;

-- ─── 5) RPC: start rolloutu ──────────────────────────────────────────────────
-- Guard: přihlášený ne-admin → forbidden; cron (auth.uid() NULL) a service_role projdou; anon nemá GRANT.
CREATE OR REPLACE FUNCTION public.kiosk_rollout_start(
  p_kind text, p_release_id uuid, p_canary_device_id uuid, p_soak_minutes int, p_wait_idle_s int,
  p_auto_reboot boolean, p_mode text DEFAULT 'manual')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_active uuid; v_rel public.kiosk_releases%ROWTYPE; v_canary public.kiosk_devices%ROWTYPE; v_ro public.kiosk_rollouts%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  IF coalesce(p_kind, '') NOT IN ('software','system') THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_kind'); END IF;
  IF coalesce(p_mode, 'manual') NOT IN ('manual','nightly') THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_mode'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('kiosk_rollouts'));
  SELECT id INTO v_active FROM public.kiosk_rollouts WHERE status IN ('canary','soak','rollout') ORDER BY created_at LIMIT 1;
  IF v_active IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'rollout_active', 'id', v_active); END IF;
  IF p_kind = 'software' THEN
    SELECT * INTO v_rel FROM public.kiosk_releases WHERE id = p_release_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'release_not_found'); END IF;
  END IF;
  IF p_canary_device_id IS NULL THEN
    SELECT * INTO v_canary FROM public.kiosk_devices d
     WHERE d.is_active AND d.last_seen_at > now() - interval '90 seconds'
       AND (d.platform = 'rpi' OR (d.platform IS NULL AND d.status <> '{}'::jsonb))
     ORDER BY d.last_seen_at DESC LIMIT 1;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'no_canary'); END IF;
  ELSE
    SELECT * INTO v_canary FROM public.kiosk_devices
     WHERE id = p_canary_device_id AND is_active AND (platform = 'rpi' OR platform IS NULL);  -- tablet nemůže být kanárek
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'canary_not_found'); END IF;
  END IF;

  INSERT INTO public.kiosk_rollouts(kind, mode, status, release_id, target_commit, canary_device_id,
                                    soak_minutes, wait_idle_s, auto_reboot, created_by, canary_started_at)
  VALUES (p_kind, coalesce(p_mode, 'manual'), 'canary', v_rel.id, v_rel.commit, v_canary.id,
          least(greatest(coalesce(p_soak_minutes, 180), 5), 1440), least(greatest(coalesce(p_wait_idle_s, 1800), 0), 14400),
          coalesce(p_auto_reboot, false), auth.uid(), now())
  RETURNING * INTO v_ro;
  INSERT INTO public.kiosk_rollout_devices(rollout_id, device_id, role, status, version_before)
  VALUES (v_ro.id, v_canary.id, 'canary', 'pending', v_canary.app_version);
  -- flotila = aktivní RPi jednotky kromě kanárka; nikdy neviděné → skipped
  INSERT INTO public.kiosk_rollout_devices(rollout_id, device_id, role, status, version_before, detail)
  SELECT v_ro.id, d.id, 'fleet', CASE WHEN d.last_seen_at IS NULL THEN 'skipped' ELSE 'pending' END, d.app_version,
         CASE WHEN d.last_seen_at IS NULL THEN '{"reason":"never_seen"}'::jsonb ELSE '{}'::jsonb END
    FROM public.kiosk_devices d
   WHERE d.is_active AND (d.platform = 'rpi' OR d.platform IS NULL) AND d.id <> v_canary.id;

  IF public.kiosk_device_updated(v_ro, v_canary, v_ro.canary_started_at) THEN
    -- kanárek už běží na cílovém commitu → rovnou sledování (soak)
    UPDATE public.kiosk_rollout_devices SET status = 'updated', version_after = v_canary.app_version, updated_at = now()
     WHERE rollout_id = v_ro.id AND device_id = v_canary.id;
    UPDATE public.kiosk_rollouts SET status = 'soak', canary_done_at = now(), soak_until = now() + make_interval(mins => soak_minutes),
           updated_at = now() WHERE id = v_ro.id RETURNING * INTO v_ro;
  ELSE
    PERFORM public.kiosk_rollout_send_command(v_ro, v_canary);
  END IF;
  UPDATE public.kiosk_rollouts SET result = result || public.kiosk_rollout_counts(id) WHERE id = v_ro.id;
  RETURN jsonb_build_object('ok', true, 'id', v_ro.id, 'status', v_ro.status);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_rollout_start(text, uuid, uuid, int, int, boolean, text) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_rollout_start(text, uuid, uuid, int, int, boolean, text) TO authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_rollout_start(text, uuid, uuid, int, int, boolean, text) IS
  'Velín/cron: založí rollout (software = release, system = apt full-upgrade), pošle příkaz kanárkovi. '
  'Chyby: forbidden, invalid_kind, rollout_active(id), release_not_found, no_canary, canary_not_found.';

-- ─── 6) RPC: zrušení rolloutu ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.kiosk_rollout_cancel(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ro public.kiosk_rollouts%ROWTYPE; v_n int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('kiosk_rollouts'));
  SELECT * INTO v_ro FROM public.kiosk_rollouts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  IF v_ro.status NOT IN ('canary','soak','rollout') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_active', 'status', v_ro.status);
  END IF;
  UPDATE public.kiosk_commands
     SET status = 'expired', executed_at = now(), result = coalesce(result, '{}'::jsonb) || '{"error":"cancelled"}'::jsonb
   WHERE status = 'pending' AND params->>'rollout_id' = p_id::text;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE public.kiosk_rollouts
     SET status = 'cancelled', finished_at = now(), updated_at = now(),
         result = result || public.kiosk_rollout_counts(id) || jsonb_build_object('expired_commands', v_n)
   WHERE id = p_id;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'cancelled', 'expired_commands', v_n);
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_rollout_cancel(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_rollout_cancel(uuid) TO authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_rollout_cancel(uuid) IS
  'Velín: zruší aktivní rollout (status cancelled) a expiruje jeho dosud nevyzvednuté příkazy.';

-- ─── 7) RPC: tick (pg_cron každých 5 min + Velín „Zkontrolovat teď") ────────
-- (a) posune aktivní rollouty (canary → soak → rollout → done/failed), (b) noční start software
-- (jen kvůli jednotkám viděným za 24 h), (c) OS aktualizace každých N dní (datum až po úspěšném startu). Vrací {ok, ticked:[ids], started: id|null, nightly_error?}.
CREATE OR REPLACE FUNCTION public.kiosk_rollout_tick()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ids uuid[] := '{}'; v_started uuid; v_start jsonb; v_nerr text; v_rid uuid;
  r public.kiosk_rollouts%ROWTYPE; rd public.kiosk_rollout_devices%ROWTYPE; dev public.kiosk_devices%ROWTYPE;
  s public.kiosk_fleet_settings%ROWTYPE; rel public.kiosk_releases%ROWTYPE;
  v_err text; v_n int; v_open int; v_failed int; v_stale int; v_errs jsonb; v_offline jsonb; v_wait interval;
  v_now_pr timestamp; v_today date; v_hour int;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('kiosk_rollouts'));

  -- (a) aktivní rollouty — každý ve vlastním bloku, chyba jednoho nezastaví ostatní
  FOR v_rid IN SELECT id FROM public.kiosk_rollouts WHERE status IN ('canary','soak','rollout') ORDER BY created_at LOOP
    v_ids := v_ids || v_rid;
    BEGIN
      SELECT * INTO r FROM public.kiosk_rollouts WHERE id = v_rid FOR UPDATE;
      v_wait := make_interval(secs => r.wait_idle_s) + interval '45 minutes';
      SELECT * INTO rd FROM public.kiosk_rollout_devices WHERE rollout_id = r.id AND role = 'canary';
      SELECT * INTO dev FROM public.kiosk_devices WHERE id = rd.device_id;

      -- canary: čekáme, až kanárek nahlásí novou verzi / dokončený OS update
      IF r.status = 'canary' THEN
        IF dev.id IS NULL THEN v_err := 'canary_missing';
        ELSIF public.kiosk_device_updated(r, dev, r.canary_started_at) THEN
          UPDATE public.kiosk_rollout_devices SET status = 'updated', version_after = dev.app_version, updated_at = now()
           WHERE rollout_id = r.id AND device_id = dev.id;
          UPDATE public.kiosk_rollouts SET status = 'soak', canary_done_at = now(), updated_at = now(),
                 soak_until = now() + make_interval(mins => soak_minutes) WHERE id = r.id RETURNING * INTO r;
          v_err := NULL;
        ELSE
          v_err := public.kiosk_device_update_error(r, dev, r.canary_started_at, rd.command_id);
          IF v_err IS NOT NULL THEN v_err := 'canary_failed: ' || v_err;
          ELSIF now() > r.canary_started_at + v_wait THEN v_err := 'canary_timeout';
          END IF;
        END IF;
        IF v_err IS NOT NULL THEN
          UPDATE public.kiosk_rollout_devices SET status = 'failed', detail = detail || jsonb_build_object('error', v_err), updated_at = now()
           WHERE rollout_id = r.id AND role = 'canary';
          UPDATE public.kiosk_rollouts SET status = 'failed', error = v_err, finished_at = now(), updated_at = now()
           WHERE id = r.id RETURNING * INTO r;
        END IF;
      END IF;

      -- soak: kanárek musí běžet bez chyb (kiosk_logs error/crash) a být online až do soak_until.
      -- Ignoruje se hlášení o spuštění boxu (source controller, detail.event STARTUP) — po restartu/rebootu
      -- má level error, když box hlásí trvající config_problems; není to chyba nové verze.
      IF r.status = 'soak' THEN
        SELECT count(*), coalesce(jsonb_agg(x.m ORDER BY x.created_at DESC) FILTER (WHERE x.rn <= 5), '[]'::jsonb)
          INTO v_n, v_errs
          FROM (SELECT left(coalesce(message, ''), 300) AS m, created_at, row_number() OVER (ORDER BY created_at DESC) AS rn
                  FROM public.kiosk_logs
                 WHERE device_id = r.canary_device_id AND level IN ('error','crash') AND created_at >= r.canary_done_at
                   AND NOT (coalesce(source, '') = 'controller' AND upper(coalesce(detail->>'event', '')) = 'STARTUP')) x;
        IF v_n > 0 THEN
          UPDATE public.kiosk_rollouts SET status = 'failed', error = 'canary_errors: ' || v_n, finished_at = now(), updated_at = now(),
                 result = result || jsonb_build_object('errors', v_errs) WHERE id = r.id RETURNING * INTO r;
        ELSIF dev.id IS NULL OR coalesce(dev.last_seen_at, r.canary_done_at) < now() - interval '10 minutes' THEN
          UPDATE public.kiosk_rollouts SET status = 'failed', error = 'canary_offline', finished_at = now(), updated_at = now()
           WHERE id = r.id RETURNING * INTO r;
        ELSIF now() >= r.soak_until THEN
          UPDATE public.kiosk_rollouts SET status = 'rollout', rollout_started_at = now(), updated_at = now()
           WHERE id = r.id RETURNING * INTO r;
        END IF;
      END IF;

      -- rollout: online jednotkám poslat příkaz, hlídat výsledek, offline zkoušet do 24 h
      IF r.status = 'rollout' THEN
        FOR rd IN SELECT * FROM public.kiosk_rollout_devices
                   WHERE rollout_id = r.id AND role = 'fleet' AND status IN ('pending','offline','commanded') ORDER BY device_id LOOP
          SELECT * INTO dev FROM public.kiosk_devices WHERE id = rd.device_id;
          IF NOT FOUND THEN CONTINUE; END IF;
          IF rd.status IN ('pending','offline') THEN
            IF public.kiosk_device_updated(r, dev, r.rollout_started_at) THEN
              UPDATE public.kiosk_rollout_devices SET status = 'updated', version_after = dev.app_version, updated_at = now()
               WHERE rollout_id = r.id AND device_id = dev.id;
            ELSIF dev.is_active AND dev.last_seen_at > now() - interval '90 seconds' THEN
              PERFORM public.kiosk_rollout_send_command(r, dev);
            ELSIF rd.status = 'pending' THEN
              UPDATE public.kiosk_rollout_devices SET status = 'offline', updated_at = now() WHERE rollout_id = r.id AND device_id = dev.id;
            END IF;
          ELSIF public.kiosk_device_updated(r, dev, rd.commanded_at) THEN
            UPDATE public.kiosk_rollout_devices SET status = 'updated', version_after = dev.app_version, updated_at = now()
             WHERE rollout_id = r.id AND device_id = dev.id;
          ELSE
            v_err := public.kiosk_device_update_error(r, dev, rd.commanded_at, rd.command_id);
            IF v_err IS NULL AND now() > rd.commanded_at + v_wait THEN v_err := 'timeout'; END IF;
            IF v_err IS NOT NULL THEN
              UPDATE public.kiosk_rollout_devices SET status = 'failed', detail = detail || jsonb_build_object('error', v_err), updated_at = now()
               WHERE rollout_id = r.id AND device_id = dev.id;
            END IF;
          END IF;
        END LOOP;
        -- v_stale = offline jednotky neviděné od začátku rozesílání (mrtvé už před ním)
        SELECT count(*) FILTER (WHERE rd2.status IN ('pending','commanded','offline')), count(*) FILTER (WHERE rd2.status = 'failed'),
               count(*) FILTER (WHERE rd2.status = 'offline' AND coalesce(d2.last_seen_at < r.rollout_started_at, true))
          INTO v_open, v_failed, v_stale
          FROM public.kiosk_rollout_devices rd2 LEFT JOIN public.kiosk_devices d2 ON d2.id = rd2.device_id
         WHERE rd2.rollout_id = r.id;
        -- konec: nic otevřeného; nebo 24 h; nebo po 2 h, když zbývají jen jednotky mrtvé už před rozesíláním
        IF v_open = 0 OR now() >= r.rollout_started_at + interval '24 hours'
           OR (v_open = v_stale AND now() >= r.rollout_started_at + interval '2 hours') THEN
          -- nedostupné jednotky (pending/commanded/offline) → offline, aby result.offline odpovídalo offline_ids
          UPDATE public.kiosk_rollout_devices
             SET status = 'offline', detail = detail || '{"error":"unreachable"}'::jsonb, updated_at = now()
           WHERE rollout_id = r.id AND status IN ('pending','commanded','offline');
          SELECT coalesce(jsonb_agg(device_id), '[]'::jsonb) INTO v_offline FROM public.kiosk_rollout_devices
           WHERE rollout_id = r.id AND status = 'offline';
          UPDATE public.kiosk_rollouts
             SET status = CASE WHEN v_failed > 0 THEN 'failed' ELSE 'done' END,
                 error = CASE WHEN v_failed > 0 THEN 'devices_failed: ' || v_failed END,
                 result = result || CASE WHEN v_open > 0 THEN jsonb_build_object('offline_ids', v_offline) ELSE '{}'::jsonb END,
                 finished_at = now(), updated_at = now()
           WHERE id = r.id RETURNING * INTO r;
        END IF;
      END IF;

      UPDATE public.kiosk_rollouts SET result = result || public.kiosk_rollout_counts(id), updated_at = now() WHERE id = r.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'kiosk_rollout_tick: rollout % selhal: %', v_rid, SQLERRM;
    END;
  END LOOP;

  -- (b) noční automatika software, (c) OS aktualizace každých N dní (software má přednost)
  SELECT * INTO s FROM public.kiosk_fleet_settings WHERE id;
  v_now_pr := now() AT TIME ZONE 'Europe/Prague'; v_today := v_now_pr::date; v_hour := extract(hour FROM v_now_pr)::int;
  IF coalesce(s.id, false) AND v_hour = s.nightly_hour
     AND NOT EXISTS (SELECT 1 FROM public.kiosk_rollouts WHERE status IN ('canary','soak','rollout')) THEN
    IF s.nightly_enabled AND (s.last_nightly_date IS NULL OR s.last_nightly_date < v_today) THEN
      SELECT * INTO rel FROM public.kiosk_releases ORDER BY committed_at DESC NULLS LAST, created_at DESC LIMIT 1;
      IF rel.id IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.kiosk_devices d
            WHERE d.is_active AND (d.platform = 'rpi' OR d.platform IS NULL)
              AND d.last_seen_at > now() - interval '24 hours'   -- jednotka mrtvá déle nespouští rollout každou noc
              AND NOT public.kiosk_version_matches(d.app_version, rel.commit)) THEN
        v_start := public.kiosk_rollout_start('software', rel.id, s.canary_device_id, s.soak_minutes, s.wait_idle_s, false, 'nightly');
        UPDATE public.kiosk_fleet_settings SET last_nightly_date = v_today, updated_at = now() WHERE id;
        IF (v_start->>'ok')::boolean THEN v_started := (v_start->>'id')::uuid; ELSE v_nerr := v_start->>'error'; END IF;
      END IF;
    END IF;
    -- OS jen když software dnes nestartoval ani neselhal (stejný kanárek by selhal znovu);
    -- last_system_date se posune až po ÚSPĚŠNÉM startu (neúspěch neodloží OS o system_every_days)
    IF v_started IS NULL AND v_nerr IS NULL AND s.system_enabled
       AND (s.last_system_date IS NULL OR s.last_system_date <= v_today - s.system_every_days) THEN
      v_start := public.kiosk_rollout_start('system', NULL, s.canary_device_id, s.soak_minutes, s.wait_idle_s, s.system_auto_reboot, 'nightly');
      IF (v_start->>'ok')::boolean THEN
        v_started := (v_start->>'id')::uuid;
        UPDATE public.kiosk_fleet_settings SET last_system_date = v_today, updated_at = now() WHERE id;
      ELSE v_nerr := v_start->>'error';
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'ticked', to_jsonb(v_ids), 'started', v_started)
         || CASE WHEN v_nerr IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('nightly_error', v_nerr) END;
END; $$;
REVOKE ALL ON FUNCTION public.kiosk_rollout_tick() FROM public;
GRANT EXECUTE ON FUNCTION public.kiosk_rollout_tick() TO authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_rollout_tick() IS
  'pg_cron (5 min) + Velín: posune aktivní rollouty (canary→soak→rollout→done/failed), noční start software, OS každých N dní.';

-- ─── 8) pg_cron: tick každých 5 minut ────────────────────────────────────────
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('kiosk-fleet-update-tick');
  EXCEPTION WHEN OTHERS THEN NULL; -- job ještě neexistuje
  END;
  PERFORM cron.schedule('kiosk-fleet-update-tick', '*/5 * * * *', $cron$ SELECT public.kiosk_rollout_tick(); $cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule kiosk-fleet-update-tick selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;
