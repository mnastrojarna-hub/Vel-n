-- =============================================================================
-- 2026-10-23 (e_b): Výpůjčka výbavy — posun zdarma a extend_booking (odebrání kusu
-- výbavy = e_d).
-- Navazuje na 20261023e_refund_unify.sql (_gear_lines_for_days, _gear_change_dates_check).
-- Motorky beze změny chování. Idempotentní.
-- =============================================================================

-- ---- 1) Posun zdarma ------------------------------------------------------------
-- Tělo dle živé DB. Výbava: místo kolize motorky/zákazníka (výbava se smí
-- překrývat, rozhodnutí §1.9) uzavírka + max. délka + sklad pro přidané dny;
-- zápis s GUC motogo.gear_rpc (strážce gear řádku). Cena se nemění (stejná délka).
CREATE OR REPLACE FUNCTION public.reschedule_booking_free(p_booking_id uuid, p_new_start date, p_new_end date, p_source text DEFAULT 'web_customer'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_bk      bookings%ROWTYPE;
  v_today   date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_hist    jsonb;
  v_chk     jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id;
  -- 2026-10-23e: NULL-bezpečně (rezervace bez vlastníka nepatří nikomu)
  IF NOT FOUND OR v_bk.user_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  -- Motorka nesmí být převzatá: na samoobslužné pobočce překlápí rezervaci na
  -- 'active' zadání kódu do boxu, na obslužné předávací protokol.
  IF v_bk.status <> 'reserved' THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF v_bk.payment_status <> 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;

  -- NOVÉ: posun zdarma jen do konce dne začátku termínu.
  IF v_bk.start_date::date < v_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'term_started');
  END IF;

  IF (p_new_end - p_new_start) <> (v_bk.end_date::date - v_bk.start_date::date) THEN
    RETURN jsonb_build_object('success', false, 'error', 'length_mismatch');
  END IF;

  IF p_new_start < v_today THEN
    RETURN jsonb_build_object('success', false, 'error', 'past_date');
  END IF;

  IF p_new_start = v_bk.start_date::date AND p_new_end = v_bk.end_date::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

  IF v_bk.booking_kind = 'gear' THEN
    -- 2026-10-23e: výbava — uzavírka pobočky, délka, sklad (přidané dny, bez sebe)
    v_chk := public._gear_change_dates_check(v_bk.id, p_new_start, p_new_end);
    IF v_chk IS NOT NULL THEN RETURN v_chk; END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM bookings b
       WHERE b.id <> v_bk.id
         AND b.moto_id = v_bk.moto_id
         AND b.status IN ('pending','reserved','active')
         AND b.start_date::date <= p_new_end
         AND b.end_date::date   >= p_new_start
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'moto_overlap');
    END IF;

    IF EXISTS (
      SELECT 1 FROM bookings b
       JOIN motorcycles m ON m.id = b.moto_id
       WHERE b.id <> v_bk.id
         AND b.user_id = v_bk.user_id
         AND b.status IN ('pending','reserved','active')
         AND m.license_required IS DISTINCT FROM 'N'
         AND b.start_date::date <= p_new_end
         AND b.end_date::date   >= p_new_start
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'customer_overlap');
    END IF;
  END IF;

  v_hist := COALESCE(v_bk.modification_history, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'at', now(),
      'from_start', v_bk.start_date::date, 'from_end', v_bk.end_date::date,
      'to_start', p_new_start, 'to_end', p_new_end,
      'source', COALESCE(p_source,'web_customer'), 'free_move', true
    )
  );

  IF v_bk.booking_kind = 'gear' THEN PERFORM set_config('motogo.gear_rpc', '1', true); END IF;
  UPDATE bookings SET
    start_date           = p_new_start,
    end_date             = p_new_end,
    original_start_date  = COALESCE(original_start_date, v_bk.start_date),
    original_end_date    = COALESCE(original_end_date,   v_bk.end_date),
    modification_history = v_hist
  WHERE id = v_bk.id;

  RETURN jsonb_build_object('success', true, 'new_start', p_new_start, 'new_end', p_new_end, 'free', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', 'server_error',
                            'detail', SQLERRM, 'sqlstate', SQLSTATE);
END;
$$;

-- ---- 2) extend_booking (jen service_role, appka ani web ho nevolají) --------------
-- Motorka beze změny. Výbava: kontrola přidaných dní + cena = gear_per_day × dny.
CREATE OR REPLACE FUNCTION public.extend_booking(p_booking_id uuid, p_new_end_date timestamp with time zone)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    booking RECORD;
    is_available BOOLEAN;
    price_result jsonb;
    extra_price NUMERIC;
    v_chk jsonb;
BEGIN
    SELECT * INTO booking FROM bookings WHERE id = p_booking_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Booking not found');
    END IF;
    IF booking.status NOT IN ('pending', 'active', 'reserved') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Booking cannot be modified');
    END IF;
    IF p_new_end_date <= booking.end_date THEN
        RETURN jsonb_build_object('success', false, 'error', 'New end date must be after current end date');
    END IF;

    IF booking.booking_kind = 'gear' THEN
        v_chk := public._gear_change_dates_check(p_booking_id, booking.start_date::date, p_new_end_date::date);
        IF v_chk IS NOT NULL THEN RETURN v_chk; END IF;
        extra_price := COALESCE(booking.gear_per_day, 0) * (p_new_end_date::date - booking.end_date::date);
        PERFORM set_config('motogo.gear_rpc', '1', true);
        UPDATE bookings
        SET end_date = p_new_end_date,
            total_price = COALESCE(total_price, 0) + extra_price,
            gear_lines = public._gear_lines_for_days(gear_lines, (p_new_end_date::date - start_date::date) + 1)
        WHERE id = p_booking_id;
        RETURN jsonb_build_object('success', true, 'extra_price', extra_price,
            'new_end_date', p_new_end_date, 'new_total', COALESCE(booking.total_price, 0) + extra_price);
    END IF;

    is_available := check_moto_availability(
        booking.moto_id, booking.end_date, p_new_end_date, p_booking_id
    );
    IF NOT is_available THEN
        RETURN jsonb_build_object('success', false, 'error', 'Motorcycle not available');
    END IF;

    -- calc_booking_price_v2 returns jsonb with total_price field
    price_result := calc_booking_price_v2(
        booking.moto_id,
        (booking.end_date + INTERVAL '1 day')::DATE,
        p_new_end_date::DATE
    );
    extra_price := COALESCE((price_result->>'total_price')::numeric, 0);

    UPDATE bookings
    SET end_date = p_new_end_date,
        total_price = COALESCE(total_price, 0) + extra_price
    WHERE id = p_booking_id;

    RETURN jsonb_build_object(
        'success', true,
        'extra_price', extra_price,
        'new_end_date', p_new_end_date,
        'new_total', COALESCE(booking.total_price, 0) + extra_price
    );
END;
$$;
REVOKE ALL ON FUNCTION public.extend_booking(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.extend_booking(uuid, timestamptz) TO service_role;

NOTIFY pgrst, 'reload schema';
