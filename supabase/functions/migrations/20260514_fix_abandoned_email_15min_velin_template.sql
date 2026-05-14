-- =============================================================================
-- MIGRACE 2026-05-14: Fix "Nedokončená rezervace" mailu pro web
-- =============================================================================
--
-- BUG: Web rezervace, která naskočila jako pending a zákazník nedokončil platbu,
--      dostávala po 4 hodinách mail "Web: Storno rezervace" (web_booking_cancelled)
--      z auto_cancel_expired_pending() místo "Web: Nedokončená rezervace"
--      (web_booking_abandoned).
--
-- FIX:
--   1) auto_cancel_expired_pending() už NEPOSÍLÁ storno mail pro web rezervace.
--      Webové pending+unpaid se po 4 h tiše stornují — abandoned mail už dorazil
--      přes send_abandoned_booking_emails() po 15 min. App rezervace (10 min)
--      si dál posílají storno mail beze změny.
--
--   2) send_abandoned_booking_emails() zjednodušená: jediná cesta pro
--      pending+unpaid+web — 15 min od created_at — pošle 'booking_abandoned'
--      přes send-booking-email, který si vyzvedne DB šablonu Velína
--      'web_booking_abandoned' (fallback 'booking_abandoned'). Path C (paid +
--      chybí doklady → 'booking_missing_docs') zůstává beze změny logiky.
-- =============================================================================


-- 1) auto_cancel_expired_pending — skip mailu pro web -----------------------
CREATE OR REPLACE FUNCTION auto_cancel_expired_pending() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url text;
  v_key text;
  v_row record;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  FOR v_row IN
    WITH cancelled AS (
      UPDATE bookings SET
        status               = 'cancelled',
        cancellation_reason  = CASE
          WHEN booking_source = 'app'
            THEN 'Automaticky zrušeno — nezaplaceno do 10 minut'
          ELSE  'Automaticky zrušeno — nezaplaceno do 4 hodin'
        END,
        cancelled_at         = now(),
        cancelled_by_source  = 'auto'
      WHERE status = 'pending'
        AND payment_status = 'unpaid'
        AND (
          (booking_source = 'app' AND created_at < now() - interval '10 minutes')
          OR (booking_source = 'web' AND created_at < now() - interval '4 hours')
        )
      RETURNING id, user_id, moto_id, start_date, end_date,
                booking_source, cancellation_reason
    )
    SELECT c.id, c.user_id, c.moto_id, c.start_date, c.end_date,
           c.booking_source, c.cancellation_reason,
           p.email AS customer_email, p.full_name AS customer_name,
           m.model AS motorcycle_model
      FROM cancelled c
      LEFT JOIN profiles p     ON p.id = c.user_id
      LEFT JOIN motorcycles m  ON m.id = c.moto_id
  LOOP
    -- Web rezervace už dostaly "Nedokončená rezervace" mail z
    -- send_abandoned_booking_emails() po 15 min — neposílej druhý "Storno" mail.
    IF v_row.booking_source = 'web' THEN
      CONTINUE;
    END IF;

    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;
    IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
      RAISE WARNING 'auto_cancel_expired_pending: app_settings missing — skipping mail for %', v_row.id;
      CONTINUE;
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-cancellation-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'booking_id',           v_row.id,
          'customer_email',       v_row.customer_email,
          'customer_name',        COALESCE(v_row.customer_name, ''),
          'motorcycle',           COALESCE(v_row.motorcycle_model, ''),
          'start_date',           v_row.start_date,
          'end_date',             v_row.end_date,
          'cancellation_reason',  v_row.cancellation_reason,
          'cancelled_by_source',  'auto',
          'refund_amount',        0,
          'refund_percent',       0,
          'source',               COALESCE(v_row.booking_source, 'app')
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_cancel_expired_pending: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;
END;
$$;


-- 2) send_abandoned_booking_emails — 15 min, jediná cesta AB + Path C -------
CREATE OR REPLACE FUNCTION send_abandoned_booking_emails()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_url        text;
  v_key        text;
  v_row        record;
  v_sent_ab    int := 0;
  v_sent_docs  int := 0;
  v_pay_url    text;
  v_docs_url   text;
  v_site_url   text := 'https://www.motogo24.cz';
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'send_abandoned_booking_emails: app_settings (supabase_url/service_role_key) missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  -- PATH AB: pending + unpaid (web) — 15 min od created_at, jediný mail
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

    v_pay_url := COALESCE(
      NULLIF(v_row.stripe_checkout_url, ''),
      v_site_url || '/rezervace?resume=' || v_row.id::text
    );

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'type',            'booking_abandoned',
          'source',          'web',
          'booking_id',      v_row.id,
          'customer_email',  v_row.customer_email,
          'customer_name',   COALESCE(v_row.customer_name, ''),
          'motorcycle',      COALESCE(v_row.motorcycle_model, ''),
          'start_date',      v_row.start_date,
          'end_date',        v_row.end_date,
          'total_price',     v_row.total_price,
          'pay_url',         v_pay_url,
          'resume_link',     v_pay_url,
          'language',        COALESCE(v_row.customer_language, 'cs')
        )
      );

      UPDATE bookings SET abandoned_email_sent_at = now() WHERE id = v_row.id;
      v_sent_ab := v_sent_ab + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails AB: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- PATH C: paid + reserved/active + chybí doklady (5 min od confirmed_at)
  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.confirmed_at,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.booking_source       = 'web'
       AND b.status                IN ('reserved','active')
       AND b.payment_status        = 'paid'
       AND b.docs_reminder_sent_at IS NULL
       AND b.confirmed_at < now() - interval '5 minutes'
       AND check_booking_docs_status(b.user_id, b.end_date, b.moto_id) IS NOT NULL
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    v_docs_url := v_site_url || '/upravit-rezervaci?id=' || v_row.id::text || '#doklady';

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'type',            'booking_missing_docs',
          'source',          'web',
          'booking_id',      v_row.id,
          'customer_email',  v_row.customer_email,
          'customer_name',   COALESCE(v_row.customer_name, ''),
          'motorcycle',      COALESCE(v_row.motorcycle_model, ''),
          'start_date',      v_row.start_date,
          'end_date',        v_row.end_date,
          'docs_url',        v_docs_url,
          'language',        COALESCE(v_row.customer_language, 'cs')
        )
      );

      UPDATE bookings SET docs_reminder_sent_at = now() WHERE id = v_row.id;
      v_sent_docs := v_sent_docs + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'send_abandoned_booking_emails C: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'sent_abandoned',    v_sent_ab,
    'sent_missing_docs', v_sent_docs
  );
END;
$$;
