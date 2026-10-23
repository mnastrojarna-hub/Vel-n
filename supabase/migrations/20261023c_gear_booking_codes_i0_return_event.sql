-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — vrácení na kiosku — potvrzení (10/14)
-- _kiosk_gear_return_confirmed: GEAR_RETURN_CONFIRMED (kiosk_log_open, kind accessories) → booking_kiosk_returns
-- (parked, detail.gear_only, door_id = šatna, box_number NULL). Volá ho _kiosk_return_from_door_event (…_i_return).
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Idempotentní.
-- =============================================================================

-- Vrácení výpůjčky výbavy potvrzené na displeji (GEAR_RETURN_CONFIRMED, kiosk ≥ 1.3.0): zaparkované vrácení
-- (booking_kiosk_returns, door_id = šatna, box_number NULL, detail.gear_only) — dokončí kiosk_process_returns
-- (returned_at = detail.confirmed_at, kód šatny 15 min po zavření šatny). closed_at = zavření šatny téže
-- návštěvy (událost relace detail.session_id, jinak detail.closed_ts z jednotky, jinak čas potvrzení).
-- Jen výpůjčka výbavy s VYDANÝM kódem šatny pobočky zařízení a s DŘÍVĚJŠÍ návštěvou šatny (převzetí) v JINÉ
-- relaci — potvrzení v relaci převzetí / bez převzetí (zbloudilé, podepsáno ve Velíně před převzetím) se
-- zahodí (debug_log no_prior_pickup), jinak by výpůjčka skončila hned po vyzvednutí. Stav reserved se připouští
-- (podpis z fronty jednotky může dorazit až po potvrzení) — dokončí jen kiosk_process_returns (aktivní,
-- zaplacená, potvrzení po převzetí; jinak skipped → obsluha).
CREATE OR REPLACE FUNCTION public._kiosk_gear_return_confirmed(p_ev public.branch_door_events)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ts      timestamptz := public._kiosk_event_ts(p_ev.detail, p_ev.created_at);
  v_session text := left(NULLIF(p_ev.detail->>'session_id', ''), 64);
  v_closed  timestamptz;
  v_cts     timestamptz;
  v_door    uuid := p_ev.door_id;
