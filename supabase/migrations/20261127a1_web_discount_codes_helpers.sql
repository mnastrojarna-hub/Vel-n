-- ===== Web: slevové kódy a dárkové poukazy u výpůjčky výbavy a u nákupu dárkového poukazu (část 1/3) =====
-- 2026-11-27, schváleno majitelem 2026-11-27.
-- Zadání majitele 2026-11-27: „uplatnit slevový kód jak na poukazy, tak na výbavu … stejná mechanika
-- jako u rezervačního formuláře … kombinace více poukazů“.
--  • _web_discount_lines: vyhodnocení seznamu kódů jako rezervace motorky / e-shop appky
--    (create_shop_order): nejvýš 1 procentní kód (počítá se z celé částky), pak pevné slevové kódy
--    a dárkové poukazy v zadaném pořadí na zbytek; kód s omezením na motorky (applicable_motos)
--    a min. hodnota objednávky se respektují; neplatné kódy se vrací v `invalid`.
--  • quote/create_web_gear_booking: nový parametr p_codes text[] (web). Bez něj (appka 5.0.2/5.0.3,
--    p_voucher_code) beze změny chování. Řádky slev do booking_discounts → po zaplacení je
--    redeem_booking_discounts_on_paid zaeviduje (poukaz redeemed, promo_code_usage).
--  • _gear_booking_json: + `discounts` (seznam uplatněných kódů pro potvrzení / úpravy na webu).
--  • quote_web_voucher_order: cena nákupu dárkového poukazu na webu se slevovými kódy (jen slevové
--    kódy — dárkovým poukazem se jiný poukaz platit nedá; po slevě musí zbýt ≥ 15 Kč);
--    používá stránka i process-payment (shop_orders.discount / discount_codes / promo_code_id →
--    použití kódu zapíše po zaplacení trigger record_shop_promo_usage_on_paid).
-- Tato část: pomocné funkce _web_discount_lines, _web_voucher_in_use a _gear_booking_json (+ `discounts`);
-- volají je části 2/3 (quote_gear_booking, create_web_gear_booking) a 3/3 (quote_web_voucher_order).
-- Idempotentní (DROP IF EXISTS starých podpisů + CREATE OR REPLACE), bez změn dat.

