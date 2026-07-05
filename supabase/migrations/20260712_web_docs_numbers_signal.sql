-- =============================================================================
-- MIGRACE 2026-07-12: Web flow — čísla dokladů POVINNÁ (smlouva), scany NEPOVINNÉ
-- =============================================================================
-- Upřesnění zadání: v kroku dokladů (po platbě) jsou ČÍSLA dokladu/ŘP POVINNÁ
-- (jdou do smlouvy), ale SCANY (fotky) NEPOVINNÉ. Proto se `web_booking_reserved`
-- (Smlouva+VOP+kódy) posílá, jakmile zákazník DOKONČÍ krok dokladů (= vyplní čísla),
-- signalizováno `bookings.docs_completed_at` — NE až po ověřené fotce.
-- Přístupové kódy (door codes) se dál uvolní jen po ověřeném scanu (existující trigger);
-- reserved mail vykreslí kódy pokud jsou uvolněné, jinak výzvu „nahraj pro kódy / ověří pobočka".
-- POUZE WEB. APP beze změny.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Signál „zákazník dokončil krok dokladů" (vyplnil čísla). Plní web _rezFinishDocs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_web_booking_docs_completed(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE bookings
     SET docs_completed_at = COALESCE(docs_completed_at, now()),
         docs_fill_seconds = COALESCE(
           docs_fill_seconds,
           GREATEST(0, LEAST(604800, EXTRACT(EPOCH FROM (now() - COALESCE(confirmed_at, created_at)))::int))
         )
   WHERE id = p_booking_id
     AND booking_source = 'web';
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('error', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_web_booking_docs_completed(uuid) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) reserved cron: web reserved AŽ po DOKONČENÍ kroku dokladů (docs_completed_at),
--    ne po ověřené fotce. APP beze změny.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_missing_booking_reserved_emails()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url   text;
  v_key   text;
  v_row   record;
  v_sent  int := 0;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_missing_booking_reserved_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.booking_source, b.docs_completed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model, m.manual_url AS manual_url
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.status                 IN ('reserved','active')
       AND b.payment_status         = 'paid'
       AND b.confirmed_at IS NOT NULL
       AND b.confirmed_at           < now() - interval '3 minutes'
       AND b.reserved_email_sent_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM message_log ml
          WHERE ml.booking_id    = b.id
            AND ml.channel       = 'email'
            AND ml.template_slug IN ('web_booking_reserved','booking_reserved')
       )
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    -- NOVÝ FLOW: WEB reserved (Smlouva+VOP+kódy) AŽ po dokončení kroku dokladů
    -- (vyplněná čísla = docs_completed_at). Kódy se v mailu vykreslí jen pokud jsou
    -- uvolněné (ověřený scan); jinak výzva k nahrání / ověření na pobočce.
    -- APP beze změny (reserved = vše najednou hned po platbě).
    IF COALESCE(v_row.booking_source, 'web') = 'web' AND v_row.docs_completed_at IS NULL THEN
      CONTINUE;
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_reserved','source',COALESCE(v_row.booking_source,'web'),
          'booking_id',v_row.id,'customer_email',v_row.customer_email,
          'customer_name',COALESCE(v_row.customer_name,''),'motorcycle',COALESCE(v_row.motorcycle_model,''),
          'start_date',v_row.start_date,'end_date',v_row.end_date,'total_price',v_row.total_price,
          'manual_url',COALESCE(v_row.manual_url,''),'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET reserved_email_sent_at = now() WHERE id = v_row.id;
      v_sent := v_sent + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_missing_booking_reserved_emails: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_reserved', v_sent);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) abandoned cron Path C (booking_missing_docs): připomínka když zákazník