BEGIN
  IF p_ev.booking_id IS NULL OR p_ev.success IS NOT TRUE OR p_ev.detail->>'emergency' = 'true' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM bookings b
                  WHERE b.id = p_ev.booking_id AND b.booking_kind = 'gear'
                    AND b.status IN ('reserved', 'active') AND b.is_test IS NOT TRUE) THEN
    RETURN;
  END IF;
  -- kiosk_log_open booking_id neověřuje → jen rezervace s vydaným kódem šatny na pobočce zařízení
  IF NOT EXISTS (SELECT 1 FROM branch_door_codes c
                  WHERE c.booking_id = p_ev.booking_id AND c.branch_id = p_ev.branch_id
                    AND c.code_type = 'accessories' AND c.sent_to_customer) THEN
    RETURN;
  END IF;
  IF v_session IS NOT NULL THEN
    SELECT max(public._kiosk_event_ts(e.detail, e.created_at)) INTO v_closed
      FROM branch_door_events e
     WHERE e.booking_id = p_ev.booking_id AND e.branch_id = p_ev.branch_id AND e.kind = 'accessories'
       AND e.success IS TRUE AND e.id <> p_ev.id
       AND e.detail->>'event' IN ('DOOR_CLOSED', 'SESSION_COMPLETED')
       AND e.detail->>'session_id' = v_session;
  END IF;
  -- záloha: closed_ts z jednotky (zavření šatny té návštěvy — z něj počítá i offline return_gate, CONTRACT §33)
  IF p_ev.detail->>'closed_ts' ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}' THEN
    v_cts := public._kiosk_event_ts(jsonb_build_object('ts', p_ev.detail->>'closed_ts'), p_ev.created_at);
  END IF;
  v_closed := LEAST(COALESCE(v_closed, v_cts, v_ts), v_ts);   -- zavření nikdy po potvrzení

  -- vrácení = návštěva PO převzetí: dřívější grant / otevření / zavření šatny téže rezervace v JINÉ relaci
  -- (stará jednotka bez relace: aspoň 10 min před zavřením). Pořadí doručení z outboxu je FIFO (převzetí dřív).
  IF NOT EXISTS (SELECT 1 FROM branch_door_events e
                  WHERE e.booking_id = p_ev.booking_id AND e.branch_id = p_ev.branch_id AND e.kind = 'accessories'
                    AND e.success IS TRUE AND e.id <> p_ev.id
                    AND COALESCE(e.detail->>'event', '') IN ('', 'ACCESS_GRANTED', 'DOOR_OPENED', 'DOOR_CLOSED', 'SESSION_COMPLETED')
                    AND e.detail->>'emergency' IS DISTINCT FROM 'true'
                    AND (v_session IS NULL OR e.detail->>'session_id' IS DISTINCT FROM v_session)
                    AND public._kiosk_event_ts(e.detail, e.created_at)
                        < v_closed - CASE WHEN v_session IS NULL THEN interval '10 minutes' ELSE interval '0' END) THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('_kiosk_gear_return_confirmed', 'no_prior_pickup', 'warning',
            jsonb_build_object('booking_id', p_ev.booking_id, 'event_id', p_ev.id, 'session_id', v_session,
                               'closed_at', v_closed, 'confirmed_at', v_ts));
    RETURN;
  END IF;
  IF v_door IS NULL THEN
    SELECT d.id INTO v_door FROM branch_doors d
     WHERE d.branch_id = p_ev.branch_id AND d.door_kind = 'accessories' AND d.is_active
     ORDER BY d.sort_order NULLS LAST LIMIT 1;
  END IF;

  INSERT INTO booking_kiosk_returns AS k
         (booking_id, branch_id, device_id, door_id, box_number, state, closed_at, locker_closed_at,
          session_id, last_event_at, detail)
  VALUES (p_ev.booking_id, p_ev.branch_id, p_ev.device_id, v_door, NULL, 'parked', v_closed, v_closed,
          v_session, now(),
          jsonb_build_object('gear_only', true, 'confirmed_at', v_ts, 'last_event', 'GEAR_RETURN_CONFIRMED',
                             'last_event_id', p_ev.id, 'unit_ts', p_ev.detail ? 'ts',
                             'offline', COALESCE(p_ev.detail->>'offline', '') = 'true'))
  ON CONFLICT (booking_id) DO UPDATE SET
    -- dokončené je konečné (opakované doručení z outboxu / další potvrzení jen zapíše událost);
    -- jinak (parked / skipped) = zaparkovat znovu s pozdějším časem
    state            = CASE WHEN k.state IN ('completed', 'completed_elsewhere') THEN k.state ELSE 'parked' END,
    reason           = CASE WHEN k.state IN ('completed', 'completed_elsewhere') THEN k.reason END,
    completed_at     = CASE WHEN k.state IN ('completed', 'completed_elsewhere') THEN k.completed_at END,
    closed_at        = CASE WHEN k.state IN ('completed', 'completed_elsewhere') THEN k.closed_at
                            ELSE GREATEST(k.closed_at, EXCLUDED.closed_at) END,
    locker_closed_at = CASE WHEN k.state IN ('completed', 'completed_elsewhere') THEN k.locker_closed_at
                            ELSE GREATEST(k.locker_closed_at, EXCLUDED.locker_closed_at) END,
    session_id       = CASE WHEN k.state IN ('completed', 'completed_elsewhere') THEN k.session_id
                            ELSE COALESCE(EXCLUDED.session_id, k.session_id) END,
    branch_id        = COALESCE(EXCLUDED.branch_id, k.branch_id),
    device_id        = COALESCE(EXCLUDED.device_id, k.device_id),
    door_id          = COALESCE(EXCLUDED.door_id, k.door_id),
    last_event_at    = now(),
    detail           = CASE WHEN k.state IN ('completed', 'completed_elsewhere')
                            THEN k.detail || jsonb_build_object('last_event', 'GEAR_RETURN_CONFIRMED', 'last_event_id', p_ev.id)
                            ELSE k.detail || EXCLUDED.detail || jsonb_build_object('confirmed_at',
                                   GREATEST(NULLIF(k.detail->>'confirmed_at', '')::timestamptz, v_ts)) END;
END $$;

REVOKE ALL ON FUNCTION public._kiosk_gear_return_confirmed(public.branch_door_events) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._kiosk_gear_return_confirmed(public.branch_door_events) TO service_role;
