-- =============================================================================
-- MIGRACE: Fix booking_source + auto_cancel_expired_pending
-- Datum: 2026-04-12
-- Popis: 1) Přidán p_booking_source param do create_web_booking (app/web)
--        2) Vytvořena chybějící auto_cancel_expired_pending() pro pg_cron
-- =============================================================================

-- 1) auto_cancel_expired_pending — chyběla v DB, cron job běžel naprázdno
CREATE OR REPLACE FUNCTION auto_cancel_expired_pending()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- App bookings: cancel after 10 minutes
  UPDATE bookings
  SET status = 'cancelled',
      cancellation_reason = 'Automaticky zrušeno — nezaplaceno do 10 minut',
      cancelled_at = now()
  WHERE status = 'pending'
    AND payment_status = 'unpaid'
    AND booking_source = 'app'
    AND created_at < now() - interval '10 minutes';

  -- Web bookings: cancel after 4 hours
  UPDATE bookings
  SET status = 'cancelled',
      cancellation_reason = 'Automaticky zrušeno — nezaplaceno do 4 hodin',
      cancelled_at = now()
  WHERE status = 'pending'
    AND payment_status = 'unpaid'
    AND booking_source = 'web'
    AND created_at < now() - interval '4 hours';
END;
$$;

-- 2) create_web_booking — přidán p_booking_source (viz SQL spuštěné v DB)
-- Parametr p_booking_source text DEFAULT 'web' přidán do signatury.
-- INSERT řádek: booking_source = COALESCE(p_booking_source, 'web')
