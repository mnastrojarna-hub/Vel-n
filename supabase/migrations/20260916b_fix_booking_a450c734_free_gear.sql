-- Rezervace #A450C734 (Hambálek) — výbava + boty spolujezdce za 980 Kč,
-- na které měl mít dle věrnostního programu (rank 4) nárok zdarma.
-- Ostrý rezervační formulář pravidlo od ranku 3 nečetl — opraveno v 4.0.0.
-- Tady se srovná ten jeden záznam a peníze se vrátí přes Stripe.

-- 1) gear řádky na 0 Kč
UPDATE booking_extras SET unit_price = 0
 WHERE booking_id = (SELECT id FROM bookings WHERE right(id::text, 8) = 'a450c734')
   AND (lower(name) LIKE '%bot%' OR lower(name) LIKE '%spolujez%');

-- 2) o stejnou částku dolů extras_price i total_price (3520 -> 2540)
UPDATE bookings
   SET total_price  = total_price - extras_price,
       extras_price = 0
 WHERE right(id::text, 8) = 'a450c734';

-- 3) Stripe vratka 980 Kč -> dobropis „Úprava výbavy" + mail zákazníkovi.
--    Podmínka payment_status='paid' je ochrana proti DVOJÍ vratce: jakmile
--    process-refund vratku vystaví, přepne rezervaci na 'partial_refund',
--    takže druhé spuštění (nebo ruční puštění v SQL editoru) neposlané nic.
SELECT net.http_post(
  url     := (SELECT value #>> '{}' FROM app_settings WHERE key = 'supabase_url')
             || '/functions/v1/process-refund',
  headers := jsonb_build_object(
               'Content-Type', 'application/json',
               'Authorization', 'Bearer ' ||
                 (SELECT value #>> '{}' FROM app_settings WHERE key = 'service_role_key')),
  body    := jsonb_build_object(
               'booking_id', (SELECT id FROM bookings WHERE right(id::text, 8) = 'a450c734'),
               'amount', 980, 'reason', 'gear_edit', 'source', 'edit')
)
 WHERE EXISTS (SELECT 1 FROM bookings
                WHERE right(id::text, 8) = 'a450c734'
                  AND payment_status = 'paid');
