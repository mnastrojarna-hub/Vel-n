-- =============================================================================
-- NÁVRH (DRAFT) — ČEKÁ NA SCHVÁLENÍ MAJITELE (rozhodnutí D1 pro výměnu motorky
-- + D6 dokončení zaplacené výměny, 2026-10-16)
-- NEcommitovat do supabase/migrations/ bez schválení: merge do main = živá DB.
-- ZÁVISÍ na 20261016p1_card_rounding.sql (sloupec bookings.card_rounding) —
-- název souboru řadí tento soubor až za něj.
--
-- split_booking_moto_swap rev.12 = rev.11 (20260922a, = živá DB, snapshot
-- 2026-10-16) + 3 nové parametry s výchozí hodnotou (uplatní je JEN server —
-- webhook-receiver / process-payment pod service_role — nebo Velín, a jen
-- v COMMITu; zákaznický JWT je nikdy neuplatní, appka 4.1.3 / web volají jako
-- dosud):
--  • p_paid numeric — SKUTEČNĚ zaplacená částka výměny (Kč). Dorovnání
--    r = zaplaceno − net se počítá z ceny přepočtené PŘI ZÁPISU (ne z dry-runu
--    v době platby), takže cena po výměně vždy sedí se strženou částkou:
--    doplatek 1–15 Kč zaplacený 15 Kč → +r (0…14), doplatek do 1 Kč bez platby
--    → r = −net (−1…0), platba v celých Kč → |r| < 1. Jiný rozdíl = cena se
--    mezi naceněním a zápisem změnila → dorovnání se neuplatní a obsluha dostane
--    debug_log swap_paid_mismatch.
--  • p_payment_ref text — značka zaplacené výměny (id PaymentIntentu / odpuštění)
--    v historii rezervace A. Opakovaný COMMIT téže platby (webhook, Stripe retry,
--    complete_extension z appky) vrátí success + already_applied a výměnu
--    NEprovede podruhé — ani když rezervace mezitím jezdí na jiné motorce.
--  • p_card_rounding numeric (starší volání bez p_paid) — meze −1 … +14 Kč
--    a net + r ≥ 0, jinak se ignoruje (debug_log swap_rounding_ignored).
--  • REPLACE: total_price += net + r, card_rounding += r, historie
--    price_diff = net + r (+ card_rounding, payment_ref) → rozdílový DP =
--    zaplacená částka s řádkem dorovnání (generate-invoice);
--  • SPLIT: nová rezervace B má cenu + r a card_rounding = r (doklady B
--    ukážou řádek dorovnání), historie A nese payment_ref;
--  • obě odpovědi navíc vrací 'card_rounding'.
--  • COMMIT (p_dry_run = false) zamyká řádek rezervace A (SELECT … FOR UPDATE)
--    hned na začátku: webhook a appka (complete_extension) zapisují tutéž
--    zaplacenou výměnu současně — druhé volání počká na první a vrátí
--    already_applied (bez zámku se doplatek přičetl dvakrát).
-- Zbytek těla beze změny (řádky označené „rev.12").
--
-- Volání se jmennými parametry (PostgREST, appka, web, webhook) zůstávají
-- platná — nové parametry mají výchozí hodnotu. Stará 6parametrová funkce (a
-- případná 7parametrová z dřívějšího návrhu) se odstraní (jinak by PostgREST
-- hlásil nejednoznačné přetížení). Edge funkce do nasazení tohoto souboru volají
-- 6parametrovou verzi (fallback v kódu, jen u výměny bez dorovnání a JEN webhook —
-- complete_extension z appky do nasazení vrací „zkusit později", aby výměnu
-- nezapisovala dvě volání bez značky platby a bez zámku současně).
-- POŘADÍ NASAZENÍ: tento soubor PŘED vydáním appky, která volá complete_extension.
--
-- Práva jako živě (PUBLIC/anon odebrány 20261011d): authenticated + service_role.
-- Rollback: znovu spustit tělo z 20260922a_swap_rev11_admin_exempt_trailer_guard.sql
-- (po DROP 9parametrové funkce).
--
-- Idempotentní (DROP … IF EXISTS na staré signatury, CREATE OR REPLACE).
-- Bez BEGIN/COMMIT. Po aplikaci aktualizovat SUPABASE_BACKEND_STATE_3 (RPC)
-- a _6 (changelog).
-- =============================================================================

DROP FUNCTION IF EXISTS public.split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean);
DROP FUNCTION IF EXISTS public.split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean, numeric);

