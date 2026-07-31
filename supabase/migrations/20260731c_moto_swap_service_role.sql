-- =============================================================================
-- MIGRACE 2026-07-31c: Výměna motorky — commit smí volat i service_role (webhook)
--
-- INCIDENT #EEC9CA33: zákazník zaplatil doplatek výměny, ale COMMIT se volal
-- JEN klientsky z appky po platbě — když selže / appka umře, výměna se tiše
-- neprovede a peníze jsou strženy. Oprava = server-side pojistka: webhook
-- (webhook-receiver) po úspěšné extension platbě se `_swap` metadaty zavolá
-- COMMIT sám se SERVICE_ROLE klíčem. RPC proto musí service_role pustit:
-- auth.uid() je u service klíče NULL → dosud spadlo na 'forbidden'.
--
-- Jediná změna proti rev.4 (20260731b_moto_swap_refund_cap.sql): v_admin
-- nově TRUE i pro JWT roli 'service_role' (jen backend klíč, nikdy klient).
-- =============================================================================

CREATE OR REPLACE FUNCTION split_booking_moto_swap(
  p_booking_id  uuid,
  p_new_moto_id uuid,
  p_swap_date   date,
  p_swap_time   text DEFAULT NULL,
  p_dry_run     boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  -- service_role (webhook/backend) smí commit — auth.uid() je NULL, ale JWT
  -- role klíče je 'service_role'; klientské anon/authenticated to mít nemohou.
  v_admin    boolean := is_admin() OR COALESCE((NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb->>'role','') = 'service_role';
  b          bookings;
  v_conflict int;
  v_a_removed numeric;
  v_b_total   numeric;
  v_net       numeric;
  v_new_id    uuid;
  v_full_swap boolean;      -- výměna od PRVNÍHO dne rezervace
  v_replace   boolean;      -- plná výměna u 'reserved' → in-place změna moto_id
  v_a_end     date;         -- nový konec původní rezervace A (split větev)
  -- Strop vratky dle skutečně zaplacené ceny (rev.4 2026-07-31b).
  v_a_full       numeric;   -- ceníková hodnota CELÉHO termínu staré motorky
  v_paid_rental  numeric;   -- skutečně zaplacený pronájem (bez dopravy/výbavy)
  v_removed_paid numeric;   -- poměrná zaplacená část za odebrané dny
  v_a_credit     numeric;   -- finální dobropisovaná hodnota odebraných dní
  -- Věrnostní sleva (JEN booking_source='app', aktuální rank zákazníka).
  v_loy_level int := 0;
  v_loy_pct   int := 0;
  v_b_disc    numeric := 0;   -- sleva na cenu B
  v_a_disc    numeric := 0;   -- sleva na odebrané dny A (net vypořádání)
  v_url text; v_key text; v_email text; v_name text; v_moto text;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  IF b.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF NOT v_admin AND (v_uid IS NULL OR b.user_id IS DISTINCT FROM v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF b.status NOT IN ('reserved', 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;
  IF b.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_paid');
  END IF;
  IF p_new_moto_id IS NULL OR p_new_moto_id = b.moto_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_new_moto');
  END IF;
  -- Povolený rozsah: KTERÝKOLI den rezervace včetně prvního a posledního.
  IF p_swap_date < b.start_date::date OR p_swap_date > b.end_date::date THEN
    RETURN jsonb_build_object('success', false, 'error', 'swap_date_out_of_range');
  END IF;
  v_full_swap := (p_swap_date = b.start_date::date);
  -- Plná výměna jen od dneška (retroaktivní kompletní náhrada nedává smysl).
  IF v_full_swap AND p_swap_date < CURRENT_DATE THEN
    RETURN jsonb_build_object('success', false, 'error', 'swap_date_out_of_range');
  END IF;
  v_replace := v_full_swap AND b.status = 'reserved';
  -- Plná výměna u aktivní (převzato dnes): A si nechá den jako den předání,
  -- jinak standardně den před výměnou.
  v_a_end := CASE WHEN v_full_swap THEN p_swap_date ELSE p_swap_date - 1 END;
  IF EXISTS (SELECT 1 FROM bookings s WHERE s.continues_booking_id = p_booking_id AND s.status <> 'cancelled') THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_split');
  END IF;

  -- Dostupnost NOVÉ motorky pro [swap_date .. end], MIMO tuto rezervaci.
  SELECT count(*) INTO v_conflict FROM (
    SELECT 1 FROM bookings ob
    WHERE ob.moto_id = p_new_moto_id AND ob.id <> p_booking_id
      AND ob.status IN ('pending','reserved','active')
      AND daterange(ob.start_date::date, ob.end_date::date, '[]')
          && daterange(p_swap_date, b.end_date::date, '[]')
    UNION ALL
    SELECT 1 FROM maintenance_log m
    WHERE m.moto_id = p_new_moto_id AND m.service_date IS NOT NULL AND m.completed_date IS NULL
      AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
      AND daterange(m.service_date::date, COALESCE(m.scheduled_date, m.service_date)::date, '[]')
          && daterange(p_swap_date, b.end_date::date, '[]')
  ) x;
  IF v_conflict > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'new_moto_unavailable');
  END IF;

  -- Ceníkové hodnoty: odebrané dny staré motorky a nová motorka za [swap..end].
  v_a_removed := _moto_dayprice_sum(b.moto_id, p_swap_date, b.end_date::date);
  v_b_total   := _moto_dayprice_sum(p_new_moto_id, p_swap_date, b.end_date::date);

  -- Věrnostní sleva JEN pro app rezervace (aktuální rank zákazníka). Level = %:
  --   level = min(20, ceil((počet dokončených app rezervací + 1)/2)); % = discount_percent.
  IF b.booking_source = 'app' THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_b_disc := round(v_b_total   * v_loy_pct / 100.0);
    v_a_disc := round(v_a_removed * v_loy_pct / 100.0);
  END IF;

  -- STROP VRATKY: odebrané dny se dobropisují max. do výše poměrné části
  -- SKUTEČNĚ zaplacené ceny pronájmu (promo/voucher/slevy → zákazník nesmí
  -- dostat zpět víc, než reálně zaplatil).
  v_a_full := _moto_dayprice_sum(b.moto_id, b.start_date::date, b.end_date::date);
  v_paid_rental := GREATEST(COALESCE(b.total_price, 0) - COALESCE(b.delivery_fee, 0) - COALESCE(b.extras_price, 0), 0);
  v_removed_paid := CASE WHEN v_a_full > 0
    THEN LEAST(round(v_paid_rental * v_a_removed / v_a_full), v_paid_rental)
    ELSE 0 END;
  v_a_credit := LEAST(v_a_removed - v_a_disc, v_removed_paid);

  -- Net = (cena B po slevě) − dobropisovaná hodnota odebraných dní A.
  v_net := (v_b_total - v_b_disc) - v_a_credit;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true, 'dry_run', true,
      'net', v_net,
      'mode', CASE WHEN v_replace THEN 'replace' ELSE 'split' END,
      'a_removed', v_a_credit, 'b_total', (v_b_total - v_b_disc),
      'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'a_new_end', CASE WHEN v_replace THEN NULL ELSE v_a_end END,
      'b_start', p_swap_date, 'b_end', b.end_date::date
    );
  END IF;

  -- COMMIT — REPLACE větev: výměna od prvního dne u 'reserved' (nic nepřevzato)
  -- = jen výměna motorky a ceny v TÉŽE rezervaci, žádný split. Mail o úpravě +
  -- rozdílový doklad + app zprávu odešle trg_booking_modified_email (moto_id/cena).
  IF v_replace THEN
    UPDATE bookings SET
      moto_id = p_new_moto_id,
      pickup_time = COALESCE(p_swap_time, pickup_time),
      total_price = GREATEST(total_price + v_net, 0),
      modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
        'at', now(), 'type', 'moto_swap_replace', 'from_moto_id', b.moto_id,
        'new_moto_id', p_new_moto_id, 'net', v_net, 'source', 'moto_swap')
    WHERE id = p_booking_id;
    RETURN jsonb_build_object('success', true, 'new_booking_id', p_booking_id, 'net', v_net, 'mode', 'replace');
  END IF;

  -- COMMIT — SPLIT (voláno AŽ po vypořádání net rozdílu frontendem — doplatek/vrácení):
  -- 1) Zkrať původní rezervaci (jen data; účetní rozpad ZF/DP/KF NEŘEŠÍ tato RPC).
  UPDATE bookings SET
    end_date = v_a_end,
    original_end_date = COALESCE(original_end_date, end_date),
    total_price = GREATEST(total_price - v_a_credit, 0),
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'type', 'moto_swap_shorten', 'to_end', v_a_end,
      'new_moto_id', p_new_moto_id, 'net', v_net, 'source', 'moto_swap')
  WHERE id = p_booking_id;

  -- 2) Vytvoř druhou rezervaci B jako ZAPLACENOU (net už vypořádán). Overlap s A
  --    pustí výjimka check_user_booking_overlap (continues_booking_id).
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time, return_time,
    status, payment_status, total_price, delivery_fee, deposit,
    loyalty_level, loyalty_percent, loyalty_discount_amount,
    booking_source, continues_booking_id, notes
  ) VALUES (
    b.user_id, p_new_moto_id, p_swap_date, b.end_date, COALESCE(p_swap_time, b.pickup_time), b.return_time,
    'reserved', 'paid', (v_b_total - v_b_disc), 0, 0,
    NULLIF(v_loy_level, 0), NULLIF(v_loy_pct, 0), v_b_disc,
    COALESCE(b.booking_source, 'web'), p_booking_id,
    'Výměna motorky — navazuje na rezervaci ' || upper(right(p_booking_id::text, 8))
  ) RETURNING id INTO v_new_id;

  -- 3) Rozešli „reserved" mail (+ smlouva) pro B server-side → web i app stejně.
  --    Best-effort, izolovaně — nikdy neshodí commit.
  BEGIN
    SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
    SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
    SELECT p.email, p.full_name, m.model INTO v_email, v_name, v_moto
    FROM profiles p, motorcycles m WHERE p.id = b.user_id AND m.id = p_new_moto_id;
    IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' AND COALESCE(v_email,'') <> '' THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/send-booking-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
        body := jsonb_build_object(
          'type', 'booking_reserved', 'booking_id', v_new_id,
          'customer_email', v_email, 'customer_name', COALESCE(v_name,''),
          'motorcycle', COALESCE(v_moto,''),
          'start_date', p_swap_date, 'end_date', b.end_date::date,
          'source', COALESCE(b.booking_source,'web')
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('split_booking_moto_swap','reserved_mail_dispatch_failed','error', SQLERRM,
            jsonb_build_object('new_booking_id', v_new_id));
  END;

  RETURN jsonb_build_object('success', true, 'new_booking_id', v_new_id, 'net', v_net, 'mode', 'split');
END;
$$;

REVOKE ALL ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
