-- =============================================================================
-- NÁVRH (DRAFT) — ČEKÁ NA SCHVÁLENÍ MAJITELE (rozhodnutí D3, 2026-10-16)
-- NEcommitovat do supabase/migrations/ bez schválení: merge do main = živá DB.
--
-- „Obnovit a zaplatit" (zrušená nezaplacená rezervace v appce) musí fungovat.
-- Dnes: appka 4.1.3 přepne zrušenou rezervaci přímým UPDATE na pending BEZ
-- restored_at → cron auto_cancel_expired_pending() ji do ≤ 2 min znovu zruší
-- (okno se počítá od created_at) a pošle storno mail, zatímco zákazník platí.
-- Nová appka volá RPC customer_restore_booking, které v DB zatím není.
--
-- Co dělá tento soubor:
--  1) bookings.restored_by_source ('app' = obnovil zákazník v appce, NULL =
--     Velín/legacy) a bookings.restore_count (ochrana proti zneužití: max. 3).
--  2) _customer_restore_check(bookings, uid) — společné kontroly (vlastník,
--     zrušená, nezaplacená a nepřevzatá, nezrušila ji obsluha, začátek v
--     budoucnu, limit obnovení, poukazy a slevové kódy stále platné).
--     Kontrola ceny (oprava 2026-10-16 po kontrole): obnovit jde jen za cenu,
--     která pořád odpovídá AKTUÁLNÍMU ceníku — spodní mez ceny se počítá stejně
--     jako v process-payment (due-verify.ts): pronájem dle ceníku dní motorky
--     (_moto_dayprice_sum) minus doložitelné slevy (platné poukazy, aktivní
--     slevové kódy, věrnost max. 20 %, sleva za vyzvednutí od 12:00 nejvýš dle
--     pravidla). Je-li mez o víc než 1 Kč nad total_price (rezervace vznikla za
--     mimosezónní ceny / ceník mezitím zdražil) → price_changed (+ current_floor):
--     zákazník si vytvoří novou rezervaci za aktuální cenu. Jinak se obnoví
--     za původní nabídku; poukazy/kódy se ověřují zvlášť (jde je utratit
--     dvakrát nebo vyprší).
--  3) _customer_restore_redeem(bookings) — poukazy rezervace (mimo Slevomat)
--     znovu označí jako uplatněné PRO TUTO rezervaci hned při obnovení (storno
--     je uvolnilo; bez toho by šly mezitím použít jinde a po zaplacení by se
--     uplatnily podruhé). Při dalším zrušení je uvolní stávající
--     trg_restore_vouchers_on_cancel.
--  4) RPC customer_restore_booking(uuid) (SECURITY DEFINER, jen authenticated)
--     → {success:true, restored_at, total_price, card_rounding, window_minutes}
--     | {success:false, error: forbidden|not_found|not_cancelled|not_restorable|
--        cancelled_by_staff|date_passed|restore_limit|voucher_unavailable(+code)|
--        promo_unavailable(+code)|price_changed(+current_floor)|moto_unavailable(+reason)}.
--  5) Pojistka trg_a_customer_restore_guard (BEFORE INSERT/UPDATE na bookings,
--     jen běžný JWT zákazníka, název řadí hned za _trg_guard_customer_booking_status):
--       • přímé obnovení appkou ≤ 4.1.3 (cancelled → pending) projde stejnými
--         kontrolami: OK → orazítkuje restored_at/restored_by_source/
--         restore_count (čerstvých 30 min, poukazy znovu uplatněné);
--         neprojde → rezervace zůstane zrušená (debug_log
--         customer_restore_refused) a platba v appce skončí srozumitelnou
--         hláškou process-payment `booking_cancelled` (nic se nestrhne);
--       • restored_at / restored_by_source / restore_count / checkout_started_at
--         zákazník přímým zápisem nezmění (dřív šlo nastavit restored_at a
--         blokovat motorku bez platby navždy — cron obnovené ve Velínu neruší).
--     Velín (admin), service_role, kiosk (anon bez uid) i SECURITY DEFINER RPC
--     customer_restore_booking (příznak motogo.customer_restore) beze změny.
--  6) auto_cancel_expired_pending(): tělo 1:1 podle živé DB, mění se jen WHERE
--     a text důvodu: obnovené v appce mají 30 min od restored_at; probíhající
--     platba (process-payment zapíše checkout_started_at při vytvoření
--     PaymentIntentu) dostane 10 min navíc, nejvýš 60 min od začátku okna.
--     Obnovené ve Velínu (restored_by_source NULL) cron dál neruší.
--  7) restore_vouchers_on_cancel() (trigger trg_restore_vouchers_on_cancel):
--     tělo 1:1 podle živé DB + oprava dvojího uplatnění poukazu — při zrušení
--     rezervace se poukaz uvolní (zpět 'active') JEN když je uplatněný PRÁVĚ
--     pro tuto rezervaci (vouchers.booking_id = NEW.id; legacy záznamy bez
--     booking_id jako dosud). Dřív: poukaz na nezaplacené rozpracované
--     rezervaci Y i na zaplacené X → cron zrušil Y → poukaz uplatněný pro X se
--     vrátil na 'active' a šel použít znovu (appka dává discount_code na každý
--     koncept). Pozor: obnovení (bod 3/5) poukazy opět uplatní pro obnovenou
--     rezervaci, takže jejich pozdější zrušení je zase uvolní.
--
-- Idempotentní (IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
-- Bez BEGIN/COMMIT. Po aplikaci aktualizovat SUPABASE_BACKEND_STATE_2
-- (sloupce), _3 (RPC + cron fce + restore_vouchers_on_cancel), _4 (trigger),
-- _6 (changelog).
-- =============================================================================

ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS restored_by_source text;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS restore_count smallint NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.bookings.restored_by_source IS
  'D3 2026-10-16: kdo zrušenou rezervaci naposledy obnovil — ''app'' = zákazník v aplikaci (cron ji zruší 30 min po obnovení, není-li zaplacená), NULL = Velín/legacy (cron neruší).';
COMMENT ON COLUMN public.bookings.restore_count IS
  'D3 2026-10-16: počet obnovení zákazníkem v aplikaci (limit 3, ochrana proti blokování motorky).';

-- ── 2) Společné kontroly ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._customer_restore_check(p_b public.bookings, p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() AT TIME ZONE 'Europe/Prague')::date;
  r record;
  v_uses bigint;
  v_rental numeric;
  v_gross numeric;
  v_vouchers numeric;
  v_promos numeric;
  v_loyalty numeric;
  v_late numeric;
  v_floor numeric;
