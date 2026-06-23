-- =============================================================================
-- MIGRACE 2026-06-23 (c): Autonomní předávací protokol na samoobslužné pobočce
--
-- Tok: na samoobslužné pobočce zadá zákazník na tabletu v appce kód ke dveřím
-- → spustí se 1h okno (`start_handover_protocol_window`). Do hodiny může vyplnit
-- a podepsat předávací protokol v appce (edge fn `submit-handover-protocol`,
-- mode='customer'). Pokud do hodiny nevyplní, cron `autofill_overdue_handover_protocols`
-- protokol vyplní automaticky („vše dle rezervace, vše OK" — MotoGo automaticky
-- souhlasí, podpis se neuvádí, mode='auto'). Po vyplnění/auto-vyplnění je protokol
-- ZAMČENÝ (zákazník už ho needituje) a zobrazí se v appce v dokumentech i rezervaci.
-- Nesrovnalosti pak zákazník hlásí jen zprávou v appce / e-mailem.
-- =============================================================================

-- 1) Sloupce na bookings ------------------------------------------------------
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS handover_protocol_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS handover_protocol_filled_at  timestamptz,
  ADD COLUMN IF NOT EXISTS handover_protocol_autofilled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN bookings.handover_protocol_started_at IS 'Start 1h okna pro samovyplnění protokolu (zadání kódu ke dveřím na tabletu v appce).';
COMMENT ON COLUMN bookings.handover_protocol_filled_at  IS 'Kdy byl předávací protokol vyplněn (zákazníkem nebo auto-fillem). NULL = ještě nevyplněn.';
COMMENT ON COLUMN bookings.handover_protocol_autofilled IS 'TRUE = protokol vyplnil systém automaticky (zákazník nestihl do 1h).';

-- 2) Helper: je rezervace na samoobslužné pobočce? ---------------------------
CREATE OR REPLACE FUNCTION _is_self_service_booking(p_booking_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(br.type = 'samoobslužná', false)
  FROM bookings b
  JOIN motorcycles m ON m.id = b.moto_id
  JOIN branches br   ON br.id = m.branch_id
  WHERE b.id = p_booking_id
$$;

-- 3) RPC: start 1h okna (volá appka při zadání kódu ke dveřím) ----------------
CREATE OR REPLACE FUNCTION start_handover_protocol_window(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF v_b.user_id <> v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF v_b.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF NOT _is_self_service_booking(p_booking_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_self_service');
  END IF;

  -- Okno spustíme jen jednou (idempotentní); pokud už protokol existuje, jen vrátíme stav.
  IF v_b.handover_protocol_started_at IS NULL AND v_b.handover_protocol_filled_at IS NULL THEN
    UPDATE bookings SET handover_protocol_started_at = now() WHERE id = p_booking_id;
    v_b.handover_protocol_started_at := now();
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'started_at', v_b.handover_protocol_started_at,
    'deadline',   v_b.handover_protocol_started_at + interval '1 hour',
    'filled_at',  v_b.handover_protocol_filled_at,
    'autofilled', v_b.handover_protocol_autofilled
  );
END;
$$;
REVOKE ALL ON FUNCTION start_handover_protocol_window(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION start_handover_protocol_window(uuid) TO authenticated;

-- 4) RPC: stav protokolu pro appku -------------------------------------------
CREATE OR REPLACE FUNCTION get_handover_protocol_state(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_b   bookings%ROWTYPE;
  v_self boolean;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  IF v_b.user_id <> v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  v_self := _is_self_service_booking(p_booking_id);

  RETURN jsonb_build_object(
    'is_self_service', v_self,
    'started_at',  v_b.handover_protocol_started_at,
    'deadline',    CASE WHEN v_b.handover_protocol_started_at IS NOT NULL
                        THEN v_b.handover_protocol_started_at + interval '1 hour' END,
    'filled_at',   v_b.handover_protocol_filled_at,
    'autofilled',  v_b.handover_protocol_autofilled,
    'locked',      (v_b.handover_protocol_filled_at IS NOT NULL),
    -- zákazník smí vyplnit: samoobslužná, aktivní/rezervovaná, okno běží, ještě nevyplněno
    'can_fill',    (v_self
                    AND v_b.status IN ('reserved','active')
                    AND v_b.handover_protocol_started_at IS NOT NULL
                    AND v_b.handover_protocol_filled_at IS NULL)
  );
END;
$$;
REVOKE ALL ON FUNCTION get_handover_protocol_state(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION get_handover_protocol_state(uuid) TO authenticated;

-- 5) Cron: auto-fill protokolů po vypršení 1h okna ---------------------------
-- Najde samoobslužné rezervace, kde okno běží > 1 h a protokol není vyplněn,
-- a pro každou zavolá edge fn `submit-handover-protocol` (mode='auto') přes pg_net.
-- Edge fn nastaví handover_protocol_filled_at → další běh řádek přeskočí.
CREATE OR REPLACE FUNCTION autofill_overdue_handover_protocols()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_url text;
  v_key text;
  v_row record;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'autofill_overdue_handover_protocols: app_settings(supabase_url|service_role_key) chybí';
    RETURN;
  END IF;

  FOR v_row IN
    SELECT b.id
    FROM bookings b
    JOIN motorcycles m ON m.id = b.moto_id
    JOIN branches br   ON br.id = m.branch_id
    WHERE br.type = 'samoobslužná'
      AND b.status IN ('reserved','active')
      AND b.handover_protocol_started_at IS NOT NULL
      AND b.handover_protocol_filled_at IS NULL
      AND b.handover_protocol_started_at < now() - interval '1 hour'
    LIMIT 50
  LOOP
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/submit-handover-protocol',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object('booking_id', v_row.id, 'mode', 'auto')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'autofill_overdue_handover_protocols: dispatch failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- pg_cron job (každých 5 min). Bezpečné re-run (idempotentní dispatch).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'autofill-handover-protocols') THEN
      PERFORM cron.unschedule('autofill-handover-protocols');
    END IF;
    PERFORM cron.schedule('autofill-handover-protocols', '*/5 * * * *',
      $cron$SELECT autofill_overdue_handover_protocols();$cron$);
  END IF;
END $$;
