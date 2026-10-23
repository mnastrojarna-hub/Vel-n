-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — crony: připomínky a přehledy (13/14)
-- send_abandoned_booking_emails (odkazy /pujceni-obleceni?resume=…, cesta C pobočka z rezervace + jen chybí-li
-- doklad), send_missing_booking_reserved_emails (doklady k rezervaci), report_unpicked_bookings (popisky výbavy).
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.send_abandoned_booking_emails()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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

  -- PATH AB: pending + unpaid (web) — 15 min od created_at. Obnovené rezervace
  -- (restored_at) se přeskakují — obnovil je admin, „nedokončená" nejsou.
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.stripe_checkout_url, b.checkout_started_at, b.created_at, b.booking_kind,
           p.email AS customer_email, p.full_name AS customer_name,
           COALESCE(NULLIF(b.language, ''), p.language) AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.booking_source        = 'web'
       AND b.status                = 'pending'
       AND b.payment_status        = 'unpaid'
       AND b.restored_at           IS NULL
       AND b.abandoned_email_sent_at IS NULL
       AND b.created_at < now() - interval '15 minutes'
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_pay_url := COALESCE(NULLIF(v_row.stripe_checkout_url, ''), v_site_url || '/rezervace?resume=' || v_row.id::text);
    -- 2026-10-23: výpůjčka výbavy se dokončuje na své stránce (pending → znovu platba; Stripe odkaz může být prošlý)
    IF v_row.booking_kind = 'gear' THEN
      v_pay_url := v_site_url || '/pujceni-obleceni?resume=' || v_row.id::text;
    END IF;

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
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.confirmed_at, b.booking_kind,
           p.email AS customer_email, p.full_name AS customer_name,
           COALESCE(NULLIF(b.language, ''), p.language) AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p  ON p.id  = b.user_id
      LEFT JOIN motorcycles m  ON m.id  = b.moto_id
      -- 2026-10-23: výpůjčka výbavy = pobočka z rezervace (obslužná Mezná → bez připomínky jako motorka)
      LEFT JOIN branches    br ON br.id = CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END
     WHERE b.booking_source             = 'web'
       AND b.status                     IN ('reserved','active')
       AND b.payment_status             = 'paid'
       AND b.docs_completed_at          IS NULL
       AND b.docs_reminder_sent_at      IS NULL
       AND b.confirmed_at < now() - interval '30 minutes'
       AND COALESCE(br.type, '')         <> 'obslužná'
       AND COALESCE(b.pickup_method, '') <> 'delivery'
       -- výbava: krok dokladů web ukáže jen když opravdu chybí (doklad totožnosti + 18+) → připomínka jen tehdy
       AND (b.booking_kind IS DISTINCT FROM 'gear' OR public.booking_docs_gate(b.id) IS NOT NULL)
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_url := v_site_url || '/rezervace?resume=' || v_row.id::text;
    IF v_row.booking_kind = 'gear' THEN
      v_docs_url := v_site_url || '/pujceni-obleceni?resume=' || v_row.id::text || '&docs=1';
    END IF;

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
$function$
;

CREATE OR REPLACE FUNCTION public.send_missing_booking_reserved_emails()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_url   text;
  v_key   text;
  v_row   record;
  v_docs  text;
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
           b.booking_source, b.docs_completed_at, b.booking_kind,
           p.email AS customer_email, p.full_name AS customer_name,
           COALESCE(NULLIF(b.language, ''), p.language) AS customer_language,
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

    -- WEB: reserved až když dokončený krok dokladů (čísla) NEBO doklady už ověřené.
    IF COALESCE(v_row.booking_source, 'web') = 'web' AND v_row.docs_completed_at IS NULL THEN
      v_docs := NULL;
      BEGIN
        IF v_row.booking_kind = 'gear' THEN
          -- 2026-10-23: výpůjčka výbavy — doklady k TÉTO rezervaci (jen totožnost + 18+, bez ŘP)
          v_docs := public.booking_docs_gate(v_row.id);
        ELSE
          v_docs := check_booking_docs_status(v_row.user_id, v_row.end_date::date, v_row.moto_id);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'send_missing_booking_reserved_emails: docs check failed for %: %', v_row.id, SQLERRM;
        CONTINUE;
      END;
      IF v_docs IS NOT NULL THEN CONTINUE; END IF;  -- ani nedokončené, ani ověřené → ještě ne
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
$function$
;

