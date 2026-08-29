-- =============================================================================
-- MIGRACE 2026-08-29: Fio API — automatické potvrzování QR / bankovních plateb
--
-- Nový firemní účet je u Fio banky s napojením na API Bankovnictví. Cron
-- `fio-bank-sync` každých 5 minut zavolá edge funkci `fio-sync`, která stáhne
-- nové příchozí pohyby (endpoint /last/{token}/transactions.json — Fio si
-- zarážku posouvá samo), spáruje je přes VS (bookings.payment_vs /
-- bookings.mod_surcharge_vs / invoices.variable_symbol) a potvrdí platbu
-- STEJNÝM flow jako ruční tlačítko „Potvrdit platbu" ve Velíně (RPC
-- confirm_payment / confirm_booking_surcharge + ZF/DP + potvrzovací mail).
-- Tlačítko ve Velíně zůstává beze změny jako fallback pro nespárované platby.
--
-- Obsah:
--   1) Tabulka `fio_transactions` — idempotence (PK = Fio ID pohybu) + audit
--   2) `fio_sync_tick()` — pg_cron → net.http_post na edge `fio-sync`
--      (URL/klíč z app_settings — ověřený vzor trigger_route_translation_backfill)
--   3) cron.schedule 'fio-bank-sync' každých 5 minut
--   4) `confirm_booking_surcharge` — guard nově pouští i service_role
--      (stejný precedent jako split_booking_moto_swap rev.5, 20260731c):
--      auto-potvrzení doplatku volá fio-sync service klíčem, auth.uid() je NULL
--      a dosavadní čistý is_admin() guard by vrátil 'forbidden'.
--
-- Idempotentní; NEmaže žádná data. Secret FIO_API_TOKEN se nastavuje v
-- Supabase dashboardu (Edge Functions → Secrets), NE v této migraci.
-- =============================================================================

-- ── 1) Tabulka fio_transactions ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fio_transactions (
  fio_id          bigint PRIMARY KEY,          -- Fio „ID pohybu" (column22) — unikátní napříč účtem
  tx_date         date NOT NULL,
  amount          numeric(12,2) NOT NULL,      -- kladná = příchozí
  currency        text,
  vs              text,                        -- variabilní symbol (column5)
  counter_account text,
  counter_bank    text,
  counter_name    text,
  message         text,                        -- zpráva pro příjemce (column16)
  tx_type         text,                        -- typ pohybu (column8)
  status          text NOT NULL DEFAULT 'new' CHECK (status IN
                    ('new','outgoing','confirmed_booking','confirmed_surcharge',
                     'already_paid','no_match','amount_mismatch','needs_review','error')),
  booking_id      uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
  note            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  processed_at    timestamptz
);

CREATE INDEX IF NOT EXISTS idx_fio_transactions_vs ON public.fio_transactions (vs);
CREATE INDEX IF NOT EXISTS idx_fio_transactions_pending ON public.fio_transactions (status)
  WHERE status IN ('new','no_match','amount_mismatch','needs_review','error');

ALTER TABLE public.fio_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fio_transactions_admin ON public.fio_transactions;
CREATE POLICY fio_transactions_admin ON public.fio_transactions
  FOR ALL USING (is_admin());
-- zápis dělá výhradně edge fn service klíčem (RLS bypass); Velín jen čte

-- ── 2) Tick funkce pro pg_cron ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fio_sync_tick()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM public.app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM public.app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RAISE WARNING 'fio_sync_tick: app_settings supabase_url/service_role_key chybí';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/fio-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := '{}'::jsonb
  );
END $$;

GRANT EXECUTE ON FUNCTION public.fio_sync_tick() TO service_role;

