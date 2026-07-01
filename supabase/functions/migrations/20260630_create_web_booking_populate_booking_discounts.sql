-- =============================================================================
-- MIGRACE 2026-06-30: FIX — create_web_booking plní booking_discounts
--
-- Problém: Velín u slevových kódů nereflektoval počet použití (used_count) a
--   vouchery se po zaplacení rezervace neoznačovaly jako 'redeemed'. Příčina:
--   jediný funkční mechanismus uplatnění je trigger redeem_booking_discounts_on_paid
--   (mig. 20260625_redeem_booking_discounts.sql), který inkrementuje
--   promo_codes.used_count (+ promo_code_usage) a nastaví vouchers.status='redeemed'.
--   Ten ale iteruje VÝHRADNĚ tabulku booking_discounts — a create_web_booking
--   (nejnovější 20260629) tuto tabulku vůbec neplnil (slevy ukládal jen do
--   bookings.discount_amount/discount_code/promo_code_id/voucher_id). Multi-discount
--   mašinerie z 25. 6. tak neměla vstupní data → used_count zůstával 0 a vouchery
--   navždy 'active'. (use_promo_code RPC se z žádného frontendu nevolá.)
--
-- Řešení: tělo 1:1 z 20260629_create_web_booking_overlap_own_pending.sql; přidán
--   JEN sběr uplatněných slev do lokálního jsonb v_bd (v sekci 5c) a nová sekce
--   8) BOOKING_DISCOUNTS, která je po INSERT/UPDATE bookingu vloží (i při re-use
--   draftu: smaž a vlož znovu) a přes _reallocate_booking_discounts rozpočítá
--   skutečně odečtené částky. Signatura, GRANT, ŘP kontrola, cena, upsert profilu,
--   overlap i INSERT/UPDATE bookingu beze změny.
-- =============================================================================
CREATE OR REPLACE FUNCTION "public"."create_web_booking"("p_moto_id" "uuid", "p_start_date" timestamp with time zone, "p_end_date" timestamp with time zone, "p_name" "text", "p_email" "text", "p_phone" "text", "p_street" "text" DEFAULT ''::"text", "p_city" "text" DEFAULT ''::"text", "p_zip" "text" DEFAULT ''::"text", "p_country" "text" DEFAULT 'CZ'::"text", "p_note" "text" DEFAULT ''::"text", "p_pickup_time" time without time zone DEFAULT NULL::time without time zone, "p_delivery_address" "text" DEFAULT NULL::"text", "p_return_address" "text" DEFAULT NULL::"text", "p_extras" "jsonb" DEFAULT '[]'::"jsonb", "p_discount_amount" numeric DEFAULT 0, "p_discount_code" "text" DEFAULT NULL::"text", "p_promo_code" "text" DEFAULT NULL::"text", "p_voucher_id" "uuid" DEFAULT NULL::"uuid", "p_license_group" "text" DEFAULT NULL::"text", "p_password" "text" DEFAULT NULL::"text", "p_helmet_size" "text" DEFAULT NULL::"text", "p_jacket_size" "text" DEFAULT NULL::"text", "p_pants_size" "text" DEFAULT NULL::"text", "p_boots_size" "text" DEFAULT NULL::"text", "p_gloves_size" "text" DEFAULT NULL::"text", "p_passenger_helmet_size" "text" DEFAULT NULL::"text", "p_passenger_jacket_size" "text" DEFAULT NULL::"text", "p_passenger_gloves_size" "text" DEFAULT NULL::"text", "p_passenger_boots_size" "text" DEFAULT NULL::"text", "p_return_time" "text" DEFAULT NULL::"text", "p_existing_booking_id" "uuid" DEFAULT NULL::"uuid", "p_passenger_pants_size" "text" DEFAULT NULL::"text", "p_consent_vop" boolean DEFAULT NULL::boolean, "p_consent_gdpr" boolean DEFAULT NULL::boolean, "p_marketing_consent" boolean DEFAULT NULL::boolean, "p_consent_photo" boolean DEFAULT NULL::boolean, "p_date_of_birth" "text" DEFAULT NULL::"text", "p_trailer_moto_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id uuid;
  v_booking_id uuid;
  v_moto record;
  v_existing_auth_id uuid;
  v_existing_booking record;
  v_reuse_booking boolean := false;
  v_total numeric;
  v_extras_total numeric := 0;
  v_extra record;
  v_is_new_user boolean := false;
  v_allowed_groups text[];
  v_moto_license text;
  v_moto_groups text[];
  v_promo_id uuid := NULL;
  v_promo_type text;
  v_promo_value numeric;
  v_voucher_amount numeric;
  v_current_date date;
  v_day_of_week integer;
  v_day_price numeric;
  v_dob date;
  v_late_discount numeric := 0;
  v_codes text[];
  v_code text;
  v_sum_discount numeric := 0;
  v_seen text[] := ARRAY[]::text[];
  v_voucher_ids uuid[] := ARRAY[]::uuid[];
  v_promo_id_tmp uuid;
  v_voucher_id_tmp uuid;
  v_bd jsonb := '[]'::jsonb;          -- NEW: sběr slev pro booking_discounts
  v_voucher_code text;                -- NEW: kód voucheru z legacy p_voucher_id větve
BEGIN
  -- 1) VALIDACE
  IF p_email IS NULL OR trim(p_email) = '' THEN
    RETURN jsonb_build_object('error','Email je povinný');
  END IF;
  IF p_moto_id IS NULL THEN
    RETURN jsonb_build_object('error','Motorka není vybrána');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN jsonb_build_object('error','Neplatný termín rezervace');
  END IF;

  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN
      v_dob := p_date_of_birth::date;
    EXCEPTION WHEN OTHERS THEN
      v_dob := NULL;
    END;
  END IF;

  -- 2) MOTORKA + ŘP
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF v_moto.id IS NULL THEN
    RETURN jsonb_build_object('error','Motorka nenalezena');
  END IF;

  IF v_moto.license_groups IS NOT NULL AND array_length(v_moto.license_groups, 1) >= 1 THEN
    SELECT array_agg(upper(btrim(x))) INTO v_moto_groups
      FROM unnest(v_moto.license_groups) AS x
      WHERE btrim(x) <> '';
  END IF;
  IF v_moto_groups IS NULL OR array_length(v_moto_groups, 1) IS NULL THEN
    v_moto_groups := ARRAY[upper(COALESCE(v_moto.license_required::text, 'A'))];
  END IF;
  v_moto_license := COALESCE(v_moto.license_required::text, 'A');

  IF NOT ('N' = ANY(v_moto_groups)) AND p_license_group IS NOT NULL AND p_license_group <> '' THEN
    CASE upper(p_license_group)
      WHEN 'A'  THEN v_allowed_groups := ARRAY['A','A2','A1','AM'];
      WHEN 'A2' THEN v_allowed_groups := ARRAY['A2','A1','AM'];
      WHEN 'A1' THEN v_allowed_groups := ARRAY['A1','AM'];
      WHEN 'AM' THEN v_allowed_groups := ARRAY['AM'];
      WHEN 'B'  THEN v_allowed_groups := ARRAY['B','AM'];
      ELSE
        RETURN jsonb_build_object('error','Neplatná skupina ŘP: '||p_license_group);
    END CASE;
    IF NOT (v_moto_groups && v_allowed_groups) THEN
      RETURN jsonb_build_object('error','Pro tuto motorku potřebujete ŘP skupiny '||array_to_string(v_moto_groups,' / ')||'. Vaše skupina: '||p_license_group);
    END IF;
  END IF;

  -- 3) DEDUPLIKACE ZÁKAZNÍKA + UPSERT profilu
  SELECT id INTO v_existing_auth_id
    FROM auth.users
    WHERE lower(email) = lower(trim(p_email))
    LIMIT 1;

  IF v_existing_auth_id IS NOT NULL
     AND p_existing_booking_id IS NULL
     AND current_user = 'anon' THEN
    RETURN jsonb_build_object(
      'error', 'email_exists',
      'message', 'Tento e-mail je v systému. Pro pokračování se přihlaste, nebo si obnovte heslo.'
    );
  END IF;

  IF v_existing_auth_id IS NOT NULL
     AND auth.uid() IS NOT NULL
     AND auth.uid() <> v_existing_auth_id THEN
    RETURN jsonb_build_object(
      'error', 'email_mismatch',
      'message', 'Přihlášený účet nesouhlasí se zadaným e-mailem.'
    );
  END IF;

  IF v_existing_auth_id IS NOT NULL THEN
    v_user_id := v_existing_auth_id;

    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country,
                          registration_source, license_group, date_of_birth,
                          consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (
      v_user_id, p_name, lower(trim(p_email)), p_phone,
      p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> ''
           THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob,
      COALESCE(p_consent_vop, true),
      COALESCE(p_consent_gdpr, true),
      COALESCE(p_marketing_consent, true),
      COALESCE(p_consent_photo, true)
    )
    ON CONFLICT (id) DO UPDATE SET
      phone = CASE WHEN EXCLUDED.phone IS NOT NULL AND EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE profiles.phone END,
      street = CASE WHEN EXCLUDED.street <> '' THEN EXCLUDED.street ELSE profiles.street END,
      city = CASE WHEN EXCLUDED.city <> '' THEN EXCLUDED.city ELSE profiles.city END,
      zip = CASE WHEN EXCLUDED.zip <> '' THEN EXCLUDED.zip ELSE profiles.zip END,
      country = CASE WHEN EXCLUDED.country <> '' AND EXCLUDED.country <> 'CZ' THEN EXCLUDED.country ELSE profiles.country END,
      full_name = CASE WHEN profiles.full_name IS NULL OR profiles.full_name = '' THEN EXCLUDED.full_name ELSE profiles.full_name END,
      license_group = CASE
        WHEN EXCLUDED.license_group IS NOT NULL
             AND (profiles.license_group IS NULL OR array_length(profiles.license_group, 1) IS NULL)
        THEN EXCLUDED.license_group
        ELSE profiles.license_group
      END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth),
      registration_source = COALESCE(profiles.registration_source, 'web'),
      consent_vop = COALESCE(p_consent_vop, profiles.consent_vop),
      consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent),
      consent_photo = COALESCE(p_consent_photo, profiles.consent_photo),
      updated_at = now();

    IF p_password IS NOT NULL AND p_password <> '' THEN
      UPDATE auth.users
        SET encrypted_password = crypt(p_password, gen_salt('bf')),
            updated_at = now()
        WHERE id = v_user_id;
    END IF;
  ELSE
    v_user_id := gen_random_uuid();
    v_is_new_user := true;

    INSERT INTO auth.users (
      id, instance_id, email, encrypted_password,
      email_confirmed_at, aud, role,
      raw_user_meta_data, created_at, updated_at
    ) VALUES (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      lower(trim(p_email)),
      crypt(COALESCE(NULLIF(p_password,''), gen_random_uuid()::text), gen_salt('bf')),
      now(), 'authenticated', 'authenticated',
      jsonb_build_object('full_name', p_name, 'phone', p_phone),
      now(), now()
    );

    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country,
                          registration_source, license_group, date_of_birth,
                          consent_vop, consent_gdpr, marketing_consent, consent_photo)
    VALUES (
      v_user_id, p_name, lower(trim(p_email)), p_phone,
      p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group <> ''
           THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END,
      v_dob,
      COALESCE(p_consent_vop, true),
      COALESCE(p_consent_gdpr, true),
      COALESCE(p_marketing_consent, true),
      COALESCE(p_consent_photo, true)
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = COALESCE(NULLIF(profiles.full_name,''), EXCLUDED.full_name),
      phone = COALESCE(NULLIF(EXCLUDED.phone,''), profiles.phone),
      street = COALESCE(NULLIF(EXCLUDED.street,''), profiles.street),
      city = COALESCE(NULLIF(EXCLUDED.city,''), profiles.city),
      zip = COALESCE(NULLIF(EXCLUDED.zip,''), profiles.zip),
      country = EXCLUDED.country,
      registration_source = COALESCE(profiles.registration_source,'web'),
      license_group = CASE
        WHEN EXCLUDED.license_group IS NOT NULL
             AND (profiles.license_group IS NULL OR array_length(profiles.license_group,1) IS NULL)
        THEN EXCLUDED.license_group
        ELSE profiles.license_group
      END,
      date_of_birth = COALESCE(v_dob, profiles.date_of_birth),
      consent_vop = COALESCE(p_consent_vop, profiles.consent_vop),
      consent_gdpr = COALESCE(p_consent_gdpr, profiles.consent_gdpr),
      marketing_consent = COALESCE(p_marketing_consent, profiles.marketing_consent),
      consent_photo = COALESCE(p_consent_photo, profiles.consent_photo),
      updated_at = now();
  END IF;

  -- 3c) RE-USE PENDING REZERVACE
  IF p_existing_booking_id IS NOT NULL THEN
    SELECT id, user_id, status, payment_status, booking_source
      INTO v_existing_booking
      FROM bookings WHERE id = p_existing_booking_id LIMIT 1;
    IF v_existing_booking.id IS NOT NULL
       AND v_existing_booking.user_id = v_user_id
       AND v_existing_booking.status = 'pending'
       AND v_existing_booking.payment_status = 'unpaid'
       AND v_existing_booking.booking_source = 'web' THEN
      v_reuse_booking := true;
    END IF;
  END IF;

  -- 4) OVERLAP  ← vlastní rozpracovaný (pending+unpaid web) draft zákazníka neblokuje
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = p_moto_id
      AND status IN ('pending','reserved','active')
      AND tstzrange(start_date, end_date,'[]') && tstzrange(p_start_date, p_end_date,'[]')
      AND (NOT v_reuse_booking OR id <> p_existing_booking_id)
      AND NOT (
        user_id = v_user_id
        AND status = 'pending'
        AND payment_status = 'unpaid'
        AND booking_source = 'web'
      )
  ) THEN
    RETURN jsonb_build_object('error','Booking overlap — motorka není v termínu dostupná');
  END IF;

  -- 5) CENA
  v_total := 0;
  v_current_date := p_start_date::date;
  WHILE v_current_date <= p_end_date::date LOOP
    v_day_of_week := EXTRACT(DOW FROM v_current_date)::integer;
    v_day_price := CASE v_day_of_week
      WHEN 0 THEN COALESCE(v_moto.price_sun, v_moto.price_weekday, 0)
      WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekday, 0)
    END;
    v_total := v_total + v_day_price;
    v_current_date := v_current_date + 1;
  END LOOP;
  IF v_total = 0 THEN v_total := COALESCE(v_moto.price_weekday,0); END IF;

  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extras_total := v_extras_total
        + COALESCE((v_extra.value->>'unit_price')::numeric,0)
        * COALESCE((v_extra.value->>'quantity')::numeric,1);
    END LOOP;
  END IF;
  v_total := v_total + v_extras_total;

  -- 5b) SLEVA 50 % NA 1. DEN (Model B — před procentem)
  v_late_discount := public._late_pickup_discount(p_moto_id, p_start_date, p_end_date, p_pickup_time);
  IF v_late_discount > 0 THEN
    v_total := GREATEST(0, v_total - v_late_discount);
  END IF;

  -- 5c) SLEVY — podpora VÍCE kódů + voucherů + % SOUČASNĚ + sběr do v_bd
  p_discount_amount := 0;
  v_sum_discount := 0;
  v_promo_id := NULL;

  IF p_discount_code IS NOT NULL AND btrim(p_discount_code) <> '' THEN
    v_codes := string_to_array(p_discount_code, ',');
  ELSIF p_promo_code IS NOT NULL AND p_promo_code <> '' THEN
    v_codes := ARRAY[p_promo_code];
  ELSE
    v_codes := ARRAY[]::text[];
  END IF;

  IF v_codes IS NOT NULL THEN
    FOREACH v_code IN ARRAY v_codes LOOP
      v_code := upper(btrim(v_code));
      CONTINUE WHEN v_code = '' OR v_code = ANY(v_seen);
      v_seen := array_append(v_seen, v_code);

      -- a) promo kód (lookup dle code)?
      SELECT id, type, value INTO v_promo_id_tmp, v_promo_type, v_promo_value
        FROM promo_codes WHERE upper(code) = v_code AND active = true LIMIT 1;
      IF v_promo_id_tmp IS NOT NULL THEN
        IF v_promo_type = 'percent' THEN
          v_sum_discount := v_sum_discount + ROUND(v_total * v_promo_value / 100);
        ELSE
          v_sum_discount := v_sum_discount + COALESCE(v_promo_value, 0);
        END IF;
        IF v_promo_id IS NULL THEN v_promo_id := v_promo_id_tmp; END IF;
        v_bd := v_bd || jsonb_build_object(            -- NEW
          'kind','promo_code','code',v_code,
          'promo_code_id',v_promo_id_tmp::text,'voucher_id',NULL,
          'discount_type',v_promo_type,'value',COALESCE(v_promo_value,0));
        CONTINUE;
      END IF;

      -- b) voucher (lookup dle code)?
      SELECT id, amount INTO v_voucher_id_tmp, v_voucher_amount
        FROM vouchers WHERE upper(code) = v_code AND status = 'active' LIMIT 1;
      IF v_voucher_id_tmp IS NOT NULL THEN
        v_sum_discount := v_sum_discount + COALESCE(v_voucher_amount, 0);
        v_voucher_ids := array_append(v_voucher_ids, v_voucher_id_tmp);
        v_bd := v_bd || jsonb_build_object(            -- NEW
          'kind','voucher','code',v_code,
          'promo_code_id',NULL,'voucher_id',v_voucher_id_tmp::text,
          'discount_type','fixed','value',COALESCE(v_voucher_amount,0));
      END IF;
    END LOOP;
  END IF;

  -- c) legacy: voucher předaný jen přes id (public-api / mcp-server bez code v listu)
  IF p_voucher_id IS NOT NULL AND NOT (p_voucher_id = ANY(v_voucher_ids)) THEN
    SELECT code, amount INTO v_voucher_code, v_voucher_amount
      FROM vouchers WHERE id = p_voucher_id AND status = 'active';
    IF v_voucher_amount IS NOT NULL THEN
      v_sum_discount := v_sum_discount + v_voucher_amount;
      v_voucher_ids := array_append(v_voucher_ids, p_voucher_id);
      v_bd := v_bd || jsonb_build_object(              -- NEW
        'kind','voucher','code',COALESCE(upper(v_voucher_code),'VOUCHER'),
        'promo_code_id',NULL,'voucher_id',p_voucher_id::text,
        'discount_type','fixed','value',COALESCE(v_voucher_amount,0));
    END IF;
  END IF;

  -- voucher_id sloupec drží první nalezený voucher (zpětně kompat reference)
  IF p_voucher_id IS NULL AND array_length(v_voucher_ids, 1) IS NOT NULL THEN
    p_voucher_id := v_voucher_ids[1];
  END IF;

  p_discount_amount := LEAST(GREATEST(v_sum_discount, 0), v_total);
  IF p_discount_amount > 0 THEN v_total := GREATEST(0, v_total - p_discount_amount); END IF;

  -- 6) UPDATE / INSERT BOOKING
  IF v_reuse_booking THEN
    UPDATE bookings SET
      moto_id = p_moto_id, start_date = p_start_date, end_date = p_end_date,
      total_price = v_total, extras_price = v_extras_total,
      late_pickup_discount_amount = v_late_discount,
      pickup_time = p_pickup_time, pickup_address = p_delivery_address,
      return_address = p_return_address, return_time = p_return_time,
      discount_amount = p_discount_amount, discount_code = p_discount_code,
      promo_code_id = v_promo_id, voucher_id = p_voucher_id, notes = p_note,
      trailer_moto_id = p_trailer_moto_id,
      helmet_size = p_helmet_size, jacket_size = p_jacket_size, pants_size = p_pants_size,
      boots_size = p_boots_size, gloves_size = p_gloves_size,
      passenger_helmet_size = p_passenger_helmet_size, passenger_jacket_size = p_passenger_jacket_size,
      passenger_pants_size = p_passenger_pants_size,
      passenger_gloves_size = p_passenger_gloves_size, passenger_boots_size = p_passenger_boots_size
    WHERE id = p_existing_booking_id;
    v_booking_id := p_existing_booking_id;
    DELETE FROM booking_extras WHERE booking_id = v_booking_id;
  ELSE
    INSERT INTO bookings (
      user_id, moto_id, start_date, end_date,
      status, payment_status, total_price, extras_price,
      late_pickup_discount_amount,
      booking_source, pickup_time,
      pickup_address, return_address, return_time,
      discount_amount, discount_code,
      promo_code_id, voucher_id, notes, trailer_moto_id,
      helmet_size, jacket_size, pants_size, boots_size, gloves_size,
      passenger_helmet_size, passenger_jacket_size, passenger_pants_size,
      passenger_gloves_size, passenger_boots_size
    ) VALUES (
      v_user_id, p_moto_id, p_start_date, p_end_date,
      'pending','unpaid', v_total, v_extras_total,
      v_late_discount,
      'web', p_pickup_time,
      p_delivery_address, p_return_address, p_return_time,
      p_discount_amount, p_discount_code,
      v_promo_id, p_voucher_id, p_note, p_trailer_moto_id,
      p_helmet_size, p_jacket_size, p_pants_size, p_boots_size, p_gloves_size,
      p_passenger_helmet_size, p_passenger_jacket_size, p_passenger_pants_size,
      p_passenger_gloves_size, p_passenger_boots_size
    ) RETURNING id INTO v_booking_id;
  END IF;

  -- 7) EXTRAS
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      INSERT INTO booking_extras (booking_id, name, unit_price, quantity)
      VALUES (
        v_booking_id,
        v_extra.value->>'name',
        COALESCE((v_extra.value->>'unit_price')::numeric, 0),
        COALESCE((v_extra.value->>'quantity')::integer, 1)
      );
    END LOOP;
  END IF;

  -- 8) BOOKING_DISCOUNTS — NEW: zdroj pravdy pro uplatnění slev.
  --    Bez tohoto se promo used_count neinkrementoval a voucher se po zaplacení
  --    neoznačil jako 'redeemed' (redeem_booking_discounts_on_paid iteruje tuto
  --    tabulku). Plní se i při re-use draftu (smaž a vlož znovu).
  DELETE FROM booking_discounts WHERE booking_id = v_booking_id;
  IF jsonb_array_length(v_bd) > 0 THEN
    INSERT INTO booking_discounts (booking_id, kind, code, promo_code_id, voucher_id, discount_type, value, amount)
    SELECT v_booking_id, e->>'kind', e->>'code',
           NULLIF(e->>'promo_code_id','')::uuid,
           NULLIF(e->>'voucher_id','')::uuid,
           e->>'discount_type', COALESCE((e->>'value')::numeric,0), 0
    FROM jsonb_array_elements(v_bd) AS e;
    -- rozpočítej skutečně odečtené částky proti hrubé ceně (po late slevě, před slevou)
    PERFORM public._reallocate_booking_discounts(v_booking_id, v_total + p_discount_amount);
  END IF;

  RETURN jsonb_build_object(
    'booking_id', v_booking_id,
    'amount', v_total,
    'late_pickup_discount', v_late_discount,
    'user_id', v_user_id,
    'is_new_user', v_is_new_user,
    'reused', v_reuse_booking
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION "public"."create_web_booking"("uuid", timestamp with time zone, timestamp with time zone, "text", "text", "text", "text", "text", "text", "text", "text", time without time zone, "text", "text", "jsonb", numeric, "text", "text", "uuid", "text", "text", "text", "text", "text", "text", "text", "text", "text", "text", "text", "text", "uuid", "text", boolean, boolean, boolean, boolean, "text", "uuid") TO "anon", "authenticated", "service_role";
