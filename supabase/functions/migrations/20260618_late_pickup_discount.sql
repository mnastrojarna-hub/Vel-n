-- =============================================================================
-- MIGRACE 2026-06-18: Sleva 50 % na 1. den při pozdním vyzvednutí
--
-- Pravidlo (schváleno zákazníkem): pokud je čas vyzvednutí 12:00 NEBO později
-- A rezervace je na 2 a více kalendářních dní (start+end včetně), napočítá se
-- sleva = round(50 % ceny prvního dne). Platí pro WEB i APP.
--
-- Model (zrcadlí věrnostní slevu, mig. 20260611_loyalty_ranks.sql):
--   - nový sloupec bookings.late_pickup_discount_amount (oddělený od
--     discount_amount [promo/voucher] i loyalty_discount_amount)
--   - helper _late_pickup_discount() = jediný autoritativní výpočet
--   - create_web_booking ji počítá server-side (web)
--   - BEFORE INSERT trigger trg_validate_late_pickup ji RE-VALIDUJE pro VŠECHNY
--     rezervace (web i app) — klientovi se nevěří, případný rozdíl se opraví
--     a dorovná total_price
--   - generate-invoice / KF ji vykáží jako samostatný záporný řádek
--
-- OVĚŘENO 2026-06-18 v živé DB (helper vrací 50 % ceny prvního dne; před 12:00
-- a u 1denní rezervace vrací 0).
--
-- MILESTONE 1 = jen vytváření rezervace. Přepočet při úpravě (DP/dobropis)
-- přijde v navazující migraci (Milestone 2).
-- =============================================================================

-- ── 1) Sloupec ───────────────────────────────────────────────────────────────
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS late_pickup_discount_amount numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.bookings.late_pickup_discount_amount IS
  'Sleva 50 % na 1. den při pozdním vyzvednutí (>=12:00) a rezervaci >=2 dny. '
  'Oddělená od discount_amount (promo/voucher) a loyalty_discount_amount. '
  'Autoritativně počítá _late_pickup_discount() + trigger trg_validate_late_pickup.';

-- ── 2) Helper: autoritativní výpočet slevy ───────────────────────────────────
-- Vrací 0 když podmínka neplatí. Cena prvního dne s trojím fallbackem
-- (price_<dow> → price_weekend [So/Ne] → price_weekday), aby seděla bez ohledu
-- na to, který per-day sloupec je vyplněný.
CREATE OR REPLACE FUNCTION public._late_pickup_discount(
  p_moto_id     uuid,
  p_start       timestamptz,
  p_end         timestamptz,
  p_pickup_time time
) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moto        motorcycles%ROWTYPE;
  v_days        int;
  v_dow         int;
  v_first_price numeric;
BEGIN
  IF p_moto_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_pickup_time IS NULL THEN
    RETURN 0;
  END IF;

  -- Podmínka A: vyzvednutí 12:00 nebo později
  IF p_pickup_time < TIME '12:00' THEN
    RETURN 0;
  END IF;

  -- Podmínka B: rezervace na 2 a více kalendářních dní (start i end včetně)
  v_days := (p_end::date - p_start::date) + 1;
  IF v_days < 2 THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_dow := EXTRACT(ISODOW FROM p_start::date)::int; -- 1=Po .. 7=Ne
  v_first_price := CASE v_dow
    WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
    WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
    WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
    WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
    WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
    WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekend, v_moto.price_weekday, 0)
    WHEN 7 THEN COALESCE(v_moto.price_sun, v_moto.price_weekend, v_moto.price_weekday, 0)
  END;

  RETURN ROUND(COALESCE(v_first_price, 0) * 0.5);
END;
$$;
REVOKE ALL ON FUNCTION public._late_pickup_discount(uuid, timestamptz, timestamptz, time) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._late_pickup_discount(uuid, timestamptz, timestamptz, time) TO authenticated, service_role;

