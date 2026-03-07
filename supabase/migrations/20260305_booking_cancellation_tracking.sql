-- =====================================================
-- Velin — Booking cancellation tracking fields
-- =====================================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_by uuid;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_by_source text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_reason text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_notified boolean DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_bookings_cancelled_at ON bookings(cancelled_at);
