-- =============================================================================
-- NÁVRH (DRAFT) — ČEKÁ NA SCHVÁLENÍ MAJITELE (rozhodnutí D1 — dorovnání na
-- minimální platbu kartou u placené výbavy + doklady ke každé změně ceny, 2026-10-16)
-- NEcommitovat do supabase/migrations/ bez schválení: merge do main = živá DB.
-- ZÁVISÍ na 20261016p1_card_rounding.sql (sloupec bookings.card_rounding a pojistka
-- _protect_card_rounding s výjimkou motogo.gear_card_rounding) — název souboru
-- řadí tento soubor až za p1–p3.
--
-- Proč: mail „Rezervace upravena" s rozdílovým dokladem (DP) posílá trigger
-- trg_send_booking_modified_email; druhý zápis do 5 min (resp. 60 s) přeskočí
-- (deduplikace). Dorovnání zaplacené výbavy (doplatek 3 Kč zaplacený 15 Kč) se
-- dosud zapisovalo ZVLÁŠŤ hned po změně výbavy → DP vznikl jen na 3 Kč, karta
-- zaplatila 15 Kč a konečná faktura pak ukázala 12 Kč „k doplacení". Totéž
-- u každé druhé změny ceny do 5 min (web zapíše termín, webhook pak cenu; dvě
-- placené úpravy po sobě) — ta doklad neměla vůbec. Odpuštěná výbava 0,60 Kč
-- dostala dokonce DP na 1 Kč za platbu, která neproběhla.
--
-- Co dělá tento soubor:
--  1) apply_paid_gear_change rev.2 (jen service_role — webhook-receiver /
--     process-payment): nové volitelné parametry p_paid (skutečně zaplaceno, Kč),
--     p_card_rounding (starší volání bez p_paid), p_payment_ref (značka platby)
--     a p_chg_hash (otisk změny). Zamkne řádek, opakování téže platby
--     (payment_ref v historii) nic neprovede (already_applied). Dorovnání
--     r = zaplaceno − doplatek spočítá ze SKUTEČNÉHO doplatku při zápisu (dry-run
--     ve stejné transakci): doplatek 1–15 Kč zaplacený 15 Kč → +r (0…14), do 1 Kč
--     bez platby → r = −doplatek (−1…0), platba v celých Kč → |r| < 1; jiný rozdíl
--     = debug_log gear_paid_mismatch (r = 0, rozhodne obsluha). Doplatek 0 (změnu
--     už zapsal web po návratu ze Stripe) → bez dorovnání. Dorovnání předá
--     update_booking_gear transakční proměnnou a ta ho zapíše v TÉMŽE UPDATE jako
--     změnu výbavy (cena + card_rounding) → JEDEN mail a DP na zaplacenou částku
--     s řádkem dorovnání (generate-invoice podle záznamu v historii). Záznam
--     výbavy v historii (track_booking_content_changes) doplní o price_diff,
--     card_rounding, paid, payment_ref a chg_hash (zápis jen historie mail nespouští;
--     při doplatku 0 se nezapisuje nic — dorovnání pak dopíše webhook samostatně).
--  2) update_booking_gear: tělo 1:1 podle živé DB (snapshot 2026-10-16, poslední
--     repo verze 20261005h) + řádky „D1 20261016p4": dorovnání z proměnné
--     motogo.gear_card_rounding = '<id rezervace>:<Kč>' (nastavuje JEN
--     apply_paid_gear_change; zákazník ji přes PostgREST nastavit nemůže) jde do
--     total_price i card_rounding; odpověď navíc vrací card_rounding. Zákaznická
--     volání (appka, web) beze změny (dorovnání 0).
--  3) trg_send_booking_modified_email: tělo 1:1 podle živé DB (poslední repo verze
--     20261001f), deduplikace (5 min message_log / 60 s http_post_queued) platí jen
--     pro zápis, který NEMĚNÍ total_price. Každá změna ceny tak dostane mail
--     a rozdílový doklad (DP; u snížení přiloží dobropis vystavený process-refund
--     — tamní dohledání je jen „recovery", novou vratku nikdy nevytvoří).
--
-- Volání se jmennými parametry (webhook, process-payment) zůstávají platná —
-- nové parametry mají výchozí hodnotu; stará 2parametrová funkce se odstraní
-- (jinak by PostgREST hlásil nejednoznačné přetížení). Edge funkce do nasazení
-- tohoto souboru volají 2parametrovou verzi (fallback v kódu) a dorovnání
-- výbavy process-payment bez tohoto souboru nepovolí (rounding_unavailable).
-- POŘADÍ NASAZENÍ: p1 → p4 (stejný merge), edge funkce kdykoli.
--
-- Práva jako živě: apply_paid_gear_change jen service_role (PUBLIC/anon/
-- authenticated odebráno — výchozí práva schématu by je jinak novému objektu
-- přidala), update_booking_gear authenticated + service_role.
-- Rollback: znovu spustit těla z živé DB / 20261005h (update_booking_gear),
-- 20261001f (trigger) a 2parametrovou apply_paid_gear_change (po DROP nové).
--
-- Idempotentní (DROP … IF EXISTS na starou signaturu, CREATE OR REPLACE).
-- Bez BEGIN/COMMIT. Po aplikaci aktualizovat SUPABASE_BACKEND_STATE_3 (RPC),
-- _4 (trigger) a _6 (changelog).
-- =============================================================================

-- ── 1) apply_paid_gear_change rev.2 ───────────────────────────────────────────
DROP FUNCTION IF EXISTS public.apply_paid_gear_change(uuid, jsonb);

