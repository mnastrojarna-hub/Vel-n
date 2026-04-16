-- ═══════════════════════════════════════════════════════
-- FIX: SOS booking swap — original booking must be 'completed'
--
-- Problem: sos_swap_bookings in DB is missing status='completed'
-- on the original booking. This causes:
--   1. Old booking shows as active in calendar (blocks dates)
--   2. User can't make new reservations
--   3. App still finds old booking via apiGetActiveLoan()
-- ═══════════════════════════════════════════════════════

-- 1. Fix overlap check — completed bookings must not block calendar
CREATE OR REPLACE FUNCTION check_booking_overlap()
RETURNS TRIGGER AS $$
BEGIN
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

-- 2. Fix existing bookings that were ended by SOS but still active
UPDATE bookings
SET status = 'completed'
WHERE ended_by_sos = true
  AND status IN ('active', 'pending');

-- 3. Re-create the RPC function with the fix
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
BEGIN
  SELECT * INTO v_incident FROM sos_incidents WHERE id = p_incident_id;
  IF v_incident IS NULL THEN
    RETURN jsonb_build_object('error', 'Incident not found');
  END IF;

  SELECT * INTO v_booking FROM bookings
    WHERE user_id = v_incident.user_id
      AND status IN ('active', 'pending')
      AND payment_status = 'paid'
      AND start_date::date <= v_today
      AND end_date::date >= v_today
    ORDER BY start_date DESC
    LIMIT 1;

  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND status NOT IN ('cancelled', 'completed')
        AND start_date::date <= v_today
        AND end_date::date >= v_today
      ORDER BY start_date DESC
      LIMIT 1;
  END IF;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('error', 'No active booking found for user');
  END IF;

  v_original_end := v_booking.end_date::date;
  v_remaining_days := GREATEST(1, (v_original_end - v_today) + 1);
  v_total_price := CASE WHEN p_is_free THEN 0 ELSE (p_daily_price * v_remaining_days + p_delivery_fee) END;

  -- End original booking — SET STATUS TO COMPLETED
  UPDATE bookings SET
    end_date = v_today,
    status = 'completed',
    ended_by_sos = true,
    sos_incident_id = p_incident_id,
    notes = COALESCE(notes, '') || E'\n[SOS] Ukončeno ke dni ' || v_today::text || '. Náhradní motorka objednána.'
  WHERE id = v_booking.id;

  -- Create replacement booking
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time,
    status, payment_status, total_price, delivery_fee,
    sos_replacement, replacement_for_booking_id, sos_incident_id,
    notes
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
    '[SOS] Náhradní motorka za ' || COALESCE((SELECT model FROM motorcycles WHERE id = v_booking.moto_id), 'původní') || '. Incident: ' || p_incident_id::text
  )
  RETURNING id INTO v_new_booking_id;

  UPDATE sos_incidents SET
    original_booking_id = v_booking.id,
    replacement_booking_id = v_new_booking_id,
    original_moto_id = v_booking.moto_id
  WHERE id = p_incident_id;

  UPDATE motorcycles SET status = 'maintenance'
  WHERE id = v_booking.moto_id;

  RETURN jsonb_build_object(
    'success', true,
    'original_booking_id', v_booking.id,
    'replacement_booking_id', v_new_booking_id,
    'remaining_days', v_remaining_days,
    'total_price', v_total_price,
    'original_end_date', v_original_end
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
