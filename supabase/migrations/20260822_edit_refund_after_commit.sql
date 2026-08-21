-- =============================================================================
-- MIGRACE 2026-08-22: Vratky úprav rezervace AŽ PO commitu (server-side)
--
-- INCIDENT (dobropisy DB-2026-0008 −189 Kč + DB-2026-0009 −95 Kč, 21.8.2026,
-- jedna úprava „výměna motorky" zákazníkem na webu):
--   Webová záložka „Výměna motorky" (split_booking_moto_swap) volala
--   process-refund KLIENTSKY PŘED commitem. Refund (−189 Kč dle plného
--   ceníkového rozdílu) proběhl → dobropis vystaven, ale následný COMMIT RPC
--   selhal → peníze vráceny BEZ jakékoli změny rezervace a bez záznamu.
--   Zákazník pak výměnu dokončil záložkou „Změna motorky"
--   (apply_booking_changes), která rozdíl −189 Kč přepočítala storno sazbou
--   50 % (48–168 h před startem) na −95 Kč a server-side dispatchla DRUHÝ
--   refund → druhý dobropis. Celkem vráceno 284 Kč místo max. 189 Kč.
--
-- OPRAVA (vzor = _apply_booking_changes_core, 20260804): vratka se NIKDY
-- nevypořádává před commitem. Nový parametr `p_settle_refund` (default FALSE
-- kvůli zpětné kompatibilitě se staršími klienty, kteří si refund dělají
-- klientsky — nesmí vzniknout dvojí dispatch):
--   1) split_booking_moto_swap (rev.7): p_settle_refund=TRUE → při net < 0
--      po ÚSPĚŠNÉM commitu (replace i split větev) dispatchne process-refund
--      přes pg_net (reason 'moto_swap', source 'edit'). Vrací refund_amount
--      + refund_manual (bez Stripe platby = vratka převodem, hint pro UI).
--   2) update_booking_gear: stejně (reason 'gear_edit').
-- Klienti (web swap/gear tab, appka swap) nově volají commit s
-- p_settle_refund=TRUE a vlastní klientský refund NEDĚLAJÍ. Selhání commitu
-- tak nemůže zanechat „osiřelou" vratku a jeden commit = max. jeden dispatch.
--
-- Pozn.: signatura se rozšiřuje → DROP + CREATE (overload by v PostgREST
-- způsobil ambiguity 300 u volání bez nového parametru).
--
-- BONUS FIX: split větev swapu vkládala do bookings sloupec `deposit`, který
-- v živé DB neexistuje (latentní bug z changelogu 2026-08-21 — split commit
-- padal na 42703 a po klientském refundu nechával osiřelou vratku). Odstraněn.
-- =============================================================================

DROP FUNCTION IF EXISTS public.split_booking_moto_swap(uuid, uuid, date, text, boolean);
DROP FUNCTION IF EXISTS public.split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean);

