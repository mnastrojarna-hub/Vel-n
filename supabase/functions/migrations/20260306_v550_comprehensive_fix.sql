-- =====================================================
-- MotoGo24 v5.5.0 — Comprehensive fixes
-- 1. sos_timeline: customer INSERT policy (replacement/tow)
-- 2. booking_cancellations: create table + RLS
-- 3. branches: ensure RLS policies
-- 4. vouchers: ensure RLS policies
-- 5. SOS auto-notification to admin_messages
-- Idempotentní — bezpečné spustit opakovaně
-- =====================================================

-- ═══════════════════════════════════════════════════════
-- 1. SOS_TIMELINE — customer INSERT policy
--    Without this, app inserts (replacement_requested,
--    tow_requested, location_shared) silently fail
-- ═══════════════════════════════════════════════════════

DROP POLICY IF EXISTS sos_timeline_customer_insert ON sos_timeline;
CREATE POLICY sos_timeline_customer_insert ON sos_timeline
  FOR INSERT WITH CHECK (
    incident_id IN (
      SELECT id FROM sos_incidents WHERE user_id = auth.uid()
    )
  );

-- ═══════════════════════════════════════════════════════
-- 2. BOOKING_CANCELLATIONS — create table if not exists
--    cancel_booking_tracked RPC inserts here
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS booking_cancellations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid REFERENCES bookings(id) ON DELETE CASCADE,
  cancelled_by uuid,
  reason text,
  refund_amount numeric(10,2) DEFAULT 0,
  refund_percent integer DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_cancellations_booking
  ON booking_cancellations(booking_id);

ALTER TABLE booking_cancellations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS booking_cancellations_admin ON booking_cancellations;
CREATE POLICY booking_cancellations_admin ON booking_cancellations
  FOR ALL USING (is_admin());

DROP POLICY IF EXISTS booking_cancellations_customer_read ON booking_cancellations;
CREATE POLICY booking_cancellations_customer_read ON booking_cancellations
  FOR SELECT USING (cancelled_by = auth.uid());

-- ═══════════════════════════════════════════════════════
-- 3. BRANCHES — ensure table + RLS policies exist
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  city text,
  address text,
  phone text,
  email text,
  opening_hours text,
  gps_lat numeric(10,7),
  gps_lng numeric(10,7),
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS branches_admin ON branches;
CREATE POLICY branches_admin ON branches
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS branches_public_read ON branches;
CREATE POLICY branches_public_read ON branches
  FOR SELECT USING (true);

-- ═══════════════════════════════════════════════════════
-- 4. VOUCHERS — ensure RLS policies
-- ═══════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'vouchers') THEN
    EXECUTE 'ALTER TABLE vouchers ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS vouchers_admin_all ON vouchers';
    EXECUTE 'CREATE POLICY vouchers_admin_all ON vouchers FOR ALL USING (is_admin()) WITH CHECK (is_admin())';
    EXECUTE 'DROP POLICY IF EXISTS vouchers_user_select ON vouchers';
    EXECUTE 'CREATE POLICY vouchers_user_select ON vouchers FOR SELECT USING (buyer_id = auth.uid() OR redeemed_by = auth.uid())';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════
-- 5. SOS auto-notification: when incident is created,
--    automatically send admin_message to notify user
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION sos_notify_user_on_create()
RETURNS trigger AS $$
DECLARE
  v_type_label text;
BEGIN
  -- Map type to readable label
  CASE NEW.type
    WHEN 'theft' THEN v_type_label := 'Krádež motorky';
    WHEN 'accident_minor' THEN v_type_label := 'Lehká nehoda';
    WHEN 'accident_major' THEN v_type_label := 'Závažná nehoda';
    WHEN 'breakdown_minor' THEN v_type_label := 'Drobná porucha';
    WHEN 'breakdown_major' THEN v_type_label := 'Vážná porucha';
    ELSE v_type_label := 'SOS hlášení';
  END CASE;

  -- Create confirmation message for the user
  INSERT INTO admin_messages (user_id, title, message, type)
  VALUES (
    NEW.user_id,
    'SOS přijato: ' || v_type_label,
    'Vaše hlášení bylo přijato centálou MotoGo24. ' ||
    COALESCE(NEW.description, '') ||
    ' Asistent vás bude kontaktovat.',
    'sos_response'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_sos_notify_user ON sos_incidents;
CREATE TRIGGER trg_sos_notify_user
  AFTER INSERT ON sos_incidents
  FOR EACH ROW EXECUTE FUNCTION sos_notify_user_on_create();

-- ═══════════════════════════════════════════════════════
-- 6. Recreate cancel_booking_tracked as SECURITY DEFINER
--    to ensure booking_cancellations insert works
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION cancel_booking_tracked(
  p_booking_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  v_booking bookings%ROWTYPE;
  v_uid uuid;
  v_hours_until numeric;
  v_refund_pct integer;
  v_refund_amt numeric;
BEGIN
  v_uid := auth.uid();

  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Rezervace nenalezena');
  END IF;

  IF v_booking.user_id != v_uid AND NOT is_admin() THEN
    RETURN jsonb_build_object('error', 'Nemáte oprávnění');
  END IF;

  IF v_booking.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'Rezervace je již stornována');
  END IF;

  v_hours_until := EXTRACT(EPOCH FROM (v_booking.start_date - now())) / 3600;
  IF v_hours_until > 7 * 24 THEN v_refund_pct := 100;
  ELSIF v_hours_until > 48 THEN v_refund_pct := 50;
  ELSE v_refund_pct := 0;
  END IF;
  v_refund_amt := ROUND(COALESCE(v_booking.total_price, 0) * v_refund_pct / 100);

  UPDATE bookings SET status = 'cancelled' WHERE id = p_booking_id;

  INSERT INTO booking_cancellations (booking_id, cancelled_by, reason, refund_amount, refund_percent)
  VALUES (p_booking_id, v_uid, p_reason, v_refund_amt, v_refund_pct);

  RETURN jsonb_build_object(
    'success', true,
    'refund_percent', v_refund_pct,
    'refund_amount', v_refund_amt
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