CREATE OR REPLACE FUNCTION public.apply_paid_gear_change(p_booking_id uuid, p_sizes jsonb, p_paid numeric DEFAULT NULL::numeric, p_card_rounding numeric DEFAULT 0, p_payment_ref text DEFAULT NULL::text, p_chg_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_user    uuid;
  v_res     jsonb;
  v_dry     jsonb;
  v_hist    jsonb;
  v_last    jsonb;
  v_entry   jsonb;
  v_n       int;
  v_pref    text := NULLIF(btrim(COALESCE(p_payment_ref, '')), '');
  v_hash    text := NULLIF(btrim(COALESCE(p_chg_hash, '')), '');
  v_net     numeric := 0;
  v_r       numeric := 0;
  v_applied numeric := 0;
BEGIN
  -- Zámek řádku: webhook a complete_extension mohou tutéž platbu dokončovat současně
  -- (druhé volání počká a najde značku platby v historii).
  SELECT user_id,
         CASE WHEN jsonb_typeof(modification_history) = 'array' THEN modification_history ELSE '[]'::jsonb END
    INTO v_user, v_hist
    FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_user IS NULL THEN RETURN jsonb_build_object('success',false,'error','not_found'); END IF;

  -- Opakování téže platby (Stripe retry, complete_extension) → nic podruhé.
  IF v_pref IS NOT NULL AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_hist) e
        WHERE jsonb_typeof(e) = 'object' AND e->>'payment_ref' = v_pref) THEN
    RETURN jsonb_build_object('success', true, 'already_applied', true, 'net_diff', 0, 'card_rounding', 0);
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user::text)::text, true);

  -- D1: dorovnání / odpuštění ze SKUTEČNÉHO doplatku při zápisu (dry-run ve stejné
  -- transakci nad zamčeným řádkem = přesně to, co zapíše commit níže).
  IF p_paid IS NOT NULL OR COALESCE(p_card_rounding, 0) <> 0 THEN
    v_dry := update_booking_gear(p_booking_id, p_sizes, true);
    IF COALESCE((v_dry->>'success')::boolean, false) THEN
      v_net := COALESCE((v_dry->>'net_diff')::numeric, 0);
      -- doplatek 0 = změnu už zapsal někdo jiný (web po návratu ze Stripe) → bez dorovnání
      IF v_net > 0 THEN
        IF p_paid IS NOT NULL THEN
          v_r := round(p_paid - v_net, 2);
          IF NOT (abs(v_r) < 1 OR (p_paid = 15 AND v_r BETWEEN 0 AND 14) OR (p_paid = 0 AND v_r BETWEEN -1 AND 0)) THEN
            INSERT INTO debug_log(source, action, status, request_data)
            VALUES ('apply_paid_gear_change', 'gear_paid_mismatch', 'error',
                    jsonb_build_object('booking_id', p_booking_id, 'net', v_net, 'paid', p_paid, 'payment_ref', v_pref));
            v_r := 0;
          END IF;
        ELSIF p_card_rounding BETWEEN -1 AND 14 AND v_net + p_card_rounding >= 0 THEN
          v_r := round(p_card_rounding, 2);
        ELSE
          INSERT INTO debug_log(source, action, status, request_data)
          VALUES ('apply_paid_gear_change', 'gear_rounding_ignored', 'error',
                  jsonb_build_object('booking_id', p_booking_id, 'net', v_net, 'card_rounding', p_card_rounding, 'payment_ref', v_pref));
        END IF;
      END IF;
    END IF;
  END IF;

  IF v_r <> 0 THEN
    PERFORM set_config('motogo.gear_card_rounding', p_booking_id::text || ':' || v_r::text, true);
  END IF;
  v_res := update_booking_gear(p_booking_id, p_sizes, false);
  PERFORM set_config('motogo.gear_card_rounding', '', true);
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RETURN v_res;
  END IF;
  v_applied := COALESCE((v_res->>'card_rounding')::numeric, 0);

  -- Historie: zaplaceno / dorovnání + značka platby na záznamu TÉTO změny (generate-invoice
  -- z něj bere řádek dorovnání DP; payment_ref = deduplikace opakování). Záznam výbavy,
  -- který v tomto UPDATE přidal track_booking_content_changes (auto, at = now()), se
  -- doplní, jinak nový záznam. Zápis jen historie mail ani doklad nespouští.
  -- Nic se nezměnilo (doplatek 0 — změnu už zapsal web) → bez záznamu: dorovnání pak
  -- dopíše webhook samostatně i se značkou platby (extension-apply roundingFixup).
  IF COALESCE((v_res->>'net_diff')::numeric, 0) <> 0 OR v_applied <> 0 THEN
    SELECT CASE WHEN jsonb_typeof(modification_history) = 'array' THEN modification_history ELSE '[]'::jsonb END
      INTO v_hist FROM bookings WHERE id = p_booking_id;
    v_entry := jsonb_build_object('price_diff', COALESCE((v_res->>'net_diff')::numeric, 0) + v_applied)
      || CASE WHEN v_applied <> 0 THEN jsonb_build_object('card_rounding', v_applied) ELSE '{}'::jsonb END
      || CASE WHEN p_paid IS NOT NULL THEN jsonb_build_object('paid', p_paid) ELSE '{}'::jsonb END
      || CASE WHEN v_pref IS NOT NULL THEN jsonb_build_object('payment_ref', v_pref) ELSE '{}'::jsonb END
      || CASE WHEN v_hash IS NOT NULL THEN jsonb_build_object('chg_hash', v_hash) ELSE '{}'::jsonb END;
    v_n := jsonb_array_length(v_hist);
    v_last := CASE WHEN v_n > 0 THEN v_hist -> (v_n - 1) END;
    IF v_last IS NOT NULL AND jsonb_typeof(v_last) = 'object' AND v_last->>'auto' = 'true'
       AND v_last->>'at' = to_jsonb(now()) #>> '{}' THEN
      v_hist := jsonb_set(v_hist, ARRAY[(v_n - 1)::text], v_last || v_entry);
    ELSE
      v_hist := v_hist || jsonb_build_array(
        jsonb_build_object('at', now(), 'type', 'gear_change', 'source', 'stripe_webhook') || v_entry);
    END IF;
    UPDATE bookings SET modification_history = v_hist WHERE id = p_booking_id;
  END IF;

  RETURN v_res || jsonb_build_object('card_rounding', v_applied);
