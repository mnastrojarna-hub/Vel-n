-- =============================================================================
-- 2026-10-23 (c): Výpůjčka JEN výbavy — vrácení na kiosku — dokončení (12/14)
-- kiosk_process_returns: výbava potvrzená na displeji = finální kdykoli v termínu (bez pravidla posledního dne),
-- returned_at = čas potvrzení, kód šatny 15 min po zavření šatny; neaktivní čeká do konce termínu; nezaplacená skipped.
-- Celek a pořadí souborů: viz 20261023c_gear_booking_codes.sql. Motorka beze změny (změny označené „2026-10-23“).
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.kiosk_process_returns()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_grace CONSTANT interval := interval '15 minutes';
  c_quiet CONSTANT interval := interval '2 minutes';
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  v_id uuid; r booking_kiosk_returns%ROWTYPE; b record;
  v_end date; v_final boolean; v_over boolean; v_reason text; v_n integer; v_step text; v_err text;
  v_until timestamptz; v_lc timestamptz; v_lu timestamptz; v_mu timestamptz;
  v_gear boolean; v_ret timestamptz;   -- 2026-10-23: výpůjčka výbavy potvrzená na displeji
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
                      OR v_today > (bk.end_date AT TIME ZONE 'Europe/Prague')::date
                      -- 2026-10-23: výpůjčka výbavy potvrzená na displeji („Vracíš všechnu výbavu?“ → Ano) = vrácení
                      -- kdykoli během termínu (bez pravidla posledního dne); dokud není aktivní, čeká do konce termínu
                      OR (k.detail->>'gear_only' = 'true' AND bk.status = 'active'))
                 -- 2026-10-23: neaktivní výbava v termínu jen čeká (krok níže by ji přeskočil) → mimo LIMIT
                 AND NOT (k.detail->>'gear_only' = 'true' AND bk.booking_kind = 'gear' AND bk.status = 'reserved'
                          AND v_today <= (bk.end_date AT TIME ZONE 'Europe/Prague')::date)
               ORDER BY k.last_event_at LIMIT 50
  LOOP
    v_step := 'complete';
    BEGIN
      -- zámky v pořadí jako kiosk_log_open (bookings → booking_kiosk_returns), stav znovu ověřit; na zamčenou
      -- rezervaci NEČEKAT (SKIP LOCKED → příští minuta) — jinak by držené zámky už zpracovaných řádků blokovaly
      -- kiosk_log_open (anon, timeout 3 s) a audit dveří by se vracel do outboxu jednotky
      SELECT bk.id, bk.status, bk.end_date, bk.is_test, bk.payment_status, bk.sos_replacement, bk.trailer_moto_id,
             bk.booking_kind, bk.picked_up_at
        INTO b FROM bookings bk WHERE bk.id = v_id FOR NO KEY UPDATE SKIP LOCKED;
      CONTINUE WHEN NOT FOUND;
      SELECT * INTO r FROM booking_kiosk_returns k
       WHERE k.booking_id = v_id AND k.state = 'parked' AND k.closed_at IS NOT NULL AND k.last_event_at <= now() - c_quiet
         FOR UPDATE SKIP LOCKED;
      CONTINUE WHEN NOT FOUND;
      v_end   := (b.end_date AT TIME ZONE 'Europe/Prague')::date;
      -- výbava: zákazník vrácení potvrdil na displeji → finální kdykoli (returned_at = čas potvrzení)
      v_gear  := COALESCE(r.detail->>'gear_only', '') = 'true' AND b.booking_kind = 'gear';
      v_final := (r.closed_at AT TIME ZONE 'Europe/Prague')::date >= v_end OR v_gear;
      v_over  := v_today > v_end;
      v_ret   := CASE WHEN v_gear THEN COALESCE(NULLIF(r.detail->>'confirmed_at', '')::timestamptz, r.closed_at)
                      ELSE r.closed_at END;

      IF b.status IN ('completed', 'cancelled') THEN
        UPDATE booking_kiosk_returns
           SET state = CASE WHEN b.status = 'completed' THEN 'completed_elsewhere' ELSE 'skipped' END,
               reason = CASE WHEN b.status = 'cancelled' THEN 'cancelled' END, completed_at = now()
         WHERE booking_id = v_id;
        IF b.status = 'completed' THEN n_else := n_else + 1; ELSE n_skip := n_skip + 1; END IF;
        CONTINUE;
      END IF;
      CONTINUE WHEN NOT v_final AND NOT v_over;
      -- výbava ještě neaktivní (podpis protokolu z fronty jednotky dorazí po potvrzení) → počkat do konce termínu
      CONTINUE WHEN v_gear AND b.status = 'reserved' AND NOT v_over;

      v_reason := CASE WHEN b.status <> 'active' THEN 'not_active'
                       WHEN b.is_test IS TRUE THEN 'test'
                       WHEN b.payment_status IS NULL
                         OR b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN 'unpaid'
                       WHEN COALESCE(b.sos_replacement, false) THEN 'sos_replacement'
                       WHEN b.trailer_moto_id IS NOT NULL THEN 'trailer'
                       -- 2026-10-23: výbava potvrzená PŘED převzetím (např. ruční aktivace ve Velínu až po
                       -- potvrzení) → returned_at < picked_up_at nedělat, dokončí obsluha
                       WHEN v_gear AND v_ret < b.picked_up_at THEN 'before_pickup' END;
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
      UPDATE bookings SET status = 'completed', returned_at = v_ret, actual_return_date = v_ret
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
        -- výbava: potvrzení přichází až po zavření šatny → kód šatny dobíhá 15 min i bez dohledané události zavření
        IF v_lc IS NULL AND v_gear THEN v_lc := r.closed_at; END IF;
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
                                 'moto_code_until', v_mu, 'locker_code_until', v_lu)
              || CASE WHEN v_gear THEN jsonb_build_object('gear_only', true, 'returned_at', v_ret) ELSE '{}'::jsonb END);
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
      SELECT bk.id, bk.status, bk.end_date, bk.returned_at INTO b FROM bookings bk WHERE bk.id = v_id
         FOR NO KEY UPDATE SKIP LOCKED;
      CONTINUE WHEN NOT FOUND;   -- zamčená rezervace → příští minuta (nečekat, viz krok 1)
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
END $function$
;
