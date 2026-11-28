-- =============================================================================
-- 2026-11-30b1 (část 1/2): požadavky na platbu převodem / QR (bank_payment_requests)
--
-- Zadání majitele 2026-11-27: QR platba na webu i pro DOPLATEK úpravy rezervace a nákup DÁRKOVÉHO
-- POUKAZU (QR pro zboží e-shopu = pozdější krok; tabulka je na něj připravená). Rezervace motorky a
-- výpůjčka JEN výbavy zůstávají na stávajícím toku (bookings.payment_vs / pay_channel='qr', edge
-- qr-payment) — beze změny.
--
-- Jeden registr = jedna řada VS (sekvence booking_vs_seq, sdílená s bookings.payment_vs
-- a bookings.mod_surcharge_vs → VS se mezi rezervacemi, doplatky a objednávkami nikdy nepotká).
--   kind = 'shop_order'     : objednávka shop_orders (poukaz) čeká na převod; po připsání ji
--                             fio-sync potvrdí STEJNOU rutinou jako Stripe webhook (confirmShopPayment)
--                             → poukaz vznikne až po zaplacení. Lhůta 7 dní; pozdější platba se uzná.
--   kind = 'booking_change' : zákazník na webu zvolil QR pro doplatek úpravy ZAPLACENÉ rezervace;
--                             změna (chg/srv = totéž, co jde u karty do Stripe metadat) se zapíše
--                             AŽ PO připsání platby (applyPaidExtension — stejně jako po kartě).
--                             Lhůta 60 minut; nový termín se mezitím NEblokuje.
-- Zápis výhradně serverem (edge = service_role, SECURITY DEFINER RPC); admin Velínu jen čte.
-- Potřebuje 20261130a1 (fio_transactions.request_id). Idempotentní, NEmaže data.
-- STATE soubory: 1, 2, 3, 5 (RLS), 6.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.bank_payment_requests (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        text NOT NULL CHECK (kind IN ('shop_order', 'booking_change')),
  vs          text NOT NULL,                              -- číselný VS (booking_vs_seq)
  amount      numeric(12,2) NOT NULL CHECK (amount > 0),  -- Kč, přesně (převod nemá minimum karty 15 Kč)
  booking_id  uuid REFERENCES public.bookings(id) ON DELETE CASCADE,
  order_id    uuid REFERENCES public.shop_orders(id) ON DELETE CASCADE,
  chg         text,                                       -- booking_change: payload změny (JSON text, jako Stripe metadata.chg…chg_8)
  srv         text,                                       -- booking_change: výsledek serverového dry-runu (metadata.srv)
  chg_hash    text,                                       -- md5(chg) — opakované odeslání téže změny vrátí tentýž požadavek
  change_kind text,                                       -- edit | swap | moto | gear (jen pro zobrazení)
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'expired', 'cancelled')),
  expires_at  timestamptz NOT NULL,
  language    text,
  created_by  uuid,                                       -- auth.uid() zákazníka (NULL = host / server)
  created_at  timestamptz NOT NULL DEFAULT now(),
  paid_at     timestamptz,
  fio_id      bigint,                                     -- pohyb, který požadavek uhradil
  result      jsonb,                                      -- výsledek zápisu (state/code z applyPaidExtension apod.)
  note        text,
  CONSTRAINT bank_payment_requests_target CHECK (
    (kind = 'shop_order' AND order_id IS NOT NULL AND booking_id IS NULL)
    OR (kind = 'booking_change' AND booking_id IS NOT NULL AND order_id IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_payment_requests_vs ON public.bank_payment_requests (vs);
-- nejvýš JEDEN čekající požadavek na rezervaci / objednávku
CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_payment_requests_pending_booking
  ON public.bank_payment_requests (booking_id) WHERE status = 'pending' AND booking_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_payment_requests_pending_order
  ON public.bank_payment_requests (order_id) WHERE status = 'pending' AND order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bank_payment_requests_open ON public.bank_payment_requests (expires_at) WHERE status = 'pending';

ALTER TABLE public.bank_payment_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bank_payment_requests_admin_select ON public.bank_payment_requests;
CREATE POLICY bank_payment_requests_admin_select ON public.bank_payment_requests FOR SELECT USING (public.is_admin());
REVOKE ALL ON public.bank_payment_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.bank_payment_requests FROM authenticated;
GRANT SELECT ON public.bank_payment_requests TO authenticated;

-- vazba pohyb → požadavek (sloupec přidala 20261130a1)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fio_transactions_request_id_fkey') THEN
    ALTER TABLE public.fio_transactions ADD CONSTRAINT fio_transactions_request_id_fkey
      FOREIGN KEY (request_id) REFERENCES public.bank_payment_requests(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Další volný VS: sekvence + pojistka proti shodě s VS, který už někde je
-- (rezervace, doplatek, jiný požadavek, VS z čísla dokladu ZF-2026-0204 → 20260204).
CREATE OR REPLACE FUNCTION public._next_bank_vs()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v text;
BEGIN
  LOOP
    v := nextval('booking_vs_seq')::text;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM bookings WHERE payment_vs = v OR mod_surcharge_vs = v)
          AND NOT EXISTS (SELECT 1 FROM bank_payment_requests WHERE vs = v)
          AND NOT EXISTS (SELECT 1 FROM invoices WHERE variable_symbol = v);
  END LOOP;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public._next_bank_vs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._next_bank_vs() TO service_role;

-- Založení požadavku (volá edge process-payment po VŠECH svých kontrolách; jen service_role).
-- Stejná změna / objednávka znovu (obnovení stránky) → vrátí TENTÝŽ čekající požadavek (týž VS, bez
-- nového e-mailu: reused = true). Jiná změna → předchozí čekající požadavek se zruší (superseded).
CREATE OR REPLACE FUNCTION public.create_bank_payment_request(
  p_kind text, p_amount numeric, p_booking_id uuid DEFAULT NULL, p_order_id uuid DEFAULT NULL,
  p_hold_minutes integer DEFAULT 60, p_chg text DEFAULT NULL, p_srv text DEFAULT NULL,
  p_change_kind text DEFAULT NULL, p_language text DEFAULT NULL, p_created_by uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_amount numeric := round(COALESCE(p_amount, 0), 2); v_hash text := CASE WHEN p_chg IS NOT NULL THEN md5(p_chg) END;
  v_min integer := GREATEST(5, LEAST(COALESCE(p_hold_minutes, 60), 43200));   -- 5 min … 30 dní
  r bank_payment_requests%ROWTYPE; v_st text; v_pay text;
BEGIN
  IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF v_amount <= 0 THEN RETURN jsonb_build_object('success', false, 'error', 'invalid_amount'); END IF;

  IF p_kind = 'shop_order' AND p_order_id IS NOT NULL AND p_booking_id IS NULL THEN
    SELECT status, payment_status INTO v_st, v_pay FROM shop_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
    IF v_pay = 'paid' THEN RETURN jsonb_build_object('success', false, 'error', 'already_paid'); END IF;
    IF v_st IN ('cancelled', 'refunded', 'returned') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
    SELECT * INTO r FROM bank_payment_requests WHERE order_id = p_order_id AND status = 'pending' FOR UPDATE;
  ELSIF p_kind = 'booking_change' AND p_booking_id IS NOT NULL AND p_order_id IS NULL THEN
    IF COALESCE(p_chg, '') = '' THEN RETURN jsonb_build_object('success', false, 'error', 'missing_change'); END IF;
    SELECT status::text INTO v_st FROM bookings WHERE id = p_booking_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
    IF v_st NOT IN ('reserved', 'active') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
    SELECT * INTO r FROM bank_payment_requests WHERE booking_id = p_booking_id AND status = 'pending' FOR UPDATE;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'bad_target');
  END IF;

  IF r.id IS NOT NULL THEN
    IF r.expires_at > now() AND r.amount = v_amount AND r.chg_hash IS NOT DISTINCT FROM v_hash THEN
      RETURN jsonb_build_object('success', true, 'reused', true, 'request_id', r.id, 'vs', r.vs,
                                'amount', r.amount, 'expires_at', r.expires_at);
    END IF;
    UPDATE bank_payment_requests
       SET status = CASE WHEN expires_at <= now() THEN 'expired' ELSE 'cancelled' END,
           note = COALESCE(note || ' · ', '') || 'nahrazeno novým požadavkem'
     WHERE id = r.id;
  END IF;

  INSERT INTO bank_payment_requests (kind, vs, amount, booking_id, order_id, chg, srv, chg_hash, change_kind,
                                     expires_at, language, created_by)
  VALUES (p_kind, public._next_bank_vs(), v_amount, p_booking_id, p_order_id, p_chg, p_srv, v_hash,
          NULLIF(left(COALESCE(p_change_kind, ''), 20), ''), now() + make_interval(mins => v_min),
          NULLIF(left(COALESCE(p_language, ''), 5), ''), p_created_by)
  RETURNING * INTO r;
  RETURN jsonb_build_object('success', true, 'reused', false, 'request_id', r.id, 'vs', r.vs,
                            'amount', r.amount, 'expires_at', r.expires_at);
END $$;
REVOKE ALL ON FUNCTION public.create_bank_payment_request(text, numeric, uuid, uuid, integer, text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_bank_payment_request(text, numeric, uuid, uuid, integer, text, text, text, text, uuid) TO service_role;