CREATE OR REPLACE FUNCTION public.split_booking_moto_swap(p_booking_id uuid, p_new_moto_id uuid, p_swap_date date, p_swap_time text DEFAULT NULL::text, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false, p_card_rounding numeric DEFAULT 0, p_paid numeric DEFAULT NULL::numeric, p_payment_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- rev.12 (D1/D6 2026-10-16): dorovnání na minimální platbu kartou (+) /
  -- odpuštěný doplatek do 1 Kč (−) a značka zaplacené výměny. Jen server/Velín.
  v_round   numeric := 0;
  v_r       numeric;
  v_pref    text := CASE WHEN p_dry_run THEN NULL ELSE NULLIF(btrim(COALESCE(p_payment_ref, '')), '') END;
  v_done    jsonb;
BEGIN
  -- rev.12 (D6 2026-10-16): COMMIT zamkne řádek rezervace HNED na začátku.
  -- Webhook (payment_intent.succeeded) a appka (complete_extension) zapisují
  -- tutéž zaplacenou výměnu současně: bez zámku obě volání přečetla starý řádek,
  -- obě prošla kontrolou payment_ref i invalid_new_moto a druhé pak přičetlo
  -- doplatek + dorovnání k ceně PODRUHÉ (ověřeno na lokální PG: 3000 → 3030
  -- místo 3015). Se zámkem druhé volání počká, přečte zapsaný řádek a vrátí
  -- already_applied. Dry-run (nacenění) nic nezapisuje → bez zámku.
  IF p_dry_run THEN
    SELECT * INTO b FROM bookings WHERE id = p_booking_id;
  ELSE
    SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  END IF;
  IF b.id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF NOT v_admin AND (v_uid IS NULL OR b.user_id IS DISTINCT FROM v_uid) THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  -- rev.12 (D6 2026-10-16): značka zaplacené výměny (payment_ref = PaymentIntent /
  -- odpuštění) zapisuje jen server/Velín. Opakovaný COMMIT téže platby (webhook ↔
  -- complete_extension ↔ process-payment, Stripe retry) se NEprovede podruhé —
  -- ani když rezervace mezitím jezdí na jiné motorce (bezplatná výměna, Velín).
  IF NOT v_admin THEN v_pref := NULL; END IF;
  IF v_pref IS NOT NULL THEN
    SELECT e INTO v_done FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(b.modification_history) = 'array' THEN b.modification_history ELSE '[]'::jsonb END) e
     WHERE e->>'payment_ref' = v_pref LIMIT 1;
    IF v_done IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'already_applied', true,
        'mode', CASE WHEN v_done->>'type' = 'moto_swap_shorten' THEN 'split' ELSE 'replace' END,
        'new_booking_id', CASE WHEN v_done->>'type' = 'moto_swap_shorten'
          THEN (SELECT s.id FROM bookings s WHERE s.continues_booking_id = p_booking_id
                 ORDER BY s.created_at DESC LIMIT 1)
          ELSE p_booking_id END,
        'card_rounding', COALESCE((v_done->>'card_rounding')::numeric, 0));
    END IF;
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
  -- rev.10 2026-09-21 (20260921h): rezervace s vozíkem nesmí přejet na motorku ze
  -- SAMOOBSLUŽNÉ pobočky — u REPLACE i u SPLITu. rev.9 blokovala jen REPLACE
  -- (datově u SPLITu vozík zůstává na rezervaci A), jenže FYZICKY s vozíkem
  -- zákazník dojede na samoobslužnou pobočku, kde ho nemá kdo převzít (pevná
  -- sestava 7 kójí + šatna, výdej 24/7 kódem). Mezi ranými validacemi → vrací se
  -- i v p_dry_run, tedy PŘED platbou (web i appka mají kód namapovaný).
  -- rev.11 2026-09-22 (20260922a): `NOT v_admin` — stejná politika jako trigger
  -- trg_check_trailer_overlap (is_admin / service_role vyjmuti). Každý ZÁKAZNICKÝ
  -- dry-run (web, appka, process-payment pod JWT volajícího) dál blokuje PŘED
  -- platbou; jen COMMIT po zaplacení (webhook-receiver pod service_role) v závodu
  -- „motorka přesunuta na samoobsluhu mezi dry-runem a webhookem" projde, aby
  -- zákazník nezůstal se strženými penězi a neprovedenou výměnou. Vozík u takové
  -- rezervace řeší obsluha (Velín u úpravy rezervace varuje).
  IF NOT v_admin AND b.trailer_moto_id IS NOT NULL AND public.moto_is_self_service(p_new_moto_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'trailer_staffed_only');
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

  -- rev.12 (D1 2026-10-16): server (webhook-receiver / process-payment pod
  -- service_role) nebo Velín předá SKUTEČNĚ zaplacenou částku p_paid (Kč) →
  -- dorovnání r = zaplaceno − net (net přepočtený TEĎ, ne z dry-runu v době
  -- platby). Platí jen v mezích: |r| < 1 (platba v celých Kč), 15 Kč za doplatek
  -- 1–15 Kč (r 0…14), 0 Kč za doplatek do 1 Kč (r −1…0). Jinak se cena mezi
  -- naceněním a zápisem změnila → dorovnání se neuplatní a obsluha dostane záznam
  -- swap_paid_mismatch (zaplaceno ≠ cena). Bez p_paid (starší volání) platí
  -- p_card_rounding v mezích −1 … +14 Kč. Zákaznický JWT nic z toho neuplatní.
  IF v_admin AND NOT p_dry_run THEN
    IF p_paid IS NOT NULL THEN
      v_r := round(p_paid - v_net, 2);
      IF v_r <> 0 THEN
        IF abs(v_r) < 1 OR (p_paid = 15 AND v_r BETWEEN 0 AND 14) OR (p_paid = 0 AND v_r BETWEEN -1 AND 0) THEN
          v_round := v_r;
        ELSE
          BEGIN
            INSERT INTO debug_log(source, action, status, error_message, request_data)
            VALUES ('split_booking_moto_swap', 'swap_paid_mismatch', 'error',
                    'Zaplacená částka výměny neodpovídá aktuální ceně — zkontrolujte doplatek/vratku',
                    jsonb_build_object('booking_id', p_booking_id, 'net', v_net, 'paid', p_paid, 'payment_ref', v_pref));
          EXCEPTION WHEN OTHERS THEN NULL;
          END;
        END IF;
      END IF;
    ELSIF COALESCE(p_card_rounding, 0) <> 0 THEN
      IF p_card_rounding BETWEEN -1 AND 14 AND v_net + p_card_rounding >= 0 THEN
        v_round := p_card_rounding;
      ELSE
        BEGIN
          INSERT INTO debug_log(source, action, status, request_data)
          VALUES ('split_booking_moto_swap', 'swap_rounding_ignored', 'warning',
                  jsonb_build_object('booking_id', p_booking_id, 'net', v_net, 'card_rounding', p_card_rounding));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
    END IF;
  END IF;

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
      total_price = GREATEST(total_price + v_net + v_round, 0),               -- rev.12
      card_rounding = COALESCE(card_rounding, 0) + v_round,                  -- rev.12
      late_pickup_discount_amount = v_b_late,
      modification_history = COALESCE(modification_history, '[]'::jsonb) || (jsonb_build_object(
        'at', now(), 'type', 'moto_swap_replace', 'from_moto_id', b.moto_id,
        'new_moto_id', p_new_moto_id, 'net', v_net, 'price_diff', v_net + v_round,
        'from_late_pickup', v_old_late, 'to_late_pickup', v_b_late, 'source', 'moto_swap')
        || CASE WHEN v_round <> 0 THEN jsonb_build_object('card_rounding', v_round) ELSE '{}'::jsonb END   -- rev.12
        || CASE WHEN v_pref IS NOT NULL THEN jsonb_build_object('payment_ref', v_pref) ELSE '{}'::jsonb END)
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
      'mode', 'replace', 'refund_amount', v_refund, 'refund_manual', v_manual,
      'card_rounding', v_round);
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
    modification_history = COALESCE(modification_history, '[]'::jsonb) || (jsonb_build_object(
      'at', now(), 'type', 'moto_swap_shorten', 'to_end', v_a_end,
      'new_moto_id', p_new_moto_id, 'net', v_net,
      'from_late_pickup', v_old_late, 'to_late_pickup', v_a_late_new, 'source', 'moto_swap')
      || CASE WHEN v_pref IS NOT NULL THEN jsonb_build_object('payment_ref', v_pref) ELSE '{}'::jsonb END)   -- rev.12
  WHERE id = p_booking_id;

  -- 2) Vytvoř druhou rezervaci B jako ZAPLACENOU (doplatek už vypořádán / vratka
  --    se dispatchne níže). Overlap s A pustí výjimka check_user_booking_overlap
  --    (continues_booking_id). B nese vlastní late slevu (čas vyzvednutí B
  --    >= 12:00 a B na 2+ dny) — cena i sloupec konzistentně; INSERT trigger
  --    trg_validate_late_pickup nadlimit jen ořeže.
  INSERT INTO bookings (
    user_id, moto_id, start_date, end_date, pickup_time, return_time,
    status, payment_status, total_price, card_rounding, delivery_fee,
    loyalty_level, loyalty_percent, loyalty_discount_amount,
    late_pickup_discount_amount,
    booking_source, continues_booking_id, notes
  ) VALUES (
    b.user_id, p_new_moto_id, p_swap_date, b.end_date, COALESCE(v_swap_time, b.pickup_time), b.return_time,
    'reserved', 'paid', GREATEST(v_b_total - v_b_late - v_b_disc + v_round, 0), v_round,   -- rev.12
    0,
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
    'mode', 'split', 'refund_amount', v_refund, 'refund_manual', v_manual,
    'card_rounding', v_round);
END;
$function$;

REVOKE ALL ON FUNCTION public.split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean, numeric, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean, numeric, numeric, text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- S3b (VOLITELNÉ, NEZAPNUTO — čeká na samostatné rozhodnutí majitele, F2):
-- zákazník by nesměl COMMITnout výměnu s doplatkem > 1 Kč bez platby (dnes jde
-- RPC zavolat přímo a výměnu tak získat zadarmo). Dopad: klientský commit
-- appky 4.1.3 a webu po návratu ze Stripe dostane 'payment_required' a výměnu
-- dokončí webhook (od D6 s opakováním) — web by do úpravy mapování ukázal
-- obecnou chybu. Zapnutí = vložit do těla funkce hned za blok „rev.12" (před
-- IF p_dry_run):
--
--   IF NOT p_dry_run AND NOT v_admin AND v_net > 1 THEN
--     RETURN jsonb_build_object('success', false, 'error', 'payment_required');
--   END IF;
-- -----------------------------------------------------------------------------

NOTIFY pgrst, 'reload schema';