-- ── 3) Cron každých 5 minut ──────────────────────────────────────────────────
DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('fio-bank-sync');
  EXCEPTION WHEN OTHERS THEN NULL; -- job ještě neexistuje
  END;
  PERFORM cron.schedule(
    'fio-bank-sync',
    '*/5 * * * *',
    $cron$ SELECT public.fio_sync_tick(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;

-- ── 4) confirm_booking_surcharge — pustit i service_role (fio-sync) ──────────
-- Tělo 1:1 s 20260727_booking_edit_surcharge_flow.sql, změněn POUZE guard.
CREATE OR REPLACE FUNCTION confirm_booking_surcharge(
  p_booking_id      uuid,
  p_method          text DEFAULT 'bank_transfer',
  p_vs              text DEFAULT NULL,
  p_paid_date       date DEFAULT NULL,
  p_transaction_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_b       bookings%ROWTYPE;
  v_due     numeric;
  v_url     text;
  v_key     text;
  v_payload jsonb;
  v_profile profiles%ROWTYPE;
  v_moto    text;
  v_app_msg text;
BEGIN
  -- service_role (fio-sync auto-potvrzení z Fio API) smí potvrdit — auth.uid()
  -- je u service klíče NULL, ale JWT role je 'service_role'; klientské
  -- anon/authenticated klíče to mít nemohou (vzor split_booking_moto_swap rev.5).
  IF NOT (is_admin()
          OR COALESCE((NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb->>'role','') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  v_due := COALESCE(v_b.mod_surcharge_due, 0);
  IF v_due <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_surcharge_pending');
  END IF;

  -- Potvrzení: vynulovat dluh, zapsat čas platby, payload vyčistit až PO odeslání.
  -- (Tento UPDATE nemění žádné pole sledované trg_booking_modified_email →
  -- trigger se neodpálí znovu.)
  UPDATE bookings
     SET mod_surcharge_due     = NULL,
         mod_surcharge_paid_at = COALESCE(p_paid_date::timestamptz, now()),
         payment_reference     = COALESCE(p_transaction_ref, payment_reference),
         updated_at            = now()
   WHERE id = p_booking_id;

  -- Odložený payload; fallback z aktuálního řádku (kdyby trigger payload neuložil).
  v_payload := v_b.mod_email_payload;
  IF v_payload IS NULL THEN
    SELECT * INTO v_profile FROM profiles WHERE id = v_b.user_id;
    SELECT model INTO v_moto FROM motorcycles WHERE id = v_b.moto_id;
    v_payload := jsonb_build_object(
      'booking_id',           v_b.id,
      'customer_email',       COALESCE(v_profile.email, ''),
      'customer_name',        COALESCE(v_profile.full_name, ''),
      'source',               COALESCE(v_b.booking_source, 'app'),
      'motorcycle',           COALESCE(v_moto, ''),
      'start_date',           v_b.start_date,
      'end_date',             v_b.end_date,
      'total_price',          v_b.total_price,
      'original_total_price', COALESCE(v_b.total_price, 0) - v_due
    );
  END IF;
  -- price_difference = skutečně zaplacený doplatek (rozdílový DP se vystaví na něj).
  v_payload := v_payload || jsonb_build_object('price_difference', v_due);

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  -- KROK 1: odložený booking_modified mail (izolovaně).
  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> ''
     AND COALESCE(v_payload->>'customer_email', '') <> '' THEN
    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'Authorization', 'Bearer ' || v_key),
        body    := v_payload || jsonb_build_object('type', 'booking_modified')
      );
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('confirm_booking_surcharge', 'deferred_modified_mail_queued', 'info',
              jsonb_build_object('booking_id', p_booking_id, 'amount', v_due));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('confirm_booking_surcharge', 'deferred_modified_mail_failed', 'error', SQLERRM,
              jsonb_build_object('booking_id', p_booking_id));
    END;
  ELSE
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('confirm_booking_surcharge', 'deferred_mail_skipped_missing_cfg', 'info',
            jsonb_build_object('booking_id', p_booking_id,
                               'has_url', v_url IS NOT NULL, 'has_key', v_key IS NOT NULL,
                               'has_email', COALESCE(v_payload->>'customer_email', '') <> ''));
  END IF;

  -- KROK 2: dispatch custom šablon (izolovaně).
  BEGIN
    PERFORM dispatch_email_event('booking_updated', v_payload);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('confirm_booking_surcharge', 'dispatch_event_failed', 'error', SQLERRM,
            jsonb_build_object('booking_id', p_booking_id));
  END;

  -- KROK 3: in-app zpráva (appka Zprávy + FCM push) — izolovaně.
  BEGIN
    v_app_msg := 'Vaše rezervace č. ' || UPPER(RIGHT(v_b.id::text, 8))
      || ' byla upravena a doplatek ' || ROUND(v_due)::text
      || ' Kč jsme v pořádku přijali. Detaily a aktualizovanou smlouvu jsme poslali e-mailem.';
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (v_b.user_id, 'Rezervace upravena', v_app_msg, 'info');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('confirm_booking_surcharge', 'app_message_failed', 'error', SQLERRM,
            jsonb_build_object('booking_id', p_booking_id));
  END;

  -- Payload už není potřeba.
  UPDATE bookings SET mod_email_payload = NULL WHERE id = p_booking_id;

  RETURN jsonb_build_object('success', true, 'amount', v_due,
                            'vs', COALESCE(p_vs, v_b.mod_surcharge_vs));
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_booking_surcharge(uuid, text, text, date, text) TO authenticated, service_role;
