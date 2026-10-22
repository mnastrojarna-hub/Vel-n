-- =============================================================================
-- NÁVRH (DRAFT) — ČEKÁ NA SCHVÁLENÍ MAJITELE (rozhodnutí D1 + D2, 2026-10-16)
-- NEcommitovat do supabase/migrations/ bez schválení: merge do main = živá DB.
--
-- Minimální platba kartou (Stripe CZK) je 15 Kč. Rozhodnutí majitele:
--   • doplatek / cena 0 < x ≤ 1 Kč  → NEÚČTUJE SE (odpuštěno, nic se nestrhne),
--   • 1 < x < 15 Kč                 → zaplatí se 15 Kč (dorovnání nahoru),
--   • ≥ 15 Kč                       → beze změny.
-- Platí pro rezervace (nová, dokončení, obnovení, doplatek úpravy, výměna
-- motorky) i e-shop. Dorovnání musí být vidět na KAŽDÉM dokladu a sedět s tím,
-- co se strhlo z karty.
--
-- Co dělá tento soubor:
--  1) Sloupec card_rounding (Kč, se znaménkem) na bookings a shop_orders:
--       +X = dorovnání na minimální platbu kartou,  −X = odpuštěná částka do 1 Kč;
--       |X| < 1 také rozdíl platby kartou v celých korunách (cena 15,40 → strženo
--       15 Kč = −0,40), aby cena na dokladech vždy seděla se strženou částkou.
--     Dorovnání nové rezervace / e-shopu zapisuje webhook-receiver AŽ PO
--     úspěšné platbě (ne při vytvoření PaymentIntentu) — opuštěná platba tak
--     nikdy nezanechá dorovnání, které se nestrhlo.
--     Hodnota JE ZAHRNUTA v bookings.total_price / shop_orders.total (storno,
--     vratky, úpravy i strop zákaznické vratky proto fungují beze změny; při
--     stornu se dorovnání vrací poměrně jako zbytek ceny). U rezervace je to
--     součet všech dorovnání (první platba + pozdější doplatky).
--     Zapisuje VÝHRADNĚ server: process-payment / webhook-receiver
--     (service_role), split_booking_moto_swap rev.12 (20261016p3) a Velín.
--  2) Pojistka _protect_card_rounding: běžný JWT zákazníka (auth.uid() NOT NULL,
--     ne admin) sloupec nezmění — INSERT = 0, UPDATE = původní hodnota
--     (stejný vzor jako _protect_booking_mileage, 20260929f; výjimka jen pro
--     apply_paid_gear_change ze 20261016p4 přes motogo.gear_card_rounding). shop_orders
--     pojistku nepotřebují (zákazník má jen SELECT, insert jde přes SECURITY
--     DEFINER create_shop_order s výchozí 0).
--     + _reset_card_rounding_on_reprice: NEZAPLACENÁ rezervace přeceněná bez
--     současného zápisu card_rounding (úprava v appce / Velínu / přímý zápis
--     zákazníka — změna ceny, motorky, termínu, výbavy, dopravy či slev)
--     → dřívější dorovnání / odpuštění už neplatí → 0 (jinak by doklady ukázaly
--     řádek dorovnání, které se nikdy nestrhlo, a process-payment by jinou
--     rezervaci potvrdil zdarma). Dorovnání zapisuje webhook až PO
--     zaplacení (s cenou v témže UPDATE), odpuštění process-payment těsně před
--     potvrzením — obojí mění oba sloupce najednou, takže se nenuluje.
--  3) Konečná faktura (KF, trigger generate_final_invoice_on_complete): tělo
--     1:1 podle živé DB (snapshot 2026-10-16) + samostatný řádek dorovnání
--     a odečet dorovnání od základu pronájmu (součet KF dál = 0).
--     Rollback: tělo bez řádků označených „D1" (= živá verze, poslední repo
--     definice supabase/functions/migrations/20260625_invoice_per_discount_lines.sql
--     + pozdější úpravy přímo v DB — pravdou je snapshot supabase-live-snapshot).
--
-- Idempotentní (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE, DROP TRIGGER IF
-- EXISTS). Bez BEGIN/COMMIT (deploy-sql.yml spouští soubor v jedné transakci).
-- Po aplikaci aktualizovat SUPABASE_BACKEND_STATE_2 (sloupce), _3 (KF),
-- _4 (triggery trg_protect_card_rounding, trg_reset_card_rounding_on_reprice),
-- _6 (changelog).
-- =============================================================================