--    NEDOKONČIL krok dokladů (docs_completed_at IS NULL) — ne dle ověřené fotky.
--    30 min, jen samoobslužné vyzvednutí (obslužná/delivery skip — tam nepovinné).
--    Path AB (15 min) beze změny.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_abandoned_booking_emails()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url         text;
  v_key         text;
  v_row         record;
  v_sent_ab     int := 0;
  v_sent_docs   int := 0;
  v_pay_url     text;
  v_docs_url    text;
  v_site_url    text := 'https://www.motogo24.cz';
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_abandoned_booking_emails: app_settings missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  -- PATH AB: pending + unpaid (web) — 15 min od created_at (BEZE ZMĚNY)
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.stripe_checkout_url, b.checkout_started_at, b.created_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.booking_source        = 'web'
       AND b.status                = 'pending'
       AND b.payment_status        = 'unpaid'
       AND b.abandoned_email_sent_at IS NULL
       AND b.created_at < now() - interval '15 minutes'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_pay_url := COALESCE(NULLIF(v_row.stripe_checkout_url, ''), v_site_url || '/rezervace?resume=' || v_row.id::text);

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_abandoned','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'total_price',v_row.total_price,
          'pay_url',v_pay_url,'resume_link',v_pay_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET abandoned_email_sent_at = now() WHERE id = v_row.id;
      v_sent_ab := v_sent_ab + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails AB: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- PATH C: paid + reserved/active + NEDOKONČIL krok dokladů (docs_completed_at IS NULL),
  -- 30 min od confirmed_at. Jen samoobslužné vyzvednutí (obslužná/delivery = doklady
  -- nepovinné, ověří obsluha → žádná připomínka). Dětská motorka: docs_completed_at
  -- se stejně nastaví při „Hotovo", takže nezacyklí.
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.confirmed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p  ON p.id  = b.user_id
      LEFT JOIN motorcycles m  ON m.id  = b.moto_id
      LEFT JOIN branches    br ON br.id = m.branch_id
     WHERE b.booking_source             = 'web'
       AND b.status                     IN ('reserved','active')
       AND b.payment_status             = 'paid'
       AND b.docs_completed_at          IS NULL
       AND b.docs_reminder_sent_at      IS NULL
       AND b.confirmed_at < now() - interval '30 minutes'
       AND COALESCE(br.type, '')         <> 'obslužná'
       AND COALESCE(b.pickup_method, '') <> 'delivery'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_url := v_site_url || '/rezervace?resume=' || v_row.id::text;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body    := jsonb_build_object(
          'type','booking_missing_docs','source','web','booking_id',v_row.id,
          'customer_email',v_row.customer_email,'customer_name',COALESCE(v_row.customer_name,''),
          'motorcycle',COALESCE(v_row.motorcycle_model,''),'start_date',v_row.start_date,
          'end_date',v_row.end_date,'docs_url',v_docs_url,'language',COALESCE(v_row.customer_language,'cs')
        )
      );
      UPDATE bookings SET docs_reminder_sent_at = now() WHERE id = v_row.id;
      v_sent_docs := v_sent_docs + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('sent_abandoned', v_sent_ab, 'sent_missing_docs', v_sent_docs);
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) get_web_booking_resume: přidat `docs_optional` (obslužná/delivery/dětská =
--    scany i čísla nepovinné, „rychlejší odbavení") + `pickup_method`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_web_booking_resume(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'booking_id', b.id, 'user_id', b.user_id, 'moto_id', b.moto_id, 'moto_model', m.model,
    'start_date', b.start_date, 'end_date', b.end_date, 'total_price', b.total_price,
    'extras_price', b.extras_price, 'discount_amount', b.discount_amount, 'discount_code', b.discount_code,
    'promo_code', pc.code, 'voucher_id', b.voucher_id, 'voucher_code', vc.code, 'voucher_amount', vc.amount,
    'pickup_time', b.pickup_time, 'return_time', b.return_time,
    'delivery_address', b.pickup_address, 'return_address', b.return_address, 'notes', b.notes,
    'helmet_size', b.helmet_size, 'jacket_size', b.jacket_size, 'pants_size', b.pants_size,
    'boots_size', b.boots_size, 'gloves_size', b.gloves_size,
    'passenger_helmet_size', b.passenger_helmet_size, 'passenger_jacket_size', b.passenger_jacket_size,
    'passenger_gloves_size', b.passenger_gloves_size, 'passenger_boots_size', b.passenger_boots_size,
    'customer_name', p.full_name, 'customer_email', p.email, 'customer_phone', p.phone,
    'customer_street', p.street, 'customer_city', p.city, 'customer_zip', p.zip, 'customer_country', p.country,
    'license_group', p.license_group, 'license_expiry', p.license_expiry, 'date_of_birth', p.date_of_birth,
    'id_number', p.id_number, 'license_number', p.license_number,
    'has_id_number', (p.id_number IS NOT NULL AND p.id_number <> ''),
    'has_license_number', (p.license_number IS NOT NULL AND p.license_number <> ''),
    'has_password', (p.password_last4_bcrypt IS NOT NULL),
    'payment_status', b.payment_status, 'booking_status', b.status, 'pay_channel', b.pay_channel,
    'pickup_method', b.pickup_method,
    'docs_status', check_booking_docs_status(b.user_id, b.end_date::date, b.moto_id),
    'docs_completed_at', b.docs_completed_at,
    -- doklady nepovinné (jen „rychlejší odbavení"): dětská motorka / delivery / obslužná pobočka
    'docs_optional', (
      COALESCE(m.license_required::text, '') = 'N'
      OR COALESCE(b.pickup_method, '') = 'delivery'
      OR COALESCE(br.type, '') = 'obslužná'
    ),
    'extras', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', be.name, 'unit_price', be.unit_price, 'quantity', be.quantity) ORDER BY be.id)
      FROM booking_extras be WHERE be.booking_id = b.id
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM bookings b
  LEFT JOIN motorcycles m ON m.id = b.moto_id
  LEFT JOIN branches    br ON br.id = m.branch_id
  LEFT JOIN profiles    p ON p.id = b.user_id
  LEFT JOIN promo_codes pc ON pc.id = b.promo_code_id
  LEFT JOIN vouchers    vc ON vc.id = b.voucher_id
  WHERE b.id = p_booking_id
    AND b.booking_source = 'web'
    AND (
      (b.status = 'pending' AND b.payment_status = 'unpaid')
      OR (b.status IN ('reserved','active') AND b.payment_status IN ('paid','partial_refund','refund_pending'))
    );

  IF v_result IS NULL THEN
    RETURN jsonb_build_object('error', 'Rezervace nebyla nalezena.');
  END IF;
  RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_web_booking_resume(uuid) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) get_web_booking_confirmation: vrátit i `docs_completed_at` — děkovací stránka
--    přesměruje na krok dokladů JEN když doklady chybí A krok NEBYL dokončen
--    (chrání přihlášeného s ověřenými doklady + numbers-only, kde scan je nepovinný).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_web_booking_confirmation(
  p_session_id text DEFAULT NULL,
  p_booking_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
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
    b.total_price, b.payment_status, b.status, b.booking_source, b.docs_completed_at,
    p.full_name AS customer_name, p.email AS customer_email,
    m.license_required
  INTO v_booking
  FROM bookings b
  LEFT JOIN profiles p     ON p.id = b.user_id
  LEFT JOIN motorcycles m  ON m.id = b.moto_id
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

  IF v_booking.license_required = 'N' THEN
    v_docs_status := NULL;
  ELSE
    BEGIN
      v_docs_status := public.check_booking_docs_status(v_booking.user_id, v_booking.end_date::date);
    EXCEPTION WHEN OTHERS THEN
      v_docs_status := NULL;
    END;
  END IF;

  RETURN jsonb_build_object(
    'id',                v_booking.id,
    'moto_id',           v_booking.moto_id,
    'start_date',        v_booking.start_date,
    'end_date',          v_booking.end_date,
    'total_price',       v_booking.total_price,
    'payment_status',    v_booking.payment_status,
    'status',            v_booking.status,
    'customer_name',     v_booking.customer_name,
    'customer_email',    v_booking.customer_email,
    'docs_status',       v_docs_status,
    'docs_completed_at', v_booking.docs_completed_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_web_booking_confirmation(text, uuid) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
