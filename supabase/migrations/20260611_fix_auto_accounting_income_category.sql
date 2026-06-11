-- =============================================================
-- FIX: příjmy se nikdy nezapisovaly do accounting_entries
-- (aplikováno v živé DB 2026-06-11, ověřeno: 11 income řádků, 54 669 Kč)
--
-- Reálný stav DB (liší se od 20260321_accounting_entries.sql):
--   • accounting_entries.type je ENUM entry_type ('income','expense'),
--     NE text s CHECK ('revenue','expense')
--   • category je TEXT NOT NULL
-- Trigger auto_accounting_on_booking_paid (z 20260312d) vkládal bez
-- category → NOT NULL violation → EXCEPTION blok chybu spolkl → žádný
-- příjmový záznam nikdy nevznikl → Dashboard/Finance ukazovaly tržby 0.
-- =============================================================

-- 1) Trigger fix: doplněna category (NOT NULL) + date
CREATE OR REPLACE FUNCTION auto_accounting_on_booking_paid()
RETURNS TRIGGER AS $$
BEGIN
  BEGIN
    IF NEW.payment_status = 'paid' AND (OLD IS NULL OR OLD.payment_status IS DISTINCT FROM 'paid') THEN
      INSERT INTO accounting_entries (booking_id, type, amount, description, category, date, created_at)
      VALUES (NEW.id, 'income', COALESCE(NEW.total_price, 0),
              'Platba za rezervaci #' || substr(NEW.id::text, 1, 8),
              'pronájem', CURRENT_DATE, now());
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'auto_accounting_on_booking_paid: % — accounting skipped', SQLERRM;
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2) Backfill zaplacených rezervací bez příjmového záznamu
INSERT INTO accounting_entries (booking_id, type, amount, description, category, date, created_at)
SELECT b.id, 'income', COALESCE(b.total_price, 0),
       'Platba za rezervaci #' || substr(b.id::text, 1, 8),
       'pronájem', COALESCE(b.confirmed_at, b.created_at)::date, COALESCE(b.confirmed_at, b.created_at)
FROM bookings b
WHERE b.payment_status IN ('paid', 'partial_refund', 'refund_pending')
  AND COALESCE(b.is_test, false) = false
  AND NOT EXISTS (SELECT 1 FROM accounting_entries ae
                  WHERE ae.booking_id = b.id AND ae.amount > 0);
