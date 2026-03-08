-- =============================================================
-- Migration: Booking overlap check + Shop auto-invoice
-- Date: 2026-03-08
-- =============================================================

-- 1) Trigger function: prevent overlapping bookings for the same moto
CREATE OR REPLACE FUNCTION check_booking_overlap()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Booking overlap detected for moto_id %', NEW.moto_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_booking_overlap ON bookings;
CREATE TRIGGER trg_check_booking_overlap
  BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION check_booking_overlap();

-- 2) Index for fast overlap queries
CREATE INDEX IF NOT EXISTS idx_bookings_moto_dates
  ON bookings (moto_id, start_date, end_date);

-- 3) Trigger function: auto-generate invoice when shop order is paid
CREATE OR REPLACE FUNCTION generate_shop_invoice()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.payment_status = 'paid' AND (OLD.payment_status IS NULL OR OLD.payment_status != 'paid') THEN
    INSERT INTO invoices (
      order_id,
      customer_id,
      amount,
      currency,
      status,
      type,
      issued_at
    ) VALUES (
      NEW.id,
      NEW.customer_id,
      NEW.total_amount,
      COALESCE(NEW.currency, 'CZK'),
      'issued',
      'shop',
      NOW()
    )
    ON CONFLICT (order_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_generate_shop_invoice ON shop_orders;
CREATE TRIGGER trg_generate_shop_invoice
  AFTER INSERT OR UPDATE OF payment_status ON shop_orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_shop_invoice();
