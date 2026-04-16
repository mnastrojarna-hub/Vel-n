-- Fix confirm_payment: podmíněný přechod stavu dle start_date
-- start_date <= dnes → pending → active (pronájem začíná dnes, motorka se vydává)
-- start_date > dnes  → pending → reserved (nadcházející, čeká na vydání)

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

  IF v_booking.user_id != auth.uid() AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nemate opravneni');
  END IF;

  -- Určení cílového stavu: active pokud pronájem začíná dnes nebo dříve, jinak reserved
  IF v_booking.status = 'pending' THEN
    IF v_booking.start_date::date <= CURRENT_DATE THEN
      v_new_status := 'active';
    ELSE
      v_new_status := 'reserved';
    END IF;
  ELSE
    v_new_status := v_booking.status;
  END IF;

  UPDATE bookings SET
    payment_status = 'paid',
    payment_method = p_method,
    status = v_new_status,
    confirmed_at = CASE WHEN v_booking.status = 'pending' AND confirmed_at IS NULL THEN now() ELSE confirmed_at END,
    picked_up_at = CASE WHEN v_booking.status = 'pending' AND v_new_status = 'active' AND picked_up_at IS NULL THEN now() ELSE picked_up_at END
  WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', 'TXN-TEST-' || substr(p_booking_id::text, 1, 8)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
