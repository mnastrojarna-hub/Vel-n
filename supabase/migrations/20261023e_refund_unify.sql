-- =============================================================================
-- 2026-10-23 (e): Jednotná vratka při zkrácení/stornu + změny termínu výpůjčky
-- výbavy (rozhodnutí majitele §1.11, DESIGN-GEAR).
-- PRAVIDLO (všechny rezervace, web, appka, AI, sdílené jádro): pásmo vratky se
-- počítá od TEĎ do AKTUÁLNÍHO začátku rezervace (před změnou) v čase vyzvednutí
-- (nejdřívějším pro daný den začátku — refund_pickup_time) v Europe/Prague: ≥168 h → 100 %, ≥48 h → 50 %, jinak 0 % ceny odebraných dní.
-- Dřív: web „Zkrátit" k NOVÉMU konci/začátku, jádro k NOVÉMU začátku, storno
-- k 00:00 UTC dne začátku (bez času vyzvednutí). Strop po posunu termínu
-- (_storno_cap_after_move) i rozpad slevy (_apply_discount_variant_b) beze změny.
-- Výbava (booking_kind='gear'): cena dne = gear_per_day; přidané dny (posun,
-- prodloužení) hlídají uzavírku pobočky, max. délku, horizont a sklad
-- (gear_stock_check; i při přímém zápisu serveru — trigger trg_zzz_gear_lines_days).
-- Soubory (limit velikosti souboru, bytové pořadí názvu): e (pomocné funkce),
-- e_a (storno + zkrácení), e_b (posun, extend_booking), e_c
-- (_apply_booking_changes_core), e_d (odebrání kusu výbavy). Idempotentní.
-- =============================================================================

-- ---- 1) Pásmo vratky ---------------------------------------------------------
-- Čas vyzvednutí pro pásmo (bezpečnostní review 2026-10-23): zákazník si čas vyzvednutí
-- mění zdarma, takže těsně před stornem/zkrácením by ho posunul na později a skočil
-- o pásmo výš (50 → 100 %). Pásmo proto počítá k NEJDŘÍVĚJŠÍMU času vyzvednutí, který
-- rezervace měla od posledního nastavení dne začátku (posun dne začátku řeší strop
-- _storno_cap_after_move). Sloupec drží trigger při KAŽDÉM zápisu (hodnota od klienta
-- se ignoruje); starší řádky = NULL → LEAST(NULL, pickup_time) = pickup_time a první
-- změna času uloží ten původní. Volající: LEAST(refund_pickup_time, pickup_time).
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS refund_pickup_time time;
COMMENT ON COLUMN public.bookings.refund_pickup_time IS
  'Nejdřívější čas vyzvednutí od posledního nastavení dne začátku — pásmo vratky (_refund_tier_pct) se počítá k LEAST(refund_pickup_time, pickup_time). Plní trigger trg_zzzz_booking_refund_pickup_time, nezapisovat ručně. 2026-10-23e.';

CREATE OR REPLACE FUNCTION public._booking_refund_pickup_time()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR (NEW.start_date AT TIME ZONE 'Europe/Prague')::date IS DISTINCT FROM (OLD.start_date AT TIME ZONE 'Europe/Prague')::date THEN
    NEW.refund_pickup_time := NEW.pickup_time;
  ELSE
    NEW.refund_pickup_time := LEAST(COALESCE(OLD.refund_pickup_time, OLD.pickup_time), NEW.pickup_time);
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._booking_refund_pickup_time() FROM PUBLIC, anon, authenticated;
-- BEFORE na každý zápis (ne jen UPDATE OF pickup_time — jinak by šel sloupec podvrhnout
-- samostatným UPDATE); jméno řadí trigger za ostatní BEFORE triggery (vidí výsledný čas).
DROP TRIGGER IF EXISTS trg_zzzz_booking_refund_pickup_time ON public.bookings;
CREATE TRIGGER trg_zzzz_booking_refund_pickup_time BEFORE INSERT OR UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._booking_refund_pickup_time();

-- Okamžik převzetí: datum začátku v Praze + čas vyzvednutí (výchozí 09:00).
-- Datum se bere v pražském čase, takže sedí UTC půlnoc (web) i pražská půlnoc.
CREATE OR REPLACE FUNCTION public._refund_tier_ref(p_start timestamptz, p_pickup_time time)
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT ((p_start AT TIME ZONE 'Europe/Prague')::date + COALESCE(p_pickup_time, TIME '09:00'))
         AT TIME ZONE 'Europe/Prague';
$$;

CREATE OR REPLACE FUNCTION public._refund_tier_pct(p_start timestamptz, p_pickup_time time,
  p_now timestamptz DEFAULT now())