ALTER TABLE public.bookings    ADD COLUMN IF NOT EXISTS card_rounding numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.shop_orders ADD COLUMN IF NOT EXISTS card_rounding numeric(10,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.bookings.card_rounding IS
  'D1 2026-10-16: dorovnání na minimální platbu kartou 15 Kč (+) / odpuštěná částka do 1 Kč (−), součet za rezervaci. JE ZAHRNUTO v total_price. Zapisuje jen server (process-payment, webhook-receiver, split_booking_moto_swap) a Velín.';
COMMENT ON COLUMN public.shop_orders.card_rounding IS
  'D2 2026-10-16: dorovnání na minimální platbu kartou 15 Kč (+) / odpuštěná částka do 1 Kč (−). JE ZAHRNUTO v total. Zapisuje jen process-payment (service_role).';

-- ── 2) Pojistka: zákazník sloupec nezmění ────────────────────────────────────
CREATE OR REPLACE FUNCTION public._protect_card_rounding()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Běžný JWT zákazníka (auth.uid() NOT NULL, ne admin): dorovnání zapisuje jen
  -- backend (service_role: auth.uid() IS NULL) nebo Velín (admin).
  -- Výjimka: apply_paid_gear_change (jen service_role, SQL 20261016p4) volá
  -- update_booking_gear pod identitou zákazníka a dorovnání zaplacené výbavy
  -- předává transakční proměnnou motogo.gear_card_rounding = '<id rezervace>:<Kč>'
  -- (zákazník ji přes PostgREST nastavit nemůže) — jen pro tuto rezervaci.
  IF auth.uid() IS NOT NULL AND NOT COALESCE(public.is_admin(), false)
     AND NOT (TG_OP = 'UPDATE'
              AND split_part(COALESCE(current_setting('motogo.gear_card_rounding', true), ''), ':', 1) = NEW.id::text) THEN
    IF TG_OP = 'INSERT' THEN
      NEW.card_rounding := 0;
    ELSE
      NEW.card_rounding := OLD.card_rounding;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._protect_card_rounding() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._protect_card_rounding() TO service_role;

DROP TRIGGER IF EXISTS trg_protect_card_rounding ON public.bookings;
CREATE TRIGGER trg_protect_card_rounding
  BEFORE INSERT OR UPDATE OF card_rounding ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._protect_card_rounding();

-- Nezaplacená rezervace přeceněná bez zápisu card_rounding → dorovnání neplatí.
-- Název řadí trigger ZA trg_protect_card_rounding (ten už případný zákaznický
-- zápis card_rounding vrátil na OLD) a PŘED trg_validate_late_pickup_update
-- (ten smí total_price ještě zvýšit — to je oprava ceny, ne nové přecenění).
CREATE OR REPLACE FUNCTION public._reset_card_rounding_on_reprice()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Přecenění = změna ceny NEBO čehokoli, z čeho se cena počítá (motorka, termín,
  -- výbava, doprava, slevy vč. slevy za vyzvednutí od 12:00 — samotný čas vyzvednutí
  -- cenu nemění, mění jen tu slevu). Zákazník smí nezaplacenou rezervaci
  -- měnit přímo (RLS bookings_user_update) i bez zápisu total_price — dřívější
  -- odpuštění by pak „potvrdilo zdarma" úplně jinou rezervaci.
  IF OLD.payment_status = 'unpaid' AND NEW.payment_status = 'unpaid'
     AND NEW.card_rounding IS NOT DISTINCT FROM OLD.card_rounding
     AND COALESCE(OLD.card_rounding, 0) <> 0
     AND (NEW.total_price                 IS DISTINCT FROM OLD.total_price
       OR NEW.moto_id                     IS DISTINCT FROM OLD.moto_id
       OR NEW.start_date                  IS DISTINCT FROM OLD.start_date
       OR NEW.end_date                    IS DISTINCT FROM OLD.end_date
       OR NEW.extras_price                IS DISTINCT FROM OLD.extras_price
       OR NEW.delivery_fee                IS DISTINCT FROM OLD.delivery_fee
       OR NEW.discount_amount             IS DISTINCT FROM OLD.discount_amount
       OR NEW.discount_code               IS DISTINCT FROM OLD.discount_code
       OR NEW.promo_code_id               IS DISTINCT FROM OLD.promo_code_id
       OR NEW.voucher_id                  IS DISTINCT FROM OLD.voucher_id
       OR NEW.loyalty_discount_amount     IS DISTINCT FROM OLD.loyalty_discount_amount
       OR NEW.late_pickup_discount_amount IS DISTINCT FROM OLD.late_pickup_discount_amount) THEN
    NEW.card_rounding := 0;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._reset_card_rounding_on_reprice() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._reset_card_rounding_on_reprice() TO service_role;

