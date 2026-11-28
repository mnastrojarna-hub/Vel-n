-- =============================================================================
-- 2026-11-30b2 (část 2/2): požadavky na platbu — stav pro web, zrušení, vypršení, realtime
--
-- Potřebuje 20261130b1 (bank_payment_requests).
--   get_bank_payment_request     stav požadavku pro čekací obrazovku webu (dotaz každých pár sekund)
--   cancel_bank_payment_request  zrušení čekajícího požadavku (zákazník = vlastník rezervace, admin, server)
--   expire_bank_payment_requests vypršení (volá fio_sync_tick každou minutu — čisté SQL)
-- Idempotentní. STATE soubory: 3, 5 (realtime), 6.
-- =============================================================================

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

-- Zrušení čekajícího požadavku: zákazník (vlastník rezervace), admin nebo server (p_note = důvod; zákazník ho nenastaví).
-- Zrušení čekajícího požadavku: zákazník (vlastník rezervace) nebo admin. Objednávku (poukaz) ruší jen
-- admin / server — host ji prostě nezaplatí a požadavek vyprší.
CREATE OR REPLACE FUNCTION public.cancel_bank_payment_request(p_request_id uuid, p_note text DEFAULT NULL)
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
         note = COALESCE(note || ' · ', '') || CASE WHEN v_priv THEN COALESCE(NULLIF(left(btrim(COALESCE(p_note, '')), 200), ''), 'zrušeno obsluhou') ELSE 'zrušeno zákazníkem' END
   WHERE id = p_request_id;
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.cancel_bank_payment_request(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_bank_payment_request(uuid, text) TO authenticated, service_role;

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
