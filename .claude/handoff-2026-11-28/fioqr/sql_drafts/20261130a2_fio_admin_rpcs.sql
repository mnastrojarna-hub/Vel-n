-- =============================================================================
-- NÁVRH (DRAFT, není v repu) 2026-11-30a2 (část 2/2): Fio banka — admin RPC pro Velín
-- (Finance → Banka), indexy VS, realtime. Potřebuje část 1/2 (20261130a1: sloupce fio_transactions,
-- fio_sync_state). Zadání a popis viz hlavička části 1/2.
--   4) admin RPC: admin_fio_set_token_expiry, admin_fio_ignore_transaction,
--      admin_fio_reopen_transaction, admin_fio_pair_transaction — vše jen is_admin(), vše s auditem
--   5) indexy VS na bookings, realtime publikace fio_transactions
-- Idempotentní, NEmaže data. STATE soubory: 3 (RPC), 5 (realtime), 6.
-- =============================================================================

-- ── 4) Admin RPC (Velín → Finance → Banka) ──────────────────────────────────
-- Platnost tokenů zadává obsluha (Fio API ji neumí vrátit). Změna data vynuluje odeslané prahy.
CREATE OR REPLACE FUNCTION public.admin_fio_set_token_expiry(p_valid_until date, p_pay_valid_until date DEFAULT NULL,
                                                             p_auto_prolong boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o fio_sync_state%ROWTYPE;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  SELECT * INTO o FROM fio_sync_state WHERE id = 1 FOR UPDATE;
  UPDATE fio_sync_state SET
    token_valid_until = p_valid_until,
    token_warned_threshold = CASE WHEN p_valid_until IS DISTINCT FROM o.token_valid_until THEN NULL ELSE token_warned_threshold END,
    pay_token_valid_until = p_pay_valid_until,
    pay_token_warned_threshold = CASE WHEN p_pay_valid_until IS DISTINCT FROM o.pay_token_valid_until THEN NULL ELSE pay_token_warned_threshold END,
    token_auto_prolong = COALESCE(p_auto_prolong, token_auto_prolong), updated_at = now()
  WHERE id = 1;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, old_data, new_data)
  VALUES (auth.uid(), 'fio_token_expiry_set', 'fio_sync_state',
    jsonb_build_object('token_valid_until', o.token_valid_until, 'pay_token_valid_until', o.pay_token_valid_until, 'auto', o.token_auto_prolong),
    jsonb_build_object('token_valid_until', p_valid_until, 'pay_token_valid_until', p_pay_valid_until, 'auto', COALESCE(p_auto_prolong, o.token_auto_prolong)));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_set_token_expiry(date, date, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_set_token_expiry(date, date, boolean) TO authenticated, service_role;

-- „Ignorovat“ nespárovaný pohyb (úrok, vlastní převod, platba vrácená ručně…) — poznámka povinná.
CREATE OR REPLACE FUNCTION public.admin_fio_ignore_transaction(p_fio_id bigint, p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t fio_transactions%ROWTYPE; v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  IF v_note IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'note_required'); END IF;
  SELECT * INTO t FROM fio_transactions WHERE fio_id = p_fio_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF t.status NOT IN ('no_match', 'amount_mismatch', 'needs_review', 'error') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status', 'status', t.status);
  END IF;
  UPDATE fio_transactions SET status = 'ignored', resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = left(v_note, 500) WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, old_data, new_data)
  VALUES (auth.uid(), 'fio_transaction_ignored', 'fio_transaction',
    jsonb_build_object('fio_id', p_fio_id, 'status', t.status, 'note', t.note),
    jsonb_build_object('fio_id', p_fio_id, 'amount', t.amount, 'vs', t.vs, 'note', left(v_note, 500)));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_ignore_transaction(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_ignore_transaction(bigint, text) TO authenticated, service_role;

-- Vrátit pohyb ke zpracování (znovu spárovat podle VS při dalším běhu; ruší i „ignorováno“).
CREATE OR REPLACE FUNCTION public.admin_fio_reopen_transaction(p_fio_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t fio_transactions%ROWTYPE;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  SELECT * INTO t FROM fio_transactions WHERE fio_id = p_fio_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF t.amount <= 0 OR t.status NOT IN ('no_match', 'amount_mismatch', 'needs_review', 'error', 'ignored') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status', 'status', t.status);
  END IF;
  UPDATE fio_transactions SET status = 'new', processed_at = NULL, manual_target_type = NULL, manual_target_id = NULL,
         manual_accept_amount = false, resolved_by = auth.uid(), resolved_at = now() WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, old_data, new_data)
  VALUES (auth.uid(), 'fio_transaction_reopened', 'fio_transaction',
    jsonb_build_object('fio_id', p_fio_id, 'status', t.status), jsonb_build_object('fio_id', p_fio_id, 'status', 'new'));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_reopen_transaction(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_reopen_transaction(bigint) TO authenticated, service_role;

-- Ruční spárování: zapíše cíl a vrátí pohyb do fronty ('new'). Potvrzení pak provede edge fio-sync
-- STEJNOU rutinou jako automatické párování (Velín ji zavolá hned — {action:'process', fio_id};
-- kdyby volání selhalo, zpracuje pohyb nejbližší běh cronu).
--   p_target_type: booking (celá platba rezervace) | surcharge (doplatek mod_surcharge_due) |
--                  order (objednávka e-shopu / poukaz) | request (bank_payment_requests — doplatek úpravy z webu)
--   p_accept_amount: obsluha výslovně přijímá i NIŽŠÍ částku, než se čekalo
CREATE OR REPLACE FUNCTION public.admin_fio_pair_transaction(p_fio_id bigint, p_target_type text, p_target_id uuid,
                                                             p_accept_amount boolean DEFAULT false, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t fio_transactions%ROWTYPE; v_ok boolean := false;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  IF p_target_id IS NULL OR p_target_type NOT IN ('booking', 'surcharge', 'order', 'request') THEN
    RETURN jsonb_build_object('success', false, 'error', 'bad_target');
  END IF;
  SELECT * INTO t FROM fio_transactions WHERE fio_id = p_fio_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF t.amount <= 0 OR t.status NOT IN ('no_match', 'amount_mismatch', 'needs_review', 'error', 'ignored') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status', 'status', t.status);
  END IF;
  IF p_target_type IN ('booking', 'surcharge') THEN
    v_ok := EXISTS (SELECT 1 FROM bookings WHERE id = p_target_id);
  ELSIF p_target_type = 'order' THEN
    v_ok := EXISTS (SELECT 1 FROM shop_orders WHERE id = p_target_id);
  ELSIF to_regclass('public.bank_payment_requests') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.bank_payment_requests WHERE id = $1)' INTO v_ok USING p_target_id;
  END IF;
  IF NOT v_ok THEN RETURN jsonb_build_object('success', false, 'error', 'target_not_found'); END IF;

  UPDATE fio_transactions SET status = 'new', processed_at = NULL,
         manual_target_type = p_target_type, manual_target_id = p_target_id,
         manual_accept_amount = COALESCE(p_accept_amount, false),
         resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = NULLIF(left(btrim(COALESCE(p_note, '')), 500), '')
   WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, old_data, new_data)
  VALUES (auth.uid(), 'fio_transaction_paired', 'fio_transaction', p_target_id,
    jsonb_build_object('fio_id', p_fio_id, 'status', t.status, 'note', t.note),
    jsonb_build_object('fio_id', p_fio_id, 'amount', t.amount, 'vs', t.vs, 'target_type', p_target_type,
                       'target_id', p_target_id, 'accept_amount', COALESCE(p_accept_amount, false), 'note', p_note));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_pair_transaction(bigint, text, uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_pair_transaction(bigint, text, uuid, boolean, text) TO authenticated, service_role;

-- ── 5) Indexy VS + realtime ──────────────────────────────────────────────────
-- fio-sync hledá rezervaci podle VS při každém pohybu (dosud bez indexu).
CREATE INDEX IF NOT EXISTS idx_bookings_payment_vs ON public.bookings (payment_vs) WHERE payment_vs IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bookings_mod_surcharge_vs ON public.bookings (mod_surcharge_vs) WHERE mod_surcharge_vs IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'fio_transactions') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.fio_transactions;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime ADD fio_transactions selhalo: %', SQLERRM;
END $$;
