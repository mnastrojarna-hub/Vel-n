-- =============================================================================
-- 2026-10-11 BEZPEČNOST (část _b k 20261011c): sos_swap_bookings
-- Dřív BEZ kontroly volajícího: kdokoli s UUID incidentu ukončil cizí
-- rezervaci, založil „zaplacenou“ 0 Kč náhradu na libovolné motorce a poslal
-- motorku do servisu. Nově:
--   admin / server (_rpc_caller_is_staff) — beze změny (Velín: ceny, is_free);
--   zákazník — jen vlastní OTEVŘENÝ incident a vlastní rezervace, cena vždy
--   serverová (náhrada zdarma = jediná cesta appky), náhradní motorka musí být
--   aktivní/servisní kus, ne původní, a volná v celém zbytku termínu
--   (check_moto_availability + kalendář get_moto_booked_dates: rezervace,
--   vozík, servisní blok, zavřená pobočka). Odmítnutí zákazníka = výjimka, aby
--   ho appka ukázala (toast), místo falešného „objednáno“.
-- Tělo = živá definice, měněno jen označené „2026-10-11“. Idempotentní.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.sos_swap_bookings(p_incident_id uuid, p_replacement_moto_id uuid, p_replacement_model text DEFAULT NULL::text, p_delivery_fee numeric DEFAULT 0, p_daily_price numeric DEFAULT 0, p_is_free boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_incident record;
  v_booking record;
  v_original_end date;
  v_new_booking_id uuid;
  v_remaining_days int;
  v_total_price numeric;
  v_today date := CURRENT_DATE;
  v_already_ended boolean := false;
  v_debug text := '';
  v_payment payment_status;
  v_status booking_status := 'active';
  v_uid uuid := auth.uid();                              -- 2026-10-11
  v_staff boolean := public._rpc_caller_is_staff();      -- 2026-10-11
BEGIN
  SELECT * INTO v_incident FROM sos_incidents WHERE id = p_incident_id;
  -- 2026-10-11: zákazník jen vlastní otevřený incident (anon nikdy)
  IF NOT v_staff THEN
    IF v_uid IS NULL OR v_incident.user_id IS DISTINCT FROM v_uid THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
    END IF;
    IF v_incident.status IN ('resolved'::sos_status, 'closed'::sos_status) THEN
      RAISE EXCEPTION 'Incident je uzavřen — náhradní motorku vyřídí operátor MotoGo24.';
    END IF;
    -- cenu u zákazníka určuje server: náhrada z appky je vždy zdarma
    p_is_free := true; p_daily_price := 0; p_delivery_fee := 0;
  END IF;
  IF v_incident IS NULL THEN
    RETURN jsonb_build_object('error', 'Incident not found', 'step', 'find_incident');
  END IF;

  -- 1. Active paid booking for today
  SELECT * INTO v_booking FROM bookings
    WHERE user_id = v_incident.user_id
      AND status IN ('active'::booking_status, 'pending'::booking_status, 'reserved'::booking_status)
      AND payment_status = 'paid'::payment_status
      AND start_date::date <= v_today
      AND end_date::date >= v_today
    ORDER BY start_date DESC LIMIT 1;
  IF v_booking IS NOT NULL THEN v_debug := 'found_via_active_paid'; END IF;

  -- 2. Any non-cancelled/completed booking
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND status NOT IN ('cancelled'::booking_status, 'completed'::booking_status)
        AND start_date::date <= v_today
        AND end_date::date >= v_today
      ORDER BY start_date DESC LIMIT 1;
    IF v_booking IS NOT NULL THEN v_debug := 'found_via_any_active'; END IF;
  END IF;

  -- 3. By incident booking_id
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id
        AND status NOT IN ('cancelled'::booking_status, 'completed'::booking_status);
    IF v_booking IS NOT NULL THEN v_debug := 'found_via_incident_booking_id'; END IF;
  END IF;

  -- 4. Already ended by SOS
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND ended_by_sos = true
        AND status = 'completed'::booking_status
        AND end_date::date >= v_today - 1
      ORDER BY end_date DESC, created_at DESC LIMIT 1;
    IF v_booking IS NOT NULL THEN
      v_already_ended := true;
      v_debug := 'found_via_ended_by_sos';
    END IF;
  END IF;

  -- 5. By incident booking_id (any non-cancelled)
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id AND status != 'cancelled'::booking_status;
    IF v_booking IS NOT NULL THEN
      IF v_booking.status = 'completed'::booking_status AND v_booking.ended_by_sos = true THEN
        v_already_ended := true;
      END IF;
      v_debug := 'found_via_incident_booking_id_any';
    END IF;
  END IF;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'No booking found for user',
      'step', 'find_booking',
      'user_id', v_incident.user_id,
      'incident_booking_id', v_incident.booking_id
    );
  END IF;

  -- 2026-10-11: sos_incidents.booking_id zákazník zapisuje sám (RLS) — cizí
  -- rezervace přes kroky 3/5 se nesmí ukončit
  IF NOT v_staff AND v_booking.user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  -- 2026-10-11: opakované volání appky (dvojklik / retry) najde krokem 1 už
  -- náhradní rezervaci TOHOTO incidentu → vrátit ji, nezakládat řetěz náhrad
  IF NOT v_staff AND v_booking.sos_replacement IS TRUE AND v_booking.sos_incident_id = p_incident_id THEN
    RETURN jsonb_build_object(
      'success', true,
      'original_booking_id', v_booking.replacement_for_booking_id,
      'replacement_booking_id', v_booking.id,
      'remaining_days', 1,
      'total_price', 0,
      'already_existed', true,
      'debug', 'double_swap_protection'
    );
  END IF;

  -- Double-swap protection
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE replacement_for_booking_id = v_booking.id
      AND sos_replacement = true
      AND status != 'cancelled'::booking_status
  ) THEN
    SELECT id INTO v_new_booking_id FROM bookings
      WHERE replacement_for_booking_id = v_booking.id
        AND sos_replacement = true
        AND status != 'cancelled'::booking_status
      LIMIT 1;
    RETURN jsonb_build_object(
      'success', true,
      'original_booking_id', v_booking.id,
      'replacement_booking_id', v_new_booking_id,
      'remaining_days', 1,
      'total_price', 0,
      'already_existed', true,
      'debug', 'double_swap_protection'
    );
  END IF;

  -- Calculate dates
  v_original_end := COALESCE(v_booking.original_end_date, v_booking.end_date)::date;
  IF v_original_end < v_today THEN
    v_original_end := v_today;
  END IF;
  v_remaining_days := GREATEST(1, (v_original_end - v_today) + 1);

  -- 2026-10-11: zákazník jen volnou motorku (SOS náhrada je vyjmutá z
  -- check_booking_overlap — bez této kontroly by vzal i motorku jiného zákazníka)
  IF NOT v_staff AND (
       p_replacement_moto_id IS NULL
       OR p_replacement_moto_id = v_booking.moto_id
       OR NOT EXISTS (SELECT 1 FROM motorcycles m
                       WHERE m.id = p_replacement_moto_id
                         AND m.status IN ('active'::moto_status, 'maintenance'::moto_status))
       OR NOT public.check_moto_availability(p_replacement_moto_id, v_today::timestamptz,
                                             v_original_end::timestamptz, v_booking.id)
       OR EXISTS (SELECT 1 FROM public.get_moto_booked_dates(p_replacement_moto_id) d
                   WHERE d.start_date <= v_original_end AND d.end_date >= v_today)) THEN
    RAISE EXCEPTION 'Vybraná motorka není do konce pronájmu volná — vyberte prosím jinou.';
  END IF;

  v_total_price := CASE WHEN p_is_free THEN 0 ELSE (p_daily_price * v_remaining_days + p_delivery_fee) END;

  -- Payment status as proper ENUM
  v_payment := CASE WHEN p_is_free THEN 'paid'::payment_status ELSE 'unpaid'::payment_status END;

  -- Step 1: End original booking
  IF NOT v_already_ended THEN
    BEGIN
      UPDATE bookings SET
        original_end_date = CASE WHEN original_end_date IS NULL THEN end_date ELSE original_end_date END,
        end_date = v_today,
        status = 'completed'::booking_status,
        ended_by_sos = true,
        sos_incident_id = p_incident_id
      WHERE id = v_booking.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'sos_swap: original booking update failed: %', SQLERRM;
      BEGIN
        UPDATE bookings SET
          status = 'completed'::booking_status,
          ended_by_sos = true
        WHERE id = v_booking.id;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'sos_swap: even minimal update failed: %', SQLERRM;
      END;
    END;
  END IF;

  -- Step 2: Create replacement booking
  BEGIN
    INSERT INTO bookings (
      user_id, moto_id, start_date, end_date, pickup_time,
      status, payment_status, total_price, delivery_fee,
      sos_replacement, replacement_for_booking_id, sos_incident_id,
      notes, booking_source, picked_up_at
    ) VALUES (
      v_incident.user_id,
      p_replacement_moto_id,
      v_today,
      v_original_end,
      '09:00',
      v_status,
      v_payment,
      v_total_price,
      CASE WHEN p_is_free THEN 0 ELSE p_delivery_fee END,
      true,
      v_booking.id,
      p_incident_id,
      '[SOS] Náhradní motorka. Incident: ' || p_incident_id::text,
      'app',
      NOW()
    )
    RETURNING id INTO v_new_booking_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'error', 'Replacement booking INSERT failed: ' || SQLERRM,
      'step', 'insert_replacement',
      'original_booking_id', v_booking.id,
      'replacement_moto_id', p_replacement_moto_id,
      'dates', v_today::text || ' → ' || v_original_end::text,
      'debug', v_debug,
      'partial', true
    );
  END;

  -- Step 3: Update incident
  UPDATE sos_incidents SET
    original_booking_id = v_booking.id,
    replacement_booking_id = v_new_booking_id,
    original_moto_id = v_booking.moto_id,
    replacement_moto_id = p_replacement_moto_id
  WHERE id = p_incident_id;

  -- Step 4: Original moto to maintenance
  UPDATE motorcycles SET status = 'maintenance'::moto_status
  WHERE id = v_booking.moto_id;

  RETURN jsonb_build_object(
    'success', true,
    'original_booking_id', v_booking.id,
    'replacement_booking_id', v_new_booking_id,
    'remaining_days', v_remaining_days,
    'total_price', v_total_price,
    'original_end_date', v_original_end,
    'debug', v_debug
  );
END;
$function$;
