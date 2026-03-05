-- =====================================================
-- Velín — Booking cancellation tracking fields
-- Adds who/where/why for every cancellation
-- =====================================================

DO $$
BEGIN
  -- cancelled_by: kdo zrušil (admin uuid / customer uuid / 'system')
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'cancelled_by'
  ) THEN
    ALTER TABLE bookings ADD COLUMN cancelled_by uuid;
  END IF;

  -- cancelled_by_source: odkud byla zrušena
  -- 'velin' = admin ve velínu, 'web' = zákazník z webu, 'app' = zákazník z appky, 'system' = auto po 4h nezaplacení
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'cancelled_by_source'
  ) THEN
    ALTER TABLE bookings ADD COLUMN cancelled_by_source text;
  END IF;

  -- cancellation_reason: důvod zrušení
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'cancellation_reason'
  ) THEN
    ALTER TABLE bookings ADD COLUMN cancellation_reason text;
  END IF;

  -- cancelled_at: kdy přesně byla zrušena
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'cancelled_at'
  ) THEN
    ALTER TABLE bookings ADD COLUMN cancelled_at timestamptz;
  END IF;

  -- cancellation_notified: zda byl zákazník informován emailem
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'bookings' AND column_name = 'cancellation_notified'
  ) THEN
    ALTER TABLE bookings ADD COLUMN cancellation_notified boolean DEFAULT false;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_bookings_cancelled_at ON bookings(cancelled_at);
