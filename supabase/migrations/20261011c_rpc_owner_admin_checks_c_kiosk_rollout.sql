-- =============================================================================
-- 2026-10-11 BEZPEČNOST (část _c k 20261011c): hromadná aktualizace jednotek
-- kiosk_rollout_start / kiosk_rollout_cancel měly guard
-- `auth.uid() IS NOT NULL AND NOT is_admin()` — anon (uid NULL) prošel a mohl
-- jen s anon klíčem rozeslat OS update s rebootem řídicím jednotkám poboček.
-- Nově fail closed přes _rpc_caller_is_staff(): admin (Velín), service_role,
-- pg_cron / postgres (kiosk_rollout_tick → kiosk_rollout_start v noci) ano;
-- anon i přihlášený ne-admin → {ok:false, error:'forbidden'} (kontrakt beze
-- změny). Těla = živá definice, měněn jen guard. Idempotentní.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.kiosk_rollout_start(p_kind text, p_release_id uuid, p_canary_device_id uuid, p_soak_minutes integer, p_wait_idle_s integer, p_auto_reboot boolean, p_mode text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active uuid; v_rel public.kiosk_releases%ROWTYPE; v_canary public.kiosk_devices%ROWTYPE; v_ro public.kiosk_rollouts%ROWTYPE;
BEGIN
  -- 2026-10-11: fail closed (dřív anon s auth.uid() NULL prošel); cron/service/admin ano
  IF NOT public._rpc_caller_is_staff() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
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
END; $function$;

CREATE OR REPLACE FUNCTION public.kiosk_rollout_cancel(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ro public.kiosk_rollouts%ROWTYPE; v_n int;
BEGIN
  -- 2026-10-11: fail closed (dřív anon s auth.uid() NULL prošel); cron/service/admin ano
  IF NOT public._rpc_caller_is_staff() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
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
END; $function$;
