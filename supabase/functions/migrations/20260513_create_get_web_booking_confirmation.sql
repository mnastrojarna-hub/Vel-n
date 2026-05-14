-- ============================================================================
-- Migrace: get_web_booking_confirmation
-- Datum:   2026-05-13
-- Důvod:   RPC byla dokumentována v BACKEND_STATE_3 jako "NEW 2026-05-07",
--          ale migrace v repu nikdy nevznikla. Na produkci funkce chyběla
--          a frontend /potvrzeni dostával 404 → po Stripe redirectu
--          (placená rezervace i 0 Kč setup-mode ověření karty) zůstávala
--          stránka navždy v "Platba se ověřuje..." stavu, i když booking
--          byl ve Stripe i Velínu paid.
--          Po obnově funkce vyšel najevo druhý bug — `check_booking_docs_status`
--          čeká signaturu (uuid, date), ale `bookings.end_date` je timestamptz.
--          Volání bez castu RPC shazovalo (42883). Smoke test s neexistujícím
--          UUID prošel cestou `not_found` před dosažením docs_status řádku,
--          takže problém se objevil až proti reálné paid rezervaci. Frontend
--          chybu četl jako "data není" a polling smyčka jela donekonečna.
--          Dětské motorky (`motorcycles.license_required='N'`) nevyžadují ŘP
--          (backend trigger `auto_generate_door_codes` u nich kódy uvolní bez
--          dokladů), takže pro ně RPC vrací `docs_status=NULL` (= "Ověřeny").
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
    b.id, b.user_id, b.moto_id, b.start_date, b.end_date,
    b.total_price, b.payment_status, b.status, b.booking_source,
    p.full_name AS customer_name, p.email AS customer_email,
    m.license_required
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p     ON p.id = b.user_id
  LEFT JOIN motorcycles m  ON m.id = b.moto_id
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

  -- Dětská motorka (license_required='N') → ŘP se nevyžaduje, docs_status=NULL.
  -- Jinak volej helper, který kontroluje OP + ŘP (cast end_date na date kvůli
  -- signatuře check_booking_docs_status(uuid, date)). EXCEPTION jako pojistka.
  IF v_booking.license_required = 'N' THEN
    v_docs_status := NULL;
  ELSE
    BEGIN
      v_docs_status := public.check_booking_docs_status(
        v_booking.user_id,
        v_booking.end_date::date
      );
    EXCEPTION WHEN OTHERS THEN
      v_docs_status := NULL;
    END;
  END IF;

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
