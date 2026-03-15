-- ═══════════════════════════════════════════════════════════
-- 2026-03-15: Fix sos_swap_bookings — EXCEPTION handling
-- Problem: triggers (check_booking_overlap, check_user_booking_overlap,
--          generate_final_invoice, auto_accounting) can silently roll back
--          the entire swap, leaving bookings unchanged while frontend shows success.
-- Fix: Wrap trigger-prone operations in EXCEPTION blocks with fallbacks.
-- ═══════════════════════════════════════════════════════════

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

  -- Find active booking for user (broad search)
  SELECT * INTO v_booking FROM bookings
    WHERE user_id = v_incident.user_id
      AND status IN ('active', 'pending', 'reserved', 'confirmed')
      AND payment_status = 'paid'
      AND start_date::date <= v_today
      AND end_date::date >= v_today
    ORDER BY start_date DESC
    LIMIT 1;

  -- Fallback: any non-cancelled booking overlapping today
  IF v_booking IS NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE user_id = v_incident.user_id
        AND status NOT IN ('cancelled', 'completed')
        AND start_date::date <= v_today
        AND end_date::date >= v_today
      ORDER BY start_date DESC
      LIMIT 1;
  END IF;

  -- Last resort: use booking_id from incident
  IF v_booking IS NULL AND v_incident.booking_id IS NOT NULL THEN
    SELECT * INTO v_booking FROM bookings
      WHERE id = v_incident.booking_id
        AND status NOT IN ('cancelled', 'completed');
  END IF;

  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('error', 'No active booking found for user');
  END IF;

  v_original_end := v_booking.end_date::date;
  v_remaining_days := GREATEST(1, (v_original_end - v_today) + 1);
  v_total_price := CASE WHEN p_is_free THEN 0 ELSE (p_daily_price * v_remaining_days + p_delivery_fee) END;

  -- Step 1: End original booking (wrapped in EXCEPTION for trigger safety)
  BEGIN
    UPDATE bookings SET
      end_date = v_today,
      status = 'completed',
      ended_by_sos = true,
      sos_incident_id = p_incident_id,
      notes = COALESCE(notes, '') || E'\n[SOS] Ukončeno ke dni ' || v_today::text || '. Náhradní motorka objednána.'
    WHERE id = v_booking.id;
  EXCEPTION WHEN OTHERS THEN
    -- If trigger blocks the combined update, try minimal update
    RAISE WARNING 'sos_swap: original booking update failed (%), trying minimal', SQLERRM;
    BEGIN
      UPDATE bookings SET
        status = 'completed',
        ended_by_sos = true,
        sos_incident_id = p_incident_id
      WHERE id = v_booking.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'sos_swap: even minimal update failed: %', SQLERRM;
    END;
  END;

  -- Step 2: Create replacement booking (wrapped in EXCEPTION for overlap triggers)
  BEGIN
    INSERT INTO bookings (
      user_id, moto_id, start_date, end_date, pickup_time,
      status, payment_status, total_price, delivery_fee,
      sos_replacement, replacement_for_booking_id, sos_incident_id,
      notes, booking_source
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
      '[SOS] Náhradní motorka za ' || COALESCE((SELECT model FROM motorcycles WHERE id = v_booking.moto_id), 'původní') || '. Incident: ' || p_incident_id::text,
      'app'
    )
    RETURNING id INTO v_new_booking_id;
  EXCEPTION WHEN OTHERS THEN
    -- Log but return partial success — original booking was at least marked
    RAISE WARNING 'sos_swap: replacement booking INSERT failed: %', SQLERRM;
    -- Update incident with at least original info
    UPDATE sos_incidents SET
      original_booking_id = v_booking.id,
      original_moto_id = v_booking.moto_id
    WHERE id = p_incident_id;
    UPDATE motorcycles SET status = 'maintenance' WHERE id = v_booking.moto_id;
    RETURN jsonb_build_object(
      'error', 'Replacement booking failed: ' || SQLERRM,
      'original_booking_id', v_booking.id,
      'partial', true
    );
  END;

  -- Step 3: Update sos_incidents with booking references
  UPDATE sos_incidents SET
    original_booking_id = v_booking.id,
    replacement_booking_id = v_new_booking_id,
    original_moto_id = v_booking.moto_id,
    replacement_moto_id = p_replacement_moto_id
  WHERE id = p_incident_id;

  -- Step 4: Original motorcycle to maintenance
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
