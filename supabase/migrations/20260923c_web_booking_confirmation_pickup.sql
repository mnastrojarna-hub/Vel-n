-- =============================================================================
-- Děkovací stránka webu: „K vyzvednutí“ — adresa pobočky motorky + mapa
-- Migrace: 20260923c_web_booking_confirmation_pickup.sql
--
-- ZADÁNÍ 2026-09-23: po zaplacení se na děkovací stránce musí zobrazit, kde si
-- zákazník motorku vyzvedne — adresa pobočky, na které motorka stojí, a odkaz
-- na mapu. `/potvrzeni` čte data VÝHRADNĚ z `get_web_booking_confirmation`
-- (web rezervace je anonymní, přímý SELECT na bookings RLS nepustí) a ta
-- o pobočce ani o přistavení nic nevracela.
--
-- OPRAVA: tělo 1:1 podle živé funkce (supabase-live-snapshot 2026-09-23),
-- navíc vrací:
--   * `is_delivery` — přistavení na adresu zákazníka (create_web_booking
--     pickup_method nevyplňuje → DEFAULT 'store' + vyplněná pickup_address),
--     blok „K vyzvednutí“ se u přistavení nezobrazuje. Samotná adresa
--     zákazníka se NEVRACÍ (RPC je volatelná anonymně podle id rezervace).
--   * `branch` — {name, address, zip, city, gps_lat, gps_lng} pobočky motorky
--     (veřejné údaje, stejné jako na /kontakt), NULL když motorka pobočku nemá.
-- Signatura beze změny (CREATE OR REPLACE), pole jen přibývají → starý web
-- i Velín (docVerification.js čte jen docs_status) fungují dál. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_web_booking_confirmation(
  p_session_id text DEFAULT NULL::text,
  p_booking_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'auth'
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
    b.pickup_method, b.pickup_address,
    p.full_name AS customer_name, p.email AS customer_email,
    m.license_required,
    br.id AS branch_id, br.name AS branch_name, br.address AS branch_address,
    br.zip AS branch_zip, br.city AS branch_city,
    br.gps_lat AS branch_gps_lat, br.gps_lng AS branch_gps_lng
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p     ON p.id = b.user_id
  LEFT JOIN motorcycles m  ON m.id = b.moto_id
  LEFT JOIN branches br    ON br.id = m.branch_id
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
    'docs_status',    v_docs_status,
    'is_delivery',    (v_booking.pickup_method = 'delivery'
                       OR NULLIF(btrim(v_booking.pickup_address), '') IS NOT NULL),
    'branch',         CASE WHEN v_booking.branch_id IS NULL THEN NULL
                      ELSE jsonb_build_object(
                        'name',    v_booking.branch_name,
                        'address', v_booking.branch_address,
                        'zip',     v_booking.branch_zip,
                        'city',    v_booking.branch_city,
                        'gps_lat', v_booking.branch_gps_lat,
                        'gps_lng', v_booking.branch_gps_lng
                      ) END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_web_booking_confirmation(text, uuid) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
