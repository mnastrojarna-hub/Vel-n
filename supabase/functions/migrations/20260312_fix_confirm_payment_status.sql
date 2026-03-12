-- Fix confirm_payment: pending → reserved (ne active)
-- Booking by měl po zaplacení přejít do 'reserved' (potvrzeno, čeká na vydání motorky),
-- NE do 'active' (motorka vydána). Stav 'active' nastavuje admin ve Velínu při vydání.
-- Zároveň nastavit confirmed_at.

CREATE OR REPLACE FUNCTION confirm_payment(
  p_booking_id uuid,
  p_method text DEFAULT 'card'
)
RETURNS jsonb AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Rezervace nenalezena');
  END IF;

  IF v_booking.user_id != auth.uid() AND NOT is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nemate opravneni');
  END IF;

  UPDATE bookings SET
    payment_status = 'paid',
    payment_method = p_method,
    status = CASE WHEN status = 'pending' THEN 'reserved' ELSE status END,
    confirmed_at = CASE WHEN status = 'pending' AND confirmed_at IS NULL THEN now() ELSE confirmed_at END
  WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', 'TXN-TEST-' || substr(p_booking_id::text, 1, 8)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
