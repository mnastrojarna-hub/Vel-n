-- =============================================================
-- Fix: confirm_payment fallback sets payment_status='paid'
-- without changing status from 'pending', causing inconsistency.
-- Root cause: nested EXCEPTION handlers split payment_status
-- and status into separate UPDATEs — if second fails,
-- booking shows "Zaplaceno" but "Čeká na platbu".
-- Fix: ALL fallbacks update BOTH fields atomically.
-- =============================================================

CREATE OR REPLACE FUNCTION confirm_payment(
  p_booking_id uuid,
  p_method text DEFAULT 'card'
)
RETURNS jsonb AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_new_status text;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rezervace nenalezena');
  END IF;

  -- Určení cílového stavu
  IF v_booking.status = 'pending' THEN
    IF v_booking.start_date::date <= CURRENT_DATE THEN
      v_new_status := 'active';
    ELSE
      v_new_status := 'reserved';
    END IF;
  ELSE
    v_new_status := v_booking.status;
  END IF;

  -- Pokus 1: kompletní update (payment + status + timestamps)
  BEGIN
    UPDATE bookings SET
      payment_status = 'paid',
      payment_method = p_method,
      status = v_new_status,
      confirmed_at = CASE WHEN v_booking.status = 'pending' AND confirmed_at IS NULL THEN now() ELSE confirmed_at END,
      picked_up_at = CASE WHEN v_booking.status = 'pending' AND v_new_status = 'active' AND picked_up_at IS NULL THEN now() ELSE picked_up_at END
    WHERE id = p_booking_id;

    RETURN jsonb_build_object('success', true, 'transaction_id', 'TXN-' || substr(p_booking_id::text, 1, 8));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'confirm_payment full update failed: %, trying minimal atomic', SQLERRM;
  END;

  -- Pokus 2: ATOMICKÝ fallback — payment_status + status SPOLU, bez timestamps
  -- NIKDY nenastavovat payment_status='paid' bez současné změny status!
  BEGIN
    UPDATE bookings SET
      payment_status = 'paid',
      payment_method = p_method,
      status = v_new_status
    WHERE id = p_booking_id;

    RETURN jsonb_build_object('success', true, 'transaction_id', 'TXN-' || substr(p_booking_id::text, 1, 8));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'confirm_payment atomic fallback also failed: %', SQLERRM;
  END;

  -- Pokus 3: jen payment_status + status SPOLU, jiný cast
  BEGIN
    UPDATE bookings SET
      payment_status = 'paid'::payment_status,
      payment_method = p_method,
      status = v_new_status::booking_status
    WHERE id = p_booking_id;

    RETURN jsonb_build_object('success', true, 'transaction_id', 'TXN-' || substr(p_booking_id::text, 1, 8));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'confirm_payment all attempts failed: % — payment NOT confirmed', SQLERRM;
  END;

  -- Všechny pokusy selhaly — NEPOTVRZOVAT platbu, vrátit chybu
  RETURN jsonb_build_object('success', false, 'error', 'Potvrzení platby selhalo. Kontaktujte podporu.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
