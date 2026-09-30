-- =============================================================================
-- STAV TACHOMETRU (rozhodnutí majitele 2026-09-29) — 1/6 (merge A): evidence + kiosk RPC
-- Migrace: 20260929c_odometer_readings.sql — aditivní, idempotentní
--  • moto_odometer_readings: return (kiosk při vrácení) | transfer (Velín přesun obslužná↔samoobslužná) | correction
--  • _kiosk_odometer(booking, branch, at) — blok `odo` pro jednotku (nápověda, hranice, důkazy fáze)
--  • _handover_pickup_km(booking) — JEDINÁ definice km při převzetí (edge, appka, _kiosk_protocol)
--  • kiosk_submit_odometer — zápis stavu z jednotky (auth device_id+token, idempotentní dle p_reading_id)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.moto_odometer_readings (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moto_id      uuid NOT NULL REFERENCES public.motorcycles(id) ON DELETE CASCADE,
  booking_id   uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
  branch_id    uuid REFERENCES public.branches(id) ON DELETE SET NULL,     -- pobočka čtení (transfer: odkud)
  to_branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,     -- jen transfer: kam
  device_id    uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL,
  km           integer NOT NULL CHECK (km BETWEEN 0 AND 9999999),
  unit         text NOT NULL DEFAULT 'km' CHECK (unit IN ('km', 'mh')),
  kind         text NOT NULL CHECK (kind IN ('return', 'transfer', 'correction')),
  source       text NOT NULL CHECK (source IN ('kiosk', 'velin')),
  status       text NOT NULL DEFAULT 'accepted' CHECK (status IN ('accepted', 'disputed')),
  reason       text,                 -- disputed: too_low | too_high | booking_status
  prev_km      integer,              -- poslední známý stav před čtením (= nápověda)
  min_km       integer,
  max_km       integer,
  recorded_at  timestamptz NOT NULL DEFAULT now(),   -- čas zadání (jednotka offline → čas z fronty, ≤ now())
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid,                 -- admin (Velín); kiosk NULL
  note         text,
  detail       jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_moto_odometer_readings_moto
  ON public.moto_odometer_readings (moto_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_moto_odometer_readings_booking
  ON public.moto_odometer_readings (booking_id, recorded_at DESC) WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_moto_odometer_readings_disputed
  ON public.moto_odometer_readings (created_at DESC) WHERE status = 'disputed';
ALTER TABLE public.moto_odometer_readings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS moto_odometer_readings_admin_select ON public.moto_odometer_readings;
CREATE POLICY moto_odometer_readings_admin_select ON public.moto_odometer_readings
  FOR SELECT USING (public.is_admin());
REVOKE ALL ON public.moto_odometer_readings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.moto_odometer_readings TO authenticated;
GRANT ALL ON public.moto_odometer_readings TO service_role;
COMMENT ON TABLE public.moto_odometer_readings IS
  'Stavy tachometru (2026-09-29): return = zákazník na kiosku při vrácení (kiosk_submit_odometer; disputed = server mimo věrohodný rozsah → bez zápisu do bookings/motorcycles), transfer = Velín přesun obslužná↔samoobslužná (admin_move_motorcycle), correction = correct_motorcycle_mileage. Zapisují jen SECURITY DEFINER RPC; čte admin.';

-- fáze výpůjčky podle otevření kóje (_kiosk_odometer, _activate_on_protocol_signed)
CREATE INDEX IF NOT EXISTS idx_branch_door_events_booking
  ON public.branch_door_events (booking_id, created_at DESC) WHERE booking_id IS NOT NULL;

-- ── _kiosk_odometer: blok `odo` (resolve + codes[] v sync) ─────────────────
-- hint = min = motorcycles.mileage (poslední známý; Velín „Korekce nájezdu“ ho smí snížit → odblokuje zákazníka)
-- max  = start_km + per_day × days (když ≤ hint → hint + per_day); start_km = mileage_start, jinak hint
-- days = kalendářní dny Praha (včetně) od start_at (nejdřív: picked_up_at | 1. otevření kóje | den začátku)
-- hint NULL (motorka bez km) → bez hranic. Fázi (vrácení?) rozhoduje JEDNOTKA; server dává jen důkazy
-- (last_open_*: detail.odometer_phase z ACCESS_GRANTED, starší události = 'out'; delivered = přistavení/SOS).
CREATE OR REPLACE FUNCTION public._kiosk_odometer(p_booking_id uuid, p_branch_id uuid, p_at timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
  v_at timestamptz := LEAST(COALESCE(p_at, now()), now());
  v_unit text; v_per_day integer; v_hint integer; v_start_km integer; v_start_at timestamptz; v_days integer;
  v_first timestamptz; v_last_open timestamptz; v_last_phase text;
  v_read_km integer; v_read_at timestamptz; v_delivered boolean;
BEGIN
  SELECT b.id, b.moto_id, b.start_date, b.picked_up_at, b.mileage_start,
         b.pickup_method, b.pickup_address, b.sos_replacement,
         m.mileage AS moto_km, m.tracking_unit
    INTO r
    FROM bookings b
    JOIN motorcycles m ON m.id = b.moto_id
   WHERE b.id = p_booking_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_unit     := CASE WHEN r.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END;
  v_per_day  := CASE v_unit WHEN 'mh' THEN 24 ELSE 1000 END;
  v_hint     := NULLIF(r.moto_km, 0);
  v_start_km := COALESCE(NULLIF(r.mileage_start, 0), v_hint);

  SELECT min(e.created_at) INTO v_first
    FROM branch_door_events e
   WHERE e.booking_id = p_booking_id AND e.branch_id = p_branch_id AND e.kind = 'motorcycle'
     AND e.success IS TRUE AND e.detail->>'event' = 'ACCESS_GRANTED';
  SELECT e.created_at, COALESCE(e.detail->>'odometer_phase', 'out') INTO v_last_open, v_last_phase
    FROM branch_door_events e
   WHERE e.booking_id = p_booking_id AND e.branch_id = p_branch_id AND e.kind = 'motorcycle'
     AND e.success IS TRUE AND e.detail->>'event' = 'ACCESS_GRANTED'
   ORDER BY e.created_at DESC LIMIT 1;

  SELECT o.km, o.recorded_at INTO v_read_km, v_read_at
    FROM moto_odometer_readings o
   WHERE o.booking_id = p_booking_id AND o.kind = 'return' AND o.status = 'accepted'
   ORDER BY o.recorded_at DESC, o.created_at DESC LIMIT 1;

  v_delivered := COALESCE(r.pickup_method, '') = 'delivery'
              OR btrim(COALESCE(r.pickup_address, '')) <> ''
              OR COALESCE(r.sos_replacement, false);
  v_start_at := LEAST(r.picked_up_at, v_first, public._door_code_valid_from(r.start_date));
  v_days := GREATEST(1, (v_at AT TIME ZONE 'Europe/Prague')::date - (v_start_at AT TIME ZONE 'Europe/Prague')::date + 1);

  RETURN jsonb_build_object(
    'booking_id',      r.id,
    'moto_id',         r.moto_id,
    'unit',            v_unit,
    'per_day',         v_per_day,
    'hint',            v_hint,
    'min',             v_hint,
    'max',             CASE WHEN v_hint IS NULL THEN NULL
                            WHEN COALESCE(v_start_km, v_hint) + v_per_day * v_days > v_hint
                            THEN COALESCE(v_start_km, v_hint) + v_per_day * v_days
                            ELSE v_hint + v_per_day END,          -- zastaralý start_km nesmí dát prázdný rozsah
    'start_km',        v_start_km,
    'start_at',        v_start_at,
    'days',            v_days,
    'last_reading_km', v_read_km,
    'last_reading_at', v_read_at,
    'last_open_at',    v_last_open,
    'last_open_phase', v_last_phase,
    'delivered',       v_delivered,
    'delivered_at',    CASE WHEN v_delivered THEN COALESCE(r.picked_up_at, public._door_code_valid_from(r.start_date)) END,
    'computed_at',     v_at);
EXCEPTION WHEN OTHERS THEN
  -- Fail-open jako _kiosk_protocol: NULL = neznámo → jednotka se řídí jen lokálním stavem
  RAISE WARNING '_kiosk_odometer failed for booking %: %', p_booking_id, SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._kiosk_odometer(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._kiosk_odometer(uuid, uuid, timestamptz) TO service_role;

-- ── _handover_pickup_km: km do předávacího protokolu (zákazník je nezadává) ──
CREATE OR REPLACE FUNCTION public._handover_pickup_km(p_booking_id uuid)
RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_b  bookings%ROWTYPE;
  v_km integer;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.moto_id IS NULL THEN RETURN NULL; END IF;
  -- 1) už zapsaný stav při převzetí (podepsaný protokol / Velín) = zmrazený
  IF COALESCE(v_b.mileage_start, 0) > 0 THEN RETURN v_b.mileage_start; END IF;
  -- 2) běžně: poslední známý stav motorky (vrácení předchozím zákazníkem na kiosku, přesun, korekce)
  IF v_b.mileage_end IS NULL THEN
    SELECT NULLIF(m.mileage, 0) INTO v_km FROM motorcycles m WHERE m.id = v_b.moto_id;
    RETURN v_km;
  END IF;
  -- 3) vrácení TÉTO rezervace už je zapsané (podpis převzetí dorazil až po vrácení) →
  --    motorcycles.mileage obsahuje i její jízdu; vezmi poslední stav z dřívějších výpůjček, nikdy > mileage_end
  SELECT NULLIF(GREATEST(COALESCE(p.mileage_end, 0), COALESCE(p.mileage_start, 0)), 0)
    INTO v_km
    FROM bookings p
   WHERE p.moto_id = v_b.moto_id AND p.id <> v_b.id AND p.status <> 'cancelled'
     AND p.start_date < v_b.start_date
     AND (COALESCE(p.mileage_end, 0) > 0 OR COALESCE(p.mileage_start, 0) > 0)
   ORDER BY p.start_date DESC
   LIMIT 1;
  RETURN CASE WHEN v_km IS NULL THEN NULL ELSE LEAST(v_km, v_b.mileage_end) END;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_handover_pickup_km failed for booking %: %', p_booking_id, SQLERRM;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._handover_pickup_km(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._handover_pickup_km(uuid) TO service_role;

-- ── kiosk_submit_odometer: stav tachometru při vrácení (trvalá fronta jednotky) ──
-- Jednotka ověřila hranice a kóji UŽ otevřela → server nikdy neodmítne platný vstup:
-- v rozsahu = accepted (bookings.mileage_end = nejnovější, motorcycles.mileage GREATEST);
-- mimo serverový rozsah (offline cache zastaralá) = disputed (jen evidence + debug_log, žádný zápis).
CREATE OR REPLACE FUNCTION public.kiosk_submit_odometer(
  p_device_id uuid, p_device_token uuid, p_reading_id uuid, p_booking_id uuid, p_km integer,
  p_recorded_at timestamptz DEFAULT NULL, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_bid uuid; v_moto uuid; v_status text; v_unit text;
  v_prev public.moto_odometer_readings%ROWTYPE;
  v_at timestamptz; v_odo jsonb; v_min integer; v_max integer;
  v_reason text; v_state text; v_detail jsonb;
BEGIN
  v_bid := public.kiosk_device_branch(p_device_id, p_device_token, true);
  IF v_bid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthorized'); END IF;
  IF p_reading_id IS NULL OR p_booking_id IS NULL OR p_km IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_inputs');
  END IF;
  IF p_km < 0 OR p_km > 9999999 THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_km'); END IF;

  -- opakované odeslání z fronty (odpověď se ztratila) = úspěch se stejným výsledkem
  SELECT * INTO v_prev FROM public.moto_odometer_readings WHERE id = p_reading_id;
  IF FOUND THEN
    IF v_prev.device_id IS DISTINCT FROM p_device_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'conflict');
    END IF;
    RETURN jsonb_build_object('ok', true, 'id', v_prev.id, 'status', v_prev.status,
                              'reason', v_prev.reason, 'duplicate', true);
  END IF;

  SELECT b.moto_id, b.status::text INTO v_moto, v_status FROM public.bookings b WHERE b.id = p_booking_id;
  IF v_moto IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  -- jen rezervace, jíž pobočka zařízení vydala kód k motorce (i už deaktivovaný — offline fronta)
  IF NOT EXISTS (SELECT 1 FROM public.branch_door_codes c
                  WHERE c.booking_id = p_booking_id AND c.branch_id = v_bid
                    AND c.code_type = 'motorcycle' AND c.sent_to_customer = true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT CASE WHEN m.tracking_unit = 'mh' THEN 'mh' ELSE 'km' END INTO v_unit
    FROM public.motorcycles m WHERE m.id = v_moto FOR UPDATE;          -- souběh čtení téže motorky
  v_at  := LEAST(now(), GREATEST(COALESCE(p_recorded_at, now()), now() - interval '30 days'));
  v_odo := public._kiosk_odometer(p_booking_id, v_bid, v_at);
  v_min := (v_odo->>'min')::integer;
  v_max := (v_odo->>'max')::integer;
  v_reason := CASE WHEN v_status NOT IN ('reserved', 'active', 'completed') THEN 'booking_status'
                   WHEN v_min IS NOT NULL AND p_km < v_min THEN 'too_low'
                   WHEN v_max IS NOT NULL AND p_km > v_max THEN 'too_high' END;
  v_state := CASE WHEN v_reason IS NULL THEN 'accepted' ELSE 'disputed' END;
  v_detail := COALESCE(p_detail, '{}'::jsonb);
  IF jsonb_typeof(v_detail) <> 'object' OR pg_column_size(v_detail) > 8192 THEN
    v_detail := jsonb_build_object('truncated', true);
  END IF;

  INSERT INTO public.moto_odometer_readings(id, moto_id, booking_id, branch_id, device_id, km, unit, kind, source,
                                            status, reason, prev_km, min_km, max_km, recorded_at, detail)
  VALUES (p_reading_id, v_moto, p_booking_id, v_bid, p_device_id, p_km, v_unit, 'return', 'kiosk',
          v_state, v_reason, (v_odo->>'hint')::integer, v_min, v_max, v_at, v_detail)
  ON CONFLICT (id) DO NOTHING;

  IF v_state = 'accepted' THEN
    -- mileage_end = NEJNOVĚJŠÍ stav vrácení (vícedenní s parkováním v kóji: každé vrácení = nový stav)
    UPDATE public.bookings bk SET mileage_end = p_km
     WHERE bk.id = p_booking_id AND bk.mileage_end IS DISTINCT FROM p_km
       AND NOT EXISTS (SELECT 1 FROM public.moto_odometer_readings o
                        WHERE o.booking_id = p_booking_id AND o.kind = 'return' AND o.status = 'accepted'
                          AND o.id <> p_reading_id AND o.recorded_at > v_at);
    -- nejvyšší známý stav = km do protokolu dalšího zákazníka + spodní mez dalšího vrácení
    UPDATE public.motorcycles SET mileage = p_km WHERE id = v_moto AND COALESCE(mileage, 0) < p_km;
  ELSE
    BEGIN
      INSERT INTO public.debug_log(source, action, status, error_message, request_data)
      VALUES ('kiosk_submit_odometer', 'disputed', 'warning', v_reason,
              jsonb_build_object('booking_id', p_booking_id, 'moto_id', v_moto, 'km', p_km,
                                 'min', v_min, 'max', v_max, 'device_id', p_device_id, 'reading_id', p_reading_id));
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', p_reading_id, 'status', v_state, 'reason', v_reason, 'duplicate', false);
END;
$$;
REVOKE ALL ON FUNCTION public.kiosk_submit_odometer(uuid, uuid, uuid, uuid, integer, timestamptz, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kiosk_submit_odometer(uuid, uuid, uuid, uuid, integer, timestamptz, jsonb)
  TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.kiosk_submit_odometer(uuid, uuid, uuid, uuid, integer, timestamptz, jsonb) IS
  'RPi jednotka (2026-09-29): stav tachometru při vrácení. Auth device_id+token; jen rezervace s kódem motorky pobočky. {ok:true,id,status accepted|disputed,reason,duplicate} | {ok:false,error unauthorized|missing_inputs|invalid_km|not_found|forbidden|conflict}. accepted → bookings.mileage_end (nejnovější) + motorcycles.mileage GREATEST; disputed → jen evidence. Idempotentní dle p_reading_id.';
