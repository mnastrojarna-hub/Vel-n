-- =============================================================================
-- 2026-10-23 (db): Výpůjčka JEN výbavy — konečná faktura (KF) a účetní záznam.
-- Navazuje na 20261023a (booking_kind/gear_lines), 20261023d (e-maily), 20261023da (smlouva).
--
-- 1) generate_final_invoice_on_complete: tělo 1:1 se živou DB (snapshot 2026-10-22) +
--    větev „GEAR 20261023db“: položky KF z bookings.gear_lines („Půjčení výbavy: <název>
--    (<velikosti>) — termín“, množství = dny, cena = Kč/den); rozdíl proti ceně rezervace
--    (zkrácení s vratkou < 100 %, ruční úprava) samostatným řádkem → součet KF dál 0 proti
--    DP/dobropisům; sleva u výbavy = dárkový poukaz (kód i z booking_discounts); BEZ řádku
--    motorky a BEZ slevového kódu VRACENI (rozhodnutí majitele §7). Motorky beze změny
--    (jen navíc SET search_path = public). Stejná větev je zrcadlená do čekajícího návrhu
--    .claude/handoff/sql-paydec/20261016p1_card_rounding.sql (ten funkci také předefinovává).
--    POJISTKA POŘADÍ: je-li p1 (sloupec bookings.card_rounding, řádek dorovnání D1) živě DŘÍV,
--    tělo níž by D1 tiše smazalo → živá verze se ponechá, pokud už obsahuje „GEAR 20261023db“
--    (p1 se zrcadlem = D1 + GEAR); bez zrcadla migrace SPADNE (sloučit ručně podle p1).
-- 2) auto_accounting_on_booking_paid: u výbavy kategorie 'půjčení výbavy' a popis
--    „Platba za rezervaci výbavy #…“ (Velín revenueUtils pozná příjem podle popisu);
--    navíc SET search_path = public (živá verze ho nemá; accounting_entries je v public).
-- Idempotentní (CREATE OR REPLACE, práva zůstávají). Bez BEGIN/COMMIT.
-- =============================================================================

-- ---- 1) Konečná faktura (KF) --------------------------------------------------
-- Pojistka pořadí s návrhem 20261016p1 (D1): živou KF s D1 + GEAR si odlož a po CREATE níž vrať.
DO $$
DECLARE v_def text;
BEGIN
  PERFORM set_config('motogo.kf_keep_def', '', false);   -- session (funguje i bez --single-transaction)
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'bookings' AND column_name = 'card_rounding') THEN
    v_def := pg_get_functiondef('public.generate_final_invoice_on_complete()'::regprocedure);
    IF position('card_rounding' IN v_def) > 0 THEN
      IF position('GEAR 20261023db' IN v_def) = 0 THEN
        RAISE EXCEPTION '20261023db: živá KF už má dorovnání D1 (20261016p1) bez větve GEAR — tělo níž by D1 smazalo. '
          'Vezmi generate_final_invoice_on_complete z .claude/handoff/sql-paydec/20261016p1_card_rounding.sql (D1 + GEAR).';
      END IF;
      PERFORM set_config('motogo.kf_keep_def', v_def, false);
    END IF;
  END IF;
END $$;

-- Tělo 1:1 se živou DB (snapshot 2026-10-22); změny označené „GEAR 20261023db“.
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
  v_booking_short text; v_promo_code text;
  v_cn_number text;                              -- NOVÉ #3
  v_gear boolean;                                -- GEAR 20261023db: výpůjčka jen výbavy (viz první příkaz)
  v_gear_days int; v_gear_sum numeric;           -- GEAR 20261023db
BEGIN
  -- GEAR 20261023db: booking_kind přes to_jsonb(NEW), NE v DECLARE (chybu inicializace DECLARE
  -- EXCEPTION níž nechytí → na DB bez sloupce booking_kind by spadlo KAŽDÉ dokončení rezervace).
  v_gear := COALESCE(to_jsonb(NEW)->>'booking_kind', 'moto') = 'gear';
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
  v_base_rental := COALESCE(NEW.total_price, 0) - v_extras - v_delivery
                   + v_discount + v_loyalty + v_late_pickup;

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
        'late_pickup_discount', v_late_pickup, 'items', v_items,
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

DO $$
DECLARE v_def text := current_setting('motogo.kf_keep_def', true);
BEGIN
  IF COALESCE(v_def, '') <> '' THEN
    EXECUTE v_def;                                       -- živá verze D1 + GEAR zůstává
    PERFORM set_config('motogo.kf_keep_def', '', false);
    RAISE NOTICE '20261023db: KF ponechána ve verzi 20261016p1 (D1 + GEAR)';
  END IF;
END $$;

-- ---- 2) Účetní záznam při zaplacení ---------------------------------------------
-- Tělo 1:1 se živou DB (20260611) + SET search_path; u výbavy jiná kategorie a popis.
CREATE OR REPLACE FUNCTION public.auto_accounting_on_booking_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
BEGIN
  BEGIN
    IF NEW.payment_status = 'paid' AND (OLD IS NULL OR OLD.payment_status IS DISTINCT FROM 'paid') THEN
      INSERT INTO accounting_entries (booking_id, type, amount, description, category, date, created_at)
      VALUES (NEW.id, 'income', COALESCE(NEW.total_price, 0),
              CASE WHEN NEW.booking_kind = 'gear' THEN 'Platba za rezervaci výbavy #'   -- GEAR 20261023db
                   ELSE 'Platba za rezervaci #' END || substr(NEW.id::text, 1, 8),
              CASE WHEN NEW.booking_kind = 'gear' THEN 'půjčení výbavy' ELSE 'pronájem' END,
              CURRENT_DATE, now());
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'auto_accounting_on_booking_paid: % — accounting skipped', SQLERRM;
  END;
  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
