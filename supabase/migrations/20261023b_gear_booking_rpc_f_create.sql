-- =============================================================================
-- 2026-10-23 (b/6): Založení výpůjčky výbavy z webu (anon i přihlášený)
-- create_web_gear_booking → řádek bookings booking_kind='gear' (pending/unpaid,
-- booking_source 'web' → neplacená se po 4 h sama zruší jako web rezervace),
-- cena VÝHRADNĚ ze serveru (_gear_prepare), dárkový poukaz, souhlasy VOP+GDPR.
-- Identita 1:1 s create_web_booking: anon + existující e-mail ⇒ email_exists
-- (výjimka = vlastní rozpracovaná gear rezervace), přihlášený s jiným e-mailem ⇒
-- email_mismatch, neznámý e-mail ⇒ auth.users + profiles (registration_source web).
-- Termín se ukládá jako web (datum = půlnoc UTC). Idempotentní.
-- =============================================================================

-- Čas převzetí / vrácení z webu ('HH:MM'); nesmysl = NULL
CREATE OR REPLACE FUNCTION public._gear_parse_time(p text)
RETURNS time LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN NULLIF(btrim(COALESCE(p, '')), '')::time;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;

-- Zákazník web výpůjčky: založení / doplnění profilu (kopie pravidel create_web_booking
-- bez ŘP a data narození; firma/IČO/DIČ jako set_web_booking_company). Vrací user_id.
CREATE OR REPLACE FUNCTION public._gear_web_upsert_customer(p_existing uuid, p_name text, p_email text, p_phone text,
  p_customer jsonb, p_password text, p_consents jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid;
  v_street text := left(btrim(COALESCE(p_customer->>'street', '')), 200);
  v_city text := left(btrim(COALESCE(p_customer->>'city', '')), 100);
  v_zip text := left(btrim(COALESCE(p_customer->>'zip', '')), 20);
  v_country text := COALESCE(NULLIF(left(btrim(COALESCE(p_customer->>'country', '')), 60), ''), 'CZ');
  v_company text := NULLIF(left(btrim(COALESCE(p_customer->>'company', '')), 200), '');
  v_ico text := NULLIF(left(btrim(COALESCE(p_customer->>'ico', '')), 20), '');
  v_dic text := NULLIF(left(btrim(COALESCE(p_customer->>'dic', '')), 20), '');
  v_vop boolean := CASE WHEN p_consents ? 'vop' THEN (p_consents->>'vop')::boolean END;
  v_gdpr boolean := CASE WHEN p_consents ? 'gdpr' THEN (p_consents->>'gdpr')::boolean END;
  v_mkt boolean := CASE WHEN p_consents ? 'marketing' THEN (p_consents->>'marketing')::boolean END;
  v_photo boolean := CASE WHEN p_consents ? 'photo' THEN (p_consents->>'photo')::boolean END;
BEGIN
  IF p_existing IS NOT NULL THEN
    v_user := p_existing;
    IF COALESCE(auth.uid() = v_user, false) OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_user) THEN
      INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source,
        consent_vop, consent_gdpr, marketing_consent, consent_photo, company_name, ico, dic)
      VALUES (v_user, p_name, p_email, p_phone, v_street, v_city, v_zip, v_country, 'web',
        COALESCE(v_vop, true), COALESCE(v_gdpr, true), COALESCE(v_mkt, true), COALESCE(v_photo, true), v_company, v_ico, v_dic)
      ON CONFLICT (id) DO UPDATE SET
        phone = CASE WHEN EXCLUDED.phone IS NOT NULL AND EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE profiles.phone END,
        street = CASE WHEN EXCLUDED.street <> '' THEN EXCLUDED.street ELSE profiles.street END,
        city = CASE WHEN EXCLUDED.city <> '' THEN EXCLUDED.city ELSE profiles.city END,
        zip = CASE WHEN EXCLUDED.zip <> '' THEN EXCLUDED.zip ELSE profiles.zip END,
        country = CASE WHEN EXCLUDED.country <> '' AND EXCLUDED.country <> 'CZ' THEN EXCLUDED.country ELSE profiles.country END,
        full_name = CASE WHEN profiles.full_name IS NULL OR profiles.full_name = '' THEN EXCLUDED.full_name ELSE profiles.full_name END,
        registration_source = COALESCE(profiles.registration_source, 'web'),
        consent_vop = COALESCE(v_vop, profiles.consent_vop), consent_gdpr = COALESCE(v_gdpr, profiles.consent_gdpr),
        marketing_consent = COALESCE(v_mkt, profiles.marketing_consent), consent_photo = COALESCE(v_photo, profiles.consent_photo),
        company_name = COALESCE(EXCLUDED.company_name, profiles.company_name),
        ico = COALESCE(EXCLUDED.ico, profiles.ico), dic = COALESCE(EXCLUDED.dic, profiles.dic), updated_at = now();
    END IF;
    IF NULLIF(p_password, '') IS NOT NULL AND COALESCE(auth.uid() = v_user, false) THEN
      UPDATE auth.users SET encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
       WHERE id = v_user;
    END IF;
    RETURN v_user;
  END IF;

  v_user := gen_random_uuid();
  INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role, raw_user_meta_data, created_at, updated_at)
  VALUES (v_user, '00000000-0000-0000-0000-000000000000', p_email,
    extensions.crypt(COALESCE(NULLIF(p_password, ''), gen_random_uuid()::text), extensions.gen_salt('bf')),
    now(), 'authenticated', 'authenticated', jsonb_build_object('full_name', p_name, 'phone', p_phone), now(), now());
  INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source,
    consent_vop, consent_gdpr, marketing_consent, consent_photo, company_name, ico, dic)
  VALUES (v_user, p_name, p_email, p_phone, v_street, v_city, v_zip, v_country, 'web',
    COALESCE(v_vop, true), COALESCE(v_gdpr, true), COALESCE(v_mkt, true), COALESCE(v_photo, true), v_company, v_ico, v_dic)
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(NULLIF(profiles.full_name, ''), EXCLUDED.full_name), phone = COALESCE(NULLIF(EXCLUDED.phone, ''), profiles.phone),
    street = COALESCE(NULLIF(EXCLUDED.street, ''), profiles.street), city = COALESCE(NULLIF(EXCLUDED.city, ''), profiles.city),
    zip = COALESCE(NULLIF(EXCLUDED.zip, ''), profiles.zip), country = EXCLUDED.country,
    registration_source = COALESCE(profiles.registration_source, 'web'),
    consent_vop = COALESCE(v_vop, profiles.consent_vop), consent_gdpr = COALESCE(v_gdpr, profiles.consent_gdpr),
    marketing_consent = COALESCE(v_mkt, profiles.marketing_consent), consent_photo = COALESCE(v_photo, profiles.consent_photo),
    company_name = COALESCE(EXCLUDED.company_name, profiles.company_name),
    ico = COALESCE(EXCLUDED.ico, profiles.ico), dic = COALESCE(EXCLUDED.dic, profiles.dic), updated_at = now();
  RETURN v_user;
