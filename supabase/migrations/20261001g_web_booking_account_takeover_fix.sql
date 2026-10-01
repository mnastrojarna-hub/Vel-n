-- =============================================================================
-- BEZPEČNOST: převzetí cizího účtu přes webovou rezervaci (nalezeno 2026-10-01)
-- Migrace: 20261001g_web_booking_account_takeover_fix.sql
--
-- `create_web_booking` (obě přetížení, GRANT anon) měl bránit anonymnímu
-- volajícímu použít e-mail EXISTUJÍCÍHO účtu podmínkou `current_user = 'anon'`.
-- Uvnitř SECURITY DEFINER funkce je ale current_user vždy vlastník (postgres)
-- → pojistka NIKDY nezabrala: kdokoli s veřejným anon klíčem webu poslal cizí
-- e-mail + své heslo a funkce přepsala heslo cizího účtu (auth.users) i jeho
-- telefon/adresu v profilu = převzetí účtu (doklady, rezervace, uložené karty,
-- kódy ke dveřím na útočníkův telefon). Ověřeno na kopii živého schématu.
-- Totéž umožňovala `set_web_booking_password(id rezervace, heslo)` (GRANT anon,
-- kontrola jen booking_source='web'); id rezervace se z 8místného čísla
-- z e-mailu dá dohledat anonymní `resolve_booking_ref`.
--
-- Oprava:
--  1) `_web_booking_caller_is_anon()` — anonymní volání se pozná z JWT role
--     (auth.uid() NULL + role 'anon'), ne z current_user;
--  2) anonym + existující e-mail → `email_exists` (web na to už umí reagovat:
--     výzva k přihlášení); výjimka jen pro skutečné znovupoužití vlastní
--     nezaplacené webové rezervace (dřív stačilo poslat libovolné
--     p_existing_booking_id — kontrola byla až po přepisu hesla);
--  3) u EXISTUJÍCÍHO účtu mění heslo a profil (telefon, adresa, souhlasy) jen
--     sám přihlášený vlastník; ostatní (anonym při znovupoužití, AI/MCP/API
--     přes service_role) rezervaci k účtu přiřadí, ale heslo ani kontakty
--     nezmění (profil se jen založí, chybí-li úplně);
--  4) `set_web_booking_password` — jen vlastník, nebo PRVNÍ rezervace čerstvě
--     založeného účtu (`_web_booking_created_account`: účet nikdy nepřihlášený,
--     < 24 h, rezervace vznikla s účtem) — tok webu (heslo hosta po dokladech)
--     i AI (nový zákazník) funguje dál; jinak `account_exists`;
--  5) `extend_booking` (bez kontroly vlastníka, GRANT anon) — nikde se nevolá
--     z webu/appky/Velínu → odebrán EXECUTE pro anon/authenticated;
--  6) staré 39parametrové přetížení `create_web_booking` se ruší — volání bez
--     p_discounts (AI chat, MCP, public-api) kvůli němu padala (PGRST203).
-- Těla funkcí PŘEVZATA z živé definice (snapshot 2026-10-01) — změněny jen
-- uvedené podmínky. Signatury zbylých funkcí beze změny. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._web_booking_caller_is_anon()
RETURNS boolean LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT auth.uid() IS NULL
     AND COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                  NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'anon'
$$;
REVOKE ALL ON FUNCTION public._web_booking_caller_is_anon() FROM PUBLIC, anon, authenticated;

-- Rezervace p_booking_id účet založila: je to jeho první rezervace, vznikla
-- nejvýš 10 min po účtu a účet se nikdy nepřihlásil a není starší 24 h.
CREATE OR REPLACE FUNCTION public._web_booking_created_account(p_booking_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.bookings b JOIN auth.users u ON u.id = b.user_id
     WHERE b.id = p_booking_id
       AND u.last_sign_in_at IS NULL
       AND u.created_at > now() - interval '24 hours'
       AND b.created_at BETWEEN u.created_at - interval '1 minute' AND u.created_at + interval '10 minutes'
       AND NOT EXISTS (SELECT 1 FROM public.bookings o
                        WHERE o.user_id = b.user_id AND o.id <> b.id AND o.created_at < b.created_at))