END
$$;

REVOKE ALL ON FUNCTION public.apply_paid_gear_change(uuid, jsonb, numeric, numeric, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_paid_gear_change(uuid, jsonb, numeric, numeric, text, text) TO service_role;

-- ── 2) update_booking_gear: tělo 1:1 se živou DB, nové řádky „D1 20261016p4" ─────
CREATE OR REPLACE FUNCTION public.update_booking_gear(p_booking_id uuid, p_sizes jsonb, p_dry_run boolean DEFAULT false, p_settle_refund boolean DEFAULT false, p_own_gear boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  -- NOVÉ 2026-09-15: od ranku 3 je placená výbava u APP rezervací zdarma
  -- (parita s appkou: booking_models.dart loyaltyFreeGearLevel = 3).
  v_gear_free boolean := false;
  v_loy_pct numeric := 0;
  v_loy_disc numeric := 0;
  v_refund numeric := 0;
  v_manual boolean := false;
  v_url text; v_key text;
  v_round numeric := 0;   -- D1 20261016p4: dorovnání zaplacené výbavy (jen apply_paid_gear_change)
  v_gucr  text;            -- D1 20261016p4
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

  -- Rank spočítej VŽDY (ne jen u doplatku) — rozhoduje o nároku na výbavu
  -- zdarma. Gate na booking_source='app' je stejný jako u věrnostní % slevy:
  -- web rezervace nemá věrnostní výhodu, ať ji upravuje kdokoli odkudkoli.
  IF COALESCE(b.booking_source, 'web') = 'app' THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(b.user_id) + 1) / 2.0))::int;
    v_gear_free := v_loy_level >= 3;
  END IF;

  s_h  := NULLIF(p_sizes->>'helmet','');  s_j := NULLIF(p_sizes->>'jacket','');
  s_p  := NULLIF(p_sizes->>'pants','');   s_b := NULLIF(p_sizes->>'boots','');
  s_g  := NULLIF(p_sizes->>'gloves','');
  s_ph := NULLIF(p_sizes->>'passenger_helmet','');  s_pj := NULLIF(p_sizes->>'passenger_jacket','');
  s_pp_:= NULLIF(p_sizes->>'passenger_pants','');   s_pb := NULLIF(p_sizes->>'passenger_boots','');
  s_pg := NULLIF(p_sizes->>'passenger_gloves','');

  v_new_pass := (s_ph IS NOT NULL OR s_pj IS NOT NULL OR s_pp_ IS NOT NULL OR s_pg IS NOT NULL);
  v_new_br   := (s_b  IS NOT NULL);
  v_new_bp   := (s_pb IS NOT NULL);
  IF v_new_pass THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pp  END; END IF;
  IF v_new_br   THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pbr END; END IF;
  IF v_new_bp   THEN v_new_paid := v_new_paid + CASE WHEN v_gear_free THEN 0 ELSE v_pbp END; END IF;

  -- OPRAVA 2026-09-15: baseline = co je REÁLNĚ uložené v booking_extras, ne
  -- dnešní ceník. Původní verze dopočítávala cenu z NÁZVU řádku, takže řádek
  -- za 0 Kč (výbava zdarma od ranku 3) ocenila plnou cenou → při odebrání
  -- výbavy se vracely peníze, které zákazník nikdy nezaplatil. Filtr je
  -- shodný s DELETE níže, aby se nepočítaly nemodelované doplňky (vozík…).
  -- 2026-10-05: názvy řádků z webu jsou v jazyce zákazníka (Stiefel Fahrer, Buty kierowca…) → _booking_extra_is_gear.
  SELECT COALESCE(ROUND(SUM(COALESCE(unit_price,0) * COALESCE(quantity,1))),0)::int
  INTO v_old_paid FROM booking_extras WHERE booking_id = p_booking_id
    AND public._booking_extra_is_gear(name);

  v_diff := v_new_paid - v_old_paid;

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — app rezervace, kladný rozdíl výbavy ──
  -- Výbava je součást loyalty base i při vzniku rezervace; doplatek za
  -- přidanou výbavu se sníží o pct dle aktuálního ranku.
  IF COALESCE(b.booking_source, 'web') = 'app' AND v_diff > 0 THEN
    -- v_loy_level je spočítaný výše (nároky na výbavu zdarma) — nepočítat 2×.
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

  -- D1 20261016p4: dorovnání / odpuštění zaplacené výbavy předává JEN apply_paid_gear_change
  -- (service_role) transakční proměnnou motogo.gear_card_rounding = '<id rezervace>:<Kč>' —
  -- zákazník ji přes PostgREST nastavit nemůže. Zapíše se v TÉMŽE UPDATE jako změna výbavy,
  -- takže mail o úpravě i rozdílový DP nesou zaplacenou částku (dřív druhý zápis dorovnání
  -- spadl do 5min deduplikace mailu a DP chyběl). Meze jako u výměny: −1 … +14 Kč, jen
  -- u doplatku (net > 0) a výsledek net + r ≥ 0.
  v_gucr := COALESCE(current_setting('motogo.gear_card_rounding', true), '');
  IF v_gucr <> '' AND split_part(v_gucr, ':', 1) = p_booking_id::text THEN
    BEGIN
      v_round := round(COALESCE(NULLIF(split_part(v_gucr, ':', 2), '')::numeric, 0), 2);
    EXCEPTION WHEN OTHERS THEN
      v_round := 0;
    END;
    IF v_net_diff <= 0 OR v_round < -1 OR v_round > 14 OR v_net_diff + v_round < 0 THEN
      v_round := 0;
    END IF;
  END IF;

  UPDATE bookings SET
    helmet_size=s_h, jacket_size=s_j, pants_size=s_p, boots_size=s_b, gloves_size=s_g,
    passenger_helmet_size = CASE WHEN v_new_pass THEN s_ph  ELSE NULL END,
    passenger_jacket_size = CASE WHEN v_new_pass THEN s_pj  ELSE NULL END,
    passenger_pants_size  = CASE WHEN v_new_pass THEN s_pp_ ELSE NULL END,
    passenger_gloves_size = CASE WHEN v_new_pass THEN s_pg  ELSE NULL END,
    passenger_boots_size  = CASE WHEN v_new_bp   THEN s_pb  ELSE NULL END,
    -- 2026-09-25: vlastní výbava (NULL = beze změny) → trg_sync_locker_code řeší kód šatny
    -- 2026-10-05: nově doplněná velikost helmy/bundy/kalhot/rukavic u „vlastní výbavy“ (web úprava posílá
    -- p_own_gear NULL) = zákazník výbavu chce → own_gear false → trg_sync_locker_code vydá kód šatny + zprávu + mail
    own_gear = COALESCE(p_own_gear,
                 CASE WHEN b.own_gear IS TRUE AND (
                        (s_h IS NOT NULL AND s_h IS DISTINCT FROM b.helmet_size)
                     OR (s_j IS NOT NULL AND s_j IS DISTINCT FROM b.jacket_size)
                     OR (s_p IS NOT NULL AND s_p IS DISTINCT FROM b.pants_size)
                     OR (s_g IS NOT NULL AND s_g IS DISTINCT FROM b.gloves_size))
                      THEN false ELSE own_gear END),
    extras_price = GREATEST(0, COALESCE(extras_price,0) + v_diff),
    total_price  = v_new_total + v_round,                         -- D1 20261016p4
    card_rounding = COALESCE(card_rounding, 0) + v_round,         -- D1 20261016p4
    discount_amount = v_new_discount,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level   = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END
  WHERE id = p_booking_id;

  DELETE FROM booking_extras WHERE booking_id = p_booking_id
    AND public._booking_extra_is_gear(name);
  -- Řádky se ukládají za cenu, která se SKUTEČNĚ účtovala (0 Kč od ranku 3),
  -- aby SUM(booking_extras.unit_price) = bookings.extras_price a faktury
  -- (ZF/DP/KF) vykázaly správnou cenu pronájmu.
  IF v_new_pass THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Výbava spolujezdce',CASE WHEN v_gear_free THEN 0 ELSE v_pp  END,1); END IF;
  IF v_new_br   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty řidič',      CASE WHEN v_gear_free THEN 0 ELSE v_pbr END,1); END IF;
  IF v_new_bp   THEN INSERT INTO booking_extras(booking_id,name,unit_price,quantity) VALUES (p_booking_id,'Boty spolujezdce',CASE WHEN v_gear_free THEN 0 ELSE v_pbp END,1); END IF;

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
    'card_rounding', v_round,                                                  -- D1 20261016p4
    'new_total', v_new_total + v_round, 'gross_diff', v_diff, 'new_discount', v_new_discount,
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level);
END;
$$;

