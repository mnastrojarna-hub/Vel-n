-- =============================================================================
-- SAMOOBSLUHA: VRÁCENÍ NA KIOSKU — vyjetí až po OTEVŘENÍ dveří (oprava 2026-10-07)
-- Migrace: 20261007_kiosk_return_pending_rideout.sql — idempotentní (CREATE OR REPLACE), trigger beze změny
--
-- PROČ (hlášení majitele k 20261006b): zákazník zaparkuje motorku PŘED posledním dnem (= jen parkování),
-- později zadá kód znovu (po 60 min grace jednotka bere jako vyjetí, fáze out) a kóji NEotevře (OPEN_TIMEOUT).
-- Trigger dosud přepnul řádek na 'out' už při grantu → motorka stála v kóji, ale po konci termínu ji nedokončil
-- procesor s časem zavření kóje, nýbrž noční cron auto_complete_expired_bookings s returned_at = now() (D3).
-- Noční cron i procesor dokončují vždy až PO posledním dni — to se nemění. Nově:
--  • grant vyjetí jen zapíše detail.pending_out {at, session, event_id} (stav beze změny),
--  • 'out' nastaví až důkaz otevřených dveří: DOOR_OPENED relace vyjetí (≥ 1.2.8: session + fáze ≠ in, i pozdní
--    otevření po OPEN_TIMEOUT; 1.2.7: DOOR_OPENED s čekajícím pending_out) nebo zavření relace vyjetí (záloha),
--  • stará jednotka: dorazil-li důkaz otevření (DOOR_OPENED / zavření > 10 min po zaparkování) DŘÍV než grant
--    vyjetí z outboxu, grant rovnou nastaví 'out' (out_at = čas té události),
--  • grant vrácení s NOVÝM čtením km / zavření vrácení (fáze in) starší čekající vyjetí ruší.
-- Neotevřené vyjetí tak nechá řádek 'parked' → po konci termínu kiosk_process_returns dokončí s returned_at =
-- čas zavření kóje. Tělo funkce = 20261006b + tyto změny (pomocná _kiosk_return_rideout).
-- =============================================================================

-- ── Pomocná: potvrzené vyjetí (dveře kóje opravdu otevřeny) → 'out' ──
-- p_need_pending = stará jednotka / spárované zavření: jen když čeká grant vyjetí (pending_out) ne mladší než
-- otevření. Ze 'skipped' (vráceno, nedokončeno) → 'out' bez starého důvodu, ať další vrácení procesor posoudí
-- znovu a Velín nenabízí ruční dokončení se starým časem, když je motorka venku. 'out' se znovu nepřepisuje.
CREATE OR REPLACE FUNCTION public._kiosk_return_rideout(p_booking_id uuid, p_branch_id uuid, p_ts timestamptz,
  p_session text, p_event text, p_event_id uuid, p_need_pending boolean)
RETURNS void
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE booking_kiosk_returns k
     SET state = 'out',
         out_at = LEAST(COALESCE((k.detail->'pending_out'->>'at')::timestamptz, p_ts), p_ts),
         last_event_at = now(),
         reason = CASE WHEN k.state = 'skipped' THEN NULL ELSE k.reason END,
         completed_at = CASE WHEN k.state = 'skipped' THEN NULL ELSE k.completed_at END,
         session_id = COALESCE(p_session, k.detail->'pending_out'->>'session', k.session_id),
         detail = (CASE WHEN k.state = 'skipped' THEN k.detail - 'errors' ELSE k.detail END) - 'pending_out'
                  || jsonb_build_object('last_event', p_event, 'last_event_id', p_event_id, 'out_confirmed_by', p_event)
   WHERE k.booking_id = p_booking_id AND k.branch_id = p_branch_id
     AND k.state IN ('returning', 'parked', 'skipped')
     AND p_ts > GREATEST(k.closed_at, k.grant_at, k.out_at)
     AND (p_session IS NULL OR p_session IS DISTINCT FROM k.session_id)   -- relace vyjetí ≠ relace vrácení
     AND (NOT p_need_pending
          OR (k.detail ? 'pending_out' AND (k.detail->'pending_out'->>'at')::timestamptz <= p_ts));