BEGIN
  IF p_uid IS NULL OR p_b.user_id IS DISTINCT FROM p_uid THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  IF p_b.status IS DISTINCT FROM 'cancelled' THEN
    RETURN jsonb_build_object('error', 'not_cancelled');
  END IF;
  -- Zaplacená / vrácená (storno s vratkou), převzatá nebo SOS náhrada → jen Velín.
  IF p_b.payment_status IS DISTINCT FROM 'unpaid' OR p_b.picked_up_at IS NOT NULL
     OR COALESCE(p_b.sos_replacement, false) THEN
    RETURN jsonb_build_object('error', 'not_restorable');
  END IF;
  IF p_b.cancelled_by_source IN ('admin', 'velin', 'stripe_portal') THEN
    RETURN jsonb_build_object('error', 'cancelled_by_staff');
  END IF;
  IF p_b.start_date IS NULL OR p_b.start_date::date <= v_today THEN
    RETURN jsonb_build_object('error', 'date_passed');
  END IF;
  IF COALESCE(p_b.restore_count, 0) >= 3 THEN
    RETURN jsonb_build_object('error', 'restore_limit');
  END IF;

  -- Poukazy (booking_discounts + legacy discount_code): aktivní a platné, nebo
  -- už uplatněné právě pro tuto rezervaci.
  FOR r IN
    SELECT v.code, v.status, v.valid_until, v.booking_id
      FROM vouchers v
     WHERE v.id IN (SELECT d.voucher_id FROM booking_discounts d
                     WHERE d.booking_id = p_b.id AND d.kind = 'voucher' AND d.voucher_id IS NOT NULL)
        OR (COALESCE(p_b.discount_code, '') <> ''
            AND upper(v.code) IN (SELECT upper(btrim(x)) FROM unnest(string_to_array(p_b.discount_code, ',')) x
                                   WHERE btrim(x) <> ''))
  LOOP
    IF (r.valid_until IS NOT NULL AND r.valid_until < v_today)
       OR NOT (r.status = 'active' OR (r.status = 'redeemed' AND r.booking_id = p_b.id)) THEN
      RETURN jsonb_build_object('error', 'voucher_unavailable', 'code', r.code);
    END IF;
  END LOOP;

  -- Slevové kódy: aktivní, nevypršené, nevyčerpané (bez použití touto rezervací).
  FOR r IN
    SELECT p.id, p.code, p.active, p.valid_to, p.max_uses
      FROM promo_codes p
     WHERE p.id IN (SELECT d.promo_code_id FROM booking_discounts d
                     WHERE d.booking_id = p_b.id AND d.kind = 'promo_code' AND d.promo_code_id IS NOT NULL)
        OR p.id = p_b.promo_code_id
  LOOP
    IF NOT COALESCE(r.active, false) OR (r.valid_to IS NOT NULL AND r.valid_to < v_today) THEN
      RETURN jsonb_build_object('error', 'promo_unavailable', 'code', r.code);
    END IF;
    IF COALESCE(r.max_uses, 0) > 0 THEN
      SELECT count(*) INTO v_uses FROM promo_code_usage u
       WHERE u.promo_code_id = r.id AND u.booking_id IS DISTINCT FROM p_b.id;
      IF v_uses >= r.max_uses THEN
        RETURN jsonb_build_object('error', 'promo_unavailable', 'code', r.code);
      END IF;
    END IF;
  END LOOP;

  -- Cena musí odpovídat AKTUÁLNÍMU ceníku (stejná spodní mez jako process-payment
  -- due-verify.ts): pronájem dle ceníku dní − doložitelné slevy; výbava a doprava
  -- se nepočítají (mez jen snižují). Mez > cena + 1 Kč → obnovit nejde (nová rezervace).
  v_rental := COALESCE(public._moto_dayprice_sum(p_b.moto_id, p_b.start_date::date, p_b.end_date::date), 0);
  v_gross  := v_rental + GREATEST(COALESCE(p_b.extras_price, 0), 0) + GREATEST(COALESCE(p_b.delivery_fee, 0), 0);

  -- poukazy rezervace (booking_discounts, voucher_id, discount_code): platné a volné / pro ni
  SELECT COALESCE(SUM(GREATEST(COALESCE(v.amount, 0), 0)), 0) INTO v_vouchers
    FROM vouchers v
   WHERE (v.id IN (SELECT d.voucher_id FROM booking_discounts d
                    WHERE d.booking_id = p_b.id AND d.kind = 'voucher' AND d.voucher_id IS NOT NULL)
          OR v.id = p_b.voucher_id
          OR (COALESCE(p_b.discount_code, '') <> ''
              AND v.code IN (SELECT btrim(x) FROM unnest(string_to_array(p_b.discount_code, ',')) x WHERE btrim(x) <> ''
                             UNION SELECT upper(btrim(x)) FROM unnest(string_to_array(p_b.discount_code, ',')) x WHERE btrim(x) <> '')))
     AND (v.valid_until IS NULL OR v.valid_until >= v_today)
     AND (v.status = 'active' OR (v.status = 'redeemed' AND v.booking_id = p_b.id));

  -- slevové kódy (id z booking_discounts / promo_code_id i podle discount_code), jen aktivní
  SELECT COALESCE(SUM(CASE WHEN p.type = 'percent'
                           THEN v_gross * LEAST(GREATEST(COALESCE(p.value, 0), 0), 100) / 100
                           ELSE GREATEST(COALESCE(p.value, 0), 0) END), 0) INTO v_promos
    FROM promo_codes p
   WHERE p.active IS DISTINCT FROM false
     AND (p.id IN (SELECT d.promo_code_id FROM booking_discounts d
                    WHERE d.booking_id = p_b.id AND d.kind = 'promo_code' AND d.promo_code_id IS NOT NULL)
          OR p.id = p_b.promo_code_id
          OR (COALESCE(p_b.discount_code, '') <> ''
              AND p.code IN (SELECT btrim(x) FROM unnest(string_to_array(p_b.discount_code, ',')) x WHERE btrim(x) <> ''
                             UNION SELECT upper(btrim(x)) FROM unnest(string_to_array(p_b.discount_code, ',')) x WHERE btrim(x) <> '')));

  -- věrnost (strop pravidla 20 %) + sleva za vyzvednutí od 12:00 (nejvýš dle pravidla)
  v_loyalty := LEAST(GREATEST(COALESCE(p_b.loyalty_discount_amount, 0), 0), round(v_gross * 0.2));
  v_late := GREATEST(COALESCE(p_b.late_pickup_discount_amount, 0), 0);
  IF v_late > 0 THEN
    v_late := LEAST(v_late, GREATEST(COALESCE(public._late_pickup_discount(p_b.moto_id, p_b.start_date, p_b.end_date, p_b.pickup_time), 0), 0));
  END IF;
  v_floor := GREATEST(round(v_rental - v_vouchers - v_promos - v_loyalty - v_late, 2), 0);
  IF v_floor > COALESCE(p_b.total_price, 0) + 1 THEN
    RETURN jsonb_build_object('error', 'price_changed', 'current_floor', v_floor, 'total_price', COALESCE(p_b.total_price, 0));
  END IF;

  RETURN NULL;  -- lze obnovit