DROP TRIGGER IF EXISTS trg_reset_card_rounding_on_reprice ON public.bookings;
CREATE TRIGGER trg_reset_card_rounding_on_reprice
  BEFORE UPDATE OF total_price, moto_id, start_date, end_date, extras_price, delivery_fee,
                   discount_amount, discount_code, promo_code_id, voucher_id,
                   loyalty_discount_amount, late_pickup_discount_amount ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._reset_card_rounding_on_reprice();

-- ── 3) KF: řádek dorovnání ───────────────────────────────────────────────────
-- Tělo 1:1 se živou DB; změny jsou označené „D1".
-- ZRCADLO „GEAR 20261023db" (doplněno 2026-10-23): migrace
-- supabase/migrations/20261023db_gear_booking_final_invoice.sql přidala do této funkce
-- větev pro výpůjčku jen výbavy (bookings.booking_kind='gear': řádky KF z gear_lines,
-- rozdílový řádek, sleva = dárkový poukaz, bez kódu VRACENI) a SET search_path. Tento návrh
-- funkci celou předefinovává — bez zrcadla by jeho pozdější aplikace gear větev tiše
-- smazala (gear KF by dostala řádek „Pronájem motorky ()" a slevový kód VRACENI).
-- Řádky „GEAR 20261023db" proto drž i při dalších úpravách; dorovnání D1 platí i pro výbavu
-- (v_rounding je odečtené ze základu, rozdílový řádek se počítá až z něj).
CREATE OR REPLACE FUNCTION public.generate_final_invoice_on_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public                       -- GEAR 20261023db: pojistka SECURITY DEFINER
AS $function$
DECLARE
  v_inv_num text; v_seq int;
  v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int;
  v_items jsonb; v_total numeric;
  v_moto_model text; v_moto_spz text;
  v_base_rental numeric; v_extras numeric; v_delivery numeric;
  v_discount numeric; v_discount_code text;
  v_loyalty numeric; v_loyalty_pct int;
  v_late_pickup numeric;
  v_rounding numeric;                            -- D1: dorovnání / odpuštěno (v total_price)
  v_booking_short text; v_promo_code text;
  v_cn_number text;                              -- NOVÉ #3
  v_gear boolean := (NEW.booking_kind = 'gear'); -- GEAR 20261023db: výpůjčka jen výbavy
  v_gear_days int; v_gear_sum numeric;           -- GEAR 20261023db
BEGIN
  IF OLD.status != 'active' OR NEW.status != 'completed' THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = NEW.id AND type = 'final') THEN RETURN NEW; END IF;
  IF NEW.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN RETURN NEW; END IF;
  IF NEW.sos_replacement = true THEN
    RAISE NOTICE 'Skipping KF for SOS replacement booking %', NEW.id;
    RETURN NEW;
  END IF;

  SELECT model, spz INTO v_moto_model, v_moto_spz FROM motorcycles WHERE id = NEW.moto_id;

  v_inv_num := next_document_number('KF');       -- NOVÉ #3: atomické číslo (místo MAX+1)

  v_extras   := COALESCE(NEW.extras_price, 0);
  v_delivery := COALESCE(NEW.delivery_fee, 0);
  v_discount := COALESCE(NEW.discount_amount, 0);
  v_discount_code := COALESCE(NEW.discount_code, '');
  v_loyalty     := COALESCE(NEW.loyalty_discount_amount, 0);
  v_loyalty_pct := COALESCE(NEW.loyalty_percent, 0);
  v_late_pickup := COALESCE(NEW.late_pickup_discount_amount, 0);
  v_rounding    := COALESCE(NEW.card_rounding, 0);                       -- D1
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery
                   + v_discount + v_loyalty + v_late_pickup
                   - v_rounding;                                          -- D1

  IF v_gear THEN
    -- GEAR 20261023db: řádky z gear_lines (komplet = velikosti kusů, kus = jeho velikost),
    -- množství = dny výpůjčky, cena = Kč/den; žádný řádek motorky.
    v_gear_days := GREATEST(1, (NEW.end_date::date - NEW.start_date::date) + 1);
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'description', 'Půjčení výbavy: ' || COALESCE(NULLIF(l->>'label', ''), l->>'key', 'výbava')
               || COALESCE(' (' || (
                    SELECT string_agg(CASE WHEN l->>'kind' = 'set' THEN lower(COALESCE(p.label, e.key)) || ' ' ELSE '' END
                                      || e.value, ', ' ORDER BY p.sort_order NULLS LAST, e.key)
                      FROM jsonb_each_text(CASE WHEN jsonb_typeof(l->'sizes') = 'object' THEN l->'sizes' ELSE '{}'::jsonb END) e
                      LEFT JOIN gear_rental_prices p ON p.key = e.key
                     WHERE NULLIF(e.value, '') IS NOT NULL) || ')', '')
               || ' — ' || TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
             'qty', v_gear_days,
             'unit_price', COALESCE((l->>'price_per_day')::numeric, 0)) ORDER BY t.o), '[]'::jsonb)
      INTO v_items
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(NEW.gear_lines) = 'array' THEN NEW.gear_lines ELSE '[]'::jsonb END)
           WITH ORDINALITY AS t(l, o);
    v_gear_sum := COALESCE((SELECT SUM((i->>'unit_price')::numeric * (i->>'qty')::numeric)
                              FROM jsonb_array_elements(v_items) AS i), 0);
    -- Cena rezervace ≠ Σ řádků (zkrácení s vratkou < 100 %, ruční úprava ceny) → rozdíl
    -- samostatně, aby KF proti DP a dobropisům dál vycházela na 0.
    IF ROUND(v_base_rental - v_gear_sum, 2) <> 0 THEN
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'description', 'Úprava ceny výpůjčky výbavy (změny rezervace)',
        'qty', 1, 'unit_price', v_base_rental - v_gear_sum));
    END IF;
    -- Sleva u výbavy = jen dárkový poukaz; kód z booking_discounts, když ho rezervace nenese.
    IF v_discount_code = '' THEN
      v_discount_code := COALESCE((SELECT string_agg(code, ', ') FROM booking_discounts
                                    WHERE booking_id = NEW.id AND NULLIF(code, '') IS NOT NULL), '');
    END IF;
  ELSE
  v_items := jsonb_build_array(jsonb_build_object(
    'description', 'Pronájem ' || COALESCE(v_moto_model, 'motorky') ||
      ' (' || COALESCE(v_moto_spz, '') || ') — ' ||
      TO_CHAR(NEW.start_date, 'DD.MM.YYYY') || ' – ' || TO_CHAR(NEW.end_date, 'DD.MM.YYYY'),
    'qty', 1, 'unit_price', v_base_rental
  ));
  END IF;                                        -- GEAR 20261023db

  IF v_extras > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Příslušenství a výbava', 'qty', 1, 'unit_price', v_extras));
  END IF;

  IF v_delivery > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Přistavení / odvoz motorky', 'qty', 1, 'unit_price', v_delivery));
  END IF;

  IF v_discount > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', CASE WHEN v_gear THEN       -- GEAR 20261023db: promo kódy u výbavy neplatí
                            CASE WHEN v_discount_code <> '' THEN 'Dárkový poukaz (kód: ' || v_discount_code || ')'
                                 ELSE 'Sleva / dárkový poukaz' END
                          WHEN v_discount_code <> '' THEN 'Sleva (kód: ' || v_discount_code || ')'
                          ELSE 'Sleva / voucher' END,
      'qty', 1, 'unit_price', -v_discount));
  END IF;

  IF v_loyalty > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Věrnostní sleva' ||
        CASE WHEN v_loyalty_pct > 0 THEN ' ' || v_loyalty_pct || ' %' ELSE '' END ||
        ' — rezervace přes aplikaci MotoGo24',
      'qty', 1, 'unit_price', -v_loyalty));
  END IF;

  IF v_late_pickup > 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Sleva 50 % na 1. den (pozdní vyzvednutí)',
      'qty', 1, 'unit_price', -v_late_pickup));
  END IF;

  -- D1: dorovnání na minimální platbu kartou (+) / zaokrouhlení platby kartou na
  -- celé Kč (+ do 1 Kč) / odpuštěná částka do 1 Kč (−)
  IF v_rounding <> 0 THEN
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', CASE WHEN v_rounding >= 1 THEN 'Dorovnání na minimální platbu kartou (15 Kč)'
                          WHEN v_rounding > 0  THEN 'Zaokrouhlení platby kartou na celé koruny'
                          ELSE 'Zaokrouhlení – částka do 1 Kč se neúčtuje' END,
      'qty', 1, 'unit_price', v_rounding));
  END IF;

  -- Odpočet všech přijatých plateb (DP)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Odpočet dle DP ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'payment_receipt' AND status != 'cancelled'
  ), '[]'::jsonb);

  -- Vrácené peníze (existující dobropisy z úprav / refundů)
  v_items := v_items || COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || number, 'qty', 1, 'unit_price', -total))
    FROM invoices WHERE booking_id = NEW.id AND type = 'credit_note' AND status != 'cancelled'
  ), '[]'::jsonb);

  v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
              FROM jsonb_array_elements(v_items) AS item);

  -- NOVÉ #3: záporná KF = zákazník přeplatil (záloha > finální cena).
  -- Vystav dobropis na přeplatek a KF dorovnej na 0 (místo záporné KF).
  IF ROUND(v_total::numeric, 2) < 0 THEN
    v_cn_number := next_document_number('DB');
    INSERT INTO invoices (number, type, customer_id, booking_id, items,
      subtotal, tax_amount, total, issue_date, due_date, status, variable_symbol, source)
    VALUES (v_cn_number, 'credit_note', NEW.user_id, NEW.id,
      jsonb_build_array(jsonb_build_object(
        'description', 'Přeplatek – záloha převyšuje finální cenu rezervace',
        'qty', 1, 'unit_price', v_total)),     -- v_total je záporné = částka dobropisu
      v_total, 0, v_total, CURRENT_DATE, CURRENT_DATE, 'issued', v_cn_number, 'final_overpay');

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'description', 'Vráceno dobropisem ' || v_cn_number, 'qty', 1, 'unit_price', -v_total));
    v_total := (SELECT SUM((item->>'unit_price')::numeric * (item->>'qty')::numeric)
                FROM jsonb_array_elements(v_items) AS item);   -- = 0
  END IF;

  IF ROUND(v_total::numeric, 2) <> 0 THEN
    INSERT INTO debug_log (source, action, component, status, error_message, request_data)
    VALUES (
      'generate_final_invoice_on_complete', 'kf_total_not_zero', 'KF assertion', 'warning',
      'KF total != 0 (booking: ' || NEW.id || ', total: ' || v_total || ' Kč) — chybí DP/dobropis pro plné pokrytí?',
      jsonb_build_object(
        'booking_id', NEW.id, 'kf_number', v_inv_num, 'computed_total', v_total,
        'base_rental', v_base_rental, 'extras', v_extras, 'delivery', v_delivery,
        'discount', v_discount, 'loyalty_discount', v_loyalty,
        'late_pickup_discount', v_late_pickup, 'card_rounding', v_rounding, 'items', v_items,   -- D1
        'sum_dp', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='payment_receipt' AND status!='cancelled'),
        'sum_credit_notes', (SELECT COALESCE(SUM(total),0) FROM invoices
                    WHERE booking_id=NEW.id AND type='credit_note' AND status!='cancelled')
      )
    );
    RAISE WARNING 'KF % pro booking % má total=% Kč (očekáváno 0). Zaloggováno do debug_log.',
      v_inv_num, NEW.id, v_total;
  END IF;

  IF NOT v_gear THEN                             -- GEAR 20261023db: výbava bez kódu VRACENI
  v_booking_short := UPPER(RIGHT(REPLACE(NEW.id::text, '-', ''), 8));
  v_promo_code    := 'VRACENI-' || v_booking_short;

  INSERT INTO promo_codes (code, type, value, active, valid_from, valid_to, max_uses, used_count)
  VALUES (v_promo_code, 'fixed', 200, true, now(),
          (CURRENT_DATE + INTERVAL '1 year')::timestamptz, 1, 0)
  ON CONFLICT (code) DO NOTHING;
  END IF;                                        -- GEAR 20261023db

  INSERT INTO invoices (
    number, type, customer_id, booking_id, items, subtotal, tax_amount, total,
    issue_date, due_date, status, variable_symbol, source
  )
  VALUES (
    v_inv_num, 'final', NEW.user_id, NEW.id, v_items, v_total, 0, v_total,
    CURRENT_DATE, CURRENT_DATE, 'paid', v_inv_num, 'final_summary'
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'generate_final_invoice_on_complete failed for booking %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
