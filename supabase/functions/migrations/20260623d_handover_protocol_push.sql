-- =============================================================================
-- MIGRACE 2026-06-23 (d): Push notifikace k autonomnímu předávacímu protokolu
--
-- Navazuje na 20260623c. Přidává:
--  1) push UPOZORNĚNÍ při spuštění 1h okna (zákazník zadal kód → „máte 60 minut").
--  2) push PŘIPOMÍNKU ~5–10 min před koncem okna (cron, dedup přes sloupec).
-- Push jde přes existující helper send_push_via_edge (respektuje consent_push;
-- appka ho během aktivní/zaplacené rezervace drží na true → nutné pushe chodí).
-- Banner v appce řeší frontend (get_handover_protocol_state).
-- =============================================================================

-- Dedup sloupec pro připomínku
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS handover_protocol_reminder_sent_at timestamptz;
COMMENT ON COLUMN bookings.handover_protocol_reminder_sent_at IS 'Kdy byla odeslána push připomínka „vyplňte protokol" (~10 min před koncem 1h okna). Dedup.';

-- 1) start_handover_protocol_window + push při PRVNÍM spuštění okna ------------
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

  IF v_b.handover_protocol_started_at IS NULL AND v_b.handover_protocol_filled_at IS NULL THEN
    UPDATE bookings SET handover_protocol_started_at = now() WHERE id = p_booking_id;
    v_b.handover_protocol_started_at := now();
    -- Push upozornění (jen poprvé). EXCEPTION-safe helper → neshodí RPC.
    IF v_b.user_id IS NOT NULL THEN
      PERFORM send_push_via_edge(
        v_b.user_id,
        'Předávací protokol',
        'Vyplňte prosím předávací protokol — máte na to 60 minut. Po hodině ho vyplníme automaticky.',
        jsonb_build_object('type', 'handover_protocol', 'id', p_booking_id::text)
      );
    END IF;
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

-- 2) Cron: připomínka ~10 min před koncem + auto-fill po vypršení -------------
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

  -- 2a) PŘIPOMÍNKA: okno běží > 50 min, ještě nevyplněno, připomínka neodeslaná.
  -- (cron */5 → fire ~5–10 min před 60min deadlinem, jednou na rezervaci.)
  FOR v_row IN
    SELECT b.id, b.user_id
    FROM bookings b
    JOIN motorcycles m ON m.id = b.moto_id
    JOIN branches br   ON br.id = m.branch_id
    WHERE br.type = 'samoobslužná'
      AND b.status IN ('reserved','active')
      AND b.user_id IS NOT NULL
      AND b.handover_protocol_filled_at IS NULL
      AND b.handover_protocol_reminder_sent_at IS NULL
      AND b.handover_protocol_started_at IS NOT NULL
      AND b.handover_protocol_started_at < now() - interval '50 minutes'
    LIMIT 50
  LOOP
    BEGIN
      PERFORM send_push_via_edge(
        v_row.user_id,
        'Předávací protokol — poslední výzva',
        'Zbývá pár minut na vyplnění předávacího protokolu. Pokud ho nevyplníte, vyplníme ho za vás (vše dle rezervace).',
        jsonb_build_object('type', 'handover_protocol', 'id', v_row.id::text)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'handover reminder push failed for %: %', v_row.id, SQLERRM;
    END;
    UPDATE bookings SET handover_protocol_reminder_sent_at = now() WHERE id = v_row.id;
  END LOOP;

  -- 2b) AUTO-FILL: okno běží > 1 h, ještě nevyplněno → zavolá edge fn (mode=auto).
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'autofill_overdue_handover_protocols: app_settings(supabase_url|service_role_key) chybí';
    RETURN;
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id
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