CREATE OR REPLACE FUNCTION public.report_unpicked_bookings()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows   text := '';
  v_count  int  := 0;
  v_url    text;
  v_key    text;
  v_to     text;
  v_r      record;
  v_gear   boolean := false;   -- 2026-10-23: v přehledu je i výpůjčka výbavy
BEGIN
  FOR v_r IN
    SELECT b.id, b.start_date::date AS sd, b.end_date::date AS ed,
           -- 2026-10-23: výpůjčka výbavy (bez motorky) = popisek + pobočka z rezervace
           CASE WHEN b.booking_kind = 'gear' THEN 'Výpůjčka výbavy (bez motorky)'
                ELSE COALESCE(m.brand || ' ' || m.model, '?') END AS moto,
           COALESCE(br.name, '?') AS branch,
           COALESCE(p.full_name, p.email, '?') AS customer,
           (b.booking_kind = 'gear') AS is_gear
      FROM bookings b
      LEFT JOIN motorcycles m ON m.id = b.moto_id
      LEFT JOIN branches br   ON br.id = CASE WHEN b.booking_kind = 'gear' THEN b.branch_id ELSE m.branch_id END
      LEFT JOIN profiles p    ON p.id = b.user_id
     WHERE b.status = 'reserved'
       AND b.payment_status = 'paid'
       AND b.is_test IS NOT TRUE
       AND b.start_date::date <= CURRENT_DATE
       AND b.end_date::date   >= CURRENT_DATE
     ORDER BY b.start_date
  LOOP
    v_count := v_count + 1;
    v_gear := v_gear OR COALESCE(v_r.is_gear, false);
    v_rows := v_rows || format(
      '<tr><td>#%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s – %s</td></tr>',
      upper(right(v_r.id::text, 8)), v_r.customer, v_r.moto, v_r.branch,
      to_char(v_r.sd, 'DD.MM.YYYY'), to_char(v_r.ed, 'DD.MM.YYYY'));
  END LOOP;

  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', true, 'count', 0);
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  SELECT COALESCE(value ->> 'email', 'info@motogo24.cz') INTO v_to FROM app_settings WHERE key = 'company_info';
  v_to := COALESCE(v_to, 'info@motogo24.cz');

  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-email',
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'Authorization', 'Bearer ' || v_key),
        body    := jsonb_build_object(
          'to', v_to,
          'subject', format('MotoGo24 — %s nevyzvednutých rezervací (termín běží)', v_count),
          'raw_html', format(
            '<h3>Zaplacené rezervace, u kterých systém neví o převzetí motorky</h3>'
            '<p>Rezervace je pořád „Nadcházející“ — na samoobslužné pobočce ji překlopí zadání kódu do boxu, na obslužné předávací protokol. '
            'Pokud zákazník motorku fyzicky má, srovnejte stav ve Velíně (detail rezervace).</p>'
            -- 2026-10-23: výpůjčka výbavy — samoobsluha: podpis protokolu na displeji po zavření šatny
            || CASE WHEN v_gear THEN '<p>Výpůjčku výbavy (bez motorky) překlopí na samoobslužné pobočce podpis předávacího protokolu na displeji po zavření šatny, na obslužné předávací protokol.</p>' ELSE '' END ||
            '<table border="1" cellpadding="6" cellspacing="0">'
            '<tr><th>Rezervace</th><th>Zákazník</th><th>' || CASE WHEN v_gear THEN 'Motorka / výbava' ELSE 'Motorka' END
            || '</th><th>Pobočka</th><th>Termín</th></tr>%s</table>', v_rows)
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'report_unpicked_bookings: mail se nepodařilo odeslat: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$function$
;
