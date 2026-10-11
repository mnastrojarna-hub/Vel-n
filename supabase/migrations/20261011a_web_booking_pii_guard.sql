-- =============================================================================
-- 2026-10-11 BEZPEČNOST: osobní údaje z webových rezervací (anonym s UUID)
-- Model „nositel odkazu" (UUID z mailu / QR / ?resume=) platí jen pro ŽIVOU
-- webovou rezervaci a nikdy nevydá cizí citlivé údaje. Vlastník (přihlášený),
-- admin a service role beze změny. Těla = živá definice, měněno jen označené.
-- get_web_booking_confirmation je v 20261011b_…_b_confirm (limit velikosti souboru).
-- Granty ai_* / send_* / resolve_booking_ref řeší 20261011d. Idempotentní.
-- =============================================================================

-- 0) Pomocné funkce (volají je jen SECURITY DEFINER funkce níže a v 20261011b)
-- plný přístup k údajům rezervace = vlastník / admin / service role
CREATE OR REPLACE FUNCTION public._web_booking_full_access(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT COALESCE(auth.uid() = p_user_id, false) OR public.is_admin()
      OR COALESCE(auth.role(), '') = 'service_role'
$function$;
-- živá webová rezervace: pending/reserved/active a konec (Praha) dnes nebo později
CREATE OR REPLACE FUNCTION public._web_booking_is_live(p_booking_id uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT EXISTS (SELECT 1 FROM public.bookings b
                  WHERE b.id = p_booking_id AND b.booking_source = 'web'
                    AND b.status IN ('pending', 'reserved', 'active')
                    AND (b.end_date AT TIME ZONE 'Europe/Prague')::date
                        >= (now() AT TIME ZONE 'Europe/Prague')::date)
$function$;
REVOKE ALL ON FUNCTION public._web_booking_full_access(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._web_booking_is_live(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._web_booking_full_access(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._web_booking_is_live(uuid) TO service_role;

-- 1) ai_lookup_bookings_by_contact: bez plného UUID (klíč k ?resume=); agent
--    pokračuje přes booking_number (resolveBookingRef, service role).
CREATE OR REPLACE FUNCTION public.ai_lookup_bookings_by_contact(p_contact text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_raw     text := trim(coalesce(p_contact, ''));
  v_is_email boolean;
  v_digits  text;
  v_rows    jsonb;
BEGIN
  IF length(v_raw) < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_inputs');
  END IF;

  v_is_email := position('@' in v_raw) > 0;
  v_digits   := regexp_replace(v_raw, '\D', '', 'g');

  IF NOT v_is_email AND length(v_digits) < 9 THEN
    RETURN jsonb_build_object('success', false, 'error', 'bad_contact');
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      upper(right(b.id::text, 8))                          AS booking_number,
      -- 2026-10-11: booking_id (plné UUID) se nevrací
      b.status::text                                       AS status,
      b.payment_status::text                               AS payment_status,
      b.booking_source                                     AS booking_source,
      b.start_date                                         AS start_date,
      b.end_date                                           AS end_date,
      b.total_price                                        AS total_price,
      b.pickup_method                                      AS pickup_method,
      b.created_at                                         AS created_at,
      b.confirmed_at                                       AS confirmed_at,
      (b.abandoned_email_sent_at IS NOT NULL)              AS abandoned_email_sent,
      (b.reserved_email_sent_at IS NOT NULL)               AS reserved_email_sent,
      coalesce(
        nullif(trim(coalesce(m.brand, '') || ' ' || coalesce(m.model, '')), ''),
        'Motorka'
      )                                                    AS moto_name,
      (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
                 'template_slug', se.template_slug,
                 'subject',       se.subject,
                 'status',        se.status,
                 'sent_at',       se.created_at
               ) ORDER BY se.created_at DESC), '[]'::jsonb)
        FROM sent_emails se
        WHERE se.booking_id = b.id
      )                                                    AS emails
    FROM bookings b
    JOIN profiles p        ON p.id = b.user_id
    LEFT JOIN motorcycles m ON m.id = b.moto_id
    WHERE coalesce(b.is_test, false) = false
      AND (
        CASE WHEN v_is_email
          THEN lower(p.email) = lower(v_raw)
          ELSE p.phone IS NOT NULL
               AND length(regexp_replace(p.phone, '\D', '', 'g')) >= 9
               AND right(regexp_replace(p.phone, '\D', '', 'g'), 9) = right(v_digits, 9)
        END
      )
    ORDER BY b.created_at DESC
    LIMIT 15
  ) t;

  RETURN jsonb_build_object(
    'success',    true,
    'count',      jsonb_array_length(v_rows),
    'matched_by', CASE WHEN v_is_email THEN 'email' ELSE 'phone' END,
    'bookings',   v_rows
  );
END;
$function$;

-- 2) get_web_booking_resume: nositel odkazu (?resume= z mailu / QR / Stripe
--    zpět / AI chat) dál obnoví rezervaci, ale čísla dokladů dostane
--    MASKOVANÁ, datum narození jen u čerstvě založeného účtu a důvod dokladů
--    bez věku / data ŘP.
CREATE OR REPLACE FUNCTION public.get_web_booking_resume(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_uid    uuid;
  v_end    date;
  v_moto   uuid;
  v_docs   text;
  v_full   boolean;   -- 2026-10-11: čitelná čísla dokladů
  v_dob_ok boolean;   -- 2026-10-11: datum narození
BEGIN
  -- Nejprve ověř, že rezervace odpovídá povoleným stavům (jinak = not found).
  SELECT b.user_id, b.end_date::date, b.moto_id
    INTO v_uid, v_end, v_moto
    FROM bookings b
   WHERE b.id = p_booking_id
     AND b.booking_source = 'web'
     AND (
       (b.status = 'pending' AND b.payment_status = 'unpaid')
       OR (b.status IN ('reserved','active') AND b.payment_status IN ('paid','partial_refund','refund_pending'))
     );

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  v_full   := public._web_booking_full_access(v_uid);
  -- 2026-10-11: nositel odkazu jen do konce pronájmu (pak přihlášení)
  IF NOT v_full AND NOT public._web_booking_is_live(p_booking_id) THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;
  v_dob_ok := v_full OR public._web_booking_created_account(p_booking_id);

  -- docs_status v izolovaném bloku — případná výjimka NESMÍ shodit celý resume
  -- (jinak by se návrat z platební brány jevil jako „Rezervace nenalezena").
  BEGIN
    v_docs := check_booking_docs_status(v_uid, v_end, v_moto);
  EXCEPTION WHEN OTHERS THEN
    v_docs := NULL;
  END;
  IF NOT v_full THEN   -- 2026-10-11 (jako ai_booking_readiness)
    v_docs := regexp_replace(regexp_replace(v_docs,
                'Zákazníkovi není 18 let', 'Údaje z dokladů nesplňují podmínky pronájmu — kontaktujte nás', 'g'),
                'ŘP propadlý [0-9.]+', 'Platnost ŘP nevyhovuje termínu pronájmu', 'g');
  END IF;

  SELECT jsonb_build_object(
    'booking_id',           b.id,
    'user_id',              b.user_id,
    'moto_id',              b.moto_id,
    'moto_model',           m.model,
    'start_date',           b.start_date,
    'end_date',             b.end_date,
    'total_price',          b.total_price,
    'extras_price',         b.extras_price,
    'discount_amount',      b.discount_amount,
    'discount_code',        b.discount_code,
    'promo_code',           pc.code,
    'voucher_id',           b.voucher_id,
    'voucher_code',         vc.code,
    'voucher_amount',       vc.amount,
    'pickup_time',          b.pickup_time,
    'return_time',          b.return_time,
    'delivery_address',     b.pickup_address,
    'return_address',       b.return_address,
    'notes',                b.notes,
    'helmet_size',          b.helmet_size,
    'jacket_size',          b.jacket_size,
    'pants_size',           b.pants_size,
    'boots_size',           b.boots_size,
    'gloves_size',          b.gloves_size,
    'passenger_helmet_size', b.passenger_helmet_size,
    'passenger_jacket_size', b.passenger_jacket_size,
    'passenger_gloves_size', b.passenger_gloves_size,
    'passenger_boots_size',  b.passenger_boots_size,
    'customer_name',        p.full_name,
    'customer_email',       p.email,
    'customer_phone',       p.phone,
    'customer_street',      p.street,
    'customer_city',        p.city,
    'customer_zip',         p.zip,
    'customer_country',     p.country,
    'license_group',        p.license_group,
    'license_expiry',       p.license_expiry,
    'date_of_birth',        CASE WHEN v_dob_ok THEN p.date_of_birth END,
    'id_number',            CASE WHEN v_full THEN p.id_number
                                 WHEN NULLIF(btrim(p.id_number), '') IS NULL THEN NULL
                                 WHEN length(btrim(p.id_number)) > 5 THEN '••••' || right(btrim(p.id_number), 3)
                                 ELSE '••••' END,
    'license_number',       CASE WHEN v_full THEN p.license_number
                                 WHEN NULLIF(btrim(p.license_number), '') IS NULL THEN NULL
                                 WHEN length(btrim(p.license_number)) > 5 THEN '••••' || right(btrim(p.license_number), 3)
                                 ELSE '••••' END,
    'docs_masked',          NOT v_full,
    'has_id_number',        (p.id_number IS NOT NULL AND p.id_number <> ''),
    'has_license_number',   (p.license_number IS NOT NULL AND p.license_number <> ''),
    'has_password',         (p.password_last4_bcrypt IS NOT NULL),
    'payment_status',       b.payment_status,
    'booking_status',       b.status,
    'pay_channel',          b.pay_channel,
    'docs_status',          v_docs,
    'extras',               COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'name',       be.name,
          'unit_price', be.unit_price,
          'quantity',   be.quantity
        )
        ORDER BY be.id
      )
      FROM booking_extras be
      WHERE be.booking_id = b.id
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM bookings b
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  LEFT JOIN profiles    p ON p.id = b.user_id
  LEFT JOIN promo_codes pc ON pc.id = b.promo_code_id
  LEFT JOIN vouchers    vc ON vc.id = b.voucher_id
  WHERE b.id = p_booking_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;

  RETURN v_result;
END;
$function$;

-- 3) Maska z resume (••••123) se NIKDY nezapíše do profilu — žádnou cestou
--    (RPC ani přímý UPDATE webu po auto-přihlášení). Nezávislé na nasazení webu.
CREATE OR REPLACE FUNCTION public._profiles_ignore_masked_docs()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
BEGIN
  IF NEW.id_number IS DISTINCT FROM OLD.id_number AND NEW.id_number LIKE '%•%' THEN
    NEW.id_number := OLD.id_number;
  END IF;
  IF NEW.license_number IS DISTINCT FROM OLD.license_number AND NEW.license_number LIKE '%•%' THEN
    NEW.license_number := OLD.license_number;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public._profiles_ignore_masked_docs() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_profiles_ignore_masked_docs ON public.profiles;
