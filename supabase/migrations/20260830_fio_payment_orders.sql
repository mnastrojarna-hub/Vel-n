-- =============================================================================
-- MIGRACE 2026-08-30: Fio API — automatické VRACENÍ plateb (parita se Stripe)
--
-- Navazuje na 20260829_fio_bank_sync.sql (automatické potvrzování příchozích
-- QR / bankovních plateb). Vratky (plné i částečné) rezervací zaplacených na
-- Fio účet nově odesílá `process-refund` automaticky platebním příkazem přes
-- Fio API (POST /v1/rest/import/, Fio XML DomesticTransaction) na protiúčet,
-- ze kterého platba přišla (z `fio_transactions`) — stejně, jako Stripe vrací
-- na kartu. Ruční fallback (refund_pending + banner „VRÁTIT NA ÚČET" ve
-- Velíně) zůstává pro platby, které na Fio účet nepřišly nebo když banka
-- příkaz nepřijme.
--
-- Tabulka `fio_payment_orders` = idempotence + audit odeslaných příkazů:
-- UNIQUE(credit_note_id) zaručuje, že k jednomu dobropisu vznikne MAXIMÁLNĚ
-- jeden platební příkaz (souběžné dispatche process-refund dostanou konflikt
-- a peníze se nikdy nepošlou dvakrát).
--
-- Token: Supabase Edge secret FIO_PAYMENT_TOKEN (doporučený SAMOSTATNÝ token
-- s právem „Sledování účtu a zadávání platebních příkazů" — vlastní 30s
-- limit, nekoliduje se sync cronem), fallback FIO_API_TOKEN. Nastavuje se
-- v dashboardu, NE v této migraci.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.fio_payment_orders (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  credit_note_id     uuid UNIQUE REFERENCES public.invoices(id) ON DELETE SET NULL,
  booking_id         uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
  amount             numeric(12,2) NOT NULL,
  account_to         text,
  bank_code          text,
  vs                 text,
  message            text,
  status             text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','submitted','failed')),
  fio_instruction_id text,             -- číslo dávky z odpovědi Fio importu
  error              text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  submitted_at       timestamptz
);

CREATE INDEX IF NOT EXISTS idx_fio_payment_orders_booking ON public.fio_payment_orders (booking_id);

ALTER TABLE public.fio_payment_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fio_payment_orders_admin ON public.fio_payment_orders;
CREATE POLICY fio_payment_orders_admin ON public.fio_payment_orders
  FOR ALL USING (is_admin());
-- zápis dělá výhradně edge fn process-refund service klíčem (RLS bypass); Velín jen čte
