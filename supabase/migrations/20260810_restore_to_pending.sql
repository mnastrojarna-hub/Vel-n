-- =============================================================================
-- 20260810_restore_to_pending.sql
-- Obnovení zrušené rezervace ve Velíně (tlačítko „Obnovit") nově vrací rezervaci
-- do stavu 'pending' (Čeká na platbu) místo 'reserved' (Nadcházející).
--
-- Problém: pending+unpaid rezervace ruší cron auto_cancel_expired_pending()
-- (app 10 min / web 4 h) podle created_at — obnovená rezervace je ale typicky
-- hodiny až dny stará, cron by ji do 2 minut zase zrušil. Proto restore dosud
-- cílil na 'reserved' (a admin neměl cestu k potvrzení platby).
--
-- Řešení: marker bookings.restored_at (nastavuje Velín handleRestore):
--   1) auto_cancel_expired_pending() obnovené rezervace PŘESKAKUJE — admin je
--      řeší ručně (potvrdí platbu, nebo rezervaci sám zruší).
--   2) send_abandoned_booking_emails() Path AB je přeskakuje — mail
--      „Nedokončená rezervace" nemá po ručním obnovení adminem smysl
--      (edge case: rezervace zrušená dřív než po 15 min má
--      abandoned_email_sent_at NULL).
-- Obě funkce = CREATE OR REPLACE nad AKTUÁLNÍMI živými verzemi
-- (auto_cancel: 20260514; abandoned: 20260712) + jedna podmínka navíc.
-- Idempotentní.
-- =============================================================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS restored_at timestamptz;

COMMENT ON COLUMN bookings.restored_at IS
  'Okamžik posledního obnovení zrušené rezervace ve Velíně (tlačítko Obnovit → pending/unpaid). Non-NULL = auto_cancel_expired_pending() ani abandoned mail (Path AB) na rezervaci nesahají — řeší ji admin ručně.';

-- ---------------------------------------------------------------------------
-- 1) auto_cancel_expired_pending — beze změny logiky, jen `restored_at IS NULL`
-- ---------------------------------------------------------------------------
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
        AND restored_at IS NULL  -- obnovené rezervace neruší cron, řeší je admin
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

-- ---------------------------------------------------------------------------
-- 2) send_abandoned_booking_emails — beze změny logiky, jen Path AB navíc
--    filtruje `b.restored_at IS NULL`. Path C beze změny.
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

  -- PATH AB: pending + unpaid (web) — 15 min od created_at. Obnovené rezervace
  -- (restored_at) se přeskakují — obnovil je admin, „nedokončená" nejsou.
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
       AND b.restored_at           IS NULL
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