REVOKE ALL ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_booking_gear(uuid, jsonb, boolean, boolean, boolean) TO authenticated, service_role;

-- ── 3) Mail o úpravě: deduplikace jen u zápisu bez změny ceny ─────────────────
-- Tělo 1:1 se živou DB; změněný je jen blok deduplikace (označený „20261016p4").
CREATE OR REPLACE FUNCTION public.trg_send_booking_modified_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
  v_url text;
  v_key text;
  v_profile profiles%ROWTYPE;
  v_moto_old text;
  v_moto_new text;
  v_already_sent boolean;
  v_changed boolean;
  v_payload jsonb;
  v_price_diff numeric;
  v_app_msg text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_status_change','info',
            jsonb_build_object('booking_id',NEW.id,'old_status',OLD.status,'new_status',NEW.status));
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('reserved','active') THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_status_not_eligible','info',
            jsonb_build_object('booking_id',NEW.id,'status',NEW.status));
    RETURN NEW;
  END IF;

  v_changed :=
       NEW.moto_id        IS DISTINCT FROM OLD.moto_id
    OR NEW.start_date     IS DISTINCT FROM OLD.start_date
    OR NEW.end_date       IS DISTINCT FROM OLD.end_date
    OR NEW.total_price    IS DISTINCT FROM OLD.total_price
    OR NEW.pickup_method  IS DISTINCT FROM OLD.pickup_method
    OR NEW.pickup_address IS DISTINCT FROM OLD.pickup_address
    OR NEW.pickup_time    IS DISTINCT FROM OLD.pickup_time
    OR NEW.return_method  IS DISTINCT FROM OLD.return_method
    OR NEW.return_address IS DISTINCT FROM OLD.return_address
    OR NEW.return_time    IS DISTINCT FROM OLD.return_time;

  IF NOT v_changed THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_field_change','info',
            jsonb_build_object(
              'booking_id',NEW.id,
              'old',jsonb_build_object('moto',OLD.moto_id,'start',OLD.start_date,'end',OLD.end_date,'total',OLD.total_price,'pickup_method',OLD.pickup_method,'pickup_time',OLD.pickup_time,'return_method',OLD.return_method,'return_time',OLD.return_time),
              'new',jsonb_build_object('moto',NEW.moto_id,'start',NEW.start_date,'end',NEW.end_date,'total',NEW.total_price,'pickup_method',NEW.pickup_method,'pickup_time',NEW.pickup_time,'return_method',NEW.return_method,'return_time',NEW.return_time)
            ));
    RETURN NEW;
  END IF;

  SELECT model INTO v_moto_old FROM motorcycles WHERE id = OLD.moto_id;
  SELECT model INTO v_moto_new FROM motorcycles WHERE id = NEW.moto_id;

  SELECT * INTO v_profile FROM profiles WHERE id = NEW.user_id;

  v_payload := jsonb_build_object(
    'booking_id', NEW.id,
    'customer_email', COALESCE(v_profile.email,''),
    'customer_name', COALESCE(v_profile.full_name,''),
    'source', COALESCE(NEW.booking_source,'app'),
    'motorcycle', COALESCE(v_moto_new,''),
    'start_date', NEW.start_date,
    'end_date', NEW.end_date,
    'total_price', NEW.total_price,
    'price_difference', COALESCE(NEW.total_price,0) - COALESCE(OLD.total_price,0),
    'pickup_method', COALESCE(NEW.pickup_method,''),
    'pickup_address', COALESCE(NEW.pickup_address,''),
    'pickup_time', COALESCE(NEW.pickup_time::text,''),
    'return_method', COALESCE(NEW.return_method,''),
    'return_address', COALESCE(NEW.return_address,''),
    'return_time', COALESCE(NEW.return_time::text,''),
    'original_motorcycle', COALESCE(v_moto_old,''),
    'original_start_date', OLD.start_date,
    'original_end_date', OLD.end_date,
    'original_total_price', OLD.total_price,
    'original_pickup_method', COALESCE(OLD.pickup_method,''),
    'original_pickup_address', COALESCE(OLD.pickup_address,''),
    'original_pickup_time', COALESCE(OLD.pickup_time::text,''),
    'original_return_method', COALESCE(OLD.return_method,''),
    'original_return_address', COALESCE(OLD.return_address,''),
    'original_return_time', COALESCE(OLD.return_time::text,'')
  );

  -- NOVÉ (2026-07-27): úprava s nezaplaceným doplatkem → mail ODLOŽIT.
  -- Payload se uschová a odešle ho confirm_booking_surcharge po potvrzení platby
  -- (zákazník mezitím dostane výzvu k platbě ze šablony booking_qr_payment přes
  -- edge fn qr-payment v režimu surcharge). Interní UPDATE nemění žádné sledované
  -- pole → rekurze se zastaví na skipped_no_field_change.
  IF COALESCE(NEW.mod_surcharge_due, 0) > 0 THEN
    BEGIN
      UPDATE bookings SET mod_email_payload = v_payload WHERE id = NEW.id;
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('trg_booking_modified_email','deferred_surcharge_pending','info',
              jsonb_build_object('booking_id',NEW.id,'surcharge_due',NEW.mod_surcharge_due));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('trg_booking_modified_email','deferred_payload_store_failed','error',SQLERRM,
              jsonb_build_object('booking_id',NEW.id));
    END;
    RETURN NEW;
  END IF;

  -- 2026-10-16 (D1, 20261016p4): deduplikace JEN u zápisu, který NEMĚNÍ cenu
  -- (druhý zápis téže úpravy — web: RPC + přímý zápis času). Zápis se změnou ceny
  -- mail + rozdílový doklad (DP / dobropis) dostane vždy: dřív druhá změna ceny do
  -- 5 min (web zapíše termín, webhook pak cenu; dvě placené úpravy po sobě;
  -- dorovnání na 15 Kč zapsané zvlášť) doklad vůbec neměla.
  IF NEW.total_price IS NOT DISTINCT FROM OLD.total_price THEN
    SELECT EXISTS(
      SELECT 1 FROM message_log
       WHERE booking_id = NEW.id AND template_slug LIKE 'booking_modified%'
         AND status = 'sent' AND created_at > now() - interval '5 minutes' LIMIT 1
    ) INTO v_already_sent;
    -- 2026-10-01: message_log zapíše až edge funkce (asynchronně po commitu), takže
    -- druhý UPDATE téže úpravy hned po prvním (web: RPC + přímý zápis času) ho
    -- ještě neviděl → zákazník dostal 2 maily. Synchronní stopa = vlastní řádek
    -- 'http_post_queued' v debug_log (commitnutý s prvním UPDATE).
    IF NOT v_already_sent THEN
      SELECT EXISTS(
        SELECT 1 FROM debug_log
         WHERE created_at > now() - interval '60 seconds'
           AND source = 'trg_booking_modified_email' AND action = 'http_post_queued'
           AND request_data->>'booking_id' = NEW.id::text LIMIT 1
      ) INTO v_already_sent;
    END IF;
    IF v_already_sent THEN
      INSERT INTO debug_log(source, action, status, request_data)
      VALUES ('trg_booking_modified_email','skipped_dedup_5min','info',
              jsonb_build_object('booking_id',NEW.id));
      RETURN NEW;
    END IF;
  END IF;

  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','app_settings_missing','error','supabase_url or service_role_key empty',
            jsonb_build_object('booking_id',NEW.id,'has_url',v_url IS NOT NULL,'has_key',v_key IS NOT NULL));
    RETURN NEW;
  END IF;

  IF v_profile.id IS NULL OR v_profile.email IS NULL OR v_profile.email = '' THEN
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','skipped_no_email','info',
            jsonb_build_object('booking_id',NEW.id,'user_id',NEW.user_id));
    RETURN NEW;
  END IF;

  -- KROK 1: hardcoded mail — isolated tak, aby selhání KROKU 2 NEROLLBACKLO http_post
  BEGIN
    PERFORM net.http_post(
      url     := v_url || '/functions/v1/send-booking-email',
      headers := jsonb_build_object('Content-Type','application/json',
                                     'Authorization','Bearer '||v_key),
      body    := v_payload || jsonb_build_object('type','booking_modified')
    );
    INSERT INTO debug_log(source, action, status, request_data)
    VALUES ('trg_booking_modified_email','http_post_queued','info',
            jsonb_build_object('booking_id',NEW.id,'recipient',v_profile.email));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','http_post_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  -- KROK 2: dispatch custom šablon — isolated v vlastním BEGIN/EXCEPTION
  BEGIN
    PERFORM dispatch_email_event('booking_updated', v_payload);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','dispatch_event_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  -- KROK 3 (2026-06-11): in-app zpráva → appka Zprávy + FCM push
  BEGIN
    v_price_diff := COALESCE(NEW.total_price,0) - COALESCE(OLD.total_price,0);
    v_app_msg := 'Vaše rezervace č. ' || UPPER(RIGHT(NEW.id::text, 8)) || ' byla upravena.'
      || CASE WHEN NEW.start_date::date <> OLD.start_date::date OR NEW.end_date::date <> OLD.end_date::date
           THEN ' Nový termín: ' || TO_CHAR(NEW.start_date,'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date,'DD.MM.YYYY') || '.'
           ELSE '' END
      || CASE WHEN NEW.moto_id IS DISTINCT FROM OLD.moto_id
           THEN ' Nová motorka: ' || COALESCE(v_moto_new,'') || '.'
           ELSE '' END
      || CASE WHEN v_price_diff > 0
           THEN ' Doplatek ' || ROUND(v_price_diff)::text || ' Kč — doklad o platbě najdete v e-mailu.'
           WHEN v_price_diff < 0
           THEN ' Vracíme ' || ROUND(ABS(v_price_diff))::text || ' Kč zpět na kartu — dobropis najdete v e-mailu.'
           ELSE '' END
      || ' Detaily a aktualizovanou smlouvu jsme poslali e-mailem.';
    INSERT INTO admin_messages (user_id, title, message, type)
    VALUES (NEW.user_id, 'Rezervace upravena', v_app_msg, 'info');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','app_message_failed','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  END;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO debug_log(source, action, status, error_message, request_data)
    VALUES ('trg_booking_modified_email','trigger_outer_exception','error',SQLERRM,
            jsonb_build_object('booking_id',NEW.id));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