CREATE FUNCTION public.split_booking_moto_swap(
  p_booking_id    uuid,
  p_new_moto_id   uuid,
  p_swap_date     date,
  p_swap_time     text DEFAULT NULL,
  p_dry_run       boolean DEFAULT false,
  p_settle_refund boolean DEFAULT false
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
  -- Vratka po commitu (rev.7 2026-08-22).
  v_refund    numeric := 0;
  v_manual    boolean := false;
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

  -- ŘP kontrola VLASTNÍKA rezervace (OR-match license_groups, fallback
  -- [license_required]). Admin / service_role neblokujeme.
  IF NOT v_admin THEN
    DECLARE
      v_groups   text[];
      v_user_lic text[];
    BEGIN
      SELECT COALESCE(NULLIF(m.license_groups, '{}'::text[]),
                      ARRAY[COALESCE(m.license_required::text, 'A')])
        INTO v_groups FROM motorcycles m WHERE m.id = p_new_moto_id;
      IF v_groups IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'invalid_new_moto');
      END IF;
      IF NOT ('N' = ANY(v_groups)) THEN
        SELECT license_group INTO v_user_lic FROM profiles WHERE id = b.user_id;
        IF v_user_lic IS NULL OR NOT EXISTS (
          SELECT 1 FROM unnest(v_groups) g
          WHERE v_user_lic && CASE g
            WHEN 'AM' THEN ARRAY['AM','A1','A2','A','B']
            WHEN 'A1' THEN ARRAY['A1','A2','A']
            WHEN 'A2' THEN ARRAY['A2','A']
            WHEN 'A'  THEN ARRAY['A']
            WHEN 'B'  THEN ARRAY['B']
            ELSE ARRAY[g]
          END
        ) THEN
          RETURN jsonb_build_object('success', false, 'error', 'license_insufficient');
        END IF;
      END IF;
    END;
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
  -- Vratka (net<0) k vypořádání po commitu; hint pro UI: bez Stripe platby
  -- půjde o manuální vratku převodem na účet (autoritativně řeší process-refund).
  v_refund := CASE WHEN p_settle_refund AND v_net < -0.5 THEN -v_net ELSE 0 END;
  v_manual := (b.stripe_payment_intent_id IS NULL AND b.stripe_session_id IS NULL);

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true, 'dry_run', true,
      'net', v_net,
      'mode', CASE WHEN v_replace THEN 'replace' ELSE 'split' END,
      'a_removed', v_a_credit, 'b_total', (v_b_total - v_b_disc),
      'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'refund_manual', v_manual,
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
        'new_moto_id', p_new_moto_id, 'net', v_net, 'price_diff', v_net, 'source', 'moto_swap')
    WHERE id = p_booking_id;

    -- Vratka AŽ PO úspěšném commitu (rev.7) — process-refund si PI dohledá
    -- ze stripe_session_id; bez Stripe platby vystaví dobropis + 'refund_pending'.
    IF v_refund > 0 THEN
      BEGIN
        SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
        SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
        IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' THEN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/process-refund',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
            body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'moto_swap', 'source', 'edit')
          );
        ELSE
          INSERT INTO debug_log(source, action, status, error_message, request_data)
          VALUES ('split_booking_moto_swap','refund_dispatch_skipped_no_settings','error',
                  'app_settings supabase_url/service_role_key missing',
                  jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
        END IF;
      EXCEPTION WHEN OTHERS THEN
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('split_booking_moto_swap','refund_dispatch_failed','error',SQLERRM,
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END;
    END IF;

    RETURN jsonb_build_object('success', true, 'new_booking_id', p_booking_id, 'net', v_net,
      'mode', 'replace', 'refund_amount', v_refund, 'refund_manual', v_manual);
  END IF;

  -- COMMIT — SPLIT (doplatek net>0 vypořádá frontend PŘED commitem; vratku
  -- net<0 dispatchne tato RPC po commitu při p_settle_refund=TRUE):
  -- 1) Zkrať původní rezervaci (jen data; účetní rozpad ZF/DP/KF NEŘEŠÍ tato RPC).
  UPDATE bookings SET
    end_date = v_a_end,
    original_end_date = COALESCE(original_end_date, end_date),
    total_price = GREATEST(total_price - v_a_credit, 0),
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'type', 'moto_swap_shorten', 'to_end', v_a_end,
      'new_moto_id', p_new_moto_id, 'net', v_net, 'source', 'moto_swap')
  WHERE id = p_booking_id;

  -- 2) Vytvoř druhou rezervaci B jako ZAPLACENOU (doplatek už vypořádán / vratka
  --    se dispatchne níže). Overlap s A pustí výjimka check_user_booking_overlap
  --    (continues_booking_id).
  -- POZOR (2026-08-22): dřívější verze vkládala i sloupec `deposit`, který v
  -- ŽIVÉ tabulce bookings NEEXISTUJE (latentní bug z changelogu 2026-08-21 —
  -- split commit na živé DB padal na 42703, zatímco klientský refund už
  -- proběhl → osiřelá vratka). Sloupec odstraněn.
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time, return_time,
    status, payment_status, total_price, delivery_fee,
    loyalty_level, loyalty_percent, loyalty_discount_amount,
    booking_source, continues_booking_id, notes
  ) VALUES (
    b.user_id, p_new_moto_id, p_swap_date, b.end_date, COALESCE(p_swap_time, b.pickup_time), b.return_time,
    'reserved', 'paid', (v_b_total - v_b_disc), 0,
    NULLIF(v_loy_level, 0), NULLIF(v_loy_pct, 0), v_b_disc,
    COALESCE(b.booking_source, 'web'), p_booking_id,
    'Výměna motorky — navazuje na rezervaci ' || upper(right(p_booking_id::text, 8))
  ) RETURNING id INTO v_new_id;

  -- 3) Vratka AŽ PO úspěšném commitu (rev.7) — na PŮVODNÍ rezervaci A.
  IF v_refund > 0 THEN
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'moto_swap', 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('split_booking_moto_swap','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('split_booking_moto_swap','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  -- 4) Rozešli „reserved" mail (+ smlouva) pro B server-side → web i app stejně.
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

  RETURN jsonb_build_object('success', true, 'new_booking_id', v_new_id, 'net', v_net,
    'mode', 'split', 'refund_amount', v_refund, 'refund_manual', v_manual);
