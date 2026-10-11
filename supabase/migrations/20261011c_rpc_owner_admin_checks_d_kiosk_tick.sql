-- =============================================================================
-- 2026-10-11 BEZPEČNOST (část _d k 20261011c): kiosk_rollout_tick
-- Stejný fail-closed guard jako _c (pg_cron 'kiosk-fleet-update-tick' běží
-- jako postgres → projde; Velín „Zkontrolovat teď“ = admin → projde; anon /
-- zákazník → forbidden). Tělo = živá definice, měněn jen guard. Idempotentní.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.kiosk_rollout_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ids uuid[] := '{}'; v_started uuid; v_start jsonb; v_nerr text; v_rid uuid;
  r public.kiosk_rollouts%ROWTYPE; rd public.kiosk_rollout_devices%ROWTYPE; dev public.kiosk_devices%ROWTYPE;
  s public.kiosk_fleet_settings%ROWTYPE; rel public.kiosk_releases%ROWTYPE;
  v_err text; v_n int; v_open int; v_failed int; v_stale int; v_errs jsonb; v_offline jsonb; v_wait interval;
  v_now_pr timestamp; v_today date; v_hour int;
BEGIN
  -- 2026-10-11: fail closed (dřív anon s auth.uid() NULL prošel); cron/service/admin ano
  IF NOT public._rpc_caller_is_staff() THEN RETURN jsonb_build_object('ok', false, 'error', 'forbidden'); END IF;
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
END; $function$;
