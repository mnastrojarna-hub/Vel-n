-- =============================================================================
-- MIGRACE 2026-09-04 (B): Okno na zaplacení APP rezervace 10 min -> 30 min
--
-- Zadání uživatele: „Prodluž čas v app na zaplacení z 10 min na 30 min."
-- Autoritativní okno drží cron fce auto_cancel_expired_pending() (pg_cron):
-- app rezervace pending+unpaid se dosud rušila po 10 minutách od created_at.
-- Nově 30 minut (+ text důvodu storna). Web okno (4 h) i výjimka pro obnovené
-- rezervace (restored_at) beze změny. Tělo fce jinak 1:1 s poslední revizí
-- (20260810_restore_to_pending.sql).
--
-- Klientská zrcadla (oba stromy appky, stejný commit):
--   payment_provider.dart  paymentTimeoutDuration 10 -> 30 min (odpočet platby)
--   pending_booking_fab_provider.dart expiryMs 600000 -> 1800000 (FAB odpočet)
-- Idempotentní (CREATE OR REPLACE).
-- =============================================================================

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
            THEN 'Automaticky zrušeno — nezaplaceno do 30 minut'
          ELSE  'Automaticky zrušeno — nezaplaceno do 4 hodin'
        END,
        cancelled_at         = now(),
        cancelled_by_source  = 'auto'
      WHERE status = 'pending'
        AND payment_status = 'unpaid'
        AND restored_at IS NULL  -- obnovené rezervace neruší cron, řeší je admin
        AND (
          (booking_source = 'app' AND created_at < now() - interval '30 minutes')
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
