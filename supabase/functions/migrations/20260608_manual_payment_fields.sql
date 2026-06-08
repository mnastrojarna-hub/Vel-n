-- 2026-06-08: Ruční potvrzení platby ve Velínu (QR / převod / hotově / krypto).
-- Stejné flow jako Stripe (confirm_payment + booking_reserved mail), jen platební
-- údaje se doplní ručně a zapíšou do rezervace i do DP / faktur.
--
-- POZN.: VS u ruční platby jde do existujícího invoices.variable_symbol,
--        datum úhrady do existujícího invoices.paid_date.

-- Reference / číslo transakce u ruční platby (payment_method na bookings už existuje).
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS payment_reference text;

-- Způsob platby + číslo transakce přímo na dokladu (DP / faktuře).
ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS transaction_ref text;
