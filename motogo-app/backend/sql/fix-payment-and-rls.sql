-- =============================================
-- MotoGo24 v4.1.0 – SQL opravy pro platby a RLS
-- Spusťte v Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================

-- 1) RPC funkce confirm_payment (SECURITY DEFINER = obchází RLS)
-- Frontend ji volá jako fallback když Edge Function není dostupná
CREATE OR REPLACE FUNCTION confirm_payment(
  p_booking_id UUID,
  p_method TEXT DEFAULT 'card'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_user_id UUID;
  v_txn_id TEXT;
BEGIN
  -- Ověř že volající je vlastníkem bookingu
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Nepřihlášen');
  END IF;

  SELECT id, user_id, payment_status, total_price
    INTO v_booking
    FROM bookings
    WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Rezervace nenalezena');
  END IF;

  IF v_booking.user_id != v_user_id THEN
    RETURN json_build_object('success', false, 'error', 'Neautorizováno');
  END IF;

  IF v_booking.payment_status = 'paid' THEN
    RETURN json_build_object('success', true, 'error', 'Již zaplaceno');
  END IF;

  -- Aktualizuj booking
  v_txn_id := 'TXN-' || extract(epoch from now())::bigint || '-' ||
    upper(substr(gen_random_uuid()::text, 1, 6));

  UPDATE bookings
    SET payment_status = 'paid',
        payment_method = p_method,
        status = 'active'
    WHERE id = p_booking_id;

  RETURN json_build_object(
    'success', true,
    'transaction_id', v_txn_id,
    'method', p_method
  );
END;
$$;

-- Udělej funkci callable pro přihlášené uživatele
GRANT EXECUTE ON FUNCTION confirm_payment(UUID, TEXT) TO authenticated;


-- 2) RLS politika pro bookings – povolí uživateli UPDATE vlastních bookingů
-- (jako záloha pokud ani RPC nefunguje)
DO $$
BEGIN
  -- Zkontroluj jestli politika existuje
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'bookings'
    AND policyname = 'users_update_own_bookings'
  ) THEN
    CREATE POLICY users_update_own_bookings ON bookings
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
    RAISE NOTICE 'Created RLS policy: users_update_own_bookings';
  ELSE
    RAISE NOTICE 'RLS policy users_update_own_bookings already exists';
  END IF;
END $$;


-- 3) Ověř že RLS je zapnutý na bookings (informativní)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_tables
    WHERE tablename = 'bookings' AND rowsecurity = true
  ) THEN
    RAISE NOTICE 'RLS je zapnutý na tabulce bookings ✓';
  ELSE
    RAISE NOTICE 'RLS je VYPNUTÝ na tabulce bookings – zvažte ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;';
  END IF;
END $$;


-- 4) Diagnostika: zobraz existující RLS politiky pro bookings
SELECT policyname, cmd, permissive, roles, qual, with_check
  FROM pg_policies
  WHERE tablename = 'bookings'
  ORDER BY policyname;
