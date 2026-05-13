-- ============================================================================
-- Migrace: get_web_booking_confirmation
-- Datum:   2026-05-13
-- Důvod:   RPC byla dokumentována v BACKEND_STATE_3 jako "NEW 2026-05-07",
--          ale migrace v repu nikdy nevznikla. Na produkci funkce chyběla
--          a frontend /potvrzeni dostával 404 → po Stripe redirectu
--          (placená rezervace i 0 Kč setup-mode ověření karty) zůstávala
--          stránka navždy v "Platba se ověřuje..." stavu, i když booking
--          byl ve Stripe i Velínu paid.
--          Tato migrace funkci dotvoří přesně podle BACKEND_STATE_3 line 101
--          a podle volání frontendu (motogo-web-php/js/pages-potvrzeni.js).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_web_booking_confirmation(
  p_session_id text DEFAULT NULL,
  p_booking_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_booking RECORD;
  v_docs_status text;
BEGIN
  IF p_session_id IS NULL AND p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_identifier');
  END IF;

  SELECT
    b.id,
    b.user_id,
    b.moto_id,
    b.start_date,
    b.end_date,
    b.total_price,
    b.payment_status,
    b.status,
    b.booking_source,
    p.full_name  AS customer_name,
    p.email      AS customer_email
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p ON p.id = b.user_id
  WHERE
    (p_booking_id IS NOT NULL AND b.id = p_booking_id)
    OR
    (p_session_id IS NOT NULL AND b.stripe_session_id = p_session_id)
  ORDER BY b.created_at DESC
  LIMIT 1;

  IF v_booking.id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  IF v_booking.booking_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'not_web_booking');
  END IF;

  v_docs_status := public.check_booking_docs_status(v_booking.user_id, v_booking.end_date);

  RETURN jsonb_build_object(
    'id',             v_booking.id,
    'moto_id',        v_booking.moto_id,
    'start_date',     v_booking.start_date,
    'end_date',       v_booking.end_date,
    'total_price',    v_booking.total_price,
    'payment_status', v_booking.payment_status,
    'status',         v_booking.status,
    'customer_name',  v_booking.customer_name,
    'customer_email', v_booking.customer_email,
    'docs_status',    v_docs_status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_web_booking_confirmation(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_booking_confirmation(text, uuid)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
