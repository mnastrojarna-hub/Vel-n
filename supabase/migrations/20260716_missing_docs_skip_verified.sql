-- =============================================================================
-- MIGRACE 2026-07-16: booking_missing_docs — neposílat ověřeným / dokončeným (fix F1)
-- =============================================================================
-- BUG (report + audit): Path C (připomínka „Nahrajte doklady") od migrace 20260712
-- gatovala JEN na `docs_completed_at IS NULL`. Přihlášený zákazník s doklady ověřenými
-- ve Velíně krok dokladů přeskočí → `docs_completed_at` zůstane NULL → 30 min po platbě
-- mu dorazí `booking_missing_docs`, PŘESTOŽE už dostal kompletní `web_booking_reserved`.
-- Totéž postihlo nového zákazníka, který schválně vyplnil jen ČÍSLA (scany jsou nepovinné).
--
-- OPRAVA: připomínku poslat JEN když zákazník krok dokladů NEdokončil
-- (`docs_completed_at IS NULL`) A ZÁROVEŇ doklady reálně chybí
-- (`check_booking_docs_status(...) IS NOT NULL`). Ověřený / numbers-hotový = přeskoč.
-- Path AB (15 min abandoned) beze změny. POUZE WEB. APP se netýká.
-- =============================================================================

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
  v_docs_reason text;
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
  -- nepovinné). NOVĚ (fix F1): navíc přeskoč, když jsou doklady reálně ověřené
  -- (check_booking_docs_status IS NULL) — přihlášený s doklady ve Velíně / numbers-hotový
  -- už dostal reserved a připomínku nesmí dostat.
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

    -- fix F1: reálná kontrola dokladů. NULL = ověřené → žádná připomínka.
    v_docs_reason := NULL;
    BEGIN
      v_docs_reason := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: docs check failed for %: %', v_row.id, SQLERRM;
      CONTINUE;
    END;
    IF v_docs_reason IS NULL THEN CONTINUE; END IF;   -- doklady OK → přeskoč

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

NOTIFY pgrst, 'reload schema';