END;
$$;

-- ── 3) Znovu uplatnit poukazy (mimo Slevomat — ten se uplatní při platbě) ────
-- Vrací kód poukazu, který se uplatnit nepodařilo (mezitím použit jinde), jinak NULL.
CREATE OR REPLACE FUNCTION public._customer_restore_redeem(p_b public.bookings)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT v.id, v.code, v.status, v.source, v.booking_id
      FROM vouchers v
     WHERE v.id IN (SELECT d.voucher_id FROM booking_discounts d
                     WHERE d.booking_id = p_b.id AND d.kind = 'voucher' AND d.voucher_id IS NOT NULL)
        OR (COALESCE(p_b.discount_code, '') <> ''
            AND upper(v.code) IN (SELECT upper(btrim(x)) FROM unnest(string_to_array(p_b.discount_code, ',')) x
                                   WHERE btrim(x) <> ''))
     ORDER BY v.id
       FOR UPDATE OF v
  LOOP
    IF r.status = 'redeemed' AND r.booking_id = p_b.id THEN
      CONTINUE;  -- už uplatněn pro tuto rezervaci
    END IF;
    IF r.status IS DISTINCT FROM 'active' THEN
      RETURN r.code;
    END IF;
    IF r.source IS DISTINCT FROM 'slevomat' THEN
      UPDATE vouchers
         SET status = 'redeemed', redeemed_at = now(), redeemed_by = p_b.user_id,
             booking_id = p_b.id, updated_at = now()
       WHERE id = r.id AND status = 'active';
      IF NOT FOUND THEN
        RETURN r.code;
      END IF;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;

