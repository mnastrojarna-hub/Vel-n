-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — aktivace a předávací protokol (6/14)
-- Pobočka výbavy z rezervace: _is_self_service_booking (→ _kiosk_release_at, get_handover_protocol_state,
-- start_handover_protocol_window), _gate_obsluzna_activation, _activate_on_handover_protocol_doc,
-- _handover_signed_notify_kiosk; _activate_on_protocol_signed (výbava = první grant/otevření šatny),
-- _activate_booking_on_door_open (výbava: grant šatny po podpisu z Velínu), auto_activate_reserved_bookings,
-- _handover_from_door_event (výbava: push k podpisu jen s viditelnou výbavou v appce, tykání).
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._is_self_service_booking(p_booking_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(br.type = 'samoobslužná', false)
  FROM bookings b
  -- 2026-10-23: LEFT JOIN + CASE — výpůjčka výbavy bere pobočku z rezervace; motorka beze změny
  -- (bez motorky → m.branch_id NULL → žádný řádek → NULL jako dřív)
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  JOIN branches br   ON br.id = CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END
  WHERE b.id = p_booking_id
$function$
;

CREATE OR REPLACE FUNCTION public._gate_obsluzna_activation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_type text;
BEGIN
  IF NEW.status <> 'active' OR OLD.status = 'active' THEN RETURN NEW; END IF;
  IF NEW.handover_protocol_filled_at IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.booking_kind = 'gear' THEN
    -- 2026-10-23: výpůjčka výbavy — typ pobočky z rezervace (bookings.branch_id)
    SELECT br.type INTO v_type FROM branches br WHERE br.id = NEW.branch_id;
  ELSE
    SELECT br.type INTO v_type FROM motorcycles m JOIN branches br ON br.id = m.branch_id WHERE m.id = NEW.moto_id;
  END IF;
  IF v_type = 'obslužná' THEN
    NEW.status := 'reserved'; NEW.picked_up_at := OLD.picked_up_at;
  ELSIF v_type = 'samoobslužná' AND NEW.sos_replacement IS NOT TRUE
        AND COALESCE(NEW.pickup_method,'') <> 'delivery' AND btrim(COALESCE(NEW.pickup_address,'')) = '' THEN
    NEW.status := 'reserved'; NEW.picked_up_at := OLD.picked_up_at;
  END IF;
  RETURN NEW;
END; $function$
;

CREATE OR REPLACE FUNCTION public._activate_on_handover_protocol_doc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_obsluzna boolean;
  v_status   text;
  v_pay      text;
BEGIN
  -- Jen elektronický PŘEDÁVACÍ protokol (ne damage/contract/vop/gdpr).
  IF COALESCE(NEW.filled_data->>'_doc_type', '') <> 'handover_protocol' THEN
    RETURN NEW;
  END IF;
  IF NEW.booking_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT b.status::text, b.payment_status::text,
         COALESCE(br.type = 'obslužná', false)
    INTO v_status, v_pay, v_obsluzna
  FROM bookings b
  -- 2026-10-23: výpůjčka výbavy = pobočka z rezervace; motorka beze změny (bez motorky žádný řádek)
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  JOIN branches br   ON br.id = CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END
  WHERE b.id = NEW.booking_id;

  -- Aktivace předáním protokolu se týká OBSLUŽNÉ pobočky (samoobslužná = kód
  -- v appce, svoz/delivery = jinak). Mimo obslužnou neaktivujeme.
  IF NOT COALESCE(v_obsluzna, false) THEN
    RETURN NEW;
  END IF;

  IF v_status = 'reserved'
     AND v_pay IN ('paid', 'partial_refund', 'refund_pending') THEN
    -- Podpis předávacího protokolu = motorka reálně předána → aktivuj.
    -- handover_protocol_filled_at PŘÍMO ve stejném UPDATE → projde strážcem.
    UPDATE bookings SET
      status = 'active',
      picked_up_at = COALESCE(picked_up_at, now()),
      handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now())
    WHERE id = NEW.booking_id
      AND status = 'reserved';
  ELSE
    -- Mimo aktivaci alespoň zaznamenej podpis protokolu (idempotentně).
    UPDATE bookings SET
      handover_protocol_filled_at = COALESCE(handover_protocol_filled_at, now())
    WHERE id = NEW.booking_id
      AND handover_protocol_filled_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._handover_signed_notify_kiosk()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_branch uuid;
  d record;