$$;
REVOKE ALL ON FUNCTION public._web_booking_created_account(uuid) FROM PUBLIC, anon, authenticated;

-- Staré 39parametrové přetížení (bez p_discounts): volání bez p_discounts
-- (AI agent create_booking_request, mcp-server, public-api) padala na
-- „Could not choose a best candidate function“ (PGRST203) — obě verze sedí.
-- S p_discounts se volá jen nová verze → stará je nedosažitelná; ruší se
-- (stejná oprava jako 2026-04-25). Nová verze má p_discounts DEFAULT NULL.
DROP FUNCTION IF EXISTS public.create_web_booking(uuid, timestamp with time zone, timestamp with time zone, text, text, text, text, text, text, text, text, time without time zone, text, text, jsonb, numeric, text, text, uuid, text, text, text, text, text, text, text, text, text, text, text, text, uuid, text, boolean, boolean, boolean, boolean, text, uuid);

CREATE OR REPLACE FUNCTION public.create_web_booking(p_moto_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_name text, p_email text, p_phone text, p_street text DEFAULT ''::text, p_city text DEFAULT ''::text, p_zip text DEFAULT ''::text, p_country text DEFAULT 'CZ'::text, p_note text DEFAULT ''::text, p_pickup_time time without time zone DEFAULT NULL::time without time zone, p_delivery_address text DEFAULT NULL::text, p_return_address text DEFAULT NULL::text, p_extras jsonb DEFAULT '[]'::jsonb, p_discount_amount numeric DEFAULT 0, p_discount_code text DEFAULT NULL::text, p_promo_code text DEFAULT NULL::text, p_voucher_id uuid DEFAULT NULL::uuid, p_license_group text DEFAULT NULL::text, p_password text DEFAULT NULL::text, p_helmet_size text DEFAULT NULL::text, p_jacket_size text DEFAULT NULL::text, p_pants_size text DEFAULT NULL::text, p_boots_size text DEFAULT NULL::text, p_gloves_size text DEFAULT NULL::text, p_passenger_helmet_size text DEFAULT NULL::text, p_passenger_jacket_size text DEFAULT NULL::text, p_passenger_gloves_size text DEFAULT NULL::text, p_passenger_boots_size text DEFAULT NULL::text, p_return_time text DEFAULT NULL::text, p_existing_booking_id uuid DEFAULT NULL::uuid, p_passenger_pants_size text DEFAULT NULL::text, p_consent_vop boolean DEFAULT NULL::boolean, p_consent_gdpr boolean DEFAULT NULL::boolean, p_marketing_consent boolean DEFAULT NULL::boolean, p_consent_photo boolean DEFAULT NULL::boolean, p_date_of_birth text DEFAULT NULL::text, p_trailer_moto_id uuid DEFAULT NULL::uuid, p_discounts jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_user_id uuid; v_booking_id uuid; v_moto record; v_existing_auth_id uuid;
  v_existing_booking record; v_reuse_booking boolean := false; v_total numeric;
  v_extras_total numeric := 0; v_extra record; v_is_new_user boolean := false;
  v_allowed_groups text[]; v_moto_license text; v_promo_id uuid := NULL;
  v_voucher_amount numeric; v_current_date date; v_day_of_week integer;
  v_day_price numeric; v_dob date; v_late_discount numeric := 0;
  v_disc jsonb := '[]'::jsonb; v_disc_final jsonb := '[]'::jsonb; v_item jsonb;
  v_pc record; v_vc record; v_pct_rate numeric := 0; v_pct_seen boolean := false;
  v_pct_amt numeric := 0; v_fixed_remaining numeric := 0; v_item_amount numeric := 0;
  v_primary_voucher_id uuid := NULL;
BEGIN
  IF p_email IS NULL OR trim(p_email) = '' THEN RETURN jsonb_build_object('error','Email je povinný'); END IF;
  IF p_moto_id IS NULL THEN RETURN jsonb_build_object('error','Motorka není vybrána'); END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN RETURN jsonb_build_object('error','Neplatný termín rezervace'); END IF;
  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN v_dob := p_date_of_birth::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END;
  END IF;
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF v_moto.id IS NULL THEN RETURN jsonb_build_object('error','Motorka nenalezena'); END IF;
  v_moto_license := COALESCE(v_moto.license_required,'A');
  IF v_moto_license <> 'N' AND p_license_group IS NOT NULL AND p_license_group <> '' THEN
    CASE upper(p_license_group)
      WHEN 'A'  THEN v_allowed_groups := ARRAY['A','A2','A1','AM'];
      WHEN 'A2' THEN v_allowed_groups := ARRAY['A2','A1','AM'];
      WHEN 'A1' THEN v_allowed_groups := ARRAY['A1','AM'];
      WHEN 'AM' THEN v_allowed_groups := ARRAY['AM'];
      WHEN 'B'  THEN v_allowed_groups := ARRAY['B','AM'];
      ELSE RETURN jsonb_build_object('error','Neplatná skupina ŘP: '||p_license_group);
    END CASE;
    IF NOT (v_moto_license = ANY(v_allowed_groups)) THEN
      RETURN jsonb_build_object('error','Pro tuto motorku potřebujete ŘP skupiny '||v_moto_license||'. Vaše skupina: '||p_license_group);
    END IF;
  END IF;
  SELECT id INTO v_existing_auth_id FROM auth.users WHERE lower(email) = lower(trim(p_email)) LIMIT 1;
  IF v_existing_auth_id IS NOT NULL AND public._web_booking_caller_is_anon() AND NOT EXISTS (SELECT 1 FROM bookings eb WHERE eb.id = p_existing_booking_id AND eb.user_id = v_existing_auth_id AND eb.status = 'pending' AND eb.payment_status = 'unpaid' AND eb.booking_source = 'web') THEN
    RETURN jsonb_build_object('error','email_exists','message','Tento e-mail je v systému. Pro pokračování se přihlaste, nebo si obnovte heslo.');
  END IF;
  IF v_existing_auth_id IS NOT NULL AND auth.uid() IS NOT NULL AND auth.uid() <> v_existing_auth_id THEN
    RETURN jsonb_build_object('error','email_mismatch','message','Přihlášený účet nesouhlasí se zadaným e-mailem.');
  END IF;
  IF v_existing_auth_id IS NOT NULL THEN
    v_user_id := v_existing_auth_id;
    IF COALESCE(auth.uid() = v_user_id, false) OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_user_id) THEN
    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source, license_group, date_of_birth, consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (v_user_id, p_name, lower(trim(p_email)), p_phone, p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> '' THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob, COALESCE(p_consent_vop,true), COALESCE(p_consent_gdpr,true), COALESCE(p_marketing_consent,true), COALESCE(p_consent_photo,true))
    ON CONFLICT (id) DO UPDATE SET
      phone = CASE WHEN EXCLUDED.phone IS NOT NULL AND EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE profiles.phone END,
      street = CASE WHEN EXCLUDED.street <> '' THEN EXCLUDED.street ELSE profiles.street END,
      city = CASE WHEN EXCLUDED.city <> '' THEN EXCLUDED.city ELSE profiles.city END,
      zip = CASE WHEN EXCLUDED.zip <> '' THEN EXCLUDED.zip ELSE profiles.zip END,
      country = CASE WHEN EXCLUDED.country <> '' AND EXCLUDED.country <> 'CZ' THEN EXCLUDED.country ELSE profiles.country END,
      full_name = CASE WHEN profiles.full_name IS NULL OR profiles.full_name = '' THEN EXCLUDED.full_name ELSE profiles.full_name END,
      license_group = CASE WHEN EXCLUDED.license_group IS NOT NULL AND (profiles.license_group IS NULL OR array_length(profiles.license_group,1) IS NULL) THEN EXCLUDED.license_group ELSE profiles.license_group END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth), registration_source = COALESCE(profiles.registration_source,'web'),
      consent_vop = COALESCE(p_consent_vop, profiles.consent_vop), consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent), consent_photo = COALESCE(p_consent_photo, profiles.consent_photo), updated_at = now();
    END IF;
    IF p_password IS NOT NULL AND p_password <> '' AND COALESCE(auth.uid() = v_user_id, false) THEN
      UPDATE auth.users SET encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() WHERE id = v_user_id;
    END IF;
  ELSE
    v_user_id := gen_random_uuid(); v_is_new_user := true;
    INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, aud, role, raw_user_meta_data, created_at, updated_at)
    VALUES (v_user_id, '00000000-0000-0000-0000-000000000000', lower(trim(p_email)), crypt(COALESCE(NULLIF(p_password,''), gen_random_uuid()::text), gen_salt('bf')),
      now(), 'authenticated', 'authenticated', jsonb_build_object('full_name', p_name, 'phone', p_phone), now(), now());
    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country, registration_source, license_group, date_of_birth, consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (v_user_id, p_name, lower(trim(p_email)), p_phone, p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> '' THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob, COALESCE(p_consent_vop,true), COALESCE(p_consent_gdpr,true), COALESCE(p_marketing_consent,true), COALESCE(p_consent_photo,true))
    ON CONFLICT (id) DO UPDATE SET
      full_name = COALESCE(NULLIF(profiles.full_name,''), EXCLUDED.full_name), phone = COALESCE(NULLIF(EXCLUDED.phone,''), profiles.phone),
      street = COALESCE(NULLIF(EXCLUDED.street,''), profiles.street), city = COALESCE(NULLIF(EXCLUDED.city,''), profiles.city),
      zip = COALESCE(NULLIF(EXCLUDED.zip,''), profiles.zip), country = EXCLUDED.country, registration_source = COALESCE(profiles.registration_source,'web'),
      license_group = CASE WHEN EXCLUDED.license_group IS NOT NULL AND (profiles.license_group IS NULL OR array_length(profiles.license_group,1) IS NULL) THEN EXCLUDED.license_group ELSE profiles.license_group END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth), consent_vop = COALESCE(p_consent_vop, profiles.consent_vop), consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent), consent_photo = COALESCE(p_consent_photo, profiles.consent_photo), updated_at = now();
  END IF;
  IF p_existing_booking_id IS NOT NULL THEN
    SELECT id, user_id, status, payment_status, booking_source INTO v_existing_booking FROM bookings WHERE id = p_existing_booking_id LIMIT 1;
    IF v_existing_booking.id IS NOT NULL AND v_existing_booking.user_id = v_user_id AND v_existing_booking.status = 'pending'
       AND v_existing_booking.payment_status = 'unpaid' AND v_existing_booking.booking_source = 'web' THEN v_reuse_booking := true; END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM bookings WHERE moto_id = p_moto_id AND status IN ('pending','reserved','active')
      AND tstzrange(start_date, end_date,'[]') && tstzrange(p_start_date, p_end_date,'[]')
      AND (NOT v_reuse_booking OR id <> p_existing_booking_id)) THEN
    RETURN jsonb_build_object('error','Booking overlap — motorka není v termínu dostupná');
  END IF;
  v_total := 0; v_current_date := p_start_date::date;
  WHILE v_current_date <= p_end_date::date LOOP
    v_day_of_week := EXTRACT(DOW FROM v_current_date)::integer;
    v_day_price := CASE v_day_of_week
      WHEN 0 THEN COALESCE(v_moto.price_sun, v_moto.price_weekday, 0) WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0) WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0) WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekday, 0) END;
    v_total := v_total + v_day_price; v_current_date := v_current_date + 1;
  END LOOP;
  IF v_total = 0 THEN v_total := COALESCE(v_moto.price_weekday,0); END IF;
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extras_total := v_extras_total + COALESCE((v_extra.value->>'unit_price')::numeric,0) * COALESCE((v_extra.value->>'quantity')::numeric,1);
    END LOOP;
  END IF;
  v_total := v_total + v_extras_total;
  v_late_discount := public._late_pickup_discount(p_moto_id, p_start_date, p_end_date, p_pickup_time);
  IF v_late_discount > 0 THEN v_total := GREATEST(0, v_total - v_late_discount); END IF;
  -- 5c) MULTI-SLEVA
  IF p_discounts IS NOT NULL AND jsonb_typeof(p_discounts) = 'array' AND jsonb_array_length(p_discounts) > 0 THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_discounts) LOOP
      IF lower(COALESCE(v_item->>'kind','')) = 'voucher' THEN
        SELECT id, code, amount INTO v_vc FROM vouchers WHERE code = upper(v_item->>'code') AND status='active' AND (valid_until IS NULL OR valid_until >= current_date) LIMIT 1;
        IF v_vc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','voucher','code',v_vc.code,'voucher_id',v_vc.id,'discount_type','fixed','value',v_vc.amount); END IF;
      ELSE
        SELECT id, code, type, value INTO v_pc FROM promo_codes WHERE code = upper(v_item->>'code') AND active = true LIMIT 1;
        IF v_pc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','promo_code','code',v_pc.code,'promo_code_id',v_pc.id,'discount_type',v_pc.type,'value',v_pc.value); END IF;
      END IF;
    END LOOP;
  ELSE
    IF p_promo_code IS NOT NULL AND p_promo_code <> '' THEN
      SELECT id, code, type, value INTO v_pc FROM promo_codes WHERE code = p_promo_code AND active = true LIMIT 1;
      IF v_pc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','promo_code','code',v_pc.code,'promo_code_id',v_pc.id,'discount_type',v_pc.type,'value',v_pc.value); END IF;
    END IF;
    IF p_voucher_id IS NOT NULL THEN
      SELECT id, code, amount INTO v_vc FROM vouchers WHERE id = p_voucher_id AND status='active' LIMIT 1;
      IF v_vc.id IS NOT NULL THEN v_disc := v_disc || jsonb_build_object('kind','voucher','code',v_vc.code,'voucher_id',v_vc.id,'discount_type','fixed','value',v_vc.amount); END IF;
    END IF;
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_disc) LOOP
    IF (v_item->>'discount_type') = 'percent' THEN
      IF v_pct_seen THEN RETURN jsonb_build_object('error','Lze uplatnit nejvýše jednu procentní slevu'); END IF;
      v_pct_seen := true; v_pct_rate := COALESCE((v_item->>'value')::numeric, 0);
    END IF;
  END LOOP;
  v_pct_amt := ROUND(v_total * v_pct_rate / 100);
  v_fixed_remaining := GREATEST(0, v_total - v_pct_amt);
  p_discount_amount := 0;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_disc) LOOP
    IF (v_item->>'discount_type') = 'percent' THEN v_item_amount := v_pct_amt;
    ELSE v_item_amount := LEAST(COALESCE((v_item->>'value')::numeric,0), v_fixed_remaining); v_fixed_remaining := v_fixed_remaining - v_item_amount; END IF;
    p_discount_amount := p_discount_amount + v_item_amount;
    v_disc_final := v_disc_final || (v_item || jsonb_build_object('amount', v_item_amount));
    IF (v_item->>'kind') = 'promo_code' AND v_promo_id IS NULL THEN v_promo_id := (v_item->>'promo_code_id')::uuid; END IF;
    IF (v_item->>'kind') = 'voucher' AND v_primary_voucher_id IS NULL THEN v_primary_voucher_id := (v_item->>'voucher_id')::uuid; END IF;
  END LOOP;
  v_total := GREATEST(0, v_total - p_discount_amount);
  IF v_reuse_booking THEN
    UPDATE bookings SET moto_id = p_moto_id, start_date = p_start_date, end_date = p_end_date, total_price = v_total, extras_price = v_extras_total,
      late_pickup_discount_amount = v_late_discount, pickup_time = p_pickup_time, pickup_address = p_delivery_address, return_address = p_return_address, return_time = p_return_time,
      discount_amount = p_discount_amount, discount_code = p_discount_code, promo_code_id = v_promo_id, voucher_id = v_primary_voucher_id, notes = p_note, trailer_moto_id = p_trailer_moto_id,
      helmet_size = p_helmet_size, jacket_size = p_jacket_size, pants_size = p_pants_size, boots_size = p_boots_size, gloves_size = p_gloves_size,
      passenger_helmet_size = p_passenger_helmet_size, passenger_jacket_size = p_passenger_jacket_size, passenger_pants_size = p_passenger_pants_size,
      passenger_gloves_size = p_passenger_gloves_size, passenger_boots_size = p_passenger_boots_size WHERE id = p_existing_booking_id;
    v_booking_id := p_existing_booking_id; DELETE FROM booking_extras WHERE booking_id = v_booking_id;
  ELSE
    INSERT INTO bookings (user_id, moto_id, start_date, end_date, status, payment_status, total_price, extras_price, late_pickup_discount_amount, booking_source, pickup_time,
      pickup_address, return_address, return_time, discount_amount, discount_code, promo_code_id, voucher_id, notes, trailer_moto_id,
      helmet_size, jacket_size, pants_size, boots_size, gloves_size, passenger_helmet_size, passenger_jacket_size, passenger_pants_size, passenger_gloves_size, passenger_boots_size)
    VALUES (v_user_id, p_moto_id, p_start_date, p_end_date, 'pending','unpaid', v_total, v_extras_total, v_late_discount, 'web', p_pickup_time,
      p_delivery_address, p_return_address, p_return_time, p_discount_amount, p_discount_code, v_promo_id, v_primary_voucher_id, p_note, p_trailer_moto_id,
      p_helmet_size, p_jacket_size, p_pants_size, p_boots_size, p_gloves_size, p_passenger_helmet_size, p_passenger_jacket_size, p_passenger_pants_size, p_passenger_gloves_size, p_passenger_boots_size)
    RETURNING id INTO v_booking_id;
  END IF;
  -- 6b) BOOKING_DISCOUNTS
  DELETE FROM booking_discounts WHERE booking_id = v_booking_id;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_disc_final) LOOP
    INSERT INTO booking_discounts (booking_id, kind, code, promo_code_id, voucher_id, discount_type, value, amount)
    VALUES (v_booking_id, v_item->>'kind', v_item->>'code', NULLIF(v_item->>'promo_code_id','')::uuid, NULLIF(v_item->>'voucher_id','')::uuid,
      v_item->>'discount_type', COALESCE((v_item->>'value')::numeric,0), COALESCE((v_item->>'amount')::numeric,0));
  END LOOP;
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      INSERT INTO booking_extras (booking_id, name, unit_price, quantity)
      VALUES (v_booking_id, v_extra.value->>'name', COALESCE((v_extra.value->>'unit_price')::numeric, 0), COALESCE((v_extra.value->>'quantity')::integer, 1));
    END LOOP;
  END IF;
  RETURN jsonb_build_object('booking_id', v_booking_id, 'amount', v_total, 'discount_amount', p_discount_amount,
    'late_pickup_discount', v_late_discount, 'discounts', v_disc_final, 'user_id', v_user_id, 'is_new_user', v_is_new_user, 'reused', v_reuse_booking);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_web_booking_password(p_booking_id uuid, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id uuid;
  v_source text;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RETURN jsonb_build_object('error', 'Heslo musí mít alespoň 8 znaků');
  END IF;

  SELECT user_id, booking_source INTO v_user_id, v_source
    FROM bookings WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source <> 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;
  -- Heslo smí nastavit jen vlastník účtu, nebo rezervace, která účet právě
  -- založila (jeho PRVNÍ rezervace, účet nikdy nepřihlášený, < 24 h). Dřív
  -- stačilo znát id libovolné webové rezervace (anon) = převzetí účtu.
  IF NOT (COALESCE(auth.uid() = v_user_id, false) OR public._web_booking_created_account(p_booking_id)) THEN
    RETURN jsonb_build_object('error', 'account_exists',
      'message', 'Účet už existuje — heslo změníte po přihlášení nebo přes „Zapomenuté heslo".');
  END IF;

  -- Hlavní heslo do auth.users
  UPDATE auth.users SET
    encrypted_password = crypt(p_password, gen_salt('bf')),
    updated_at = now()
  WHERE id = v_user_id;

  -- Hash posledních 4 znaků pro AI ověření
  UPDATE profiles
     SET password_last4_bcrypt = crypt(right(p_password, 4), gen_salt('bf'))
   WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

DO $$ BEGIN
  IF to_regprocedure('public.extend_booking(uuid, timestamptz)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.extend_booking(uuid, timestamptz) FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.extend_booking(uuid, date)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.extend_booking(uuid, date) FROM PUBLIC, anon, authenticated';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