END $$;

CREATE OR REPLACE FUNCTION public.create_web_gear_booking(
  p_branch_id uuid, p_start date, p_end date, p_items jsonb, p_customer jsonb,
  p_pickup_time text DEFAULT NULL, p_return_time text DEFAULT NULL, p_lang text DEFAULT 'cs',
  p_note text DEFAULT NULL, p_voucher_code text DEFAULT NULL, p_existing_booking_id uuid DEFAULT NULL,
  p_password text DEFAULT NULL, p_consents jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_c jsonb := COALESCE(p_customer, '{}'::jsonb); v_cons jsonb := COALESCE(p_consents, '{}'::jsonb);
  v_name text; v_email text; v_phone text; v_p jsonb; v_v jsonb; v_disc numeric := 0; v_total numeric;
  v_existing uuid; v_user uuid; v_reuse boolean := false; v_id uuid; v_sz jsonb;
  v_time time; v_rtime text; v_lang text; v_note text;
BEGIN
  v_name := left(btrim(COALESCE(v_c->>'name', '')), 200);
  v_email := lower(left(btrim(COALESCE(v_c->>'email', '')), 200));
  v_phone := NULLIF(left(btrim(COALESCE(v_c->>'phone', '')), 30), '');
  IF length(v_name) < 3 OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR v_phone IS NULL THEN
    RETURN jsonb_build_object('error', 'bad_customer');
  END IF;
  IF COALESCE(v_cons->>'vop', '') <> 'true' OR COALESCE(v_cons->>'gdpr', '') <> 'true' THEN
    RETURN jsonb_build_object('error', 'consents_required');
  END IF;

  -- vlastní rozpracovaná (pending/unpaid) web výpůjčka výbavy téhož e-mailu → přepíše se
  SELECT id INTO v_existing FROM auth.users WHERE lower(email) = v_email LIMIT 1;
  IF v_existing IS NOT NULL THEN
    v_reuse := p_existing_booking_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM bookings eb WHERE eb.id = p_existing_booking_id AND eb.user_id = v_existing
         AND eb.status = 'pending' AND eb.payment_status = 'unpaid' AND eb.booking_source = 'web'
         AND eb.booking_kind = 'gear');
  END IF;

  -- pravidla + cena + sklad (se zámkem pobočky do konce transakce; přepisovaný koncept se nepočítá)
  v_p := public._gear_prepare(p_branch_id, p_start, p_end, p_items,
                              CASE WHEN v_reuse THEN p_existing_booking_id END, false, true);
  IF v_p ? 'error' THEN RETURN v_p; END IF;
  v_v := public._gear_voucher(p_voucher_code, (v_p->>'subtotal')::numeric);
  IF v_v ? 'error' THEN RETURN v_v; END IF;
  -- Poukaz smí držet jen JEDNA živá rezervace (bezpečnostní review 2026-10-23: jinak
  -- jeden poukaz zlevnil libovolný počet nezaplacených rezervací). Zámek řádku poukazu
  -- do konce transakce = dvě souběžná založení ho nepoužijí obě; přepisovaný vlastní
  -- koncept se nepočítá.
  IF v_v IS NOT NULL THEN
    PERFORM 1 FROM vouchers WHERE id = (v_v->>'voucher_id')::uuid FOR UPDATE;
    IF EXISTS (SELECT 1 FROM booking_discounts d JOIN bookings ob ON ob.id = d.booking_id
                WHERE d.voucher_id = (v_v->>'voucher_id')::uuid
                  AND ob.status IN ('pending', 'reserved', 'active')
                  AND ob.id IS DISTINCT FROM CASE WHEN v_reuse THEN p_existing_booking_id END) THEN
      RETURN jsonb_build_object('error', 'bad_voucher', 'in_use', true);
    END IF;
    v_disc := (v_v->>'amount')::numeric;
  END IF;
  v_total := GREATEST((v_p->>'subtotal')::numeric - v_disc, 0);
  IF public._gear_below_card_min(v_total) THEN   -- poukaz nechal 1–14 Kč → kartou nezaplatitelné
    RETURN jsonb_build_object('error', 'below_minimum', 'min', 15, 'total', v_total);
  END IF;

  -- identita (pravidla create_web_booking)
  IF v_existing IS NOT NULL AND public._web_booking_caller_is_anon() AND NOT v_reuse THEN
    RETURN jsonb_build_object('error', 'email_exists',
      'message', 'Tento e-mail je v systému. Pro pokračování se přihlas, nebo si obnov heslo.');
  END IF;
  IF v_existing IS NOT NULL AND auth.uid() IS NOT NULL AND auth.uid() <> v_existing THEN
    RETURN jsonb_build_object('error', 'email_mismatch',
      'message', 'Přihlášený účet nesouhlasí se zadaným e-mailem.');
  END IF;
  IF v_existing IS NOT NULL AND NOT v_reuse AND (
       SELECT count(*) FROM bookings WHERE user_id = v_existing AND booking_kind = 'gear'
          AND status = 'pending' AND created_at > now() - interval '1 hour') >= 5 THEN
    RETURN jsonb_build_object('error', 'too_many');
  END IF;

  v_user := public._gear_web_upsert_customer(v_existing, v_name, v_email, v_phone, v_c, p_password, v_cons);
  v_time := public._gear_parse_time(p_pickup_time);
  v_rtime := to_char(public._gear_parse_time(p_return_time), 'HH24:MI');
  v_lang := CASE WHEN p_lang IN ('cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk') THEN p_lang ELSE 'cs' END;
  v_note := NULLIF(left(btrim(COALESCE(p_note, '')), 500), '');
  v_sz := v_p->'sizes';

  PERFORM set_config('motogo.gear_rpc', '1', true);   -- strážce gear řádku (20261023a)
  IF v_reuse THEN
    -- přepis konceptu anonymem = akce zákazníka, ne ruční oprava pobočky (bez auditu v _booking_set_branch)
    PERFORM set_config('motogo.branch_reattribution', 'gear_rpc', true);
    UPDATE bookings SET branch_id = p_branch_id,
      start_date = (p_start::timestamp AT TIME ZONE 'UTC'), end_date = (p_end::timestamp AT TIME ZONE 'UTC'),
      total_price = v_total, extras_price = 0, delivery_fee = 0, discount_amount = v_disc,
      discount_code = v_v->>'code', voucher_id = (v_v->>'voucher_id')::uuid, promo_code_id = NULL,
      pickup_time = v_time, return_time = v_rtime, notes = v_note, language = v_lang,
      helmet_size = v_sz->>'helmet', jacket_size = v_sz->>'jacket', pants_size = v_sz->>'pants',
      gloves_size = v_sz->>'gloves', boots_size = v_sz->>'boots',
      gear_lines = v_p->'lines', gear_per_day = (v_p->>'per_day')::numeric
     WHERE id = p_existing_booking_id;
    PERFORM set_config('motogo.branch_reattribution', '', true);
    v_id := p_existing_booking_id;
  ELSE
    INSERT INTO bookings (user_id, moto_id, branch_id, booking_kind, start_date, end_date, status, payment_status,
      total_price, extras_price, delivery_fee, late_pickup_discount_amount, discount_amount, discount_code, voucher_id,
      booking_source, source, pickup_method, return_method, pickup_time, return_time, notes, language,
      helmet_size, jacket_size, pants_size, gloves_size, boots_size, gear_lines, gear_per_day)
    VALUES (v_user, NULL, p_branch_id, 'gear', (p_start::timestamp AT TIME ZONE 'UTC'), (p_end::timestamp AT TIME ZONE 'UTC'),
      'pending', 'unpaid', v_total, 0, 0, 0, v_disc, v_v->>'code', (v_v->>'voucher_id')::uuid,
      'web', 'web', 'store', 'store', v_time, v_rtime, v_note, v_lang,
      v_sz->>'helmet', v_sz->>'jacket', v_sz->>'pants', v_sz->>'gloves', v_sz->>'boots', v_p->'lines', (v_p->>'per_day')::numeric)
    RETURNING id INTO v_id;
  END IF;
  PERFORM set_config('motogo.gear_rpc', '', true);

  DELETE FROM booking_discounts WHERE booking_id = v_id;
  IF v_v IS NOT NULL THEN
    INSERT INTO booking_discounts (booking_id, kind, code, voucher_id, discount_type, value, amount)
    VALUES (v_id, 'voucher', v_v->>'code', (v_v->>'voucher_id')::uuid, 'fixed', (v_v->>'value')::numeric, v_disc);
  END IF;

  RETURN jsonb_build_object('success', true, 'booking_id', v_id, 'booking_number', upper(right(v_id::text, 8)),
    'amount', v_total, 'total', v_total, 'subtotal', (v_p->>'subtotal')::numeric, 'discount', v_disc,
    'per_day', (v_p->>'per_day')::numeric, 'days', (v_p->>'days')::int, 'lines', v_p->'lines',
    'user_id', v_user, 'is_new_user', v_existing IS NULL, 'reused', v_reuse,
    'voucher', CASE WHEN v_v IS NOT NULL THEN jsonb_build_object('code', v_v->>'code', 'amount', v_disc) END);
EXCEPTION WHEN OTHERS THEN
  RETURN public._gear_rpc_failed('create_web_gear_booking', SQLSTATE, SQLERRM,
    jsonb_build_object('branch_id', p_branch_id, 'existing_booking_id', p_existing_booking_id));
END $$;

REVOKE ALL ON FUNCTION public._gear_parse_time(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._gear_web_upsert_customer(uuid, text, text, text, jsonb, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_parse_time(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._gear_web_upsert_customer(uuid, text, text, text, jsonb, text, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb)
  TO anon, authenticated, service_role;
COMMENT ON FUNCTION public.create_web_gear_booking(uuid, date, date, jsonb, jsonb, text, text, text, text, text, uuid, text, jsonb) IS
  'Web /pujceni-obleceni: výpůjčka JEN výbavy = bookings booking_kind=gear (pending/unpaid, web). Cena ze serveru, dárkový poukaz, souhlasy VOP+GDPR, identita jako create_web_booking. 2026-10-23.';