BEGIN
  -- Jen samoobsluha a živá rezervace (obslužné pobočky nastavuje Velín,
  -- auto_complete završuje nevyzvednuté — jednotka nic nečeká)
  IF NEW.status NOT IN ('reserved', 'active') THEN RETURN NULL; END IF;
  IF NOT _is_self_service_booking(NEW.id) THEN RETURN NULL; END IF;
  IF NEW.booking_kind = 'gear' THEN
    v_branch := NEW.branch_id;   -- 2026-10-23: výpůjčka výbavy — pobočka z rezervace
  ELSE
    SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.moto_id;
  END IF;
  IF v_branch IS NULL THEN RETURN NULL; END IF;

  -- Příkaz = urychlení (broadcast ~1 s, po 10 min expiruje); zdroj pravdy je
  -- protocols[] v kiosk_sync_config (sync_config níže + pravidelný sync).
  FOR d IN SELECT id FROM kiosk_devices WHERE branch_id = v_branch AND is_active LOOP
    INSERT INTO kiosk_commands (device_id, branch_id, command, params)
    VALUES (d.id, v_branch, 'protocol_signed', jsonb_build_object('booking_id', NEW.id));
  END LOOP;
  PERFORM kiosk_request_sync(v_branch);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_handover_signed_notify_kiosk failed for booking %: %', NEW.id, SQLERRM;
  RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public._activate_on_protocol_signed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_opened timestamptz; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  IF NEW.status <> 'reserved' OR NEW.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') OR NEW.is_test IS TRUE THEN RETURN NULL; END IF;
  IF NOT COALESCE(public._is_self_service_booking(NEW.id), false) THEN RETURN NULL; END IF;
  IF (NEW.start_date AT TIME ZONE 'Europe/Prague')::date > v_today
     OR (NEW.end_date AT TIME ZONE 'Europe/Prague')::date < v_today THEN RETURN NULL; END IF;
  -- 2026-10-23: výpůjčka výbavy = první úspěšný grant / otevření ŠATNY (kód motorky neexistuje); čas jednotky
  -- (detail.ts — z outboxu doručené převzetí jinak dostane čas doručení, pozdější než potvrzené vrácení)
  SELECT min(CASE WHEN NEW.booking_kind = 'gear' THEN public._kiosk_event_ts(e.detail, e.created_at)
                  ELSE e.created_at END) INTO v_opened FROM public.branch_door_events e
   WHERE e.booking_id = NEW.id AND e.success IS TRUE
     AND e.kind = CASE WHEN NEW.booking_kind = 'gear' THEN 'accessories' ELSE 'motorcycle' END
     AND COALESCE(e.detail->>'event','') IN ('','ACCESS_GRANTED','DOOR_OPENED')
     AND e.created_at >= public._door_code_valid_from(NEW.start_date);
  IF v_opened IS NULL THEN RETURN NULL; END IF;
  UPDATE public.bookings SET status = 'active', picked_up_at = COALESCE(picked_up_at, v_opened)
   WHERE id = NEW.id AND status = 'reserved';
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_activate_on_protocol_signed failed for booking %: %', NEW.id, SQLERRM; RETURN NULL;
END; $function$
;

CREATE OR REPLACE FUNCTION public._activate_booking_on_door_open()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_event text := COALESCE(NEW.detail->>'event', '');
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  IF NEW.booking_id IS NULL OR NEW.success IS NOT TRUE OR NEW.kind <> 'motorcycle' THEN
    -- 2026-10-23: výpůjčka výbavy (bez motorky) — grant / otevření ŠATNY aktivuje, jen když už je protokol
    -- podepsaný (podpis až po zavření šatny aktivuje _activate_on_protocol_signed); motorka beze změny
    IF NEW.booking_id IS NOT NULL AND NEW.success IS TRUE AND NEW.kind = 'accessories'
       AND v_event IN ('', 'ACCESS_GRANTED', 'DOOR_OPENED') THEN
      UPDATE public.bookings b
         SET status       = 'active',
             picked_up_at = COALESCE(b.picked_up_at, public._kiosk_event_ts(NEW.detail, NEW.created_at))
       WHERE b.id = NEW.booking_id
         AND b.booking_kind = 'gear'
         AND b.handover_protocol_filled_at IS NOT NULL
         AND b.status = 'reserved'
         AND b.payment_status IN ('paid', 'partial_refund', 'refund_pending')
         AND (b.start_date AT TIME ZONE 'Europe/Prague')::date <= v_today
         AND (b.end_date   AT TIME ZONE 'Europe/Prague')::date >= v_today;
    END IF;
    RETURN NULL;
  END IF;
  IF v_event <> '' AND v_event NOT IN ('ACCESS_GRANTED', 'DOOR_OPENED') THEN
    RETURN NULL;
  END IF;

  UPDATE public.bookings b
     SET status       = 'active',
         picked_up_at = COALESCE(b.picked_up_at, now())
   WHERE b.id = NEW.booking_id
     AND b.status = 'reserved'
     AND b.payment_status IN ('paid', 'partial_refund', 'refund_pending')   -- 2026-09-29: i po vratce z úpravy
     AND (b.start_date AT TIME ZONE 'Europe/Prague')::date <= v_today
     AND (b.end_date   AT TIME ZONE 'Europe/Prague')::date >= v_today;

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Audit dveří se NIKDY nesmí kvůli aktivaci nezapsat (offline outbox by se
  -- pokoušel donekonečna) — chybu jen zalogujeme.
  RAISE WARNING '_activate_booking_on_door_open failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NULL;
END; $function$
;

