-- =============================================================================
-- MIGRACE 2026-09-04: Late-pickup půlden (sleva 50 % na 1. den od 12:00) —
-- dotažení do všech flow (audit "half-day extension pricing")
--
-- (1) BEFORE UPDATE anti-cheat trigger na bookings:
--     trg_validate_late_pickup byl JEN BEFORE INSERT — appka i Velín ale
--     zapisují úpravy přímým UPDATE (bez RPC), takže klientem poslaná
--     late_pickup_discount_amount nebyla při úpravě nijak validovaná.
--     validate_late_pickup_discount() nově obsluhuje INSERT i UPDATE:
--       - u UPDATE zasahuje JEN když se sloupec reálně mění (IS DISTINCT FROM)
--         → bezplatný posun termínu (reschedule_booking_free, hromadný posun),
--         který sloupec nechává být, trigger nedorovnává (drží goodwill cenu);
--       - clamp-down only: slevu NIKDY nepřidá, jen OŘEŽE nadlimitní nárok
--         a rozdíl vrátí do total_price (stejná filosofie jako INSERT verze);
--       - EXCEPTION-safe — nikdy neshodí zápis rezervace.
--
-- (2) split_booking_moto_swap rev.8 — late-pickup ve výměně motorky:
--     Dosud funkce počítala čistě z _moto_dayprice_sum a sloupec
--     late_pickup_discount_amount IGNOROVALA. Důsledky (worked example:
--     den 1000 Kč, uložená sleva 500 Kč):
--       - REPLACE větev: nový total = plná cena B (sleva tiše propadla),
--         sloupec ale zůstal 500 → ZF/DP tiskly o 500 míň, KF nevyšla na 0;
--       - SPLIT větev: zkrácená A pod 2 dny si nechala slevu, na kterou už
--         nemá nárok; nová rezervace B s časem vyzvednutí >= 12:00 slevu
--         nedostala (INSERT trigger ji z principu sám nepřidá).
--     Rev.8 (model zrcadlí _apply_booking_changes_core a vznik rezervace —
--     late sleva se odečítá PŘED věrnostní %):
--       - hodnota odebraného úseku A = (ceník odebraných dnů) − (uložená late
--         sleva, pokud odebraný úsek obsahuje 1. den) + (nová late sleva
--         zbytku A) — tj. (stará netto hodnota A) − (nová netto hodnota A);
--       - cena B = ceník B − late(B) − věrnostní % z (ceník B − late(B)),
--         kde late(B) = _late_pickup_discount(nová moto, swap..end, čas
--         vyzvednutí B = p_swap_time ?? původní čas);
--       - strop vratky (rev.4) se poměřuje netto-k-netto: podíl
--         v_a_loss / (ceník celé A − uložená late sleva);
--       - REPLACE zapisuje late_pickup_discount_amount = late(B) (přepočet pro
--         novou motorku), SPLIT zapisuje A = přepočet zkráceného rozsahu
--         (kolaps pod 2 dny ⇒ 0) a B = late(B) v INSERTu.
--     Signatura beze změny (6 argumentů) → CREATE OR REPLACE, žádný overload.
--     Dry-run nese navíc late_pickup_from / late_pickup_to (parita s core).
--
-- Idempotentní: CREATE OR REPLACE + DROP TRIGGER IF EXISTS.
-- =============================================================================

-- ── (1) validate_late_pickup_discount — INSERT i UPDATE ──────────────────────
CREATE OR REPLACE FUNCTION public.validate_late_pickup_discount()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max numeric;
  v_sent numeric;
