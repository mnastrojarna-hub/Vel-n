-- =============================================================================
-- MIGRACE 2026-06-17: Záchranný cron pro nedoručený booking_reserved mail
-- =============================================================================
--
-- BUG (rezervace #E60E74DD, 2026-06-16): zákazník dostal `web_door_codes`, ale
--      NE `web_booking_reserved`. Door codes jdou DB triggerem přes pg_net (bez
--      příloh) → spolehlivé. `booking_reserved` se posílá SYNCHRONNĚ uvnitř
--      Stripe webhooku (confirmBookingPayment), kde send-booking-email musí
--      nejdřív vygenerovat 4 PDF přílohy (ZF, DP, Smlouva, VOP) přes PDFShift.
--      Když se to v časově omezené webhookové cestě „utne", mail tiše zmizí —
--      bez řádku v sent_emails/message_log i bez debug_log (try/catch vše spolkl).
--      Potvrzeno z dat: PI event vyhrál atomic flip (confirm_booking_payment ok,
--      was_already_paid=false), ale žádný web_booking_reserved řádek nevznikl.
--
-- FIX: cron `send_missing_booking_reserved_emails()` (každé 2 min) najde web
--      rezervace reserved/active + paid, kterým v message_log chybí
--      web_booking_reserved/booking_reserved, a mail došle přes send-booking-email.
--      Běží v čistém kontextu (mimo Stripe webhook), takže má plný čas na
--      generování příloh. Dedup:
--        1) NOT EXISTS message_log (realtime mail úspěšný → cron skipne),
--        2) reserved_email_sent_at marker (cron sám sebe nezdvojí během dlouhé
--           generace příloh — jeden pokus na rezervaci).
--      3 min grace od confirmed_at dává realtime cestě přednost.
--
-- POZN.: webhook-receiver/payment-confirmers.ts nově loguje výsledek odeslání
--        booking_reserved do debug_log (booking_reserved_mail_sent / _http_error /
--        _failed / _no_email / _outer_exception) — drop už nikdy nebude neviditelný.
-- =============================================================================

-- 1) Marker proti opakovanému dispatchi z cronu (realtime cesta ho nenastavuje –
--    tam jistí dedup přes message_log).
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reserved_email_sent_at timestamptz;

-- 2) Catch-up funkce
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
    RAISE WARNING 'send_missing_booking_reserved_emails: app_settings (supabase_url/service_role_key) missing — abort';
    RETURN jsonb_build_object('error', 'app_settings_missing');
  END IF;

  FOR v_row IN
    SELECT b.id, b.user_id, b.moto_id, b.start_date, b.end_date, b.total_price,
           b.booking_source,
           p.email AS customer_email, p.full_name AS customer_name,
           p.language AS customer_language,
           m.model AS motorcycle_model, m.manual_url AS manual_url
      FROM bookings b
      LEFT JOIN profiles    p ON p.id = b.user_id
      LEFT JOIN motorcycles m ON m.id = b.moto_id
     WHERE b.status                 IN ('reserved','active')
       AND b.payment_status         = 'paid'
       AND b.confirmed_at IS NOT NULL
       AND b.confirmed_at           < now() - interval '3 minutes'  -- realtime cestě dej přednost
       AND b.reserved_email_sent_at IS NULL                         -- cron už to nezkoušel
       AND NOT EXISTS (                                             -- realtime mail nedorazil
         SELECT 1 FROM message_log ml
          WHERE ml.booking_id    = b.id
            AND ml.channel       = 'email'
            AND ml.template_slug IN ('web_booking_reserved','booking_reserved')
       )
  LOOP
    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'type',           'booking_reserved',
          'source',         COALESCE(v_row.booking_source, 'web'),
          'booking_id',     v_row.id,
          'customer_email', v_row.customer_email,
          'customer_name',  COALESCE(v_row.customer_name, ''),
          'motorcycle',     COALESCE(v_row.motorcycle_model, ''),
          'start_date',     v_row.start_date,
          'end_date',       v_row.end_date,
          'total_price',    v_row.total_price,
          'manual_url',     COALESCE(v_row.manual_url, ''),
          'language',       COALESCE(v_row.customer_language, 'cs')
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

-- 3) pg_cron — každé 2 minuty
SELECT cron.schedule(
  'send-missing-booking-reserved-emails',
  '*/2 * * * *',
  $$ SELECT send_missing_booking_reserved_emails(); $$
);