RETURNS integer LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p_start IS NULL THEN 0
    WHEN EXTRACT(EPOCH FROM (public._refund_tier_ref(p_start, p_pickup_time) - COALESCE(p_now, now()))) / 3600 >= 168 THEN 100
    WHEN EXTRACT(EPOCH FROM (public._refund_tier_ref(p_start, p_pickup_time) - COALESCE(p_now, now()))) / 3600 >= 48 THEN 50
    ELSE 0 END;
$$;
COMMENT ON FUNCTION public._refund_tier_pct(timestamptz, time, timestamptz) IS
  'Pásmo vratky (storno, zkrácení, odebrání kusu výbavy): hodiny od p_now do začátku rezervace v čase vyzvednutí (Praha). ≥168 h 100, ≥48 h 50, jinak 0. Volající ještě aplikuje _storno_cap_after_move. 2026-10-23e.';

REVOKE ALL ON FUNCTION public._refund_tier_ref(timestamptz, time) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._refund_tier_pct(timestamptz, time, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._refund_tier_ref(timestamptz, time) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._refund_tier_pct(timestamptz, time, timestamptz) TO authenticated, service_role;

-- ---- 2) Výbava: řádky gear_lines podle počtu dní ------------------------------
-- total každého řádku = price_per_day × dny (cena za den se při změně termínu nemění).
CREATE OR REPLACE FUNCTION public._gear_lines_for_days(p_lines jsonb, p_days integer)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN jsonb_typeof(p_lines) = 'array' THEN
    COALESCE((SELECT jsonb_agg(CASE WHEN jsonb_typeof(x.l) = 'object' AND x.l ? 'price_per_day'
                                    THEN x.l || jsonb_build_object('total', (x.l->>'price_per_day')::numeric * GREATEST(p_days, 0))
                                    ELSE x.l END ORDER BY x.i)
                FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS x(l, i)), '[]'::jsonb)
  ELSE p_lines END;