-- ── 3) BEFORE INSERT trigger: anti-cheat „clamp-down" (NEpřidává slevu sám) ──
-- DŮLEŽITÉ: trigger slevu NIKDY sám nepřidá — jen OŘEŽE, pokud klient pošle
-- VÍC, než povoluje pravidlo (a dorovná total_price nahoru). Tím:
--   - web (create_web_booking) i app slevu reálně aplikují ve své cestě,
--   - business riziko (over-discount od zmanipulovaného klienta) je pokryto,
--   - ostatní flow (Velín admin, SOS náhrada, default booking_source='app')
--     zůstávají NEtknuté — žádná tichá sleva na rezervacích, které ji nemají
--     mít. Podhodnocení (klient pošle míň/0) není business riziko (zákazník
--     by jen zaplatil víc), proto se nedorovnává dolů.
-- EXCEPTION safe — nikdy neshodí insert rezervace.
CREATE OR REPLACE FUNCTION public.validate_late_pickup_discount()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max numeric;
  v_sent numeric;
BEGIN
  BEGIN
    v_sent := COALESCE(NEW.late_pickup_discount_amount, 0);
    IF v_sent > 0 THEN
      v_max := public._late_pickup_discount(NEW.moto_id, NEW.start_date, NEW.end_date, NEW.pickup_time);
      IF v_sent > v_max THEN
        -- klient si nárokoval víc, než pravidlo dovolí → ořež a vrať rozdíl do total_price
        NEW.total_price := COALESCE(NEW.total_price, 0) + (v_sent - v_max);
        NEW.late_pickup_discount_amount := v_max;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_late_pickup ON public.bookings;
CREATE TRIGGER trg_validate_late_pickup
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_late_pickup_discount();

-- ── 4) create_web_booking — doplnění výpočtu slevy (web) ─────────────────────
-- Beze změny dosavadní logiky; jen přidán blok 5b a uložení sloupce.
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
  p_license_group text DEFAULT NULL,
  p_password text DEFAULT NULL,
  p_helmet_size text DEFAULT NULL,
  p_jacket_size text DEFAULT NULL,
  p_pants_size text DEFAULT NULL,
  p_boots_size text DEFAULT NULL,
  p_gloves_size text DEFAULT NULL
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
  v_promo_type text;
  v_promo_value numeric;
  v_voucher_amount numeric;
  v_current_date date;
  v_day_of_week integer;
  v_day_price numeric;
  v_late_discount numeric := 0;   -- NEW: sleva 50 % na 1. den