$$;
ALTER FUNCTION public._kiosk_return_rideout(uuid, uuid, timestamptz, text, text, uuid, boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION public._kiosk_return_rideout(uuid, uuid, timestamptz, text, text, uuid, boolean) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public._kiosk_return_rideout(uuid, uuid, timestamptz, text, text, uuid, boolean) IS
  'Potvrzené vyjetí motorky po zaparkování (otevřené dveře kóje) → booking_kiosk_returns.state out (2026-10-07). Volá jen _kiosk_return_from_door_event.';

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
  v_pair_at timestamptz;
  v_pair_rd text;
BEGIN
  -- nouzové servisní otevření (zone_access.service_unlock_locked) nese booking běžící relace, ale není to
  -- zákaznický grant (bez fáze) → nesmí řádek přepnout na 'out' ani posloužit k párování
  IF NEW.kind IS DISTINCT FROM 'motorcycle' OR v_event IS NULL OR NEW.detail->>'emergency' = 'true' THEN
    RETURN NULL;
  END IF;
  v_ts := public._kiosk_event_ts(NEW.detail, NEW.created_at);

  IF NEW.booking_id IS NULL THEN
    -- kóji otevřel kód BEZ rezervace (krátkodobý kód z Velína — online i z offline cache): zaparkovaná motorka mohla
    -- odjet → 'out' (dokončení počká na další vrácení / obsluhu, starý čas zavření se nepoužije); completed beze změny
    IF NEW.success IS TRUE AND v_event = 'ACCESS_GRANTED' AND NEW.door_id IS NOT NULL THEN
      UPDATE booking_kiosk_returns k
         SET state = 'out', out_at = v_ts, last_event_at = now(),
             detail = k.detail || jsonb_build_object('last_event', 'FOREIGN_GRANT', 'last_event_id', NEW.id)
       WHERE k.door_id = NEW.door_id AND k.branch_id = NEW.branch_id AND k.state IN ('returning', 'parked')
         AND v_ts > GREATEST(k.closed_at, k.grant_at, k.out_at);
    END IF;
    RETURN NULL;
  END IF;

  IF v_event = 'OPEN_TIMEOUT' THEN
    -- opakovaný kód po zaparkování (grace jednotky → fáze in, bez nových km) a kóje neotevřena → motorka pořád
    -- stojí v kóji: zpět 'parked' (jinak by řádek uvízl v 'returning'); po vyjetí (closed_at < out_at) nic
    IF NEW.success IS FALSE AND NOT (NEW.detail ? 'odometer_reading_id') THEN
      UPDATE booking_kiosk_returns k
         SET state = 'parked', last_event_at = now(),
             detail = k.detail || jsonb_build_object('last_event', v_event, 'last_event_id', NEW.id)
       WHERE k.booking_id = NEW.booking_id AND k.branch_id = NEW.branch_id
         AND k.state = 'returning' AND k.closed_at IS NOT NULL
         AND k.closed_at >= COALESCE(k.out_at, '-infinity')
         AND (v_session IS NULL OR k.session_id = v_session);
    END IF;
    RETURN NULL;
  END IF;

  IF v_event = 'DOOR_OPENED' THEN
    -- (2026-10-07) dveře kóje se OPRAVDU otevřely v relaci vyjetí → teprve teď motorka mohla odjet:
    -- ≥ 1.2.8 = relace s session a fází ≠ in (i pozdní otevření po OPEN_TIMEOUT nese tutéž relaci);
    -- 1.2.7 (bez session/fáze) = jen když čeká grant vyjetí (detail.pending_out) starší než toto otevření
    IF NEW.success IS TRUE AND v_phase IS DISTINCT FROM 'in' THEN
      PERFORM public._kiosk_return_rideout(NEW.booking_id, NEW.branch_id, v_ts, v_session, v_event, NEW.id,
                                           v_session IS NULL);
      RETURN NULL;
    END IF;
    -- znovuotevření kóje v potvrzovacím okně (táž relace vrácení; jen jednotka ≥ 1.2.8 nese fázi + session):
    -- dokončení počká na další zavření, které vrátí 'parked' s pozdějším closed_at (D3)
    IF NEW.success IS TRUE AND v_phase = 'in' AND v_session IS NOT NULL THEN
      UPDATE booking_kiosk_returns k
         SET state = 'returning', last_event_at = now(),
             detail = k.detail || jsonb_build_object('last_event', v_event, 'last_event_id', NEW.id, 'reopened', true)
       WHERE k.booking_id = NEW.booking_id AND k.branch_id = NEW.branch_id AND k.state = 'parked'
         AND k.session_id = v_session AND v_ts > k.closed_at;
    END IF;
    RETURN NULL;
  END IF;

  IF NEW.success IS NOT TRUE OR v_event NOT IN ('ACCESS_GRANTED', 'DOOR_CLOSED', 'SESSION_COMPLETED') THEN
    RETURN NULL;
  END IF;
  -- kiosk_log_open booking_id neověřuje → jen rezervace s vydaným kódem motorky na pobočce zařízení
  IF NOT EXISTS (SELECT 1 FROM branch_door_codes c
                  WHERE c.booking_id = NEW.booking_id AND c.branch_id = NEW.branch_id
                    AND c.code_type = 'motorcycle' AND c.sent_to_customer) THEN
    RETURN NULL;
  END IF;
  IF NEW.door_id IS NOT NULL THEN
    SELECT d.box_number INTO v_box FROM branch_doors d WHERE d.id = NEW.door_id;
  END IF;
  IF v_box IS NULL AND NEW.detail->>'box_number' ~ '^[0-9]{1,4}$' THEN
    v_box := (NEW.detail->>'box_number')::integer;
  END IF;

  IF v_event = 'ACCESS_GRANTED' THEN
    IF v_phase IS DISTINCT FROM 'in' THEN
      -- kód vyjetí (out / bez fáze) po zaparkování: (2026-10-07) motorka ještě NEodjela — kód mohl skončit
      -- OPEN_TIMEOUT (dveře neotevřeny, motorka dál v kóji). Jen zapsat čekající vyjetí; 'out' nastaví až otevření
      -- dveří (DOOR_OPENED / zavření relace vyjetí). Jinak by takto zaparkovaná motorka po konci termínu
      -- nedostala čas vrácení = zavření kóje (dokončil by ji noční cron s now()). Převzetí řádek nezakládá.
      UPDATE booking_kiosk_returns k
         SET last_event_at = now(),
             detail = k.detail || jsonb_build_object('pending_out', jsonb_build_object('at', v_ts, 'session', v_session,
                                                     'event_id', NEW.id), 'last_event', v_event, 'last_event_id', NEW.id)
       WHERE k.booking_id = NEW.booking_id AND k.state IN ('returning', 'parked', 'skipped')
         AND v_ts > GREATEST(k.closed_at, k.grant_at, k.out_at);
      -- stará jednotka (bez session): otevření / zavření relace vyjetí mohlo dorazit DŘÍV než tento grant z outboxu
      -- (tehdy bez čekajícího vyjetí nic nezměnilo) → událost dveří > 10 min po zaparkované relaci = důkaz → 'out'
      IF v_session IS NULL AND FOUND THEN
        SELECT min(e.created_at) INTO v_pair_at
          FROM booking_kiosk_returns k
          JOIN branch_door_events e ON e.booking_id = k.booking_id AND e.branch_id = NEW.branch_id
         WHERE k.booking_id = NEW.booking_id AND e.kind = 'motorcycle' AND e.success IS TRUE AND e.id <> NEW.id
           AND e.detail->>'event' IN ('DOOR_OPENED', 'DOOR_CLOSED', 'SESSION_COMPLETED')
           AND e.detail->>'session_id' IS NULL
           AND e.created_at > GREATEST(k.closed_at, k.grant_at) + interval '10 minutes'
           AND e.created_at <= NEW.created_at;
        IF v_pair_at IS NOT NULL THEN
          PERFORM public._kiosk_return_rideout(NEW.booking_id, NEW.branch_id, v_pair_at, NULL, v_event, NEW.id, false);
        END IF;
      END IF;
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
                   WHEN EXCLUDED.reading_id = k.reading_id AND k.closed_at IS NOT NULL
                     THEN k.state                                       -- tentýž grant znovu z outboxu (stará jednotka bez ts)
                   WHEN k.closed_at >= EXCLUDED.grant_at THEN k.state   -- zavření dorazilo dřív než jeho grant
                   WHEN k.out_at >= EXCLUDED.grant_at THEN k.state      -- starý grant (motorka mezitím vyjela)
                   ELSE 'returning' END,
      grant_at   = CASE WHEN EXCLUDED.reading_id = k.reading_id THEN k.grant_at
                        ELSE GREATEST(k.grant_at, EXCLUDED.grant_at) END,
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
      detail     = CASE WHEN EXCLUDED.reading_id IS NOT NULL AND EXCLUDED.reading_id IS DISTINCT FROM k.reading_id
                             AND (k.detail->'pending_out'->>'at')::timestamptz < EXCLUDED.grant_at
                        THEN k.detail - 'pending_out' ELSE k.detail END || EXCLUDED.detail;
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
    SELECT COALESCE(NULLIF(e.detail->>'odometer_phase', ''), 'out'), 'paired', e.created_at,
           lower(e.detail->>'odometer_reading_id')
      INTO v_phase, v_src, v_pair_at, v_pair_rd
      FROM branch_door_events e
     WHERE e.booking_id = NEW.booking_id AND e.branch_id = NEW.branch_id AND e.kind = 'motorcycle'
       AND e.success IS TRUE AND e.detail->>'event' = 'ACCESS_GRANTED' AND e.id <> NEW.id
       AND e.detail->>'emergency' IS DISTINCT FROM 'true'
       AND e.created_at <= NEW.created_at AND e.created_at >= NEW.created_at - interval '12 hours'
     ORDER BY e.created_at DESC LIMIT 1;
    -- stará jednotka: relace spárovaného grantu 'in' už byla zavřena (closed_at ≥ grant; i jeho kopie z outboxu se
    -- stejným reading_id) a toto zavření přišlo o > 10 min později → patří jiné relaci (vyjetí, jehož grant
    -- ještě nedorazil z outboxu) → fáze neznámá, nic. Zavření téže relace (potvrzovací okno) je do 10 min.
    IF v_phase = 'in' AND EXISTS (SELECT 1 FROM booking_kiosk_returns k
                                   WHERE k.booking_id = NEW.booking_id AND v_ts > k.closed_at + interval '10 minutes'
                                     AND (k.closed_at >= v_pair_at
                                          OR (v_pair_rd = k.reading_id::text AND k.closed_at >= k.grant_at))) THEN
      RETURN NULL;
    END IF;
  END IF;
  IF COALESCE(v_phase, 'out') <> 'in' THEN
    -- převzetí / vyjetí: zavření relace vyjetí dokládá otevřené dveře (záloha za ztracený DOOR_OPENED);
    -- spárované (stará jednotka) jen s čekajícím vyjetím
    PERFORM public._kiosk_return_rideout(NEW.booking_id, NEW.branch_id, v_ts, v_session, v_event, NEW.id,
                                         COALESCE(v_src = 'paired', true) OR v_session IS NULL);
    RETURN NULL;
  END IF;

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
    -- pozdní znovuzavření v okně, když doběh kódů už skončil → doběh znovu otevřít, ať cron posune returned_at (D3)
    codes_closed_at = CASE WHEN k.state = 'completed' AND EXCLUDED.closed_at > k.closed_at
                             AND EXCLUDED.closed_at <= COALESCE(k.moto_code_until, k.closed_at + interval '15 minutes') + interval '5 minutes'
                           THEN NULL ELSE k.codes_closed_at END,
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
    detail     = CASE WHEN (k.detail->'pending_out'->>'at')::timestamptz < EXCLUDED.closed_at
                      THEN k.detail - 'pending_out' ELSE k.detail END || EXCLUDED.detail
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
  'branch_door_events → booking_kiosk_returns (2026-10-06, 2026-10-07): ACCESS_GRANTED in = returning (kopie grantu se stejným reading_id po zavření stav nemění), zavření kóje fáze in = parked, kód vyjetí po zaparkování jen detail.pending_out — out (i ze skipped) až po otevření dveří (DOOR_OPENED / zavření relace vyjetí; 1.2.7 jen s pending_out), OPEN_TIMEOUT opakovaného kódu = zpět parked, DOOR_OPENED téže relace vrácení (≥ 1.2.8) = zpět returning, grant kódu bez rezervace (krátkodobý) na kóji = out; stará jednotka: zavření > 10 min po zavřené relaci spárovaného grantu se ignoruje; pozdní znovuzavření v okně otevře doběh kódů. Jen levné čtení + 1 zápis, bookings/kódy nemění (dokončuje cron kiosk_process_returns). Chyba = WARNING.';