$$;
REVOKE ALL ON FUNCTION public._gear_lines_for_days(jsonb, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._gear_lines_for_days(jsonb, integer) TO authenticated, service_role;

-- ---- 3) Výbava: kontrola PŘIDANÝCH dní (posun / prodloužení) -----------------
-- Sklad jen pro přidané dny (p_os/p_oe = dosavadní termín na téže pobočce; NULL =
-- celý nový termín), bez této rezervace; stejný zámek a výpočet jako založení
-- (_gear_prepare / _gear_stock_shortfall, 20261023b). '[]' = vše volné / kontrola vypnutá.
CREATE OR REPLACE FUNCTION public._gear_added_days_shortfall(p_booking_id uuid, p_branch_id uuid, p_sizes jsonb,
  p_os date, p_oe date, p_new_start date, p_new_end date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_seg record; v_short jsonb := '[]'::jsonb;
BEGIN
  IF p_branch_id IS NULL OR p_new_start IS NULL OR p_new_end IS NULL OR p_new_end < p_new_start
     OR NOT public._gear_stock_check_on('gear_rental') THEN
    RETURN v_short;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('gear_stock'), hashtext(p_branch_id::text));
  FOR v_seg IN SELECT * FROM (VALUES (p_new_start, CASE WHEN p_os IS NULL THEN p_new_end ELSE LEAST(p_new_end, p_os - 1) END),
                                     (GREATEST(p_new_start, p_oe + 1), CASE WHEN p_oe IS NULL THEN NULL ELSE p_new_end END)) s(a, z)
                WHERE s.a <= s.z LOOP
    v_short := v_short || COALESCE(public._gear_stock_shortfall(p_branch_id, v_seg.a, v_seg.z, p_sizes, p_booking_id), '[]'::jsonb);
  END LOOP;
  RETURN COALESCE((SELECT jsonb_agg(DISTINCT e) FROM jsonb_array_elements(v_short) e), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public._gear_added_days_shortfall(uuid, uuid, jsonb, date, date, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_added_days_shortfall(uuid, uuid, jsonb, date, date, date, date) TO service_role;

-- NULL = v pořádku, jinak chybový objekt {success:false, error:…}. Zkrácení nic
-- nekontroluje. Uzavírka = celý nový termín (stejně jako check_booking_branch_open),
-- délka = app_settings.gear_rental.max_days (jen když se termín prodlužuje),
-- horizont = max_ahead_days pro začátek (jako založení; jen posun na později),
-- sklad = jen přidané dny, bez této rezervace.
CREATE OR REPLACE FUNCTION public._gear_change_dates_check(p_booking_id uuid, p_new_start date, p_new_end date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b bookings%ROWTYPE; v_os date; v_oe date; v_max int; v_ahead int; v_cfg jsonb; v_short jsonb;
BEGIN
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.booking_kind IS DISTINCT FROM 'gear' THEN RETURN NULL; END IF;
  IF p_new_start IS NULL OR p_new_end IS NULL OR p_new_end < p_new_start THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_range');
  END IF;
  v_os := v_b.start_date::date; v_oe := v_b.end_date::date;
  IF p_new_start >= v_os AND p_new_end <= v_oe THEN RETURN NULL; END IF;

  SELECT value INTO v_cfg FROM app_settings WHERE key = 'gear_rental';
  v_max := LEAST(GREATEST(COALESCE((v_cfg->>'max_days')::int, 30), 1), 366);
  v_ahead := LEAST(GREATEST(COALESCE((v_cfg->>'max_ahead_days')::int, 400), 1), 800);
  IF (p_new_end - p_new_start) + 1 > GREATEST(v_max, (v_oe - v_os) + 1) THEN
    RETURN jsonb_build_object('success', false, 'error', 'too_long', 'max_days', v_max);
  END IF;
  IF p_new_start > v_os AND p_new_start > (now() AT TIME ZONE 'Europe/Prague')::date + v_ahead THEN
    RETURN jsonb_build_object('success', false, 'error', 'too_far', 'max_ahead_days', v_ahead);
  END IF;
  IF public.branch_is_closed(v_b.branch_id, p_new_start, p_new_end) THEN
    RETURN jsonb_build_object('success', false, 'error', 'branch_closed');
  END IF;

  v_short := public._gear_added_days_shortfall(v_b.id, v_b.branch_id,
    jsonb_strip_nulls(jsonb_build_object('helmet', v_b.helmet_size, 'jacket', v_b.jacket_size,
      'pants', v_b.pants_size, 'gloves', v_b.gloves_size, 'boots', v_b.boots_size)),
    v_os, v_oe, p_new_start, p_new_end);
  IF jsonb_array_length(v_short) > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'out_of_stock', 'items', v_short);
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public._gear_change_dates_check(uuid, date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gear_change_dates_check(uuid, date, date) TO service_role;

-- ---- 4) Trigger: řádky podle dní + sklad i při zápisu mimo RPC -----------------
-- Zaplacené prodloužení zapisuje webhook přímo (extension-apply-columns), Velín
-- a obsluha také: změna termínu gear řádku přepočte total řádků, pokud je volající
-- v témže UPDATE sám nezměnil. Přidané dny se znovu ověří proti skladu (souběh
-- dvou plateb o poslední kus: náhled v jádru zámek nedrží) — chyba P0001
-- „out_of_stock“ → webhook změnu nezapíše; main po hotfixu #2213 jen zaloguje debug_log
-- extension_change_apply_failed (žádná automatická vratka ani upozornění) → platbu řeší obsluha ve Velínu.
-- Admin (Velín) sklad jen varuje (admin_update_gear_booking) → u něj se nehlídá.
-- SECURITY DEFINER: pomocné funkce nemají EXECUTE pro všechny role. Jméno řadí
-- trigger za strážce.
CREATE OR REPLACE FUNCTION public._gear_lines_follow_days()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_same boolean; v_short jsonb;
BEGIN
  IF NEW.booking_kind = 'gear' AND jsonb_typeof(NEW.gear_lines) = 'array'
     AND NEW.gear_lines IS NOT DISTINCT FROM OLD.gear_lines
     AND (NEW.start_date::date IS DISTINCT FROM OLD.start_date::date
          OR NEW.end_date::date IS DISTINCT FROM OLD.end_date::date) THEN
    NEW.gear_lines := public._gear_lines_for_days(NEW.gear_lines, (NEW.end_date::date - NEW.start_date::date) + 1);
  END IF;

  IF NEW.booking_kind = 'gear' AND NEW.status IN ('pending', 'reserved', 'active') AND NEW.is_test IS NOT TRUE
     AND (NEW.start_date::date < OLD.start_date::date OR NEW.end_date::date > OLD.end_date::date)
     AND NOT public.is_admin() THEN
    v_same := NEW.branch_id IS NOT DISTINCT FROM OLD.branch_id;
    v_short := public._gear_added_days_shortfall(NEW.id, NEW.branch_id,
      jsonb_strip_nulls(jsonb_build_object('helmet', NEW.helmet_size, 'jacket', NEW.jacket_size,
        'pants', NEW.pants_size, 'gloves', NEW.gloves_size, 'boots', NEW.boots_size)),
      CASE WHEN v_same THEN OLD.start_date::date END, CASE WHEN v_same THEN OLD.end_date::date END,
      NEW.start_date::date, NEW.end_date::date);
    IF jsonb_array_length(v_short) > 0 THEN
      RAISE EXCEPTION 'out_of_stock: výbava v přidaných dnech není volná %', v_short::text
        USING ERRCODE = 'P0001', HINT = 'gear_stock_check';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._gear_lines_follow_days() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_zzz_gear_lines_days ON public.bookings;
CREATE TRIGGER trg_zzz_gear_lines_days BEFORE UPDATE OF start_date, end_date ON public.bookings
  FOR EACH ROW WHEN (NEW.booking_kind = 'gear') EXECUTE FUNCTION public._gear_lines_follow_days();

NOTIFY pgrst, 'reload schema';