BEGIN
  -- ===== 1) VALIDACE VSTUPŮ =====
  IF p_email IS NULL OR trim(p_email) = '' THEN
    RETURN jsonb_build_object('error', 'Email je povinný');
  END IF;
  IF p_moto_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Motorka není vybrána');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN jsonb_build_object('error', 'Neplatný termín rezervace');
  END IF;

  -- ===== 2) NAČTENÍ MOTORKY + KONTROLA ŘP SKUPINY =====
  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF v_moto.id IS NULL THEN
    RETURN jsonb_build_object('error', 'Motorka nenalezena');
  END IF;

  v_moto_license := COALESCE(v_moto.license_required, 'A');

  IF v_moto_license != 'N' AND p_license_group IS NOT NULL AND p_license_group != '' THEN
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
        THEN ARRAY[upper(p_license_group)::license_group]
        ELSE license_group
      END,
      updated_at = now()
    WHERE id = v_user_id;

    IF p_password IS NOT NULL AND p_password != '' THEN
      UPDATE auth.users SET
        encrypted_password = crypt(p_password, gen_salt('bf')),
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
      crypt(COALESCE(NULLIF(p_password, ''), gen_random_uuid()::text), gen_salt('bf')),
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
           THEN ARRAY[upper(p_license_group)::license_group] ELSE NULL END
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

  -- ===== 5) VÝPOČET CENY (per-day pricing, inclusive start+end) =====
  v_total := 0;
  v_current_date := p_start_date::date;
  WHILE v_current_date <= p_end_date::date LOOP
    v_day_of_week := EXTRACT(DOW FROM v_current_date)::integer; -- 0=Sun,1=Mon,...6=Sat
    v_day_price := CASE v_day_of_week
      WHEN 0 THEN COALESCE(v_moto.price_sun, v_moto.price_weekend, v_moto.price_weekday, 0)
      WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekend, v_moto.price_weekday, 0)
    END;
    v_total := v_total + v_day_price;
    v_current_date := v_current_date + 1;
  END LOOP;
  IF v_total = 0 THEN
    v_total := COALESCE(v_moto.price_weekday, 0);
  END IF;

  -- Extras
  IF p_extras IS NOT NULL AND jsonb_array_length(p_extras) > 0 THEN
    FOR v_extra IN SELECT * FROM jsonb_array_elements(p_extras) LOOP
      v_extras_total := v_extras_total
        + COALESCE((v_extra.value->>'unit_price')::numeric, 0)
        * COALESCE((v_extra.value->>'quantity')::numeric, 1);
    END LOOP;
  END IF;
  v_total := v_total + v_extras_total;

  -- ===== 5b) SLEVA 50 % NA 1. DEN (>=12:00, >=2 dny) — PŘED procentuální slevou =====
  -- Late snižuje základ PŘED výpočtem promo %, aby se procento nepočítalo z částky,
  -- kterou už late sleva odebrala (jinak dvojí slevnění 1. dne). Autoritativně přes
  -- helper (trigger trg_validate_late_pickup ji navíc revaliduje).
  v_late_discount := public._late_pickup_discount(p_moto_id, p_start_date, p_end_date, p_pickup_time);
  IF v_late_discount > 0 THEN
    v_total := GREATEST(0, v_total - v_late_discount);
  END IF;

  -- Promo code → najdi ID + typ + hodnotu a VYPOČÍTEJ slevu na serveru
  p_discount_amount := 0; -- IGNORUJ frontend hodnotu, vždy počítej server-side
  IF p_promo_code IS NOT NULL AND p_promo_code != '' THEN
    SELECT id, type, value INTO v_promo_id, v_promo_type, v_promo_value
      FROM promo_codes
      WHERE code = p_promo_code AND active = true LIMIT 1;

    IF v_promo_id IS NOT NULL THEN
      IF v_promo_type = 'percent' THEN
        p_discount_amount := ROUND(v_total * v_promo_value / 100);
      ELSE
        p_discount_amount := LEAST(v_promo_value, v_total);
      END IF;
    END IF;
  END IF;

  -- Voucher — přidej k slevě z promo kódu
  IF p_voucher_id IS NOT NULL THEN
    SELECT amount INTO v_voucher_amount FROM vouchers
      WHERE id = p_voucher_id AND status = 'active';
    IF v_voucher_amount IS NOT NULL THEN
      p_discount_amount := p_discount_amount
        + LEAST(v_voucher_amount, GREATEST(0, v_total - p_discount_amount));
    END IF;
  END IF;

  -- Sleva — aplikuj server-side vypočtenou hodnotu
  IF p_discount_amount > 0 THEN
    v_total := GREATEST(0, v_total - p_discount_amount);
  END IF;

  -- ===== 6) VYTVOŘENÍ BOOKINGU =====
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date,
    status, payment_status, total_price, extras_price,
    booking_source, pickup_time,
    pickup_address, return_address,
    discount_amount, discount_code,
    promo_code_id, voucher_id,
    late_pickup_discount_amount,
    notes,
    helmet_size, jacket_size, pants_size, boots_size, gloves_size
  ) VALUES (
    v_user_id, p_moto_id, p_start_date, p_end_date,
    'pending', 'unpaid', v_total, v_extras_total,
    'web', p_pickup_time,
    p_delivery_address, p_return_address,
    p_discount_amount, p_discount_code,
    v_promo_id, p_voucher_id,
    v_late_discount,
    p_note,
    p_helmet_size, p_jacket_size, p_pants_size, p_boots_size, p_gloves_size
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
    'late_pickup_discount', v_late_discount,
    'user_id', v_user_id,
    'is_new_user', v_is_new_user
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
