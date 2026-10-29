-- =============================================================================
-- 2026-10-23 (b/7): Čtení výpůjčky výbavy pro web a appku + konec staré cesty
--  • get_web_gear_booking (anon): potvrzení / obnovení / doklady na webu.
--    Osobní údaje jako get_web_booking_confirmation: vlastník / admin / service,
--    shodná Stripe session nebo čerstvá (≤ 2 h) rezervace; jinak restricted.
--    Bez session a bez přihlášení jen do konce pronájmu (_web_booking_is_live).
--  • get_my_gear_bookings (přihlášený): výpůjčky výbavy zákazníka — přímý SELECT
--    gear řádků zákazníkem blokuje RESTRICTIVE RLS (20261023a), proto RPC.
--  • create_gear_rental_order / get_gear_rental_confirmation (e-shop cesta
--    20261022) → bez práva pro anon/authenticated (tabulka gear_rentals zůstává
--    jen pro čtení ve Velínu). Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._gear_booking_json(p_booking_id uuid, p_full boolean, p_restricted boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_sd date; v_ed date; v_docs jsonb; v_miss jsonb;
BEGIN
  SELECT bk.*, br.name AS br_name, br.address AS br_address, br.city AS br_city, br.zip AS br_zip, br.type AS br_type,
         p.full_name AS cust_name, p.email AS cust_email
    INTO b
    FROM bookings bk
    LEFT JOIN branches br ON br.id = bk.branch_id
    LEFT JOIN profiles p ON p.id = bk.user_id
   WHERE bk.id = p_booking_id AND bk.booking_kind = 'gear';
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_sd := (b.start_date AT TIME ZONE 'Europe/Prague')::date;
  v_ed := (b.end_date AT TIME ZONE 'Europe/Prague')::date;
  v_docs := public._gear_docs_checklist(b.user_id, v_sd, v_ed);
  v_miss := COALESCE(v_docs->'missing', '[]'::jsonb);
  IF NOT p_full THEN   -- nositeli odkazu neprozrazovat věk (jako get_web_booking_confirmation)
    SELECT COALESCE(jsonb_agg(CASE WHEN m = 'Zákazníkovi není 18 let'
                                   THEN 'Údaje z dokladů nesplňují podmínky pronájmu — kontaktujte nás' ELSE m END), '[]'::jsonb)
      INTO v_miss FROM jsonb_array_elements_text(v_miss) m;
  END IF;
  RETURN jsonb_build_object(
    'id', b.id, 'booking_number', upper(right(b.id::text, 8)), 'booking_kind', 'gear',
    'status', b.status, 'payment_status', b.payment_status, 'booking_source', b.booking_source,
    'start_date', v_sd, 'end_date', v_ed, 'days', (v_ed - v_sd) + 1,
    'pickup_time', to_char(b.pickup_time, 'HH24:MI'), 'return_time', b.return_time,
    'refund_pickup_time', to_char(b.refund_pickup_time, 'HH24:MI'),   -- náhled pásma vratky (20261023e)
    'branch', CASE WHEN b.branch_id IS NULL THEN NULL ELSE jsonb_build_object('id', b.branch_id, 'name', b.br_name,
               'address', b.br_address, 'city', b.br_city, 'zip', b.br_zip, 'type', b.br_type,
               'has_gate', public.branch_has_gate(b.branch_id)) END,
    'lines', COALESCE(b.gear_lines, '[]'::jsonb), 'per_day', b.gear_per_day,
    'subtotal', COALESCE(b.gear_per_day, 0) * ((v_ed - v_sd) + 1), 'total', b.total_price,
    'voucher_amount', COALESCE((SELECT sum(d.amount) FROM booking_discounts d
                                 WHERE d.booking_id = b.id AND d.kind = 'voucher'), 0),
    'sizes', jsonb_strip_nulls(jsonb_build_object('helmet', b.helmet_size, 'jacket', b.jacket_size,
               'pants', b.pants_size, 'gloves', b.gloves_size, 'boots', b.boots_size)),
    'docs', jsonb_build_object('required', b.status IN ('pending', 'reserved', 'active'),
               'ok', COALESCE((v_docs->>'ok')::boolean, false),
               'identity_ok', COALESCE((v_docs->>'identity_ok')::boolean, false), 'missing', v_miss),
    'codes_released', EXISTS (SELECT 1 FROM branch_door_codes c WHERE c.booking_id = b.id
                                AND c.is_active AND c.sent_to_customer),
    'can_pay', b.status = 'pending' AND b.payment_status = 'unpaid' AND b.booking_source = 'web',
    'language', b.language, 'created_at', b.created_at,
    -- pro náhledy úprav na webu (strop vratky po posunu, historie, sleva, platba kartou)
    'discount_amount', COALESCE(b.discount_amount, 0), 'picked_up_at', b.picked_up_at,
    'original_start_date', b.original_start_date, 'original_end_date', b.original_end_date,
    'modification_history', CASE WHEN p_full THEN COALESCE(b.modification_history, '[]'::jsonb) END,
    'card_paid', b.stripe_payment_intent_id IS NOT NULL,
    'customer_name', CASE WHEN NOT p_restricted THEN b.cust_name END,
    'customer_email', CASE WHEN NOT p_restricted THEN b.cust_email END,
    'restricted', p_restricted);
END $$;

CREATE OR REPLACE FUNCTION public.get_web_gear_booking(p_booking_id uuid, p_session_id text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; v_sess boolean; v_full boolean;
BEGIN
  IF p_booking_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  SELECT id, user_id, booking_kind, stripe_session_id, created_at INTO b FROM bookings WHERE id = p_booking_id;
  IF b.id IS NULL OR b.booking_kind IS DISTINCT FROM 'gear' THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
  v_sess := NULLIF(p_session_id, '') IS NOT NULL AND p_session_id = b.stripe_session_id;
  v_full := public._web_booking_full_access(b.user_id);
  IF NOT (v_sess OR v_full OR public._web_booking_is_live(b.id)) THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;
  RETURN public._gear_booking_json(b.id, v_full,
           NOT (v_full OR v_sess OR b.created_at > now() - interval '2 hours'));
END $$;

CREATE OR REPLACE FUNCTION public.get_my_gear_bookings()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(public._gear_booking_json(b.id, true, false) ORDER BY b.created_at DESC), '[]'::jsonb)
    FROM bookings b
   WHERE auth.uid() IS NOT NULL AND b.user_id = auth.uid() AND b.booking_kind = 'gear';
$$;

REVOKE ALL ON FUNCTION public._gear_booking_json(uuid, boolean, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_booking_json(uuid, boolean, boolean) TO service_role;
REVOKE ALL ON FUNCTION public.get_web_gear_booking(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_web_gear_booking(uuid, text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_gear_bookings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_gear_bookings() TO authenticated, service_role;

-- Stará cesta „výpůjčka = e-shop objednávka“ (20261022) už z webu nejde
REVOKE EXECUTE ON FUNCTION public.create_gear_rental_order(uuid, date, date, jsonb, jsonb, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_gear_rental_confirmation(uuid, text) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