CREATE OR REPLACE FUNCTION public._web_discount_lines(p_codes text[], p_base numeric, p_allow_voucher boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_codes text[] := '{}'; v_c text; v_r jsonb; v_pc promo_codes%ROWTYPE; v_vr jsonb;
  v_pct jsonb; v_rest jsonb := '[]'::jsonb; v_bad jsonb := '[]'::jsonb; v_lines jsonb := '[]'::jsonb;
  v_base numeric := GREATEST(COALESCE(p_base, 0), 0); v_rem numeric; v_amt numeric; v_l jsonb; v_disc numeric := 0;
BEGIN
  FOREACH v_c IN ARRAY COALESCE(p_codes, '{}'::text[]) LOOP
    v_c := upper(btrim(COALESCE(v_c, '')));
    CONTINUE WHEN v_c = '' OR v_c = ANY (v_codes) OR length(v_c) > 64;
    EXIT WHEN COALESCE(array_length(v_codes, 1), 0) >= 10;
    v_codes := v_codes || v_c;
  END LOOP;
  FOREACH v_c IN ARRAY v_codes LOOP
    SELECT * INTO v_pc FROM promo_codes WHERE code = v_c;
    IF FOUND THEN
      v_r := public.validate_promo_code(v_c);
      IF NOT COALESCE((v_r->>'valid')::boolean, false) THEN
        v_bad := v_bad || jsonb_build_object('code', v_c, 'error', 'code_invalid', 'message', COALESCE(v_r->>'error', 'Kód není platný.'));
      ELSIF NULLIF(btrim(COALESCE(v_pc.applicable_motos, '')), '') IS NOT NULL THEN
        v_bad := v_bad || jsonb_build_object('code', v_c, 'error', 'not_applicable', 'message', 'Tento kód platí jen na vybrané motorky.');
      ELSIF v_pc.min_order_amount IS NOT NULL AND v_base < v_pc.min_order_amount THEN
        v_bad := v_bad || jsonb_build_object('code', v_c, 'error', 'min_order', 'min', v_pc.min_order_amount,
          'message', 'Kód platí od hodnoty objednávky ' || trim(to_char(v_pc.min_order_amount, 'FM9999990')) || ' Kč.');
      ELSIF v_pc.type = 'percent' AND v_pct IS NOT NULL THEN
        v_bad := v_bad || jsonb_build_object('code', v_c, 'error', 'multiple_percent', 'message', 'Uplatnit jde jen jeden procentní kód.');
      ELSIF v_pc.type = 'percent' THEN
        v_pct := jsonb_build_object('kind', 'promo_code', 'code', v_c, 'promo_code_id', v_pc.id, 'discount_type', 'percent', 'value', v_pc.value);
      ELSE
        v_rest := v_rest || jsonb_build_object('kind', 'promo_code', 'code', v_c, 'promo_code_id', v_pc.id, 'discount_type', 'fixed', 'value', v_pc.value);
      END IF;
      CONTINUE;
    END IF;
    v_vr := public.validate_voucher_code(v_c);
    IF COALESCE((v_vr->>'valid')::boolean, false) AND NULLIF(v_vr->>'id', '') IS NOT NULL THEN
      IF NOT COALESCE(p_allow_voucher, true) THEN
        v_bad := v_bad || jsonb_build_object('code', v_c, 'error', 'voucher_not_allowed', 'message', 'Dárkový poukaz se tu uplatnit nedá — platí na půjčení motorky a výbavy.');
      ELSE
        v_rest := v_rest || jsonb_build_object('kind', 'voucher', 'code', v_c, 'voucher_id', (v_vr->>'id')::uuid, 'discount_type', 'fixed', 'value', COALESCE((v_vr->>'value')::numeric, 0));
      END IF;
    ELSE
      v_bad := v_bad || jsonb_build_object('code', v_c,
        'error', CASE WHEN COALESCE((v_vr->>'rate_limited')::boolean, false) THEN 'rate_limited' ELSE 'code_invalid' END,
        'message', CASE WHEN v_vr->>'error' IS NULL OR v_vr->>'error' = 'Poukaz neexistuje nebo není aktivní'
                        THEN 'Kód neexistuje nebo už neplatí.' ELSE v_vr->>'error' END);
    END IF;
  END LOOP;
  -- procentní kód z celé částky, pevné slevy a poukazy na zbytek (v zadaném pořadí)
  IF v_pct IS NOT NULL THEN
    v_amt := LEAST(ROUND(v_base * (v_pct->>'value')::numeric / 100), v_base);
    v_lines := v_lines || jsonb_build_array(v_pct || jsonb_build_object('amount', v_amt));
    v_disc := v_amt;
  END IF;
  v_rem := v_base - v_disc;
  FOR v_l IN SELECT * FROM jsonb_array_elements(v_rest) LOOP
    v_amt := LEAST(GREATEST((v_l->>'value')::numeric, 0), v_rem);
    v_rem := v_rem - v_amt;
    v_disc := v_disc + v_amt;
    v_lines := v_lines || jsonb_build_array(v_l || jsonb_build_object('amount', v_amt));
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'discount', v_disc, 'invalid', v_bad);
END $$;
REVOKE ALL ON FUNCTION public._web_discount_lines(text[], numeric, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._web_discount_lines(text[], numeric, boolean) TO service_role;

-- Dárkový poukaz drží nejvýš jedna živá rezervace (jako dosud u výbavy); zámek řádku poukazu.
CREATE OR REPLACE FUNCTION public._web_voucher_in_use(p_voucher_id uuid, p_exclude_booking uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM 1 FROM vouchers WHERE id = p_voucher_id FOR UPDATE;
  RETURN EXISTS (SELECT 1 FROM booking_discounts d JOIN bookings ob ON ob.id = d.booking_id
                  WHERE d.voucher_id = p_voucher_id
                    AND ob.status IN ('pending', 'reserved', 'active')
                    AND ob.id IS DISTINCT FROM p_exclude_booking);
END $$;
REVOKE ALL ON FUNCTION public._web_voucher_in_use(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._web_voucher_in_use(uuid, uuid) TO service_role;

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
    -- uplatněné kódy (web 2026-11-27: slevové kódy + dárkové poukazy, pořadí jako výpočet)
    'discounts', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', d.kind, 'code', d.code, 'amount', d.amount)
                                            ORDER BY (d.discount_type = 'percent') DESC, d.created_at)
                             FROM booking_discounts d WHERE d.booking_id = b.id), '[]'::jsonb),
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
