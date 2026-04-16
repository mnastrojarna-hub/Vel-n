-- ═══════════════════════════════════════════════════════════════
-- 2026-03-15c: Fix SOS swap — check_booking_overlap exemption
--              + robust sos_swap_bookings + data cleanup
--
-- Problémy:
-- 1. check_booking_overlap() NEMÁ výjimku pro sos_replacement=true
--    → INSERT nové SOS rezervace selže pokud má náhradní motorka
--      jakoukoliv overlapping rezervaci
-- 2. sos_swap_bookings nedetekuje existující replacement booking
--    (double-swap protection)
-- 3. Booking v nekonzistentním stavu: active + ended_by_sos=true
-- ═══════════════════════════════════════════════════════════════

-- 1) check_booking_overlap: přidána výjimka pro sos_replacement + completed
CREATE OR REPLACE FUNCTION check_booking_overlap()
RETURNS TRIGGER AS $$
BEGIN
  -- SOS replacement bookings are exempt from moto overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Překrývající se rezervace pro moto_id %', NEW.moto_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2) Data cleanup: fix booking se stavem active + ended_by_sos
UPDATE bookings
SET status = 'completed'
WHERE ended_by_sos = true
  AND status IN ('active', 'pending');

-- 3) Robustnější sos_swap_bookings s debug info + double-swap protection
CREATE OR REPLACE FUNCTION sos_swap_bookings(
  p_incident_id uuid,
  p_replacement_moto_id uuid,
  p_replacement_model text DEFAULT NULL,
  p_delivery_fee numeric DEFAULT 0,
  p_daily_price numeric DEFAULT 0,
  p_is_free boolean DEFAULT true
)
RETURNS jsonb AS $$
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
BEGIN
  SELECT * INTO v_incident FROM sos_incidents WHERE id = p_incident_id;
  IF v_incident IS NULL THEN
    RETURN jsonb_build_object('error', 'Incident not found', 'step', 'find_incident');
  END IF;

  -- 1. Active paid booking for today
  SELECT * INTO v_booking FROM bookings
    WHERE user_id = v_incident.user_id
      AND status IN ('active', 'pending', 'reserved')
      AND payment_status = 'paid'
      AND start_date::date <= v_today
      AND end_date::date >= v_today
    ORDER BY start_date DESC LIMIT 1;
  IF v_booking IS NOT NULL THEN v_debug := 'found_via_active_paid'; END IF;

  -- 2. Any non-cancelled/completed booking
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND status NOT IN ('cancelled', 'completed')
        AND start_date::date <= v_today
        AND end_date::date >= v_today
      ORDER BY start_date DESC LIMIT 1;
    IF v_booking IS NOT NULL THEN v_debug := 'found_via_any_active'; END IF;
  END IF;

  -- 3. By incident booking_id (non-cancelled/completed)
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id
        AND status NOT IN ('cancelled', 'completed');
    IF v_booking IS NOT NULL THEN v_debug := 'found_via_incident_booking_id'; END IF;
  END IF;

  -- 4. Already ended by SOS (within 1 day)
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND ended_by_sos = true
        AND status = 'completed'
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
      WHERE id = v_incident.booking_id AND status != 'cancelled';
    IF v_booking IS NOT NULL THEN
      IF v_booking.status = 'completed' AND v_booking.ended_by_sos = true THEN
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

  -- Double-swap protection: check if replacement already exists
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE replacement_for_booking_id = v_booking.id
      AND sos_replacement = true
      AND status != 'cancelled'
  ) THEN
    SELECT id INTO v_new_booking_id FROM bookings
      WHERE replacement_for_booking_id = v_booking.id
        AND sos_replacement = true
        AND status != 'cancelled'
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
  v_total_price := CASE WHEN p_is_free THEN 0 ELSE (p_daily_price * v_remaining_days + p_delivery_fee) END;

  -- Step 1: End original booking
  IF NOT v_already_ended THEN
    BEGIN
      UPDATE bookings SET
        original_end_date = CASE WHEN original_end_date IS NULL THEN end_date ELSE original_end_date END,
        end_date = v_today,
        status = 'completed',
        ended_by_sos = true,
        sos_incident_id = p_incident_id
      WHERE id = v_booking.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'sos_swap: original booking update failed: %', SQLERRM;
      BEGIN
        UPDATE bookings SET
          status = 'completed',
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
      'active',
      CASE WHEN p_is_free THEN 'paid' ELSE 'unpaid' END,
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
  UPDATE motorcycles SET status = 'maintenance'
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
$$ LANGUAGE plpgsql SECURITY DEFINER;
