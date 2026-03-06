-- =============================================
-- MotoGo24 v4.1.0 – Diagnostika Edge Functions a Secrets
-- Spusťte v Supabase SQL Editor
-- =============================================

-- 1) Zkontroluj jestli existují potřebné secrets (env vars)
-- POZOR: nemůžeš číst hodnoty, jen ověřit že existují
-- Toto musíš zkontrolovat v Dashboard → Edge Functions → Secrets
-- Potřebné secrets:
--   STRIPE_SECRET_KEY    (sk_test_... pro testovací režim)
--   MINDEE_API_KEY       (z mindee.com dashboard)
--   STRIPE_WEBHOOK_SECRET (whsec_...)
--   EMAIL_API_KEY        (Resend API key)
--   EMAIL_FROM           (noreply@motogo24.cz)

-- 2) Otestuj RPC funkci confirm_payment
-- (toto funguje i bez Edge Functions)
-- SELECT confirm_payment('váš-booking-uuid'::uuid, 'cash');

-- 3) Zkontroluj bookings tabulku
SELECT id, user_id, status, payment_status, payment_method, total_price
  FROM bookings
  ORDER BY created_at DESC
  LIMIT 5;

-- 4) Zkontroluj jestli existují webhook_events a accounting_entries tabulky
-- (potřebné pro Edge Function process-payment)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'webhook_events') THEN
    RAISE NOTICE 'Tabulka webhook_events existuje ✓';
  ELSE
    RAISE NOTICE 'Tabulka webhook_events NEEXISTUJE – vytvořte ji:';
    RAISE NOTICE 'CREATE TABLE webhook_events (id uuid DEFAULT gen_random_uuid() PRIMARY KEY, event_id text UNIQUE NOT NULL, source text, payload jsonb, created_at timestamptz DEFAULT now());';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'accounting_entries') THEN
    RAISE NOTICE 'Tabulka accounting_entries existuje ✓';
  ELSE
    RAISE NOTICE 'Tabulka accounting_entries NEEXISTUJE – Edge Function process-payment ji potřebuje';
  END IF;
END $$;