BEGIN
  BEGIN
    -- UPDATE: validuj jen skutečnou změnu sloupce — dotčené nejsou bezplatné
    -- posuny termínu, které slevu (záměrně) nechávají být.
    IF TG_OP = 'UPDATE'
       AND NEW.late_pickup_discount_amount IS NOT DISTINCT FROM OLD.late_pickup_discount_amount THEN
      RETURN NEW;
    END IF;
    v_sent := COALESCE(NEW.late_pickup_discount_amount, 0);
    IF v_sent > 0 THEN
      v_max := public._late_pickup_discount(NEW.moto_id, NEW.start_date, NEW.end_date, NEW.pickup_time);
      IF v_sent > v_max THEN
        -- klient si nárokoval víc, než pravidlo dovolí → ořež a vrať rozdíl do total_price
        NEW.total_price := COALESCE(NEW.total_price, 0) + (v_sent - v_max);
        NEW.late_pickup_discount_amount := v_max;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_late_pickup_update ON public.bookings;
CREATE TRIGGER trg_validate_late_pickup_update
  BEFORE UPDATE OF late_pickup_discount_amount ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_late_pickup_discount();

-- ── (2) split_booking_moto_swap rev.8 — late-pickup ──────────────────────────
CREATE OR REPLACE FUNCTION public.split_booking_moto_swap(
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
  -- Late-pickup sleva 50 % na 1. den (rev.8 2026-09-04).
  v_swap_time  time;        -- p_swap_time::time (NULL = beze změny času)
  v_old_late   numeric;     -- REÁLNĚ uložená sleva rezervace (ne přepočet)
  v_a_late_new numeric := 0;-- sleva zkrácené A (split; replace/kolaps ⇒ 0)
  v_b_late     numeric := 0;-- sleva nové rezervace B / replacnuté rezervace
  v_a_loss     numeric;     -- netto hodnota odebraná z A (vč. změny late)
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

  -- ── Late-pickup (rev.8): stará hodnota = ULOŽENÁ; nové hodnoty = přepočet ──
  v_swap_time := NULLIF(btrim(COALESCE(p_swap_time, '')), '')::time;
  v_old_late  := COALESCE(b.late_pickup_discount_amount, 0);
  -- Sleva nové rezervace B (u replace: replacnuté rezervace) — čas vyzvednutí
  -- B je p_swap_time, jinak původní čas rezervace.
  v_b_late := public._late_pickup_discount(
    p_new_moto_id, p_swap_date::timestamptz, b.end_date,
    COALESCE(v_swap_time, b.pickup_time));
  -- Sleva zkrácené A po splitu (kolaps pod 2 dny ⇒ helper vrací 0);
  -- u replace stará motorka mizí celá ⇒ 0.
  IF NOT v_replace THEN
    v_a_late_new := public._late_pickup_discount(
      b.moto_id, b.start_date, v_a_end::timestamptz, b.pickup_time);
  END IF;
  -- Netto hodnota odebraná z A = (stará netto A) − (nová netto A)
  --   = (v_a_full − uložená late) − ((v_a_full − v_a_removed) − v_a_late_new)
  --   = v_a_removed − v_old_late + v_a_late_new.
  -- Pokrývá replace (v_a_late_new=0, removed=celá A), split uprostřed
  -- (v_a_late_new ≈ v_old_late → loss = removed) i kolaps A pod 2 dny
  -- (v_a_late_new=0 → vratka snížená o ztracenou slevu).
  v_a_loss := GREATEST(v_a_removed - v_old_late + v_a_late_new, 0);

  -- Věrnostní sleva JEN pro app rezervace (aktuální rank zákazníka). Level = %:
  --   level = min(20, ceil((počet dokončených app rezervací + 1)/2)); % = discount_percent.
  -- Základ pro % je cena PO late slevě (parita se vznikem rezervace i core).
  IF b.booking_source = 'app' THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_b_disc := round((v_b_total - v_b_late) * v_loy_pct / 100.0);
    v_a_disc := round(v_a_loss * v_loy_pct / 100.0);
  END IF;

  -- STROP VRATKY: odebraná netto hodnota se dobropisuje max. do výše poměrné
  -- části SKUTEČNĚ zaplacené ceny pronájmu (promo/voucher/slevy → zákazník
  -- nesmí dostat zpět víc, než reálně zaplatil). Poměr netto-k-netto:
  -- zaplacený pronájem už uloženou late slevu obsahuje.
  v_a_full := _moto_dayprice_sum(b.moto_id, b.start_date::date, b.end_date::date);
  v_paid_rental := GREATEST(COALESCE(b.total_price, 0) - COALESCE(b.delivery_fee, 0) - COALESCE(b.extras_price, 0), 0);
  v_removed_paid := CASE WHEN (v_a_full - v_old_late) > 0
    THEN LEAST(round(v_paid_rental * v_a_loss / (v_a_full - v_old_late)), v_paid_rental)
    ELSE 0 END;
  v_a_credit := LEAST(v_a_loss - v_a_disc, v_removed_paid);

  -- Net = (cena B po late + věrnostní slevě) − dobropisovaná hodnota odebrané A.
  v_net := (v_b_total - v_b_late - v_b_disc) - v_a_credit;
  -- Vratka (net<0) k vypořádání po commitu; hint pro UI: bez Stripe platby
  -- půjde o manuální vratku převodem na účet (autoritativně řeší process-refund).
  v_refund := CASE WHEN p_settle_refund AND v_net < -0.5 THEN -v_net ELSE 0 END;
  v_manual := (b.stripe_payment_intent_id IS NULL AND b.stripe_session_id IS NULL);

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true, 'dry_run', true,
      'net', v_net,
      'mode', CASE WHEN v_replace THEN 'replace' ELSE 'split' END,
      'a_removed', v_a_credit, 'b_total', (v_b_total - v_b_late - v_b_disc),
      'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'late_pickup_from', v_old_late,
      'late_pickup_to', CASE WHEN v_replace THEN v_b_late ELSE v_a_late_new END,
      'late_pickup_b', v_b_late,
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
      pickup_time = COALESCE(v_swap_time, pickup_time),
      total_price = GREATEST(total_price + v_net, 0),
      late_pickup_discount_amount = v_b_late,
      modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
        'at', now(), 'type', 'moto_swap_replace', 'from_moto_id', b.moto_id,
        'new_moto_id', p_new_moto_id, 'net', v_net, 'price_diff', v_net,
        'from_late_pickup', v_old_late, 'to_late_pickup', v_b_late, 'source', 'moto_swap')
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
  --    late sloupec = přepočet pro zkrácený rozsah (kolaps pod 2 dny ⇒ 0).
  UPDATE bookings SET
    end_date = v_a_end,
    original_end_date = COALESCE(original_end_date, end_date),
    total_price = GREATEST(total_price - v_a_credit, 0),
    late_pickup_discount_amount = v_a_late_new,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || jsonb_build_object(
      'at', now(), 'type', 'moto_swap_shorten', 'to_end', v_a_end,
      'new_moto_id', p_new_moto_id, 'net', v_net,
      'from_late_pickup', v_old_late, 'to_late_pickup', v_a_late_new, 'source', 'moto_swap')
  WHERE id = p_booking_id;

  -- 2) Vytvoř druhou rezervaci B jako ZAPLACENOU (doplatek už vypořádán / vratka
  --    se dispatchne níže). Overlap s A pustí výjimka check_user_booking_overlap
  --    (continues_booking_id). B nese vlastní late slevu (čas vyzvednutí B
  --    >= 12:00 a B na 2+ dny) — cena i sloupec konzistentně; INSERT trigger
  --    trg_validate_late_pickup nadlimit jen ořeže.
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time, return_time,
    status, payment_status, total_price, delivery_fee,
    loyalty_level, loyalty_percent, loyalty_discount_amount,
    late_pickup_discount_amount,
    booking_source, continues_booking_id, notes
  ) VALUES (
    b.user_id, p_new_moto_id, p_swap_date, b.end_date, COALESCE(v_swap_time, b.pickup_time), b.return_time,
    'reserved', 'paid', GREATEST(v_b_total - v_b_late - v_b_disc, 0), 0,
    NULLIF(v_loy_level, 0), NULLIF(v_loy_pct, 0), v_b_disc,
    v_b_late,
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
