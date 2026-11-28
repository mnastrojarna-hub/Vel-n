-- =============================================================================
-- 2026-11-30a3 (část 3/3): Fio banka — admin RPC pro Velín (Finance → Banka), indexy VS, realtime
--
-- Potřebuje 20261130a1 (sloupce fio_transactions, fio_sync_state).
--   admin_fio_pair_transaction    ruční spárování pohybu s rezervací / doplatkem / objednávkou / požadavkem
--   admin_fio_ignore_transaction  „ignorovat“ s povinnou poznámkou (úrok, vlastní převod, vráceno ručně…)
--   admin_fio_reopen_transaction  vrátit ke zpracování (znovu spárovat podle VS)
--   admin_fio_ack_followup        odškrtnout úkol u potvrzeného pohybu (přeplatek vrácen)
--   admin_fio_set_token_expiry    platnost API tokenů (Fio API ji neumí vrátit — zadává obsluha)
--   admin_fio_overview            stav synchronizace + počty pro stavový pruh a odznak v menu
-- Vše jen is_admin(), vše se zápisem do admin_audit_log. Samotné POTVRZENÍ platby dělá edge funkce
-- fio-sync stejnou rutinou jako automatické párování (Velín ji zavolá hned; kdyby volání selhalo,
-- zpracuje pohyb nejbližší běh cronu). Automatické vratky z Velína se nezavádějí (rozhodnutí majitele).
-- Idempotentní, NEmaže data. STATE soubory: 3 (RPC), 5 (realtime), 6.
-- =============================================================================

-- Změna data vynuluje odeslané prahy upozornění.
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
         resolution_note = left(v_note, 500), claimed_until = NULL WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, old_data, new_data)
  VALUES (auth.uid(), 'fio_transaction_ignored', 'fio_transaction',
    jsonb_build_object('fio_id', p_fio_id, 'status', t.status, 'reason_code', t.reason_code, 'note', t.note),
    jsonb_build_object('fio_id', p_fio_id, 'amount', t.amount, 'vs', t.vs, 'note', left(v_note, 500)));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_ignore_transaction(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_ignore_transaction(bigint, text) TO authenticated, service_role;

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
         manual_accept_amount = false, attempts = 0, first_error_at = NULL, claimed_until = NULL, reason_code = NULL,
         resolved_by = auth.uid(), resolved_at = now() WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, old_data, new_data)
  VALUES (auth.uid(), 'fio_transaction_reopened', 'fio_transaction',
    jsonb_build_object('fio_id', p_fio_id, 'status', t.status, 'reason_code', t.reason_code),
    jsonb_build_object('fio_id', p_fio_id, 'status', 'new'));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_reopen_transaction(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_reopen_transaction(bigint) TO authenticated, service_role;

--   p_target_type: booking (celá platba rezervace) | surcharge (doplatek mod_surcharge_due) |
--                  order (objednávka e-shopu / poukaz) | request (bank_payment_requests — doplatek úpravy z webu)
--   p_accept_amount: obsluha výslovně přijímá i NIŽŠÍ částku, než se čekalo
-- Zapíše cíl a vrátí pohyb do fronty ('new'); potvrzení pak provede edge fio-sync.
CREATE OR REPLACE FUNCTION public.admin_fio_pair_transaction(p_fio_id bigint, p_target_type text, p_target_id uuid,
                                                             p_accept_amount boolean DEFAULT false, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t fio_transactions%ROWTYPE; v_ok boolean := false;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  IF p_target_id IS NULL OR p_target_type IS NULL OR p_target_type NOT IN ('booking', 'surcharge', 'order', 'request') THEN
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
         attempts = 0, first_error_at = NULL, claimed_until = NULL,
         resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = NULLIF(left(btrim(COALESCE(p_note, '')), 500), '')
   WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, old_data, new_data)
  VALUES (auth.uid(), 'fio_transaction_paired', 'fio_transaction', p_target_id,
    jsonb_build_object('fio_id', p_fio_id, 'status', t.status, 'reason_code', t.reason_code, 'note', t.note),
    jsonb_build_object('fio_id', p_fio_id, 'amount', t.amount, 'vs', t.vs, 'target_type', p_target_type,
                       'target_id', p_target_id, 'accept_amount', COALESCE(p_accept_amount, false), 'note', p_note));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_pair_transaction(bigint, text, uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_pair_transaction(bigint, text, uuid, boolean, text) TO authenticated, service_role;

-- Úkol u potvrzeného pohybu je vyřízen (přeplatek vrácen zákazníkovi).
CREATE OR REPLACE FUNCTION public.admin_fio_ack_followup(p_fio_id bigint, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t fio_transactions%ROWTYPE;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  SELECT * INTO t FROM fio_transactions WHERE fio_id = p_fio_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF t.followup IS NULL OR t.followup_done_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'nothing_to_ack');
  END IF;
  UPDATE fio_transactions SET followup_done_at = now(), resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = COALESCE(NULLIF(left(btrim(COALESCE(p_note, '')), 500), ''), resolution_note)
   WHERE fio_id = p_fio_id;
  INSERT INTO admin_audit_log (admin_id, action, entity_type, old_data, new_data)
  VALUES (auth.uid(), 'fio_followup_done', 'fio_transaction',
    jsonb_build_object('fio_id', p_fio_id, 'followup', t.followup),
    jsonb_build_object('fio_id', p_fio_id, 'amount', t.amount, 'expected_amount', t.expected_amount, 'note', p_note));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_ack_followup(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_ack_followup(bigint, text) TO authenticated, service_role;

-- Stav pro stavový pruh záložky „Banka“ a odznak v menu (jedno volání).
CREATE OR REPLACE FUNCTION public.admin_fio_overview()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE s fio_sync_state%ROWTYPE; v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_todo integer; v_wait integer := 0; v_cfg text;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN RETURN jsonb_build_object('success', false, 'error', 'forbidden'); END IF;
  SELECT * INTO s FROM fio_sync_state WHERE id = 1;
  SELECT count(*) INTO v_todo FROM fio_transactions
   WHERE status IN ('no_match', 'amount_mismatch', 'needs_review', 'error') OR (followup IS NOT NULL AND followup_done_at IS NULL);
  IF to_regclass('public.bank_payment_requests') IS NOT NULL THEN
    EXECUTE 'SELECT count(*) FROM public.bank_payment_requests WHERE status = ''pending'' AND expires_at > now()' INTO v_wait;
  END IF;
  SELECT NULLIF(upper(regexp_replace(COALESCE(value->>'bank_iban', ''), '\s', '', 'g')), '') INTO v_cfg FROM app_settings WHERE key = 'company_info';
  RETURN jsonb_build_object('success', true,
    'state', to_jsonb(s),
    'sync', CASE WHEN s.consecutive_failures >= 3 THEN 'failing'
                 WHEN s.last_ok_at IS NULL THEN 'never'
                 WHEN s.last_ok_at < now() - interval '20 minutes' THEN 'stale'
                 ELSE 'ok' END,
    'todo_count', v_todo, 'waiting_requests', v_wait,
    'token_days_left', s.token_valid_until - v_today, 'pay_token_days_left', s.pay_token_valid_until - v_today,
    'company_iban', v_cfg,
    'account_match', CASE WHEN s.account_iban IS NULL OR v_cfg IS NULL THEN NULL ELSE s.account_iban = v_cfg END);
END $$;
REVOKE ALL ON FUNCTION public.admin_fio_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_fio_overview() TO authenticated, service_role;

-- ── Indexy VS + realtime ─────────────────────────────────────────────────────
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
