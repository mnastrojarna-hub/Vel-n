-- =============================================================================
-- AKTIVACE REZERVACE I PO VRATCE Z ÚPRAVY (partial_refund / refund_pending)
-- Migrace: 20260929a_booking_activation_refund_states.sql
--
-- NÁLEZ 2026-09-29 (review „Nadcházející do podpisu protokolu“): rezervace,
-- které zákazník před vyzvednutím zkrátil nebo vyměnil motorku za levnější,
-- má payment_status 'partial_refund' (process-refund; 'refund_pending' dokud
-- Stripe vratku nepotvrdí) — stav běžný a trvalý. Kódy ke dveřím platí, kiosk
-- motorku vydá, zákazník podepíše protokol — ale tři aktivační místa pouštěla
-- do 'active' JEN 'paid', takže rezervace zůstala 'reserved' po celou jízdu
-- (Velín i appka „Nadcházející“, bez picked_up_at; SOS/záznam jízdy/vrácení
-- s tím počítají). _activate_on_handover_protocol_doc a druhá větev
-- _activate_on_protocol_signed už tyto stavy pouštěly — sjednoceno.
--
-- Těla = živé verze (supabase-live-snapshot 2026-09-29) 1:1, změněna jen
-- podmínka payment_status. Idempotentní (CREATE OR REPLACE), granty zůstávají.
-- =============================================================================

CREATE OR REPLACE FUNCTION "public"."_activate_booking_on_door_open"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_event text := COALESCE(NEW.detail->>'event', '');
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  IF NEW.booking_id IS NULL OR NEW.success IS NOT TRUE OR NEW.kind <> 'motorcycle' THEN
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
END; $$;

CREATE OR REPLACE FUNCTION "public"."_activate_on_protocol_signed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_opened timestamptz; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
BEGIN
  IF NEW.status <> 'reserved' OR NEW.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') OR NEW.is_test IS TRUE THEN RETURN NULL; END IF;
  IF NOT COALESCE(public._is_self_service_booking(NEW.id), false) THEN RETURN NULL; END IF;
  IF (NEW.start_date AT TIME ZONE 'Europe/Prague')::date > v_today
     OR (NEW.end_date AT TIME ZONE 'Europe/Prague')::date < v_today THEN RETURN NULL; END IF;
  SELECT min(e.created_at) INTO v_opened FROM public.branch_door_events e
   WHERE e.booking_id = NEW.id AND e.kind = 'motorcycle' AND e.success IS TRUE
     AND COALESCE(e.detail->>'event','') IN ('','ACCESS_GRANTED','DOOR_OPENED')
     AND e.created_at >= public._door_code_valid_from(NEW.start_date);
  IF v_opened IS NULL THEN RETURN NULL; END IF;
  UPDATE public.bookings SET status = 'active', picked_up_at = COALESCE(picked_up_at, v_opened)
   WHERE id = NEW.id AND status = 'reserved';
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_activate_on_protocol_signed failed for booking %: %', NEW.id, SQLERRM; RETURN NULL;
END; $$;

CREATE OR REPLACE FUNCTION "public"."auto_activate_reserved_bookings"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
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
    -- Samoobslužné pobočky se aktivují zadáním kódu do boxu (trigger
    -- _activate_booking_on_door_open). Cron je tu jen POJISTKA pro případ,
    -- že signál z jednotky nedorazí (výpadek LTE, ruční výdej obsluhou) —
    -- proto až DEN PO začátku termínu; v den vyzvednutí musí rezervace
    -- zůstat 'reserved', aby šel bezplatný posun termínu.
    AND (
      b.start_date::date < CURRENT_DATE
      OR NOT EXISTS (
        SELECT 1 FROM motorcycles m
        JOIN branches br ON br.id = m.branch_id
        WHERE m.id = b.moto_id AND br.type = 'samoobslužná'
      )
    );
END;
$$;
