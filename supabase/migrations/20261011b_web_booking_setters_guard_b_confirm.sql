-- =============================================================================
-- 2026-10-11 BEZPEČNOST (část _b k 20261011b): potvrzovací stránky, granty, RLS
-- Potvrzení e-shopu / poukazu a webové rezervace pro nositele odkazu, explicitní
-- granty webových RPC (anon zůstává, PUBLIC ne) a dvě RLS opravy. Helpery
-- _web_booking_full_access / _is_live: 20261011a. Těla = živá definice, měněno jen
-- označené (2026-10-11). Idempotentní.
-- =============================================================================

-- 8) Potvrzení e-shop / poukaz: kódy a osobní údaje jen vlastníkovi / adminovi /
--    service, při shodné Stripe session (nový p_session_id) nebo do 2 h od založení
--    (živý web je hned po platbě zobrazí). 1-arg verze se ruší (nejednoznačné RPC).
DROP FUNCTION IF EXISTS public.get_web_shop_order_confirmation(uuid);
CREATE OR REPLACE FUNCTION public.get_web_shop_order_confirmation(p_order_id uuid, p_session_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order record;
  v_vouchers jsonb;
  v_full boolean;  -- 2026-10-11
begin
  if p_order_id is null then
    return jsonb_build_object('error', 'missing_identifier');
  end if;

  select id, order_number, customer_name, customer_email,
         total, subtotal, shipping_cost, discount,
         payment_status, status, shipping_method,
         created_at, confirmed_at, notes,
         customer_id, stripe_session_id  -- 2026-10-11
    into v_order
    from public.shop_orders
   where id = p_order_id
   limit 1;

  if v_order.id is null then
    return jsonb_build_object('error', 'not_found');
  end if;

  v_full := public._web_booking_full_access(v_order.customer_id)
            or (nullif(p_session_id, '') is not null and p_session_id = v_order.stripe_session_id)
            or v_order.created_at > now() - interval '2 hours';

  -- Načti případné vouchery vytvořené pro tuto objednávku
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', case when v_full then code end,  -- 2026-10-11
           'amount', amount,
           'valid_until', valid_until
         ) order by created_at), '[]'::jsonb)
    into v_vouchers
    from public.vouchers
   where order_id = p_order_id;

  return jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'customer_name', case when v_full then v_order.customer_name end,
    'customer_email', case when v_full then v_order.customer_email end,
    'total', v_order.total,
    'subtotal', v_order.subtotal,
    'shipping_cost', v_order.shipping_cost,
    'discount', v_order.discount,
    'payment_status', v_order.payment_status,
    'status', v_order.status,
    'shipping_method', v_order.shipping_method,
    'created_at', v_order.created_at,
    'confirmed_at', v_order.confirmed_at,
    'notes', case when v_full then v_order.notes end,
    'vouchers', v_vouchers,
    'restricted', not v_full  -- 2026-10-11: kódy jsou v e-mailu
  );
end;
$function$;

-- 9) get_web_booking_confirmation (patří k 20261011a): nositel odkazu jen u živé
--    rezervace a důvod dokladů bez věku / data ŘP (/potvrzeni ho v cs zobrazuje).
CREATE OR REPLACE FUNCTION public.get_web_booking_confirmation(p_session_id text DEFAULT NULL::text, p_booking_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
$function$;

-- 10) Granty: host webu tyto funkce potřebuje (anon zůstává), PUBLIC ne.
DO $grants$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'get_web_booking_resume(uuid)', 'get_web_booking_confirmation(text, uuid)',
    'set_web_booking_docs(uuid, text, text, text, text, text)',
    'set_web_booking_company(uuid, text, text, text, text)',
    'set_web_booking_device(uuid, text, text)', 'set_web_booking_chosen_method(uuid, text)',
    'set_web_booking_docs_completed(uuid)', 'set_booking_form_seconds(uuid, timestamp with time zone)',
    'cancel_pending_web_booking(uuid)', 'check_web_booking_user_overlap(text, date, date, uuid)',
    'get_web_shop_order_confirmation(uuid, text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO anon, authenticated, service_role', f);
  END LOOP;
END
$grants$;

-- 11) RLS bookings: anon SELECT rozpracovaných webových rezervací (zrcadlo PC↔mobil)
--     vydával komukoli (REST i realtime) UUID a údaje všech rozpracovaných rezervací
--     = klíč k funkcím výše. Vlastník zrcadlo dál má přes bookings_user_select;
--     redirect po platbě anonymovi nešel ani dřív (zaplacený řádek nepouštěla).
DROP POLICY IF EXISTS bookings_anon_pending_realtime ON public.bookings;

-- 12) Reklamace: politika „Admin full access" měla USING (true) pro PUBLIC
--     (anon četl/měnil/mazal vše). Volá je jen Velín (admin) a edge (service role).
DROP POLICY IF EXISTS "Admin full access booking_complaints" ON public.booking_complaints;
DROP POLICY IF EXISTS booking_complaints_admin_all ON public.booking_complaints;
CREATE POLICY booking_complaints_admin_all ON public.booking_complaints
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
REVOKE ALL ON TABLE public.booking_complaints FROM anon;

NOTIFY pgrst, 'reload schema';