CREATE TRIGGER trg_profiles_ignore_masked_docs
  BEFORE UPDATE OF id_number, license_number ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._profiles_ignore_masked_docs();

-- 4) set_web_booking_docs: vlastník / admin / service role jako dosud; nositel
--    odkazu (anon i cizí přihlášený) jen u ŽIVÉ rezervace, OCR-ověřené číslo
--    nepřepíše, datum narození jen doplní (mimo čerstvý účet této rezervace);
--    maska = beze změny; čísla jen znaky dokladu (žádné HTML).
CREATE OR REPLACE FUNCTION public.set_web_booking_docs(p_booking_id uuid, p_id_number text DEFAULT NULL::text, p_license_number text DEFAULT NULL::text, p_license_expiry text DEFAULT NULL::text, p_license_group text DEFAULT NULL::text, p_date_of_birth text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid;
  v_source text;
  v_created timestamptz;        -- 2026-10-11
  v_id_ver boolean := false;    -- 2026-10-11
  v_lic_ver boolean := false;   -- 2026-10-11
  v_dob_ok boolean := true;     -- 2026-10-11: smí přepsat datum narození
  v_lic_group license_group[];
  v_lic_expiry date;
  v_dob date;
BEGIN
  IF p_booking_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Booking ID je povinné');
  END IF;

  SELECT user_id, booking_source, created_at INTO v_user_id, v_source, v_created
    FROM bookings WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;
  IF v_source IS DISTINCT FROM 'web' THEN
    RETURN jsonb_build_object('error', 'Pouze pro webové rezervace');
  END IF;

  -- 2026-10-11: nositel odkazu jen u živé rezervace; čísla ověřená PŘED
  -- založením této rezervace nemění (oprava OCR v rámci této rezervace smí)
  IF NOT public._web_booking_full_access(v_user_id) THEN
    IF NOT public._web_booking_is_live(p_booking_id) THEN
      RETURN jsonb_build_object('error', 'login_required',
        'message', 'Doklady změníte po přihlášení (účet na webu nebo aplikace).');
    END IF;
    SELECT COALESCE(GREATEST(id_verified_at, passport_verified_at) < v_created, false),
           COALESCE(license_verified_at < v_created, false)
      INTO v_id_ver, v_lic_ver
      FROM profiles WHERE id = v_user_id;
    IF COALESCE(v_id_ver, false)  THEN p_id_number := NULL; END IF;
    IF COALESCE(v_lic_ver, false) THEN p_license_number := NULL; END IF;
    -- datum narození nositel nevidí (resume) → jen doplní prázdné; přepíše jen
    -- u účtu, který tato rezervace právě založila
    v_dob_ok := public._web_booking_created_account(p_booking_id);
  END IF;

  -- 2026-10-11: maska z get_web_booking_resume = beze změny; jinak jen
  -- písmena (latinka vč. diakritiky, cyrilice), číslice, mezera, . / - (max 30)
  IF p_id_number LIKE '%•%' THEN p_id_number := NULL; END IF;
  IF p_license_number LIKE '%•%' THEN p_license_number := NULL; END IF;
  p_id_number      := NULLIF(left(btrim(regexp_replace(p_id_number, '[^0-9A-Za-zÀ-žА-яЁёЇїІіЄєҐґ /.-]', '', 'g')), 30), '');
  p_license_number := NULLIF(left(btrim(regexp_replace(p_license_number, '[^0-9A-Za-zÀ-žА-яЁёЇїІіЄєҐґ /.-]', '', 'g')), 30), '');

  -- ŘP skupina → enum array. Podporuje VÍCE skupin oddělených čárkou ("A,B").
  -- Neplatné/prázdné tokeny ignorujeme; když nic platného nezbyde → NULL (nepřepíše).
  IF p_license_group IS NOT NULL AND p_license_group <> '' THEN
    BEGIN
      SELECT array_agg(DISTINCT g)
        INTO v_lic_group
        FROM (
          SELECT upper(trim(tok))::license_group AS g
          FROM unnest(string_to_array(p_license_group, ',')) AS tok
          WHERE trim(tok) <> ''
            AND upper(trim(tok)) IN ('AM','A1','A2','A','B','N')
        ) s;
    EXCEPTION WHEN OTHERS THEN
      v_lic_group := NULL;
    END;
  END IF;

  -- platnost ŘP → date (neplatný formát ignorujeme)
  IF p_license_expiry IS NOT NULL AND p_license_expiry <> '' THEN
    BEGIN
      v_lic_expiry := p_license_expiry::date;
    EXCEPTION WHEN OTHERS THEN
      v_lic_expiry := NULL;
    END;
  END IF;

  -- datum narození → date (neplatný formát ignorujeme)
  IF p_date_of_birth IS NOT NULL AND p_date_of_birth <> '' THEN
    BEGIN
      v_dob := p_date_of_birth::date;
    EXCEPTION WHEN OTHERS THEN
      v_dob := NULL;
    END;
  END IF;

  UPDATE profiles SET
    id_number      = COALESCE(NULLIF(p_id_number, ''), id_number),
    license_number = COALESCE(NULLIF(p_license_number, ''), license_number),
    license_group  = COALESCE(v_lic_group, license_group),
    license_expiry = COALESCE(v_lic_expiry::text, license_expiry),
    date_of_birth  = CASE WHEN v_dob_ok OR date_of_birth IS NULL           -- 2026-10-11
                          THEN COALESCE(v_dob, date_of_birth) ELSE date_of_birth END,
    updated_at     = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

NOTIFY pgrst, 'reload schema';
