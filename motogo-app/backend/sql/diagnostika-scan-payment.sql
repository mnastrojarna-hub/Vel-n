-- =============================================
-- MotoGo24 v4.1.0 – KOMPLETNÍ DIAGNOSTIKA
-- Spusťte v Supabase SQL Editor (Dashboard → SQL Editor)
-- =============================================


-- ============ ČÁST 1: TABULKY ============

-- 1a) Existují potřebné tabulky?
SELECT table_name,
  CASE WHEN table_name IS NOT NULL THEN '✅ existuje' END AS status
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('bookings','profiles','motorcycles','documents',
    'webhook_events','accounting_entries','sos_incidents','admin_messages')
ORDER BY table_name;

-- 1b) Chybějící tabulky? (porovnej s očekávanými)
SELECT unnest(ARRAY[
  'bookings','profiles','motorcycles','documents',
  'webhook_events','accounting_entries'
]) AS expected_table
EXCEPT
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public';


-- ============ ČÁST 2: RLS POLITIKY ============

-- 2a) Které tabulky mají zapnutý RLS?
SELECT tablename, rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('bookings','profiles','motorcycles','documents')
ORDER BY tablename;

-- 2b) Všechny RLS politiky na bookings
SELECT policyname, cmd, permissive, roles::text,
  substr(qual::text, 1, 80) AS using_clause,
  substr(with_check::text, 1, 80) AS check_clause
FROM pg_policies
WHERE tablename = 'bookings'
ORDER BY policyname;

-- 2c) Chybí UPDATE politika pro bookings?
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'bookings' AND cmd = 'UPDATE'
  ) THEN
    RAISE WARNING '❌ CHYBÍ UPDATE politika na bookings – uživatel nemůže zaplatit!';
    RAISE NOTICE 'Spusťte fix-payment-and-rls.sql pro opravu.';
  ELSE
    RAISE NOTICE '✅ UPDATE politika na bookings existuje';
  END IF;
END $$;


-- ============ ČÁST 3: RPC FUNKCE ============

-- 3a) Existuje confirm_payment RPC?
SELECT routine_name, routine_type, security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'confirm_payment';

-- 3b) Pokud neexistuje → varování
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_name = 'confirm_payment'
  ) THEN
    RAISE WARNING '❌ RPC confirm_payment NEEXISTUJE – spusťte fix-payment-and-rls.sql';
  ELSE
    RAISE NOTICE '✅ RPC confirm_payment existuje';
  END IF;
END $$;


-- ============ ČÁST 4: BOOKINGS STAV ============

-- 4a) Posledních 10 bookingů se stavem platby
SELECT id,
  substr(id::text, 1, 8) AS short_id,
  status,
  payment_status,
  payment_method,
  total_price,
  created_at::date AS created
FROM bookings
ORDER BY created_at DESC
LIMIT 10;

-- 4b) Kolik bookingů čeká na platbu?
SELECT
  count(*) FILTER (WHERE payment_status = 'unpaid') AS unpaid,
  count(*) FILTER (WHERE payment_status = 'paid') AS paid,
  count(*) FILTER (WHERE status = 'pending') AS pending,
  count(*) FILTER (WHERE status = 'active') AS active,
  count(*) FILTER (WHERE status = 'cancelled') AS cancelled,
  count(*) AS total
FROM bookings;


-- ============ ČÁST 5: EDGE FUNCTIONS TEST ============

-- 5a) Webhook events tabulka (potřebná pro process-payment)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'webhook_events'
  ) THEN
    RAISE WARNING '❌ Tabulka webhook_events neexistuje – process-payment Edge Function ji potřebuje';
    RAISE NOTICE 'Vytvořte ji:';
    RAISE NOTICE 'CREATE TABLE webhook_events (id uuid DEFAULT gen_random_uuid() PRIMARY KEY, event_id text UNIQUE NOT NULL, source text, payload jsonb, created_at timestamptz DEFAULT now());';
  ELSE
    RAISE NOTICE '✅ webhook_events existuje';
  END IF;
END $$;

-- 5b) Accounting entries tabulka
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'accounting_entries'
  ) THEN
    RAISE WARNING '❌ Tabulka accounting_entries neexistuje – process-payment Edge Function ji potřebuje';
  ELSE
    RAISE NOTICE '✅ accounting_entries existuje';
  END IF;
END $$;


-- ============ ČÁST 6: PROFILES & AUTH ============

-- 6a) Profily s emailem
SELECT id,
  substr(id::text, 1, 8) AS uid_short,
  full_name,
  email,
  created_at::date AS created
FROM profiles
ORDER BY created_at DESC
LIMIT 5;


-- ============ ČÁST 7: RYCHLÝ TEST PLATBY ============
-- Odkomentuj a vyplň booking ID pro ruční test:

-- SELECT confirm_payment(
--   'VLOŽ-BOOKING-UUID-ZDE'::uuid,
--   'card'
-- );