CREATE OR REPLACE FUNCTION public.auto_activate_reserved_bookings()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  UPDATE bookings b SET
    status = 'active',
    picked_up_at = COALESCE(b.picked_up_at, NOW())
  WHERE b.status = 'reserved'
    AND b.payment_status IN ('paid', 'partial_refund', 'refund_pending')   -- 2026-09-29: i po vratce z úpravy
    AND b.start_date::date <= CURRENT_DATE
    -- Testovací rezervace se nikdy neaktivují (NEW 2026-08-20)
    AND b.is_test IS NOT TRUE
    -- Obslužné pobočky se aktivují AŽ předávacím protokolem (strážce
    -- _gate_obsluzna_activation), nikoli půlnočním cronem.
    AND NOT EXISTS (
      SELECT 1 FROM motorcycles m
      JOIN branches br ON br.id = m.branch_id
      WHERE m.id = b.moto_id AND br.type = 'obslužná'
    )
    -- 2026-10-23: výpůjčka výbavy (bez motorky) — stejná pravidla, pobočka z rezervace (bookings.branch_id)
    AND NOT (b.booking_kind = 'gear' AND EXISTS (
      SELECT 1 FROM branches br WHERE br.id = b.branch_id AND br.type = 'obslužná'))
    -- Samoobslužné pobočky se aktivují zadáním kódu do boxu (trigger
    -- _activate_booking_on_door_open). Cron je tu jen POJISTKA pro případ,
    -- že signál z jednotky nedorazí (výpadek LTE, ruční výdej obsluhou) —
    -- proto až DEN PO začátku termínu; v den vyzvednutí musí rezervace
    -- zůstat 'reserved', aby šel bezplatný posun termínu.
    AND (
      b.start_date::date < CURRENT_DATE
      OR (NOT EXISTS (
        SELECT 1 FROM motorcycles m
        JOIN branches br ON br.id = m.branch_id
        WHERE m.id = b.moto_id AND br.type = 'samoobslužná'
      )
      AND NOT (b.booking_kind = 'gear' AND EXISTS (
        SELECT 1 FROM branches br WHERE br.id = b.branch_id AND br.type = 'samoobslužná')))
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public._handover_from_door_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_event  text := COALESCE(NEW.detail->>'event', '');
  v_closed boolean;
  v_b      record;
BEGIN
  IF NEW.booking_id IS NULL OR NEW.success IS NOT TRUE THEN RETURN NULL; END IF;
  v_closed := (NEW.kind = 'accessories' AND v_event = 'DOOR_CLOSED');
  IF NOT v_closed AND v_event <> 'PROTOCOL_SHOWN' THEN RETURN NULL; END IF;

  -- (a) první zavření šatny = výbava vyzvednuta (i když je protokol už podepsaný)
  IF v_closed THEN
    UPDATE bookings SET gear_collected_at = now()
     WHERE id = NEW.booking_id AND gear_collected_at IS NULL;
  END IF;

  -- (b) výzva k podpisu: started_at jednou (historie), prompted_at při každé
  --     výzvě (appka na ni reaguje), push nejvýš jednou za 10 minut
  SELECT user_id, status, handover_protocol_filled_at, handover_protocol_prompted_at,
         booking_kind   -- 2026-10-23
    INTO v_b FROM bookings WHERE id = NEW.booking_id;
  IF NOT FOUND OR v_b.handover_protocol_filled_at IS NOT NULL
     OR v_b.status NOT IN ('reserved', 'active') THEN
    RETURN NULL;
  END IF;

  UPDATE bookings
     SET handover_protocol_started_at  = COALESCE(handover_protocol_started_at, now()),
         handover_protocol_prompted_at = now()
   WHERE id = NEW.booking_id;

  IF v_b.user_id IS NOT NULL
     AND (v_b.handover_protocol_prompted_at IS NULL
          OR v_b.handover_protocol_prompted_at < now() - interval '10 minutes') THEN
    IF v_b.booking_kind = 'gear' THEN
      -- 2026-10-23: výpůjčka výbavy — podepisuje se jen na displeji; push (otevře detail rezervace v appce) až
      -- s výbavou viditelnou v appce (app_settings.gear_rental.app_visible), jinak by stará appka otevřela
      -- skrytý řádek (RLS); text tykáním
      IF public._gear_customer_visible() THEN
        PERFORM send_push_via_edge(
          v_b.user_id,
          'Předávací protokol',
          'Podepiš prosím předávací protokol výpůjčky výbavy na displeji pobočky.',
          jsonb_build_object('type', 'handover_protocol', 'id', NEW.booking_id::text)
        );
      END IF;
    ELSE
    PERFORM send_push_via_edge(
      v_b.user_id,
      'Předávací protokol',
      'Podepište prosím předávací protokol — v aplikaci nebo na displeji pobočky.',
      jsonb_build_object('type', 'handover_protocol', 'id', NEW.booking_id::text)
    );
    END IF;
  END IF;

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Audit dveří se NIKDY nesmí kvůli protokolu nezapsat (outbox jednotky by
  -- se pokoušel donekonečna) — chybu jen zalogujeme.
  RAISE WARNING '_handover_from_door_event failed for booking %: %', NEW.booking_id, SQLERRM;
  RETURN NULL;
END;
$function$
;
