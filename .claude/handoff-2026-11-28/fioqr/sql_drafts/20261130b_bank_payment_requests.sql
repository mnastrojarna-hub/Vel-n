-- =============================================================================
-- NÁVRH (DRAFT, není v repu) 2026-11-30b: požadavky na platbu převodem / QR (bank_payment_requests)
--
-- Zadání majitele 2026-11-27: QR platba na webu i pro DOPLATEK úpravy rezervace, nákup DÁRKOVÉHO
-- POUKAZU a (volitelně) objednávku e-shopu. Rezervace motorky a výpůjčka JEN výbavy zůstávají na
-- stávajícím toku (bookings.payment_vs / pay_channel='qr', edge qr-payment) — beze změny.
--
-- Jeden registr = jedna řada VS (sekvence booking_vs_seq, sdílená s bookings.payment_vs
-- a bookings.mod_surcharge_vs → VS se mezi rezervacemi, doplatky a objednávkami nikdy nepotká).
--   kind = 'shop_order'     : objednávka shop_orders (poukaz / zboží) čeká na převod; po připsání
--                             fio-sync potvrdí STEJNOU rutinou jako Stripe webhook (confirmShopPayment)
--   kind = 'booking_change' : zákazník na webu zvolil QR pro doplatek úpravy ZAPLACENÉ rezervace;
--                             změna (chg/srv = totéž, co jde u karty do Stripe metadat) se zapíše
--                             AŽ PO připsání platby (applyPaidExtension — stejně jako po kartě)
-- Zápis výhradně serverem (edge = service_role, SECURITY DEFINER RPC); admin Velínu jen čte.
-- Idempotentní, NEmaže data. STATE soubory: 1, 2, 3, 5 (RLS, realtime), 6.
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

-- Stav požadavku pro web (čekací obrazovka s QR; dotaz každých pár sekund).
--   p_request_id / p_order_id : znalost UUID = oprávnění (jako get_web_shop_order_confirmation) — vrací jen
--                               platební údaje (VS, částka, stav), žádné osobní údaje
--   p_booking_id              : jen vlastník rezervace (přihlášený) nebo admin
CREATE OR REPLACE FUNCTION public.get_bank_payment_request(p_request_id uuid DEFAULT NULL, p_booking_id uuid DEFAULT NULL,
                                                           p_order_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r bank_payment_requests%ROWTYPE; v_owner uuid;
BEGIN
  IF p_request_id IS NOT NULL THEN
    SELECT * INTO r FROM bank_payment_requests WHERE id = p_request_id;
  ELSIF p_order_id IS NOT NULL THEN
    SELECT * INTO r FROM bank_payment_requests WHERE order_id = p_order_id
     ORDER BY (status = 'pending') DESC, created_at DESC LIMIT 1;   -- čekající má přednost
  ELSIF p_booking_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM bookings WHERE id = p_booking_id;
    IF NOT (COALESCE(public.is_admin(), false) OR (auth.uid() IS NOT NULL AND auth.uid() = v_owner)) THEN
      RETURN jsonb_build_object('error', 'login_required');
    END IF;
    SELECT * INTO r FROM bank_payment_requests WHERE booking_id = p_booking_id
     ORDER BY (status = 'pending') DESC, created_at DESC LIMIT 1;
  ELSE
    RETURN jsonb_build_object('error', 'missing_identifier');
  END IF;
  IF r.id IS NULL THEN RETURN jsonb_build_object('status', 'none'); END IF;
  RETURN jsonb_build_object(
    'request_id', r.id, 'kind', r.kind, 'booking_id', r.booking_id, 'order_id', r.order_id,
    'status', CASE WHEN r.status = 'pending' AND r.expires_at <= now() THEN 'expired' ELSE r.status END,
    'vs', r.vs, 'amount', r.amount, 'expires_at', r.expires_at, 'change_kind', r.change_kind,
    'created_at', r.created_at, 'paid_at', r.paid_at,
    -- proč zaplacenou změnu nešlo zapsat (kód pro web: moto_unavailable, stale_booking…) — bez interních detailů
    'reason', CASE WHEN r.status = 'failed' THEN r.result->>'reason' END);
END $$;
REVOKE ALL ON FUNCTION public.get_bank_payment_request(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_bank_payment_request(uuid, uuid, uuid) TO anon, authenticated, service_role;

-- Zrušení čekajícího požadavku: zákazník (vlastník rezervace) nebo admin. Objednávku (poukaz) ruší jen
-- admin / server — host ji prostě nezaplatí a požadavek vyprší.
CREATE OR REPLACE FUNCTION public.cancel_bank_payment_request(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r bank_payment_requests%ROWTYPE; v_owner uuid; v_priv boolean;
BEGIN
  SELECT * INTO r FROM bank_payment_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  v_priv := auth.role() IS NULL OR auth.role() = 'service_role' OR COALESCE(public.is_admin(), false);
  IF NOT v_priv THEN
    IF r.booking_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
    SELECT user_id INTO v_owner FROM bookings WHERE id = r.booking_id;
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM v_owner THEN
      RETURN jsonb_build_object('success', false, 'error', 'forbidden');
    END IF;
  END IF;
  IF r.status <> 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status', 'status', r.status); END IF;
  UPDATE bank_payment_requests SET status = 'cancelled',
         note = COALESCE(note || ' · ', '') || CASE WHEN v_priv THEN 'zrušeno obsluhou' ELSE 'zrušeno zákazníkem' END
   WHERE id = p_request_id;
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.cancel_bank_payment_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_bank_payment_request(uuid) TO authenticated, service_role;

-- Vypršení čekajících požadavků (volá fio_sync_tick každou minutu — čisté SQL, bez edge funkce).
-- Objednávka (poukaz) se NEruší: pozdní platba se u ní potvrdí normálně (nic se nedrží).
CREATE OR REPLACE FUNCTION public.expire_bank_payment_requests()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n integer;
BEGIN
  UPDATE bank_payment_requests SET status = 'expired' WHERE status = 'pending' AND expires_at <= now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.expire_bank_payment_requests() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_bank_payment_requests() TO service_role;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'bank_payment_requests') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bank_payment_requests;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD bank_payment_requests selhalo: %', SQLERRM;
END $$;
