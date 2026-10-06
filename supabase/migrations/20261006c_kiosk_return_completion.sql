-- =============================================================================
-- SAMOOBSLUHA: VRÁCENÍ NA KIOSKU — DOKONČENÍ + DOBĚH KÓDŮ (rozhodnutí majitele 2026-10-06) — 2/2 (SQL A)
-- Migrace: 20261006c_kiosk_return_completion.sql — idempotentní (OR REPLACE, cron unschedule+schedule)
--
-- Navazuje na 20261006b (booking_kiosk_returns plní trigger z branch_door_events). Cron každou minutu:
--  1) parked + 2 min klid po posledním zavření kóje:
--     • zavření v POSLEDNÍ den pronájmu (Praha) nebo později → completed, returned_at = actual_return_date =
--       čas zavření podle hodin jednotky (D1, D3); kód motorky dobíhá 15 min po zavření kóje, kód šatny 15 min
--       po zavření šatny (výbava vrácená ≤ 90 min PŘED motorkou → 15 min po zavření kóje); šatna po vrácení
--       nezavřená → kód šatny drží běžnou platnost (D2 — nikdy nezabít dřív, než zákazník vrátí výbavu)
--     • zaparkováno dřív a termín mezitím skončil (pražská půlnoc) → completed se starým časem zavření,
--       kódy zneplatní standardní trigger
--     • nezpůsobilá (není active / test / nezaplacená / SOS / vozík) → skipped + reason, rezervace zůstane obsluze
--  2) completed s dobíhajícími kódy: pozdější zavření šatny / kóje (znovuotevření tímtéž kódem v okně) posune
--     platnost i returned_at; po vypršení kódy zneplatní (is_active=false → resync jednotek).
-- Aby completed nezabil kódy okamžitě, auto_deactivate_door_codes přeskočí rezervaci uvedenou v transakční
-- GUC motogo.kiosk_return_keep_codes (nastavuje JEN kiosk_process_returns, hned ji nuluje).
-- =============================================================================

-- ── auto_deactivate_door_codes: ŽIVÉ tělo 1:1 + výjimka pro doběh kódů po vrácení na kiosku ──
CREATE OR REPLACE FUNCTION public.auto_deactivate_door_codes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- 2026-10-06: dokončení po vrácení na kiosku — kódy dobíhají 15 min, zneplatní je kiosk_process_returns
  IF NEW.id::text = current_setting('motogo.kiosk_return_keep_codes', true) THEN
    RETURN NEW;
  END IF;
  -- Pouze při přechodu na completed nebo cancelled
  IF NEW.status NOT IN ('completed', 'cancelled') THEN
    RETURN NEW;
  END IF;
  -- Pouze pokud se status skutečně změnil
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Deaktivuj všechny aktivní kódy pro tento booking
  UPDATE branch_door_codes
  SET is_active = false
  WHERE booking_id = NEW.id
    AND is_active = true;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'auto_deactivate_door_codes failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.auto_deactivate_door_codes() OWNER TO postgres;

-- ── Procesor (cron kiosk-return-completion, každou minutu) ──
CREATE OR REPLACE FUNCTION public.kiosk_process_returns()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_grace CONSTANT interval := interval '15 minutes';
  c_quiet CONSTANT interval := interval '2 minutes';
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_id uuid; r booking_kiosk_returns%ROWTYPE; b record;
  v_end date; v_final boolean; v_over boolean; v_reason text; v_n integer; v_step text; v_err text;
  v_until timestamptz; v_lc timestamptz; v_lu timestamptz; v_mu timestamptz;
  n_done integer := 0; n_skip integer := 0; n_else integer := 0; n_closed integer := 0; n_err integer := 0;