-- ── 4) RPC pro appku ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.customer_restore_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_b    bookings%ROWTYPE;
  v_err  jsonb;
  v_code text;
  v_now  timestamptz := now();
  v_row  jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;

  v_err := public._customer_restore_check(v_b, v_uid);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('success', false) || v_err;
  END IF;

  BEGIN
    v_code := public._customer_restore_redeem(v_b);
    IF v_code IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'MGR01', MESSAGE = v_code;
    END IF;

    -- Pojistka trg_a_customer_restore_guard tuto (už ověřenou) změnu propustí.
    PERFORM set_config('motogo.customer_restore', p_booking_id::text, true);
    UPDATE bookings SET
      status                = 'pending',
      payment_status        = 'unpaid',
      cancelled_at          = NULL,
      cancelled_by          = NULL,
      cancelled_by_source   = NULL,
      cancellation_reason   = NULL,
      cancellation_notified = false,
      restored_at           = v_now,
      restored_by_source    = 'app',
      restore_count         = COALESCE(restore_count, 0) + 1,
      checkout_started_at   = NULL
    WHERE id = p_booking_id;
    PERFORM set_config('motogo.customer_restore', '', true);
  EXCEPTION
    WHEN SQLSTATE 'MGR01' THEN
      RETURN jsonb_build_object('success', false, 'error', 'voucher_unavailable', 'code', SQLERRM);
    WHEN unique_violation OR check_violation OR exclusion_violation OR raise_exception THEN
      -- trg_check_booking_overlap / trg_check_trailer_overlap / zavřená pobočka /
      -- zákazník má v termínu jinou rezervaci → nic se nezměnilo (savepoint).
      RETURN jsonb_build_object('success', false, 'error', 'moto_unavailable',
        'reason', CASE WHEN SQLERRM LIKE 'Zákazník má překrývající%' THEN 'own_overlap'
                       WHEN SQLERRM LIKE 'Pobočka%zavřená%' THEN 'branch_closed'
                       WHEN SQLERRM LIKE '%vozík%' OR SQLERRM LIKE 'trailer_unavailable%' THEN 'trailer'
                       ELSE 'moto_overlap' END);
  END;

  SELECT to_jsonb(b) INTO v_row FROM bookings b WHERE b.id = p_booking_id;
  BEGIN
    INSERT INTO debug_log(source, action, component, status, request_data)
    VALUES ('customer_restore_booking', 'customer_restore_ok', 'booking', 'ok',
            jsonb_build_object('booking_id', p_booking_id, 'restore_count', v_row->'restore_count',
                               'previous_cancelled_by_source', v_b.cancelled_by_source));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'restored_at', v_now,
    'total_price', COALESCE((v_row->>'total_price')::numeric, 0),
    'card_rounding', COALESCE((v_row->>'card_rounding')::numeric, 0),
    'window_minutes', 30
  );
