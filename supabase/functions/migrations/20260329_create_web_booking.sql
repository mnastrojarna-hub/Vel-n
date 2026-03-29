-- =============================================================================
-- MIGRACE: create_web_booking RPC — deduplikace zákazníků + kontrola ŘP
-- Datum: 2026-03-29
-- Popis: Vytvoří web rezervaci. Najde existujícího zákazníka podle emailu
--        nebo vytvoří nového. Kontroluje ŘP skupinu vs. motorka.
--        Aktualizuje profil (adresa, telefon) u existujících zákazníků.
-- =============================================================================

CREATE OR REPLACE FUNCTION create_web_booking(
  p_moto_id uuid,
  p_start_date timestamptz,
  p_end_date timestamptz,
  p_name text,
  p_email text,
  p_phone text,
  p_street text DEFAULT '',
  p_city text DEFAULT '',
  p_zip text DEFAULT '',
  p_country text DEFAULT 'CZ',
  p_note text DEFAULT '',
  p_pickup_time time DEFAULT NULL,
  p_delivery_address text DEFAULT NULL,
  p_return_address text DEFAULT NULL,
  p_extras jsonb DEFAULT '[]'::jsonb,
  p_discount_amount numeric DEFAULT 0,
  p_discount_code text DEFAULT NULL,
  p_promo_code text DEFAULT NULL,
  p_voucher_id uuid DEFAULT NULL,
  p_license_group text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_booking_id uuid;
  v_moto record;
  v_existing_auth record;
  v_total numeric;
  v_extras_total numeric := 0;
  v_days integer;
  v_extra record;
  v_is_new_user boolean := false;
  v_allowed_groups text[];
  v_moto_license text;
  v_promo_id uuid := NULL;
BEGIN
  -- ===== 1) VALIDACE VSTUPŮ =====
  IF p_email IS NULL OR trim(p_email) = '' THEN
    RETURN jsonb_build_object('error', 'Email je povinný');
  END IF;
  IF p_moto_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Motorka není vybrána');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date <= p_start_date THEN
    RETURN jsonb_build_object('error', 'Neplatný termín rezervace');
  END IF;

  -- ===== 2) NAČTENÍ MOTORKY + KONTROLA ŘP SKUPINY =====
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF v_moto.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Motorka nenalezena');
  END IF;

  v_moto_license := COALESCE(v_moto.license_required, 'A');

  -- Motorky s license_required = 'N' může jet kdokoliv (bez ŘP)
  IF v_moto_license != 'N' THEN
    IF p_license_group IS NULL OR p_license_group = '' THEN
      RETURN jsonb_build_object('error', 'Pro tuto motorku je nutné zadat skupinu ŘP');
    END IF;

    -- Hierarchie ŘP skupin: A > A2 > A1 > AM, B = AM
    CASE upper(p_license_group)
      WHEN 'A'  THEN v_allowed_groups := ARRAY['A','A2','A1','AM'];
      WHEN 'A2' THEN v_allowed_groups := ARRAY['A2','A1','AM'];
      WHEN 'A1' THEN v_allowed_groups := ARRAY['A1','AM'];
      WHEN 'AM' THEN v_allowed_groups := ARRAY['AM'];
      WHEN 'B'  THEN v_allowed_groups := ARRAY['B','AM'];
      ELSE
        RETURN jsonb_build_object('error', 'Neplatná skupina ŘP: ' || p_license_group);
    END CASE;

    IF NOT (v_moto_license = ANY(v_allowed_groups)) THEN
      RETURN jsonb_build_object(
        'error',
        'Pro tuto motorku potřebujete ŘP skupiny ' || v_moto_license
          || '. Vaše skupina: ' || p_license_group
      );
    END IF;
  END IF;

  -- ===== 3) DEDUPLIKACE ZÁKAZNÍKA — hledání podle emailu =====
  SELECT id INTO v_existing_auth
    FROM auth.users
    WHERE lower(email) = lower(trim(p_email))
    LIMIT 1;

  IF v_existing_auth.id IS NOT NULL THEN
    -- Existující zákazník — aktualizuj profil (adresa, telefon)
    v_user_id := v_existing_auth.id;

    UPDATE profiles SET
      phone = CASE WHEN p_phone IS NOT NULL AND p_phone != '' THEN p_phone ELSE phone END,
      street = CASE WHEN p_street != '' THEN p_street ELSE street END,
      city = CASE WHEN p_city != '' THEN p_city ELSE city END,
      zip = CASE WHEN p_zip != '' THEN p_zip ELSE zip END,
      country = CASE WHEN p_country != '' AND p_country != 'CZ' THEN p_country ELSE country END,
      full_name = CASE WHEN full_name IS NULL OR full_name = '' THEN p_name ELSE full_name END,
      license_group = CASE
        WHEN p_license_group IS NOT NULL AND p_license_group != ''
             AND (license_group IS NULL OR array_length(license_group, 1) IS NULL)
        THEN ARRAY[upper(p_license_group)]
        ELSE license_group
      END,
      updated_at = now()
    WHERE id = v_user_id;

  ELSE
    -- Nový zákazník — vytvoř auth usera + profil
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
      crypt(gen_random_uuid()::text, gen_salt('bf')),
      now(), 'authenticated', 'authenticated',
      jsonb_build_object('full_name', p_name, 'phone', p_phone),
      now(), now()
    );

    INSERT INTO profiles (id, full_name, email, phone, street, city, zip, country,
                          registration_source, license_group)
    VALUES (
      v_user_id, p_name, lower(trim(p_email)), p_phone,
      p_street, p_city, p_zip, p_country, 'web',
      CASE WHEN p_license_group IS NOT NULL AND p_license_group != ''
           THEN ARRAY[upper(p_license_group)] ELSE NULL END
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = COALESCE(NULLIF(profiles.full_name, ''), EXCLUDED.full_name),
      phone = COALESCE(NULLIF(EXCLUDED.phone, ''), profiles.phone),
      street = COALESCE(NULLIF(EXCLUDED.street, ''), profiles.street),
      city = COALESCE(NULLIF(EXCLUDED.city, ''), profiles.city),
      zip = COALESCE(NULLIF(EXCLUDED.zip, ''), profiles.zip),
      country = EXCLUDED.country,
      registration_source = COALESCE(profiles.registration_source, 'web'),
      license_group = CASE
        WHEN EXCLUDED.license_group IS NOT NULL
             AND (profiles.license_group IS NULL OR array_length(profiles.license_group, 1) IS NULL)
        THEN EXCLUDED.license_group
        ELSE profiles.license_group
      END,
      updated_at = now();
  END IF;

  -- ===== 4) KONTROLA PŘEKRYVU (dostupnost motorky) =====
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = p_moto_id
      AND status IN ('pending','reserved','active')
      AND tstzrange(start_date, end_date, '[]') && tstzrange(p_start_date, p_end_date, '[]')
  ) THEN
    RETURN jsonb_build_object('error', 'Booking overlap — motorka není v termínu dostupná');
  END IF;

  -- ===== 5) VÝPOČET CENY =====
  v_days := GREATEST(1, EXTRACT(DAY FROM (p_end_date - p_start_date))::integer);
  v_total := COALESCE(v_moto.price_weekday, 0) * v_days;

  -- Extras
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extras_total := v_extras_total
        + COALESCE((v_extra.value->>'unit_price')::numeric, 0)
        * COALESCE((v_extra.value->>'quantity')::numeric, 1);
    END LOOP;
  END IF;
  v_total := v_total + v_extras_total;

  -- Sleva
  IF p_discount_amount IS NOT NULL AND p_discount_amount > 0 THEN
    v_total := GREATEST(0, v_total - p_discount_amount);
  END IF;

  -- Promo code → najdi ID
  IF p_promo_code IS NOT NULL AND p_promo_code != '' THEN
    SELECT id INTO v_promo_id FROM promo_codes
      WHERE code = p_promo_code AND active = true LIMIT 1;
  END IF;

  -- ===== 6) VYTVOŘENÍ BOOKINGU =====
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date,
    status, payment_status, total_price, extras_price,
    booking_source, pickup_time,
    pickup_address, return_address,
    discount_amount, discount_code,
    promo_code_id, voucher_id,
    notes
  ) VALUES (
    v_user_id, p_moto_id, p_start_date, p_end_date,
    'pending', 'unpaid', v_total, v_extras_total,
    'web', p_pickup_time,
    p_delivery_address, p_return_address,
    p_discount_amount, p_discount_code,
    v_promo_id, p_voucher_id,
    p_note
  )
  RETURNING id INTO v_booking_id;

  -- ===== 7) VLOŽENÍ EXTRAS =====
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

  -- ===== 8) VÝSLEDEK =====
  RETURN jsonb_build_object(
    'booking_id', v_booking_id,
    'amount', v_total,
    'user_id', v_user_id,
    'is_new_user', v_is_new_user
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
