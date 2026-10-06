-- =============================================================================
-- SAMOOBSLUHA: VRÁCENÍ NA KIOSKU — SLEDOVÁNÍ (rozhodnutí majitele 2026-10-06) — 1/2 (SQL A)
-- Migrace: 20261006b_kiosk_return_tracking.sql — aditivní, idempotentní
--
-- PROČ: jednotka zná jen fázi motorky (`odometer_phase` in = zaparkování / out = vyjetí) a zavření dveří
-- kóje. Dokončení rezervace přímo z události v kiosk_log_open nejde: běží pod rolí anon (statement_timeout
-- 3 s) a řetěz completed (KF, e-maily, věrnost) je těžký; navíc vícedenní pronájem smí motorku přes noc
-- zaparkovat (D1 — dokončuje se jen vrácení v POSLEDNÍ den nebo po konci termínu). Proto:
--  • booking_kiosk_returns — 1 řádek / rezervace = aktuální stav vrácení na kiosku (Velín čte realtime)
--  • trg_kiosk_return_from_door_event — z branch_door_events JEN levně zapíše stav (indexy + 1 upsert),
--    na bookings ani kódy NIKDY nesahá; dokončení a dobíhání kódů dělá cron kiosk_process_returns (20261006c)
--  • _kiosk_event_ts / _kiosk_return_locker_close — čas události dle jednotky, zavření šatny patřící k vrácení
-- Čas události = `detail.ts` z hodin jednotky (≥ 1.2.8, D3); starší jednotka bez ts → created_at a fáze
-- zavření se páruje s posledním ACCESS_GRANTED (≤ 12 h). Chyba triggeru NIKDY nesmí shodit audit dveří.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.booking_kiosk_returns (
  booking_id        uuid PRIMARY KEY REFERENCES public.bookings(id) ON DELETE CASCADE,
  branch_id         uuid REFERENCES public.branches(id) ON DELETE SET NULL,
  device_id         uuid REFERENCES public.kiosk_devices(id) ON DELETE SET NULL,
  door_id           uuid REFERENCES public.branch_doors(id) ON DELETE SET NULL,
  box_number        integer,
  state             text NOT NULL CHECK (state IN ('returning', 'parked', 'out', 'completed', 'skipped', 'completed_elsewhere')),
  grant_at          timestamptz,          -- čas jednotky: ACCESS_GRANTED fáze in (kód motorky + km)
  out_at            timestamptz,          -- čas jednotky: poslední vyjetí (fáze out) po zaparkování
  closed_at         timestamptz,          -- čas jednotky: finální zavření kóje relace vrácení
  locker_closed_at  timestamptz,          -- čas jednotky: zavření šatny patřící k vrácení
  reading_id        uuid,                 -- moto_odometer_readings.id z grantu (km při vrácení)
  km                integer,
  session_id        text,
  last_event_at     timestamptz NOT NULL DEFAULT now(),   -- čas SERVERU poslední relevantní události
  completed_at      timestamptz,          -- kdy server rezervaci dokončil / uzavřel řádek
  moto_code_until   timestamptz,          -- kód motorky dobíhá do (zavření kóje + 15 min)
  locker_code_until timestamptz,          -- kód šatny dobíhá do (NULL = běžná platnost)
  codes_closed_at   timestamptz,          -- všechny kódy rezervace už neplatí (doběh hotov)
  reason            text,                 -- skipped: not_active | unpaid | sos_replacement | trailer | test | cancelled | error
  detail            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_booking_kiosk_returns_open
  ON public.booking_kiosk_returns (state, last_event_at)
  WHERE state IN ('returning', 'parked', 'out') OR (state = 'completed' AND codes_closed_at IS NULL);
COMMENT ON TABLE public.booking_kiosk_returns IS
  'Vrácení motorky na kiosku samoobslužné pobočky (2026-10-06): 1 řádek / rezervace. returning = kód motorky + km, parked = kóje zavřena (motorka uvnitř), out = po zaparkování znovu vyjeta, completed = dokončeno automaticky (kódy dobíhají 15 min), skipped = vráceno, ale nedokončeno (reason), completed_elsewhere = dokončila obsluha/cron. Zapisuje JEN trigger z branch_door_events a cron kiosk_process_returns; čte admin (Velín, realtime).';

ALTER TABLE public.booking_kiosk_returns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS booking_kiosk_returns_admin_select ON public.booking_kiosk_returns;
CREATE POLICY booking_kiosk_returns_admin_select ON public.booking_kiosk_returns
  FOR SELECT USING (public.is_admin());
REVOKE ALL ON public.booking_kiosk_returns FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.booking_kiosk_returns TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_booking_kiosk_returns_touch ON public.booking_kiosk_returns;
CREATE TRIGGER trg_booking_kiosk_returns_touch BEFORE UPDATE ON public.booking_kiosk_returns
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Události rezervace (párování fáze, šatna) — index z 20260929c; jen pojistka, kdyby chyběl.
CREATE INDEX IF NOT EXISTS idx_branch_door_events_booking
  ON public.branch_door_events (booking_id, created_at DESC) WHERE booking_id IS NOT NULL;
-- Kontrola vlastnictví v triggeru (kód motorky rezervace na pobočce) — branch_door_codes index na booking_id neměla.
CREATE INDEX IF NOT EXISTS idx_branch_door_codes_booking ON public.branch_door_codes (booking_id);

-- Realtime: Velín (detail rezervace → „Vrácení na kiosku“) odebírá změny řádku.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'booking_kiosk_returns'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_kiosk_returns;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD booking_kiosk_returns selhalo: %', SQLERRM;
END $$;

-- ── Čas události podle jednotky (detail.ts, ISO 8601) ────────────────────────
-- Neparsovatelný / o víc než 5 min v budoucnosti / starší 30 dní (vůči příjmu na serveru) → created_at.
-- Vztaženo k created_at (ne now()), aby trigger i pozdější cron vyhodnotily tutéž událost stejně.
CREATE OR REPLACE FUNCTION public._kiosk_event_ts(p_detail jsonb, p_created_at timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_raw text := p_detail->>'ts';
  v_ts  timestamptz;
BEGIN
  IF v_raw IS NULL OR v_raw !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}' THEN RETURN p_created_at; END IF;
  BEGIN
    v_ts := v_raw::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RETURN p_created_at;
  END;
  IF p_created_at IS NOT NULL AND (v_ts > p_created_at + interval '5 minutes' OR v_ts < p_created_at - interval '30 days') THEN
    RETURN p_created_at;
  END IF;
  RETURN v_ts;
END $$;
ALTER FUNCTION public._kiosk_event_ts(jsonb, timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._kiosk_event_ts(jsonb, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._kiosk_event_ts(jsonb, timestamptz) TO service_role;
COMMENT ON FUNCTION public._kiosk_event_ts(jsonb, timestamptz) IS
  'Čas události kiosku: detail.ts (hodiny jednotky ≥ 1.2.8), jinak / neplatný / > příjem+5 min / < příjem−30 dní → created_at (2026-10-06).';

-- ── Zavření šatny patřící k vrácení (NULL = šatna po vrácení nezavřena; používá kiosk_process_returns) ──
-- Poslední DOOR_CLOSED/SESSION_COMPLETED šatny téže rezervace a pobočky s časem jednotky ≥ zavření kóje − 90 min
-- a zároveň PO posledním vyjetí motorky (grant out) před zavřením kóje — vyzvednutí výbavy při převzetí se
-- tak nikdy nespočte jako její vrácení.
CREATE OR REPLACE FUNCTION public._kiosk_return_locker_close(p_booking_id uuid, p_branch_id uuid, p_closed_at timestamptz)
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  WITH ev AS (
    SELECT e.kind, e.detail->>'event' AS event,
           COALESCE(NULLIF(e.detail->>'odometer_phase', ''), 'out') AS phase,
           public._kiosk_event_ts(e.detail, e.created_at) AS ts
      FROM branch_door_events e
     WHERE e.booking_id = p_booking_id AND e.branch_id = p_branch_id AND e.success IS TRUE
       AND e.created_at >= p_closed_at - interval '95 minutes'
  )
  SELECT max(l.ts) FROM ev l
   WHERE l.kind = 'accessories' AND l.event IN ('DOOR_CLOSED', 'SESSION_COMPLETED')
     AND l.ts >= p_closed_at - interval '90 minutes'
     AND l.ts > COALESCE((SELECT max(o.ts) FROM ev o
                           WHERE o.kind = 'motorcycle' AND o.event = 'ACCESS_GRANTED'
                             AND o.phase <> 'in' AND o.ts <= p_closed_at), '-infinity');
$$;
ALTER FUNCTION public._kiosk_return_locker_close(uuid, uuid, timestamptz) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._kiosk_return_locker_close(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._kiosk_return_locker_close(uuid, uuid, timestamptz) TO service_role;
COMMENT ON FUNCTION public._kiosk_return_locker_close(uuid, uuid, timestamptz) IS
  'Čas jednotky posledního zavření šatny téže rezervace a pobočky ≥ zavření kóje − 90 min a po posledním vyjetí motorky (NULL = šatna po vrácení nezavřena) — doběh kódu šatny (2026-10-06).';

-- ── Trigger: událost kóje → stav vrácení (běží v kiosk_log_open pod anon, timeout 3 s) ──
CREATE OR REPLACE FUNCTION public._kiosk_return_from_door_event()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event   text := NEW.detail->>'event';
  v_ts      timestamptz;
  v_phase   text := NULLIF(NEW.detail->>'odometer_phase', '');
  v_session text := left(NULLIF(NEW.detail->>'session_id', ''), 64);
  v_src     text := 'detail';
  v_box     integer;
  v_reading uuid;
  v_km      integer;
  v_info    jsonb;
BEGIN
  IF NEW.success IS NOT TRUE OR NEW.booking_id IS NULL OR NEW.kind IS DISTINCT FROM 'motorcycle'
     OR v_event IS NULL OR v_event NOT IN ('ACCESS_GRANTED', 'DOOR_CLOSED', 'SESSION_COMPLETED')
     OR NEW.detail->>'emergency' = 'true' THEN
    -- nouzové servisní otevření (zone_access.service_unlock_locked) nese booking běžící relace, ale není to
    -- zákaznický grant (bez fáze) → nesmí řádek přepnout na 'out' ani posloužit k párování
    RETURN NULL;
  END IF;
  -- kiosk_log_open booking_id neověřuje → jen rezervace s vydaným kódem motorky na pobočce zařízení
  IF NOT EXISTS (SELECT 1 FROM branch_door_codes c
                  WHERE c.booking_id = NEW.booking_id AND c.branch_id = NEW.branch_id
                    AND c.code_type = 'motorcycle' AND c.sent_to_customer) THEN
    RETURN NULL;
  END IF;

  v_ts := public._kiosk_event_ts(NEW.detail, NEW.created_at);
  IF NEW.door_id IS NOT NULL THEN
    SELECT d.box_number INTO v_box FROM branch_doors d WHERE d.id = NEW.door_id;
  END IF;
  IF v_box IS NULL AND NEW.detail->>'box_number' ~ '^[0-9]{1,4}$' THEN
    v_box := (NEW.detail->>'box_number')::integer;
  END IF;

  IF v_event = 'ACCESS_GRANTED' THEN
    IF v_phase IS DISTINCT FROM 'in' THEN
      -- vyjetí (out / bez fáze): jen po zaparkování; převzetí řádek nezakládá
      UPDATE booking_kiosk_returns k
         SET state = 'out', out_at = v_ts, last_event_at = now(),
             session_id = COALESCE(v_session, k.session_id),
             detail = k.detail || jsonb_build_object('last_event', v_event, 'last_event_id', NEW.id)
       WHERE k.booking_id = NEW.booking_id AND k.state IN ('returning', 'parked', 'out')
         AND v_ts > GREATEST(k.closed_at, k.grant_at, k.out_at);
      RETURN NULL;
    END IF;
    IF NEW.detail->>'odometer_reading_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      v_reading := (NEW.detail->>'odometer_reading_id')::uuid;
    END IF;
    IF NEW.detail->>'odometer_km' ~ '^[0-9]{1,7}$' THEN v_km := (NEW.detail->>'odometer_km')::integer; END IF;
    v_info := jsonb_build_object('last_event', v_event, 'last_event_id', NEW.id, 'unit_ts', NEW.detail ? 'ts');
    INSERT INTO booking_kiosk_returns AS k
           (booking_id, branch_id, device_id, door_id, box_number, state, grant_at, reading_id, km, session_id, last_event_at, detail)
    VALUES (NEW.booking_id, NEW.branch_id, NEW.device_id, NEW.door_id, v_box, 'returning', v_ts, v_reading, v_km, v_session, now(), v_info)
    ON CONFLICT (booking_id) DO UPDATE SET
      state = CASE WHEN k.state IN ('completed', 'skipped', 'completed_elsewhere') THEN k.state
                   WHEN k.closed_at >= EXCLUDED.grant_at THEN k.state   -- zavření dorazilo dřív než jeho grant
                   WHEN k.out_at >= EXCLUDED.grant_at THEN k.state      -- starý grant (motorka mezitím vyjela)
                   ELSE 'returning' END,
      grant_at   = GREATEST(k.grant_at, EXCLUDED.grant_at),
      reading_id = CASE WHEN EXCLUDED.reading_id IS NOT NULL AND EXCLUDED.grant_at >= COALESCE(k.grant_at, '-infinity')
                        THEN EXCLUDED.reading_id ELSE k.reading_id END,
      km         = CASE WHEN EXCLUDED.km IS NOT NULL AND EXCLUDED.grant_at >= COALESCE(k.grant_at, '-infinity')
                        THEN EXCLUDED.km ELSE k.km END,
      session_id = CASE WHEN EXCLUDED.grant_at >= COALESCE(k.grant_at, '-infinity')
                        THEN COALESCE(EXCLUDED.session_id, k.session_id) ELSE k.session_id END,
      branch_id  = COALESCE(EXCLUDED.branch_id, k.branch_id),
      device_id  = COALESCE(EXCLUDED.device_id, k.device_id),
      door_id    = COALESCE(EXCLUDED.door_id, k.door_id),
      box_number = COALESCE(EXCLUDED.box_number, k.box_number),
      last_event_at = now(),
      detail     = k.detail || EXCLUDED.detail;
    RETURN NULL;
  END IF;

  -- DOOR_CLOSED / SESSION_COMPLETED: fáze z detailu (≥ 1.2.8), jinak z grantu téže relace, jinak párování
  -- s posledním ACCESS_GRANTED (stará jednotka; created_at ≤ zavření, ≥ zavření − 12 h); nic → 'out'.
  IF v_phase IS NULL AND v_session IS NOT NULL THEN
    SELECT COALESCE(NULLIF(e.detail->>'odometer_phase', ''), 'out'), 'session' INTO v_phase, v_src
      FROM branch_door_events e
     WHERE e.booking_id = NEW.booking_id AND e.branch_id = NEW.branch_id AND e.kind = 'motorcycle'
       AND e.success IS TRUE AND e.detail->>'event' = 'ACCESS_GRANTED' AND e.detail->>'session_id' = v_session
     ORDER BY e.created_at DESC LIMIT 1;
  END IF;
  IF v_phase IS NULL THEN
    SELECT COALESCE(NULLIF(e.detail->>'odometer_phase', ''), 'out'), 'paired' INTO v_phase, v_src
      FROM branch_door_events e
     WHERE e.booking_id = NEW.booking_id AND e.branch_id = NEW.branch_id AND e.kind = 'motorcycle'
       AND e.success IS TRUE AND e.detail->>'event' = 'ACCESS_GRANTED' AND e.id <> NEW.id
       AND e.detail->>'emergency' IS DISTINCT FROM 'true'
       AND e.created_at <= NEW.created_at AND e.created_at >= NEW.created_at - interval '12 hours'
     ORDER BY e.created_at DESC LIMIT 1;
  END IF;
  IF COALESCE(v_phase, 'out') <> 'in' THEN RETURN NULL; END IF;   -- převzetí / vyjetí: zavření nic neznamená

  v_info := jsonb_build_object('last_event', v_event, 'last_event_id', NEW.id, 'phase_source', v_src, 'unit_ts', NEW.detail ? 'ts');
  INSERT INTO booking_kiosk_returns AS k
         (booking_id, branch_id, device_id, door_id, box_number, state, closed_at, session_id, last_event_at, detail)
  VALUES (NEW.booking_id, NEW.branch_id, NEW.device_id, NEW.door_id, v_box, 'parked', v_ts, v_session, now(), v_info)
  ON CONFLICT (booking_id) DO UPDATE SET
    -- po automatickém dokončení posune čas jen znovuotevření v okně kódu (+5 min tolerance)
    closed_at = CASE WHEN k.state = 'completed'
                      AND EXCLUDED.closed_at > COALESCE(k.moto_code_until, k.closed_at + interval '15 minutes') + interval '5 minutes'
                     THEN k.closed_at
                     ELSE GREATEST(k.closed_at, EXCLUDED.closed_at) END,
    state = CASE WHEN k.state IN ('completed', 'skipped', 'completed_elsewhere') THEN k.state
                 WHEN k.state = 'returning' AND k.grant_at > EXCLUDED.closed_at THEN k.state   -- zavření předchozí relace
                 ELSE 'parked' END,
    session_id = CASE WHEN EXCLUDED.closed_at >= COALESCE(k.closed_at, '-infinity')
                      THEN COALESCE(EXCLUDED.session_id, k.session_id) ELSE k.session_id END,
    branch_id  = COALESCE(EXCLUDED.branch_id, k.branch_id),
    device_id  = COALESCE(EXCLUDED.device_id, k.device_id),
    door_id    = COALESCE(EXCLUDED.door_id, k.door_id),
    box_number = COALESCE(EXCLUDED.box_number, k.box_number),
    last_event_at = now(),
    detail     = k.detail || EXCLUDED.detail
  WHERE k.out_at IS NULL OR k.out_at <= EXCLUDED.closed_at;   -- zavření starší než poslední vyjetí = nic
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Audit dveří se NIKDY nesmí kvůli sledování vrácení nezapsat (outbox jednotky by to zkoušel donekonečna).
  RAISE WARNING '_kiosk_return_from_door_event failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NULL;
END $$;
ALTER FUNCTION public._kiosk_return_from_door_event() OWNER TO postgres;
REVOKE ALL ON FUNCTION public._kiosk_return_from_door_event() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public._kiosk_return_from_door_event() IS
  'branch_door_events → booking_kiosk_returns (2026-10-06): ACCESS_GRANTED in = returning, zavření kóje fáze in = parked, vyjetí po zaparkování = out. Jen levné čtení + 1 upsert, bookings/kódy nemění (dokončuje cron kiosk_process_returns). Chyba = WARNING.';

DROP TRIGGER IF EXISTS trg_kiosk_return_from_door_event ON public.branch_door_events;
CREATE TRIGGER trg_kiosk_return_from_door_event
  AFTER INSERT ON public.branch_door_events
  FOR EACH ROW EXECUTE FUNCTION public._kiosk_return_from_door_event();