BEGIN
  -- 0) rozběhnuté vrácení (returning/out), rezervaci ale mezitím uzavřela obsluha / noční cron
  WITH h AS (
    UPDATE booking_kiosk_returns k
       SET state = CASE WHEN b2.status = 'completed' THEN 'completed_elsewhere' ELSE 'skipped' END,
           reason = CASE WHEN b2.status = 'completed' THEN k.reason ELSE 'cancelled' END,
           completed_at = now()
      FROM bookings b2
     WHERE b2.id = k.booking_id
       AND k.booking_id IN (SELECT x.booking_id FROM booking_kiosk_returns x
                              JOIN bookings y ON y.id = x.booking_id AND y.status IN ('completed', 'cancelled')
                             WHERE x.state IN ('returning', 'out') FOR UPDATE OF x SKIP LOCKED)
    RETURNING k.state)
  SELECT count(*) FILTER (WHERE state = 'completed_elsewhere'), count(*) FILTER (WHERE state = 'skipped')
    INTO n_else, n_skip FROM h;

  -- 1) DOKONČENÍ zaparkovaných — jen řádky, se kterými jde něco udělat (zaparkováno před posledním dnem
  --    během termínu se přeskočí už v dotazu, ať LIMIT nezablokují)
  FOR v_id IN SELECT k.booking_id FROM booking_kiosk_returns k JOIN bookings bk ON bk.id = k.booking_id
               WHERE k.state = 'parked' AND k.closed_at IS NOT NULL AND k.last_event_at <= now() - c_quiet
                 AND (bk.status IN ('completed', 'cancelled')
                      OR (k.closed_at AT TIME ZONE 'Europe/Prague')::date >= (bk.end_date AT TIME ZONE 'Europe/Prague')::date
                      OR v_today > (bk.end_date AT TIME ZONE 'Europe/Prague')::date)
               ORDER BY k.last_event_at LIMIT 50
  LOOP
    v_step := 'complete';
    BEGIN
      -- zámky v pořadí jako kiosk_log_open (bookings → booking_kiosk_returns), stav znovu ověřit
      SELECT bk.id, bk.status, bk.end_date, bk.is_test, bk.payment_status, bk.sos_replacement, bk.trailer_moto_id
        INTO b FROM bookings bk WHERE bk.id = v_id FOR NO KEY UPDATE;
      SELECT * INTO r FROM booking_kiosk_returns k
       WHERE k.booking_id = v_id AND k.state = 'parked' AND k.closed_at IS NOT NULL AND k.last_event_at <= now() - c_quiet
         FOR UPDATE SKIP LOCKED;
      CONTINUE WHEN NOT FOUND;
      v_end   := (b.end_date AT TIME ZONE 'Europe/Prague')::date;
      v_final := (r.closed_at AT TIME ZONE 'Europe/Prague')::date >= v_end;
      v_over  := v_today > v_end;

      IF b.status IN ('completed', 'cancelled') THEN
        UPDATE booking_kiosk_returns
           SET state = CASE WHEN b.status = 'completed' THEN 'completed_elsewhere' ELSE 'skipped' END,
               reason = CASE WHEN b.status = 'cancelled' THEN 'cancelled' END, completed_at = now()
         WHERE booking_id = v_id;
        IF b.status = 'completed' THEN n_else := n_else + 1; ELSE n_skip := n_skip + 1; END IF;
        CONTINUE;
      END IF;
      CONTINUE WHEN NOT v_final AND NOT v_over;

      v_reason := CASE WHEN b.status <> 'active' THEN 'not_active'
                       WHEN b.is_test IS TRUE THEN 'test'
                       WHEN b.payment_status IS NULL
                         OR b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN 'unpaid'
                       WHEN COALESCE(b.sos_replacement, false) THEN 'sos_replacement'
                       WHEN b.trailer_moto_id IS NOT NULL THEN 'trailer' END;
      IF v_reason IS NOT NULL THEN
        UPDATE booking_kiosk_returns SET state = 'skipped', reason = v_reason, completed_at = now() WHERE booking_id = v_id;
        INSERT INTO debug_log(source, action, status, request_data)
        VALUES ('kiosk_process_returns', 'skipped', 'info',
                jsonb_build_object('booking_id', v_id, 'reason', v_reason, 'closed_at', r.closed_at));
        n_skip := n_skip + 1;
        CONTINUE;
      END IF;

      v_mu := NULL; v_lc := NULL; v_lu := NULL;
      IF NOT v_over THEN   -- kódy ještě v okně → completed je NEzneplatní, dobíhají
        PERFORM set_config('motogo.kiosk_return_keep_codes', v_id::text, true);
      END IF;
      UPDATE bookings SET status = 'completed', returned_at = r.closed_at, actual_return_date = r.closed_at
       WHERE id = v_id AND status = 'active';
      GET DIAGNOSTICS v_n = ROW_COUNT;
      PERFORM set_config('motogo.kiosk_return_keep_codes', '', true);
      IF v_n = 0 THEN RAISE EXCEPTION 'bookings % se nepodařilo dokončit', v_id; END IF;

      IF NOT v_over THEN
        v_mu := r.closed_at + c_grace;
        UPDATE branch_door_codes SET valid_until = LEAST(COALESCE(valid_until, v_mu), v_mu)
         WHERE booking_id = v_id AND code_type = 'motorcycle' AND is_active
           AND valid_until IS DISTINCT FROM LEAST(COALESCE(valid_until, v_mu), v_mu);
        v_lc := public._kiosk_return_locker_close(v_id, r.branch_id, r.closed_at);
        IF v_lc IS NOT NULL THEN
          v_lu := GREATEST(v_lc, r.closed_at) + c_grace;
          v_until := LEAST(public._door_code_valid_until(b.end_date), v_lu);
          UPDATE branch_door_codes SET valid_until = v_until
           WHERE booking_id = v_id AND code_type = 'accessories' AND is_active AND valid_until IS DISTINCT FROM v_until;
        END IF;
      END IF;
      UPDATE booking_kiosk_returns
         SET state = 'completed', completed_at = now(), reason = NULL,
             moto_code_until = v_mu, locker_closed_at = v_lc, locker_code_until = v_lu,
             codes_closed_at = CASE WHEN v_over THEN now() END,
             detail = detail || jsonb_build_object('completed_after_end', v_over)
       WHERE booking_id = v_id;
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('kiosk_process_returns', 'completed', 'info',
              jsonb_build_object('booking_id', v_id, 'closed_at', r.closed_at, 'after_end', v_over,
                                 'moto_code_until', v_mu, 'locker_code_until', v_lu));
      n_done := n_done + 1;
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM; n_err := n_err + 1;
      PERFORM set_config('motogo.kiosk_return_keep_codes', '', true);
      RAISE WARNING 'kiosk_process_returns (%) booking %: %', v_step, v_id, v_err;
      BEGIN
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('kiosk_process_returns', 'error', 'error', v_err, jsonb_build_object('booking_id', v_id, 'step', v_step));
        -- opakovaná chyba (10×) → skipped/error, ať to obsluha dokončí ručně a cron se nezacyklí
        UPDATE booking_kiosk_returns
           SET detail = detail || jsonb_build_object('last_error', left(v_err, 500),
                                                     'errors', COALESCE((detail->>'errors')::int, 0) + 1),
               state = CASE WHEN COALESCE((detail->>'errors')::int, 0) + 1 >= 10 THEN 'skipped' ELSE state END,
               reason = CASE WHEN COALESCE((detail->>'errors')::int, 0) + 1 >= 10 THEN 'error' ELSE reason END
         WHERE booking_id = v_id AND state = 'parked';
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END;
  END LOOP;

  -- 2) DOBĚH kódů po automatickém dokončení
  FOR v_id IN SELECT k.booking_id FROM booking_kiosk_returns k
               WHERE k.state = 'completed' AND k.codes_closed_at IS NULL
               ORDER BY k.completed_at LIMIT 500
  LOOP
    v_step := 'codes';
    BEGIN
      -- bez zámků: je vůbec co dělat? (většina řádků jen čeká na vypršení — nezamykat je každou minutu)
      SELECT bk.status, bk.returned_at INTO b FROM bookings bk WHERE bk.id = v_id;
      SELECT * INTO r FROM booking_kiosk_returns WHERE booking_id = v_id;
      CONTINUE WHEN b.status = 'completed' AND r.closed_at + c_grace <= r.moto_code_until
        AND NOT COALESCE(public._kiosk_return_locker_close(v_id, r.branch_id, r.closed_at)
                         > COALESCE(r.locker_closed_at, '-infinity'), false)
        AND NOT COALESCE(r.closed_at > b.returned_at AND r.closed_at <= r.moto_code_until + interval '5 minutes', false)
        AND EXISTS (SELECT 1 FROM branch_door_codes c WHERE c.booking_id = v_id AND c.is_active)
        AND NOT EXISTS (SELECT 1 FROM branch_door_codes c WHERE c.booking_id = v_id AND c.is_active
                          AND (COALESCE(c.valid_until, 'infinity') < now()
                               OR (c.code_type = 'motorcycle' AND now() > r.moto_code_until)
                               OR (c.code_type = 'accessories' AND now() > COALESCE(r.locker_code_until, c.valid_until, 'infinity'))));
      SELECT bk.id, bk.status, bk.end_date, bk.returned_at INTO b FROM bookings bk WHERE bk.id = v_id FOR NO KEY UPDATE;
      CONTINUE WHEN NOT FOUND;
      SELECT * INTO r FROM booking_kiosk_returns k
       WHERE k.booking_id = v_id AND k.state = 'completed' AND k.codes_closed_at IS NULL FOR UPDATE SKIP LOCKED;
      CONTINUE WHEN NOT FOUND;
      v_until := public._door_code_valid_until(b.end_date);
      IF b.status <> 'completed' THEN
        -- dokončení někdo vrátil zpět → automatika kódy dál neřídí, aktivním vrátí běžnou platnost
        UPDATE branch_door_codes SET valid_until = v_until
         WHERE booking_id = v_id AND is_active AND valid_until < v_until;
        UPDATE booking_kiosk_returns SET codes_closed_at = now(), detail = detail || '{"reverted": true}'::jsonb
         WHERE booking_id = v_id;
        CONTINUE;
      END IF;
      -- (a) šatna zavřená později (výbava vrácena po motorce) → nový doběh kódu šatny
      v_lc := public._kiosk_return_locker_close(v_id, r.branch_id, r.closed_at);
      IF v_lc > COALESCE(r.locker_closed_at, '-infinity') THEN
        r.locker_closed_at := v_lc;
        r.locker_code_until := GREATEST(v_lc, r.closed_at) + c_grace;
        UPDATE branch_door_codes SET valid_until = LEAST(v_until, r.locker_code_until)
         WHERE booking_id = v_id AND code_type = 'accessories' AND is_active
           AND valid_until IS DISTINCT FROM LEAST(v_until, r.locker_code_until);
      END IF;
      -- (b) znovuotevření kóje tímtéž kódem v okně a nové zavření → returned_at i doběh kódu motorky se posunou
      IF r.closed_at > COALESCE(b.returned_at, '-infinity')
         AND r.closed_at <= COALESCE(r.moto_code_until, r.closed_at) + interval '5 minutes' THEN
        UPDATE bookings SET returned_at = r.closed_at, actual_return_date = r.closed_at
         WHERE id = v_id AND status = 'completed';
      END IF;
      v_mu := GREATEST(r.moto_code_until, r.closed_at + c_grace);
      IF v_mu > COALESCE(r.moto_code_until, '-infinity') THEN
        r.moto_code_until := v_mu;
        UPDATE branch_door_codes SET valid_until = LEAST(v_until, v_mu)
         WHERE booking_id = v_id AND code_type = 'motorcycle' AND is_active
           AND valid_until IS DISTINCT FROM LEAST(v_until, v_mu);
      END IF;
      -- (c) vypršelé kódy zneplatnit (→ _door_code_manual_revoke zruší i aliasy, kiosk_request_sync)
      UPDATE branch_door_codes SET is_active = false
       WHERE booking_id = v_id AND is_active
         AND (COALESCE(valid_until, 'infinity') < now()
              OR (code_type = 'motorcycle' AND now() > r.moto_code_until)
              OR (code_type = 'accessories' AND now() > COALESCE(r.locker_code_until, valid_until, 'infinity')));
      -- (d) nezbyl aktivní kód → doběh hotov
      IF NOT EXISTS (SELECT 1 FROM branch_door_codes WHERE booking_id = v_id AND is_active) THEN
        r.codes_closed_at := now();
        n_closed := n_closed + 1;
      END IF;
      UPDATE booking_kiosk_returns k
         SET locker_closed_at = r.locker_closed_at, locker_code_until = r.locker_code_until,
             moto_code_until = r.moto_code_until, codes_closed_at = r.codes_closed_at
       WHERE k.booking_id = v_id
         AND (k.locker_closed_at, k.locker_code_until, k.moto_code_until, k.codes_closed_at)
             IS DISTINCT FROM (r.locker_closed_at, r.locker_code_until, r.moto_code_until, r.codes_closed_at);
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM; n_err := n_err + 1;
      RAISE WARNING 'kiosk_process_returns (%) booking %: %', v_step, v_id, v_err;
      BEGIN
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('kiosk_process_returns', 'error', 'error', v_err, jsonb_build_object('booking_id', v_id, 'step', v_step));
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END;
  END LOOP;

  RETURN jsonb_build_object('completed', n_done, 'skipped', n_skip, 'completed_elsewhere', n_else,
                            'codes_closed', n_closed, 'errors', n_err);
END $$;
ALTER FUNCTION public.kiosk_process_returns() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.kiosk_process_returns() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_process_returns() TO service_role;
COMMENT ON FUNCTION public.kiosk_process_returns() IS
  'Cron kiosk-return-completion (každou minutu, 2026-10-06): booking_kiosk_returns parked + 2 min klid → vrácení v poslední den / po konci termínu dokončí rezervaci (returned_at = zavření kóje dle jednotky), nezpůsobilé → skipped; po dokončení kód motorky dobíhá 15 min po zavření kóje, kód šatny 15 min po zavření šatny (bez zavření běžná platnost). Vrací počty.';

DO $$
BEGIN
  BEGIN
    PERFORM cron.unschedule('kiosk-return-completion');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM cron.schedule('kiosk-return-completion', '* * * * *', $cron$ SELECT public.kiosk_process_returns(); $cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule kiosk-return-completion selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;