END;
$$;

REVOKE ALL ON FUNCTION public._customer_restore_check(public.bookings, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._customer_restore_redeem(public.bookings) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._customer_restore_check(public.bookings, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._customer_restore_redeem(public.bookings) TO service_role;
REVOKE ALL ON FUNCTION public.customer_restore_booking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.customer_restore_booking(uuid) TO authenticated, service_role;

-- ── 5) Pojistka: přímé obnovení starou appkou + sloupce obnovy jen ze serveru ──
CREATE OR REPLACE FUNCTION public._customer_restore_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_err  jsonb;
  v_code text;
BEGIN
  -- Jen běžný JWT zákazníka. service_role (auth.uid() NULL), Velín (admin),
  -- kiosk (anon) a přímé spojení k DB beze změny.
  IF v_uid IS NULL OR COALESCE(public.is_admin(), false) THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.restored_at         := NULL;
    NEW.restored_by_source  := NULL;
    NEW.restore_count       := 0;
    NEW.checkout_started_at := NULL;
    RETURN NEW;
  END IF;

  -- RPC customer_restore_booking (vše už ověřilo a zapsalo).
  IF current_setting('motogo.customer_restore', true) = NEW.id::text THEN
    RETURN NEW;
  END IF;

  -- Sloupce obnovy / probíhající platby zapisuje jen server.
  NEW.restored_at         := OLD.restored_at;
  NEW.restored_by_source  := OLD.restored_by_source;
  NEW.restore_count       := OLD.restore_count;
  NEW.checkout_started_at := OLD.checkout_started_at;

  -- Přímé obnovení appkou ≤ 4.1.3: UPDATE status cancelled → pending.
  IF OLD.status = 'cancelled' AND NEW.status = 'pending' THEN
    v_err := public._customer_restore_check(OLD, v_uid);
    IF v_err IS NULL THEN
      v_code := public._customer_restore_redeem(OLD);
      IF v_code IS NOT NULL THEN
        v_err := jsonb_build_object('error', 'voucher_unavailable', 'code', v_code);
      END IF;
    END IF;

    IF v_err IS NOT NULL THEN
      -- Neobnovovat: rezervace zůstane zrušená; platba v appce dostane
      -- process-payment `booking_cancelled` (srozumitelná hláška, nic se nestrhne).
      NEW.status              := OLD.status;
      NEW.payment_status      := OLD.payment_status;
      NEW.cancelled_at        := OLD.cancelled_at;
      NEW.cancelled_by        := OLD.cancelled_by;
      NEW.cancelled_by_source := OLD.cancelled_by_source;
      NEW.cancellation_reason := OLD.cancellation_reason;
      BEGIN
        INSERT INTO debug_log(source, action, component, status, request_data)
        VALUES ('customer_restore_guard', 'customer_restore_refused', 'booking', 'warning',
                jsonb_build_object('booking_id', NEW.id) || v_err);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      RETURN NEW;
    END IF;

    NEW.restored_at           := now();
    NEW.restored_by_source    := 'app';
    NEW.restore_count         := COALESCE(OLD.restore_count, 0) + 1;
    NEW.checkout_started_at   := NULL;
    NEW.cancelled_at          := NULL;
    NEW.cancelled_by          := NULL;
    NEW.cancelled_by_source   := NULL;
    NEW.cancellation_reason   := NULL;
    NEW.cancellation_notified := false;
    BEGIN
      INSERT INTO debug_log(source, action, component, status, request_data)
      VALUES ('customer_restore_guard', 'customer_restore_stamped', 'booking', 'ok',
              jsonb_build_object('booking_id', NEW.id, 'restore_count', NEW.restore_count));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._customer_restore_guard() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._customer_restore_guard() TO service_role;

-- Název řadí trigger hned ZA _trg_guard_customer_booking_status (ten už status
-- očistil) a PŘED kontroly překryvu/pobočky (trg_check_*), které tak vidí už
-- výsledný stav (odmítnuté obnovení = zůstává cancelled = bez kontroly).
DROP TRIGGER IF EXISTS trg_a_customer_restore_guard ON public.bookings;
CREATE TRIGGER trg_a_customer_restore_guard
  BEFORE INSERT OR UPDATE OF status, restored_at, restored_by_source, restore_count, checkout_started_at
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._customer_restore_guard();

-- ── 6) Cron: tělo 1:1 se živou DB, změněné řádky označené „D3" ─────────────────
CREATE OR REPLACE FUNCTION public.auto_cancel_expired_pending()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_url text;
  v_key text;
  v_row record;
