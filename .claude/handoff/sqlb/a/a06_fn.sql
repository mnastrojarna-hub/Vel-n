CREATE OR REPLACE FUNCTION public.get_web_booking_confirmation(p_session_id text DEFAULT NULL::text, p_booking_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
  v_booking RECORD;
  v_docs_status text;
  v_late jsonb;          -- 2026-11-07 (i4): záznam automatické vratky pozdní platby (webhook late-payment.ts)
  v_extra jsonb := '{}'::jsonb;
  v_order text;
BEGIN
  IF p_session_id IS NULL AND p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_identifier');
  END IF;

  SELECT
    b.id, b.user_id, b.moto_id, b.start_date, b.end_date,
    b.total_price, b.payment_status, b.status, b.booking_source,
    b.pickup_method, b.pickup_address, b.stripe_session_id,  -- 2026-10-11
    p.full_name AS customer_name, p.email AS customer_email,
    m.license_required,
    br.id AS branch_id, br.name AS branch_name, br.address AS branch_address,
    br.zip AS branch_zip, br.city AS branch_city,
    br.gps_lat AS branch_gps_lat, br.gps_lng AS branch_gps_lng
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p     ON p.id = b.user_id
  LEFT JOIN motorcycles m  ON m.id = b.moto_id
  LEFT JOIN branches br    ON br.id = COALESCE(b.branch_id, m.branch_id)  -- 2026-10-11: pobočka rezervace
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

  -- 2026-10-11: přes samotné id rezervace (bez Stripe session) jen do konce pronájmu
  IF NOT COALESCE(p_session_id IS NOT NULL AND v_booking.stripe_session_id = p_session_id, false)
     AND NOT public._web_booking_full_access(v_booking.user_id)
     AND NOT public._web_booking_is_live(v_booking.id) THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  -- Dětské motorky (license_required='N') nepotřebují doklady → NULL = OK
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

  -- 2026-10-11: nositeli odkazu neprozrazovat věk ani datum ŘP
  IF NOT public._web_booking_full_access(v_booking.user_id) THEN
    v_docs_status := regexp_replace(regexp_replace(v_docs_status,
                       'Zákazníkovi není 18 let', 'Údaje z dokladů nesplňují podmínky pronájmu — kontaktujte nás', 'g'),
                       'ŘP propadlý [0-9.]+', 'Platnost ŘP nevyhovuje termínu pronájmu', 'g');
  END IF;

  -- 2026-11-07 (i4): zrušená rezervace — výsledek pozdní platby pro /potvrzeni: late_refund (true = platba vrácena
  -- automaticky, false = běžné storno), vrácená částka a přibalená objednávka zboží, která zůstává zaplacená.
  IF v_booking.status = 'cancelled' THEN
    SELECT d.request_data INTO v_late FROM debug_log d
     WHERE d.action = 'late_payment_refunded' AND d.source = 'webhook-receiver'
       AND d.request_data->>'booking_id' = v_booking.id::text
     ORDER BY d.created_at DESC LIMIT 1;
    v_extra := jsonb_build_object('late_refund', v_late IS NOT NULL);
    IF v_late IS NOT NULL THEN
      v_extra := v_extra || jsonb_build_object('late_refund_amount',
        CASE WHEN COALESCE(v_late->>'refund_haleru', '') ~ '^[0-9]+$' THEN round((v_late->>'refund_haleru')::numeric / 100, 2) ELSE v_booking.total_price END);
      IF NULLIF(v_late->>'shop_order_id', '') IS NOT NULL THEN
        SELECT so.order_number INTO v_order FROM shop_orders so
         WHERE so.id::text = v_late->>'shop_order_id' AND so.payment_status = 'paid';
        IF v_order IS NOT NULL THEN v_extra := v_extra || jsonb_build_object('bundled_order_number', v_order); END IF;
      END IF;
    END IF;
  END IF;

  RETURN v_extra || jsonb_build_object(
    'id',             v_booking.id,
    'moto_id',        v_booking.moto_id,
    'start_date',     v_booking.start_date,
    'end_date',       v_booking.end_date,
    'total_price',    v_booking.total_price,
    'payment_status', v_booking.payment_status,
    'status',         v_booking.status,
    'customer_name',  v_booking.customer_name,
    'customer_email', v_booking.customer_email,
    'docs_status',    v_docs_status,
    'is_delivery',    (v_booking.pickup_method = 'delivery'
                       OR NULLIF(btrim(v_booking.pickup_address), '') IS NOT NULL),
    'branch',         CASE WHEN v_booking.branch_id IS NULL THEN NULL
                      ELSE jsonb_build_object(
                        'id',      v_booking.branch_id,
                        -- jen příznak brány se schránkou (Velké Němčice), NIKDY kód
                        'has_gate', public.branch_has_gate(v_booking.branch_id),
                        'name',    v_booking.branch_name,
                        'address', v_booking.branch_address,
                        'zip',     v_booking.branch_zip,
                        'city',    v_booking.branch_city,
                        'gps_lat', v_booking.branch_gps_lat,
                        'gps_lng', v_booking.branch_gps_lng
                      ) END
  );
END;
$$