END;
$$;

REVOKE ALL ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean) FROM public;
GRANT EXECUTE ON FUNCTION split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean) TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- update_booking_gear + p_settle_refund (vratka za odebranou výbavu po commitu)
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.update_booking_gear(uuid, jsonb, boolean);
DROP FUNCTION IF EXISTS public.update_booking_gear(uuid, jsonb, boolean, boolean);

CREATE FUNCTION public.update_booking_gear(
  "p_booking_id" uuid, "p_sizes" jsonb, "p_dry_run" boolean DEFAULT false,
  "p_settle_refund" boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  b record;
  v_pp int; v_pbr int; v_pbp int;
  v_new_pass boolean; v_new_br boolean; v_new_bp boolean;
  v_old_paid int := 0; v_new_paid int := 0; v_diff int;
  s_h text; s_j text; s_p text; s_b text; s_g text;
  s_ph text; s_pj text; s_pp_ text; s_pb text; s_pg text;
  v_dtype text;
  v_calc jsonb;
  v_net_diff numeric;
  v_new_total numeric;
  v_new_discount numeric;
  v_loy_level int := 0;
  v_loy_pct numeric := 0;
  v_loy_disc numeric := 0;
  v_refund numeric := 0;
  v_manual boolean := false;
  v_url text; v_key text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','unauthenticated'); END IF;
  SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','not_found'); END IF;
  IF b.user_id <> v_uid AND NOT is_admin() THEN RETURN jsonb_build_object('success',false,'error','not_owner'); END IF;
  IF b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success',false,'error','wrong_status'); END IF;
  IF b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success',false,'error','not_paid'); END IF;

  SELECT COALESCE(MAX(CASE WHEN key='passenger_gear'  AND pricing_unit<>'free' THEN price_czk END),690),
         COALESCE(MAX(CASE WHEN key='boots_rider'     AND pricing_unit<>'free' THEN price_czk END),290),
         COALESCE(MAX(CASE WHEN key='boots_passenger' AND pricing_unit<>'free' THEN price_czk END),290)
    INTO v_pp, v_pbr, v_pbp
    FROM accessory_types WHERE key IN ('passenger_gear','boots_rider','boots_passenger');

  s_h  := NULLIF(p_sizes->>'helmet','');  s_j := NULLIF(p_sizes->>'jacket','');
  s_p  := NULLIF(p_sizes->>'pants','');   s_b := NULLIF(p_sizes->>'boots','');
  s_g  := NULLIF(p_sizes->>'gloves','');
  s_ph := NULLIF(p_sizes->>'passenger_helmet','');  s_pj := NULLIF(p_sizes->>'passenger_jacket','');
  s_pp_:= NULLIF(p_sizes->>'passenger_pants','');   s_pb := NULLIF(p_sizes->>'passenger_boots','');
  s_pg := NULLIF(p_sizes->>'passenger_gloves','');

  v_new_pass := (s_ph IS NOT NULL OR s_pj IS NOT NULL OR s_pp_ IS NOT NULL OR s_pg IS NOT NULL);
  v_new_br   := (s_b  IS NOT NULL);
  v_new_bp   := (s_pb IS NOT NULL);
  IF v_new_pass THEN v_new_paid := v_new_paid + v_pp;  END IF;
  IF v_new_br   THEN v_new_paid := v_new_paid + v_pbr; END IF;
  IF v_new_bp   THEN v_new_paid := v_new_paid + v_pbp; END IF;

  SELECT COALESCE(SUM(
    CASE
      WHEN (lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%')
       AND (lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%') THEN v_pbp
      WHEN (lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%')           THEN v_pbr
      WHEN (lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%')  THEN v_pp
      ELSE 0 END),0)
  INTO v_old_paid FROM booking_extras WHERE booking_id = p_booking_id;

  v_diff := v_new_paid - v_old_paid;

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — app rezervace, kladný rozdíl výbavy ──
  -- Výbava je součást loyalty base i při vzniku rezervace; doplatek za
  -- přidanou výbavu se sníží o pct dle aktuálního ranku.
  IF COALESCE(b.booking_source, 'web') = 'app' AND v_diff > 0 THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND(v_diff * v_loy_pct / 100.0);
  END IF;

  -- ── VARIANTA B (2026-06-11): sleva se přepočítá na nový obsah rezervace ──
  -- v_diff je HRUBÝ rozdíl výbavy; net_diff (po slevě) je to, co se účtuje /
  -- vrací zákazníkovi. Loyalty sleva se odečítá už z gross rozdílu.
  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(b.id, b.total_price, b.discount_amount, v_diff - v_loy_disc, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_manual := (b.stripe_payment_intent_id IS NULL AND b.stripe_session_id IS NULL);

  IF p_dry_run THEN
    RETURN jsonb_build_object('success',true,'payment_required', v_net_diff>0,'net_diff',v_net_diff,
      'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
      'refund_manual', v_manual,
      'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
  END IF;

  UPDATE bookings SET
    helmet_size=s_h, jacket_size=s_j, pants_size=s_p, boots_size=s_b, gloves_size=s_g,
    passenger_helmet_size = CASE WHEN v_new_pass THEN s_ph  ELSE NULL END,
    passenger_jacket_size = CASE WHEN v_new_pass THEN s_pj  ELSE NULL END,
    passenger_pants_size  = CASE WHEN v_new_pass THEN s_pp_ ELSE NULL END,
    passenger_gloves_size = CASE WHEN v_new_pass THEN s_pg  ELSE NULL END,
    passenger_boots_size  = CASE WHEN v_new_bp   THEN s_pb  ELSE NULL END,
    extras_price = GREATEST(0, COALESCE(extras_price,0) + v_diff),
    total_price  = v_new_total,
    discount_amount = v_new_discount,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level   = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END
  WHERE id = p_booking_id;

  DELETE FROM booking_extras WHERE booking_id = p_booking_id
    AND ( lower(name) LIKE '%bot%' OR lower(name) LIKE '%boots%'
       OR lower(name) LIKE '%spolujez%' OR lower(name) LIKE '%passenger%' );
  IF v_new_pass THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Výbava spolujezdce',v_pp,1); END IF;
  IF v_new_br   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty řidič',v_pbr,1); END IF;
  IF v_new_bp   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty spolujezdce',v_pbp,1); END IF;

  -- Vratka AŽ PO úspěšném commitu (2026-08-22) — dřív ji klient volal PŘED
  -- uložením a selhaný commit nechal „osiřelý" refund (incident DB-2026-0008/9).
  IF p_settle_refund AND v_net_diff < -0.5 THEN
    v_refund := -v_net_diff;
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF COALESCE(v_url,'') <> '' AND COALESCE(v_key,'') <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', 'gear_edit', 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('update_booking_gear','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('update_booking_gear','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object('success',true,'payment_required',false,'net_diff',v_net_diff,
    'refund_amount', CASE WHEN v_net_diff<0 THEN -v_net_diff ELSE 0 END,
    'refund_dispatched', (v_refund > 0), 'refund_manual', v_manual,
    'new_total', v_new_total, 'gross_diff', v_diff, 'new_discount', v_new_discount,
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
END;
$$;

REVOKE ALL ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