BEGIN
  SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
  SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';

  FOR v_row IN
    WITH cancelled AS (
      UPDATE bookings SET
        status               = 'cancelled',
        cancellation_reason  = CASE
          WHEN booking_source = 'app' OR restored_by_source = 'app'                 -- D3
            THEN 'Automaticky zrušeno — nezaplaceno do 30 minut'
          ELSE  'Automaticky zrušeno — nezaplaceno do 4 hodin'
        END,
        cancelled_at         = now(),
        cancelled_by_source  = 'auto'
      WHERE status = 'pending'
        AND payment_status = 'unpaid'
        AND (                                                                       -- D3
          -- běžné (neobnovené) rezervace jako dosud
          (restored_at IS NULL AND (
            (booking_source = 'app' AND created_at < now() - interval '30 minutes')
            OR (booking_source = 'web' AND created_at < now() - interval '4 hours')
          ))
          -- obnovené zákazníkem v appce: 30 min od obnovení
          OR (restored_by_source = 'app' AND restored_at < now() - interval '30 minutes')
          -- obnovené ve Velínu (restored_by_source NULL) cron neruší — řeší admin
        )
        -- D3: probíhající platba (process-payment zapsal checkout_started_at při
        -- vytvoření PaymentIntentu) → 10 min navíc, nejvýš 60 min od začátku okna
        AND NOT (checkout_started_at IS NOT NULL
                 AND checkout_started_at > now() - interval '10 minutes'
                 AND COALESCE(restored_at, created_at) > now() - interval '60 minutes')
      RETURNING id, user_id, moto_id, start_date, end_date,
                booking_source, cancellation_reason
    )
    SELECT c.id, c.user_id, c.moto_id, c.start_date, c.end_date,
           c.booking_source, c.cancellation_reason,
           p.email AS customer_email, p.full_name AS customer_name,
           m.model AS motorcycle_model
      FROM cancelled c
      LEFT JOIN profiles p     ON p.id = c.user_id
      LEFT JOIN motorcycles m  ON m.id = c.moto_id
  LOOP
    -- Web rezervace už dostaly "Nedokončená rezervace" mail z
    -- send_abandoned_booking_emails() po 15 min — neposílej druhý "Storno" mail.
    IF v_row.booking_source = 'web' THEN
      CONTINUE;
    END IF;

    IF v_row.customer_email IS NULL OR v_row.customer_email = '' THEN CONTINUE; END IF;
    IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
      RAISE WARNING 'auto_cancel_expired_pending: app_settings missing — skipping mail for %', v_row.id;
      CONTINUE;
    END IF;

    BEGIN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-cancellation-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_key
        ),
        body    := jsonb_build_object(
          'booking_id',           v_row.id,
          'customer_email',       v_row.customer_email,
          'customer_name',        COALESCE(v_row.customer_name, ''),
          'motorcycle',           COALESCE(v_row.motorcycle_model, ''),
          'start_date',           v_row.start_date,
          'end_date',             v_row.end_date,
          'cancellation_reason',  v_row.cancellation_reason,
          'cancelled_by_source',  'auto',
          'refund_amount',        0,
          'refund_percent',       0,
          'source',               COALESCE(v_row.booking_source, 'app')
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_cancel_expired_pending: mail call failed for %: %', v_row.id, SQLERRM;
    END;
  END LOOP;
END;
$function$;

-- ── 7) Uvolnění poukazů při zrušení: jen poukaz uplatněný pro TUTO rezervaci ──
-- Tělo 1:1 se živou DB; změněné řádky označené „D3".
CREATE OR REPLACE FUNCTION public.restore_vouchers_on_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_code text; v_codes text[];
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
    UPDATE vouchers v SET status='active', redeemed_at=NULL, redeemed_by=NULL, booking_id=NULL, updated_at=now()
      FROM booking_discounts bd
      WHERE bd.booking_id = NEW.id AND bd.kind='voucher' AND bd.voucher_id = v.id
        AND v.status='redeemed' AND v.source IS DISTINCT FROM 'slevomat'
        AND (v.booking_id = NEW.id OR v.booking_id IS NULL);                    -- D3
    IF NEW.discount_code IS NOT NULL AND NEW.discount_code <> '' THEN
      v_codes := string_to_array(NEW.discount_code, ',');
      FOREACH v_code IN ARRAY v_codes LOOP
        v_code := trim(v_code);
        IF v_code <> '' THEN
          UPDATE vouchers SET status='active', redeemed_at=NULL, redeemed_by=NULL, booking_id=NULL, updated_at=now()
            WHERE code = v_code AND status='redeemed' AND source IS DISTINCT FROM 'slevomat'
              AND (booking_id = NEW.id OR booking_id IS NULL);                  -- D3
        END IF;
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END; $function$;

NOTIFY pgrst, 'reload schema';
