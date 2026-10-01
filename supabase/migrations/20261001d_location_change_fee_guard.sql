-- =============================================================================
-- Úprava místa rezervace: přistavení/odvoz počítá SERVER po stranách
-- Migrace: 20261001d_location_change_fee_guard.sql
--
-- INCIDENT 2026-10-01 18:22 (web /upravit-rezervaci, záložka Místo):
-- AKTIVNÍ rezervace (motorka už převzatá) s přistavením na adresu (poplatek X,
-- vše v delivery_fee) a vrácením na pobočce. Zákaznice změnila vrácení na
-- odvoz z adresy (poplatek Y ≈ X, skoro stejné místo). Místo doplatku Y jí
-- systém VRÁTIL 11 Kč:
--   • web u aktivní rezervace vykreslí stranu vyzvednutí zamčenou BEZ skrytého
--     pole pickupFee → poslal p_new_pickup_method='delivery', p_new_pickup_fee=0;
--   • jádro připsalo CELÉ staré delivery_fee vyzvednutí a starý odvoz bralo
--     jako 0: (0 − X) + (Y − 0) = Y − X = −11 → refund přes process-refund,
--     delivery_fee přepsáno na Y (poplatek za přistavení z rezervace zmizel).
-- Reprodukováno 1:1 na lokální kopii živého schématu (snapshot 2026-10-01):
-- net_diff −11, refund_amount 11, total 17 310 → 17 299.
--
-- OPRAVA (server je autoritativní — klient už nemůže cenu podstrčit):
--  1) přistavení = metoda 'delivery' NEBO vyplněná adresa (web/AI rezervace
--     nechávají 'store' + adresu; shodně s generate-document a appkou);
--  2) NEZMĚNĚNÁ strana (druh i místo) si nechává svůj podíl delivery_fee —
--     poslaný poplatek se u ní ignoruje; místo se posuzuje dle souřadnic
--     (> ~50 m), bez nich dle textu adresy;
--  3) aktivní rezervace → strana vyzvednutí je neměnná (`active_pickup_locked`
--     při pokusu o změnu, jinak se parametry vyzvednutí ignorují);
--  4) nově přidaná / přesunutá strana stojí aspoň `_delivery_fee_floor`
--     (1 000 Kč + 40 Kč × vzdušná vzdálenost od Mezné − 2 km tolerance) —
--     silniční trasa (web i appka: 1000 + 40 × km) nikdy není kratší, takže
--     poctivý klient podlahu nepozná; poplatek 0 / chybějící adresa už
--     nedá přistavení zdarma; bez GPS (AI agent souřadnice neposílá) přesun
--     adresy nikdy nezlevní pod dosavadní podíl strany → žádná vratka;
--  5) delivery_fee = staré + rozdíly změněných stran (zbytek zůstává). Obě
--     strany přistavením → přesné podíly z poslední úpravy v historii
--     (`fee_split_exact`), jinak odhad v poměru podlah dle uložených GPS (bez
--     nich půl na půl) — u ODHADU přesun adresy nevrací peníze; strana
--     přepnutá na pobočku → adresa/GPS se smažou, přesun adresy bez nových
--     GPS → staré GPS se smažou;
--  6) dry-run i commit vrací `new_delivery_fee`, `location_changed` +
--     breakdown pickup/return fee from/to a `fee_split_exact` (process-payment
--     je ukládá do metadat, webhook je zapíše); historie nese
--     from/to_delivery_fee, podíly stran a `fee_split_exact`;
--  7) `apply_booking_change_light` (AI agent BEZ hesla): změna místa už není
--     „nulový dopad" → vždy plné ověření (konec souboru).
-- Signatura funkce se NEMĚNÍ (overload by v PostgREST dal ambiguity 300).
-- Tělo jinak PŘEVZATO BEZE ZMĚNY z 20260921e (= živá definice ze snapshotu
-- 2026-10-01, ověřeno diffem). Idempotentní (CREATE OR REPLACE).
-- =============================================================================

-- Normalizace adresy pro porovnání (malá písmena, bez okrajových/vícenásobných mezer).
CREATE OR REPLACE FUNCTION public._addr_norm(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT NULLIF(lower(regexp_replace(btrim(COALESCE(p, '')), '\s+', ' ', 'g')), '')
$$;

-- Spodní mez poplatku za přistavení/odvoz jedné strany. Web i appka účtují
-- 1000 Kč + 40 Kč × SILNIČNÍ km od pobočky Mezná (49.3464, 15.2119); silnice
-- nikdy není kratší než vzdušná čára, tolerance p_tolerance_km kryje odchylku
-- geokódování výchozího bodu. Bez souřadnic / s nesmyslnými (> 2000 km) jen
-- základ 1000 Kč. POZOR: při změně sazeb na webu/v appce upravit i zde.
CREATE OR REPLACE FUNCTION public._delivery_fee_floor(
  p_lat double precision, p_lng double precision, p_tolerance_km numeric DEFAULT 2)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p_lat IS NULL OR p_lng IS NULL THEN 1000::numeric
    ELSE (SELECT CASE WHEN d > 2000 THEN 1000::numeric
                      ELSE ROUND(1000 + 40 * GREATEST(0, d - COALESCE(p_tolerance_km, 0))) END
          FROM (SELECT (2 * 6371 * asin(LEAST(1::double precision, sqrt(
                   power(sin(radians(p_lat - 49.3464) / 2), 2)
                 + cos(radians(49.3464)) * cos(radians(p_lat)) * power(sin(radians(p_lng - 15.2119) / 2), 2)))))::numeric AS d) s)
  END
$$;

CREATE OR REPLACE FUNCTION "public"."_apply_booking_changes_core"(
  "p_user_id" "uuid", "p_booking_id" "uuid", "p_new_start" "date", "p_new_end" "date",
  "p_new_moto_id" "uuid", "p_new_pickup_method" "text", "p_new_pickup_address" "text",
  "p_new_pickup_lat" double precision, "p_new_pickup_lng" double precision, "p_new_pickup_fee" numeric,
  "p_new_return_method" "text", "p_new_return_address" "text", "p_new_return_lat" double precision,
  "p_new_return_lng" double precision, "p_new_return_fee" numeric, "p_reason" "text",
  "p_dry_run" boolean, "p_source" "text", "p_new_pickup_time" time DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b               bookings%ROWTYPE;
  v_old_moto        motorcycles%ROWTYPE;
  v_new_moto        motorcycles%ROWTYPE;
  v_use_moto        motorcycles%ROWTYPE;
  v_fs date := NULL;  v_fe date := NULL;
  v_old_dates_total numeric := 0;
  v_new_dates_total numeric := 0;
  v_dates_diff      numeric := 0;
  v_moto_diff       numeric := 0;
  v_pickup_fee_diff numeric := 0;
  v_return_fee_diff numeric := 0;
  v_gross_diff      numeric := 0;
  v_net_diff        numeric := 0;
  v_refund          numeric := 0;
  v_storno_pct      int := 100;
  v_now             timestamptz := now();
  v_overlap_count   int;
  v_user_lic        text[];
  v_lic_required    text;
  v_d               date;
  v_dow             int;
  v_p_old           numeric;
  v_p_new           numeric;
  v_history_entry   jsonb;
  v_is_active       boolean;
  v_payment_required boolean := false;
  v_changed         boolean := false;
  v_dtype           text;
  v_calc            jsonb;
  v_new_total       numeric;
  v_new_discount    numeric;
  v_url             text;
  v_key             text;
  v_old_late        numeric := 0;
  v_new_late        numeric := 0;
  v_eff_pickup      time;
  v_pickup_changed  boolean := false;
  v_loy_level       int := 0;
  v_loy_pct         numeric := 0;
  v_loy_disc        numeric := 0;
  v_new_on_old_total numeric := 0;   -- nový rozsah oceněný ceníkem STARÉ motorky
  v_new_late_old    numeric := 0;    -- late sleva nového rozsahu dle STARÉ motorky
  v_moto_swapped    boolean := false;
  v_refund_reason   text;
  -- 2026-10-01: přistavení/odvoz po stranách (incident „vratka −11 Kč")
  v_old_pd          boolean;          -- vyzvednutí BYLO přistavením
  v_old_rd          boolean;          -- vrácení BYLO odvozem z adresy
  v_new_pd          boolean;
  v_new_rd          boolean;
  v_pick_loc_changed boolean := false;
  v_ret_loc_changed  boolean := false;
  v_pick_side_changed boolean := false;
  v_ret_side_changed  boolean := false;
  v_old_fee         numeric := 0;
  v_old_pfee        numeric := 0;
  v_old_rfee        numeric := 0;
  v_new_pfee        numeric := 0;
  v_new_rfee        numeric := 0;
  v_new_delivery_fee numeric;
  v_wp              numeric;
  v_wr              numeric;
  v_hp              numeric;
  v_hr              numeric;
  v_split_est       boolean := false;   -- podíly stran jen odhadnuté
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND OR v_b.user_id <> p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_b.status NOT IN ('reserved','active') OR v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'wrong_status');
  END IF;

  v_is_active := (v_b.status = 'active');
  v_eff_pickup := COALESCE(p_new_pickup_time, v_b.pickup_time);
  v_pickup_changed := (p_new_pickup_time IS NOT NULL AND p_new_pickup_time IS DISTINCT FROM v_b.pickup_time);

  v_fs := COALESCE(p_new_start, v_b.start_date);
  v_fe := COALESCE(p_new_end,   v_b.end_date);
  IF v_is_active AND v_fs <> v_b.start_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_start_locked');
  END IF;
  IF v_fs > v_fe THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_range');
  END IF;

  SELECT * INTO v_old_moto FROM motorcycles WHERE id = v_b.moto_id;
  IF p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id THEN
    IF v_is_active THEN
      RETURN jsonb_build_object('success', false, 'error', 'active_moto_locked');
    END IF;
    -- 2026-09-12: i 'maintenance' (web /upravit-rezervaci i appka je nabízejí —
    -- servisní dny blokuje kontrola maintenance_log níže; dřív server vracel
    -- moto_not_found a web výměnu neprovedl).
    SELECT * INTO v_new_moto FROM motorcycles WHERE id = p_new_moto_id AND status IN ('active','maintenance');
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'moto_not_found');
    END IF;
    -- rev. 2026-09-21: vozík vydává jen OBSLUŽNÁ pobočka, takže rezervace
    -- s přiřazeným vozíkem nesmí přejet na motorku ze samoobslužné.
    -- Umístění je ZÁMĚRNÉ: mezi ranými validacemi, tedy PŘED `IF p_dry_run OR
    -- v_payment_required THEN RETURN` i před jakýmkoli zápisem. Web
    -- (/upravit-rezervaci → „Změna motorky") posílá nejdřív dry-run, pak
    -- zákazníka na Stripe a změnu commituje AŽ PO platbě (a to přímým
    -- UPDATE, který se `_apply_booking_changes_core` ani nedotkne) — kontrola
    -- proto MUSÍ padnout už v dry-runu, jinak by se strhly peníze a změna se
    -- stejně nesměla provést. Stejná úvaha jako u `split_booking_moto_swap`
    -- rev.9 (20260921d) a důvod, proč `20260921c` `moto_id` z triggeru
    -- `trg_check_trailer_overlap` odebralo.
    IF v_b.trailer_moto_id IS NOT NULL AND public.moto_is_self_service(p_new_moto_id) THEN
      RETURN jsonb_build_object('success', false, 'error', 'trailer_staffed_only');
    END IF;
    -- OR-match přes VŠECHNY přijímané skupiny ŘP (license_groups; fallback
    -- [license_required]) — parita s katalogem/appkou.
    DECLARE
      v_groups text[] := (SELECT COALESCE(NULLIF(m.license_groups, '{}'::text[]),
                                          ARRAY[COALESCE(m.license_required::text, 'A')])
                            FROM motorcycles m WHERE m.id = v_new_moto.id);
    BEGIN
      IF NOT ('N' = ANY(COALESCE(v_groups, ARRAY['A']))) THEN
        SELECT license_group INTO v_user_lic FROM profiles WHERE id = p_user_id;
        IF v_user_lic IS NULL OR NOT EXISTS (
          SELECT 1 FROM unnest(COALESCE(v_groups, ARRAY['A'])) g
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
    v_use_moto := v_new_moto;
    v_moto_swapped := true;
  ELSE
    v_use_moto := v_old_moto;
  END IF;

  IF p_new_start IS NOT NULL OR p_new_end IS NOT NULL OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id) THEN
    SELECT COUNT(*) INTO v_overlap_count FROM bookings b2
      WHERE b2.moto_id = v_use_moto.id
        AND b2.id <> p_booking_id
        AND b2.status IN ('pending','reserved','active')
        AND NOT (b2.end_date < v_fs OR b2.start_date > v_fe);
    IF v_overlap_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'overlap');
    END IF;
    -- Plánovaný SERVIS blokuje termín i server-side (stejná logika jako
    -- split_booking_moto_swap).
    SELECT COUNT(*) INTO v_overlap_count FROM maintenance_log m
      WHERE m.moto_id = v_use_moto.id
        AND m.service_date IS NOT NULL AND m.completed_date IS NULL
        AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
        AND daterange(m.service_date::date, COALESCE(m.scheduled_date, m.service_date)::date, '[]')
            && daterange(v_fs, v_fe, '[]');
    IF v_overlap_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'overlap');
    END IF;
  END IF;

  v_d := v_b.start_date;
  WHILE v_d <= v_b.end_date LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_old := CASE v_dow
      WHEN 1 THEN COALESCE(v_old_moto.price_mon, v_old_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_old_moto.price_tue, v_old_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_old_moto.price_wed, v_old_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_old_moto.price_thu, v_old_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_old_moto.price_fri, v_old_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_old_moto.price_sat, v_old_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_old_moto.price_sun, v_old_moto.price_weekend, 0)
    END;
    v_old_dates_total := v_old_dates_total + v_p_old;
    v_d := v_d + 1;
  END LOOP;

  v_d := v_fs;
  WHILE v_d <= v_fe LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_new := CASE v_dow
      WHEN 1 THEN COALESCE(v_use_moto.price_mon, v_use_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_use_moto.price_tue, v_use_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_use_moto.price_wed, v_use_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_use_moto.price_thu, v_use_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_use_moto.price_fri, v_use_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_use_moto.price_sat, v_use_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_use_moto.price_sun, v_use_moto.price_weekend, 0)
    END;
    v_new_dates_total := v_new_dates_total + v_p_new;
    v_d := v_d + 1;
  END LOOP;

  -- Nový rozsah oceněný ceníkem STARÉ motorky — základ rozdílu TERMÍNU
  -- (storno se krátí jen odebrané dny, ne rozdíl ceníku motorek).
  v_d := v_fs;
  WHILE v_d <= v_fe LOOP
    v_dow := EXTRACT(ISODOW FROM v_d)::int;
    v_p_old := CASE v_dow
      WHEN 1 THEN COALESCE(v_old_moto.price_mon, v_old_moto.price_weekday, 0)
      WHEN 2 THEN COALESCE(v_old_moto.price_tue, v_old_moto.price_weekday, 0)
      WHEN 3 THEN COALESCE(v_old_moto.price_wed, v_old_moto.price_weekday, 0)
      WHEN 4 THEN COALESCE(v_old_moto.price_thu, v_old_moto.price_weekday, 0)
      WHEN 5 THEN COALESCE(v_old_moto.price_fri, v_old_moto.price_weekday, 0)
      WHEN 6 THEN COALESCE(v_old_moto.price_sat, v_old_moto.price_weekend, 0)
      WHEN 7 THEN COALESCE(v_old_moto.price_sun, v_old_moto.price_weekend, 0)
    END;
    v_new_on_old_total := v_new_on_old_total + v_p_old;
    v_d := v_d + 1;
  END LOOP;

  -- ── LATE PICKUP ── stará = REÁLNĚ uložená hodnota (ne přepočet — jinak by
  -- legacy rezervace bez late vykázala fantomový rozdíl); nová = přepočet pro
  -- nový obsah + efektivní čas vyzvednutí.
  v_old_late     := COALESCE(v_b.late_pickup_discount_amount, 0);
  v_new_late     := public._late_pickup_discount(v_use_moto.id, v_fs, v_fe, v_eff_pickup);
  v_new_late_old := CASE WHEN v_moto_swapped
                         THEN public._late_pickup_discount(v_old_moto.id, v_fs, v_fe, v_eff_pickup)
                         ELSE v_new_late END;

  -- ── ROZDÍL TERMÍNU (ceník STARÉ motorky) — jen tahle část podléhá stornu ──
  v_dates_diff := (v_new_on_old_total - v_new_late_old) - (v_old_dates_total - v_old_late);
  -- ── ROZDÍL VÝMĚNY MOTORKY na novém rozsahu (nový − starý ceník) — 100 % v
  -- obou směrech, storno se NEvztahuje (2026-09-12, parita split_booking_moto_swap
  -- a Velín; incident C69236EB: levnější motorka <48 h před startem → storno 0 %
  -- → rozdíl 0 Kč → žádný dobropis). ──
  v_moto_diff := CASE WHEN v_moto_swapped
                      THEN (v_new_dates_total - v_new_late) - (v_new_on_old_total - v_new_late_old)
                      ELSE 0 END;
  IF v_dates_diff < 0 THEN
    v_storno_pct := CASE
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 168 THEN 100
      WHEN EXTRACT(EPOCH FROM (v_fs::timestamptz - v_now))/3600 >= 48  THEN 50
      ELSE 0
    END;
    -- 2026-08-22c: STROP PO POSUNU TERMÍNU — jakmile byl start rezervace
    -- kdykoli posunut, vratka za odebrané dny už nikdy není 100 %
    -- (viz _storno_cap_after_move; vždy přísnější sazba pro zákazníka).
    v_storno_pct := LEAST(v_storno_pct, public._storno_cap_after_move(
      v_b.modification_history, v_b.original_start_date::date, v_b.start_date::date));
    v_dates_diff := ROUND(v_dates_diff * v_storno_pct / 100.0);
  END IF;

  -- ── PŘISTAVENÍ / ODVOZ — po stranách, server je autoritativní ──────────────
  -- 2026-10-01 (incident: aktivní rezervace, přistavení X, zákaznice přidala
  -- odvoz Y → web poslal p_new_pickup_fee=0 za zamčenou stranu vyzvednutí a
  -- jádro připsalo CELÉ staré delivery_fee vyzvednutí → rozdíl Y−X = −11 Kč
  -- = VRATKA místo doplatku Y, delivery_fee přepsáno na Y). Nově:
  --  • přistavení = metoda 'delivery' NEBO vyplněná adresa (web/AI rezervace
  --    nechávají 'store' + adresu — shodně s generate-document a appkou);
  --  • NEZMĚNĚNÁ strana si nechává svůj podíl delivery_fee — klientem poslaný
  --    poplatek se u ní ignoruje (0, přepočet trasy, cokoli);
  --  • aktivní rezervace: vyzvednutí už proběhlo → strana vyzvednutí je
  --    neměnná (pokus o změnu = active_pickup_locked, poplatek se ignoruje);
  --  • nově přidaná / přesunutá strana přistavení stojí aspoň podlahu
  --    _delivery_fee_floor (1000 Kč + 40 Kč × vzdušná čára od Mezné − 2 km;
  --    silniční trasa nikdy není kratší) → přidání přistavení NIKDY nesníží cenu;
  --  • nové delivery_fee = staré + rozdíly změněných stran (zbytek zůstává).
  v_old_pd := (v_b.pickup_method = 'delivery' OR NULLIF(btrim(COALESCE(v_b.pickup_address, '')), '') IS NOT NULL);
  v_old_rd := (v_b.return_method = 'delivery' OR NULLIF(btrim(COALESCE(v_b.return_address, '')), '') IS NOT NULL);
  -- Metoda NULL nebo shodná s uloženou = beze změny druhu (web posílá u volby
  -- „pobočka" uloženou metodu, např. 'store' i u přistavení přes adresu).
  v_new_pd := CASE WHEN p_new_pickup_method IS NULL OR p_new_pickup_method IS NOT DISTINCT FROM v_b.pickup_method
                   THEN v_old_pd ELSE p_new_pickup_method = 'delivery' END;
  v_new_rd := CASE WHEN p_new_return_method IS NULL OR p_new_return_method IS NOT DISTINCT FROM v_b.return_method
                   THEN v_old_rd ELSE p_new_return_method = 'delivery' END;
  -- Přesun adresy u strany, která přistavením zůstává: rozhoduje FYZICKÉ
  -- místo — souřadnice (posun > ~50 m); bez srovnatelných souřadnic text adresy.
  IF v_old_pd AND v_new_pd THEN
    v_pick_loc_changed := CASE
      WHEN p_new_pickup_lat IS NOT NULL AND p_new_pickup_lng IS NOT NULL
           AND v_b.pickup_lat IS NOT NULL AND v_b.pickup_lng IS NOT NULL
        THEN abs(p_new_pickup_lat - v_b.pickup_lat) > 0.0005 OR abs(p_new_pickup_lng - v_b.pickup_lng) > 0.0005
      ELSE p_new_pickup_address IS NOT NULL
           AND public._addr_norm(p_new_pickup_address) IS DISTINCT FROM public._addr_norm(v_b.pickup_address)
      END;
  END IF;
  IF v_old_rd AND v_new_rd THEN
    v_ret_loc_changed := CASE
      WHEN p_new_return_lat IS NOT NULL AND p_new_return_lng IS NOT NULL
           AND v_b.return_lat IS NOT NULL AND v_b.return_lng IS NOT NULL
        THEN abs(p_new_return_lat - v_b.return_lat) > 0.0005 OR abs(p_new_return_lng - v_b.return_lng) > 0.0005
      ELSE p_new_return_address IS NOT NULL
           AND public._addr_norm(p_new_return_address) IS DISTINCT FROM public._addr_norm(v_b.return_address)
      END;
  END IF;
  v_pick_side_changed := (v_new_pd IS DISTINCT FROM v_old_pd) OR v_pick_loc_changed;
  v_ret_side_changed  := (v_new_rd IS DISTINCT FROM v_old_rd) OR v_ret_loc_changed;
  IF v_is_active AND v_pick_side_changed THEN
    RETURN jsonb_build_object('success', false, 'error', 'active_pickup_locked');
  END IF;

  -- Podíly starého delivery_fee po stranách (DB drží jen součet). Obě strany
  -- přistavením → poměr podlah dle uložených souřadnic, bez nich půl na půl.
  v_old_fee := GREATEST(COALESCE(v_b.delivery_fee, 0), 0);
  IF v_old_pd AND v_old_rd THEN
    -- Přesný podíl z poslední úpravy (od 2026-10-01 historie nese
    -- pickup_fee_to/return_fee_to + fee_split_exact) — platí, jen když byl
    -- přesný a součet sedí na současné delivery_fee (nikdo ji mezitím nezměnil).
    BEGIN
      SELECT (x.e->>'pickup_fee_to')::numeric, (x.e->>'return_fee_to')::numeric
        INTO v_hp, v_hr
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_b.modification_history) = 'array'
                                       THEN v_b.modification_history ELSE '[]'::jsonb END)
             WITH ORDINALITY AS x(e, i)
       WHERE jsonb_typeof(x.e) = 'object' AND x.e ? 'pickup_fee_to' AND x.e ? 'return_fee_to'
         AND x.e->>'fee_split_exact' = 'true'
       ORDER BY x.i DESC LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_hp := NULL; v_hr := NULL;
    END;
    IF v_hp IS NOT NULL AND v_hr IS NOT NULL AND v_hp >= 0 AND v_hr >= 0 AND v_hp + v_hr = v_old_fee THEN
      v_old_pfee := v_hp;
      v_old_rfee := v_hr;
    ELSE
      -- Odhad v poměru podlah dle uložených GPS, bez nich půl na půl.
      v_split_est := true;
      IF v_b.pickup_lat IS NOT NULL AND v_b.pickup_lng IS NOT NULL
         AND v_b.return_lat IS NOT NULL AND v_b.return_lng IS NOT NULL THEN
        v_wp := public._delivery_fee_floor(v_b.pickup_lat, v_b.pickup_lng, 0);
        v_wr := public._delivery_fee_floor(v_b.return_lat, v_b.return_lng, 0);
      ELSE
        v_wp := 1; v_wr := 1;
      END IF;
      v_old_pfee := ROUND(v_old_fee * v_wp / (v_wp + v_wr));
      v_old_rfee := v_old_fee - v_old_pfee;
    END IF;
  ELSIF v_old_pd THEN
    v_old_pfee := v_old_fee;
  ELSIF v_old_rd THEN
    v_old_rfee := v_old_fee;
  END IF;

  v_new_pfee := CASE
    WHEN NOT v_pick_side_changed THEN v_old_pfee
    WHEN NOT v_new_pd THEN 0
    -- Bez GPS nelze vzdálenost ověřit (AI agent souřadnice neposílá): přesun
    -- adresy pak nikdy nezlevní pod dosavadní podíl strany → žádná vratka.
    -- … a u jen ODHADNUTÉHO podílu (obě strany přistavením bez přesného
    -- rozdělení z historie) přesun adresy taky nevrací (parita s appkou).
    ELSE GREATEST(ROUND(COALESCE(p_new_pickup_fee, 0)),
                  public._delivery_fee_floor(p_new_pickup_lat, p_new_pickup_lng, 2),
                  CASE WHEN p_new_pickup_lat IS NULL OR p_new_pickup_lng IS NULL
                         OR (v_split_est AND v_old_pd) THEN v_old_pfee ELSE 0 END)
    END;
  v_new_rfee := CASE
    WHEN NOT v_ret_side_changed THEN v_old_rfee
    WHEN NOT v_new_rd THEN 0
    ELSE GREATEST(ROUND(COALESCE(p_new_return_fee, 0)),
                  public._delivery_fee_floor(p_new_return_lat, p_new_return_lng, 2),
                  CASE WHEN p_new_return_lat IS NULL OR p_new_return_lng IS NULL
                         OR (v_split_est AND v_old_rd) THEN v_old_rfee ELSE 0 END)
    END;
  v_pickup_fee_diff  := v_new_pfee - v_old_pfee;
  v_return_fee_diff  := v_new_rfee - v_old_rfee;
  v_new_delivery_fee := GREATEST(0, COALESCE(v_b.delivery_fee, 0) + v_pickup_fee_diff + v_return_fee_diff);

  -- ── VĚRNOSTNÍ SLEVA (2026-08-06) — JEN app rezervace, JEN kladný rozdíl
  -- pronájmu (doplatek za přidané dny / dražší motorku). Aktuální rank
  -- zákazníka, stejný vzorec jako split_booking_moto_swap. Delivery poplatky
  -- slevě nepodléhají (parita se vznikem rezervace).
  IF COALESCE(v_b.booking_source, 'web') = 'app' AND (v_dates_diff + v_moto_diff) > 0 THEN
    v_loy_level := LEAST(20, CEIL((_loyalty_qualifying_count(v_b.user_id) + 1) / 2.0))::int;
    SELECT COALESCE(discount_percent, 0) INTO v_loy_pct FROM loyalty_levels WHERE level = v_loy_level;
    v_loy_pct := COALESCE(v_loy_pct, 0);
    v_loy_disc := ROUND((v_dates_diff + v_moto_diff) * v_loy_pct / 100.0);
  END IF;

  v_gross_diff := v_dates_diff - v_loy_disc + v_moto_diff + v_pickup_fee_diff + v_return_fee_diff;

  -- typ slevy a multi-rozklad řeší _recalc_booking_discount (krok 3c)
  v_calc  := public._recalc_booking_discount(v_b.id, v_b.total_price, v_b.discount_amount, v_gross_diff, false);
  v_net_diff     := (v_calc->>'net_diff')::numeric;
  v_new_total    := (v_calc->>'new_total')::numeric;
  v_new_discount := (v_calc->>'new_discount')::numeric;

  v_changed := (
    v_fs <> v_b.start_date OR v_fe <> v_b.end_date
    OR (p_new_moto_id IS NOT NULL AND p_new_moto_id <> v_b.moto_id)
    OR v_pickup_changed
    OR v_pick_side_changed OR v_ret_side_changed
    OR (NOT v_is_active AND p_new_pickup_method IS NOT NULL AND p_new_pickup_method IS DISTINCT FROM v_b.pickup_method)
    OR (NOT v_is_active AND p_new_pickup_address IS NOT NULL AND p_new_pickup_address IS DISTINCT FROM v_b.pickup_address)
    OR (p_new_return_method IS NOT NULL AND p_new_return_method IS DISTINCT FROM v_b.return_method)
    OR (p_new_return_address IS NOT NULL AND p_new_return_address IS DISTINCT FROM v_b.return_address)
  );
  IF NOT v_changed THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_change');
  END IF;

  v_payment_required := (v_net_diff > 0);
  v_refund := CASE WHEN v_net_diff < 0 THEN -v_net_diff ELSE 0 END;

  IF p_dry_run OR v_payment_required THEN
    RETURN jsonb_build_object(
      'success', true, 'payment_required', v_payment_required,
      'net_diff', v_net_diff, 'refund_amount', v_refund,
      'new_total', v_new_total, 'new_discount', v_new_discount,
      'new_delivery_fee', CASE WHEN v_pick_side_changed OR v_ret_side_changed THEN v_new_delivery_fee ELSE COALESCE(v_b.delivery_fee, 0) END,
      'location_changed', (v_pick_side_changed OR v_ret_side_changed),
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
      'breakdown', jsonb_build_object(
        'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
        'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
        'pickup_fee_from', v_old_pfee, 'pickup_fee_to', v_new_pfee,
        'return_fee_from', v_old_rfee, 'return_fee_to', v_new_rfee,
        'fee_split_exact', (NOT v_split_est OR (v_pick_side_changed AND v_ret_side_changed) OR NOT (v_new_pd AND v_new_rd)),
        'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
        'late_pickup_from', v_old_late, 'late_pickup_to', v_new_late,
        'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct
      )
    );
  END IF;

  v_history_entry := jsonb_build_object(
    'at', v_now,
    'from_start', v_b.start_date, 'from_end', v_b.end_date,
    'to_start', v_fs, 'to_end', v_fe,
    'from_moto', v_b.moto_id, 'to_moto', v_use_moto.id,
    'from_pickup_method', v_b.pickup_method,
    'to_pickup_method', CASE WHEN v_is_active THEN v_b.pickup_method ELSE p_new_pickup_method END,
    'from_pickup_address', v_b.pickup_address,
    'to_pickup_address', CASE WHEN v_is_active THEN v_b.pickup_address ELSE p_new_pickup_address END,
    'from_return_method', v_b.return_method, 'to_return_method', p_new_return_method,
    'from_return_address', v_b.return_address, 'to_return_address', p_new_return_address,
    'from_pickup_time', v_b.pickup_time::text, 'to_pickup_time', v_eff_pickup::text,
    'net_diff', v_net_diff, 'gross_diff', v_gross_diff,
    'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
    'refund_amount', v_refund, 'storno_pct', v_storno_pct,
    'discount_type', v_dtype, 'from_discount', v_b.discount_amount, 'to_discount', v_new_discount,
    'from_late_pickup', v_old_late, 'to_late_pickup', v_new_late,
    'loyalty_surcharge_discount', v_loy_disc, 'loyalty_percent', v_loy_pct,
    'price_diff', v_net_diff,
    'from_delivery_fee', v_b.delivery_fee,
    'to_delivery_fee', CASE WHEN v_pick_side_changed OR v_ret_side_changed THEN v_new_delivery_fee ELSE v_b.delivery_fee END,
    'pickup_fee_from', v_old_pfee, 'pickup_fee_to', v_new_pfee,
    'return_fee_from', v_old_rfee, 'return_fee_to', v_new_rfee,
    -- přesné rozdělení = žádný odhad, nebo se změnily obě strany, nebo po
    -- změně zbyla jen jedna strana přistavením (podíl = celé delivery_fee)
    'fee_split_exact', (NOT v_split_est OR (v_pick_side_changed AND v_ret_side_changed)
                        OR NOT (v_new_pd AND v_new_rd)),
    'reason', p_reason, 'source', COALESCE(p_source, 'web_customer')
  );

  UPDATE bookings SET
    original_start_date = COALESCE(original_start_date, start_date),
    original_end_date   = COALESCE(original_end_date,   end_date),
    start_date          = v_fs,
    end_date            = v_fe,
    moto_id             = v_use_moto.id,
    pickup_time         = COALESCE(p_new_pickup_time, pickup_time),
    -- Aktivní rezervace: vyzvednutí proběhlo → sloupce vyzvednutí se nemění.
    -- Strana přepnutá z přistavení na pobočku → adresa/GPS se smažou (jinak by
    -- ji generate-document, appka i Velín dál četly jako přistavení).
    pickup_method       = CASE WHEN v_is_active THEN pickup_method ELSE COALESCE(p_new_pickup_method, pickup_method) END,
    pickup_address      = CASE WHEN v_is_active THEN pickup_address
                               WHEN v_pick_side_changed AND NOT v_new_pd THEN NULL
                               ELSE COALESCE(p_new_pickup_address, pickup_address) END,
    -- … a přesun adresy bez nových GPS (AI agent) smaže staré souřadnice —
    -- patřily původní adrese.
    pickup_lat          = CASE WHEN v_is_active THEN pickup_lat
                               WHEN v_pick_side_changed AND NOT v_new_pd THEN NULL
                               WHEN v_pick_loc_changed AND (p_new_pickup_lat IS NULL OR p_new_pickup_lng IS NULL) THEN NULL
                               ELSE COALESCE(p_new_pickup_lat, pickup_lat) END,
    pickup_lng          = CASE WHEN v_is_active THEN pickup_lng
                               WHEN v_pick_side_changed AND NOT v_new_pd THEN NULL
                               WHEN v_pick_loc_changed AND (p_new_pickup_lat IS NULL OR p_new_pickup_lng IS NULL) THEN NULL
                               ELSE COALESCE(p_new_pickup_lng, pickup_lng) END,
    return_method       = COALESCE(p_new_return_method, return_method),
    return_address      = CASE WHEN v_ret_side_changed AND NOT v_new_rd THEN NULL
                               ELSE COALESCE(p_new_return_address, return_address) END,
    return_lat          = CASE WHEN v_ret_side_changed AND NOT v_new_rd THEN NULL
                               WHEN v_ret_loc_changed AND (p_new_return_lat IS NULL OR p_new_return_lng IS NULL) THEN NULL
                               ELSE COALESCE(p_new_return_lat, return_lat) END,
    return_lng          = CASE WHEN v_ret_side_changed AND NOT v_new_rd THEN NULL
                               WHEN v_ret_loc_changed AND (p_new_return_lat IS NULL OR p_new_return_lng IS NULL) THEN NULL
                               ELSE COALESCE(p_new_return_lng, return_lng) END,
    -- delivery_fee počítá VÝHRADNĚ server (staré + rozdíly změněných stran).
    delivery_fee        = CASE WHEN v_pick_side_changed OR v_ret_side_changed
                               THEN v_new_delivery_fee ELSE delivery_fee END,
    total_price         = v_new_total,
    discount_amount     = v_new_discount,
    late_pickup_discount_amount = v_new_late,
    loyalty_discount_amount = CASE WHEN v_loy_disc > 0
                                   THEN COALESCE(loyalty_discount_amount, 0) + v_loy_disc
                                   ELSE loyalty_discount_amount END,
    loyalty_level       = CASE WHEN v_loy_disc > 0 THEN v_loy_level ELSE loyalty_level END,
    loyalty_percent     = CASE WHEN v_loy_disc > 0 THEN v_loy_pct   ELSE loyalty_percent END,
    modification_history = COALESCE(modification_history, '[]'::jsonb) || v_history_entry
  WHERE id = p_booking_id;

  -- Dispatch VŽDY když je co vracet — process-refund si PI dohledá ze
  -- stripe_session_id, a bez Stripe platby vystaví dobropis + 'refund_pending'.
  IF v_refund > 0 THEN
    -- Důvod vratky = kód pro položku dobropisu (process-refund reasonTextFor):
    -- jen výměna motorky → „Výměna motorky", změna termínu → „Zkrácení
    -- rezervace", jinak „Úprava rezervace". p_reason je volný text zákazníka
    -- (web textarea) — do dokladu nepatří, zůstává jen v historii.
    v_refund_reason := CASE
      WHEN v_moto_swapped AND v_fs = v_b.start_date AND v_fe = v_b.end_date THEN 'moto_swap'
      WHEN v_fs <> v_b.start_date OR v_fe <> v_b.end_date THEN 'edit_shortening'
      ELSE 'edit' END;
    BEGIN
      SELECT value #>> '{}' INTO v_url FROM app_settings WHERE key = 'supabase_url';
      SELECT value #>> '{}' INTO v_key FROM app_settings WHERE key = 'service_role_key';
      IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/process-refund',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
          body := jsonb_build_object('booking_id', p_booking_id, 'amount', v_refund, 'reason', v_refund_reason, 'source', 'edit')
        );
      ELSE
        INSERT INTO debug_log(source, action, status, error_message, request_data)
        VALUES ('_apply_booking_changes_core','refund_dispatch_skipped_no_settings','error',
                'app_settings supabase_url/service_role_key missing',
                jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO debug_log(source, action, status, error_message, request_data)
      VALUES ('_apply_booking_changes_core','refund_dispatch_failed','error',SQLERRM,
              jsonb_build_object('booking_id',p_booking_id,'refund',v_refund));
    END;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'payment_required', false,
    'net_diff', v_net_diff, 'refund_amount', v_refund,
    'new_total', v_new_total, 'new_discount', v_new_discount,
    'new_delivery_fee', CASE WHEN v_pick_side_changed OR v_ret_side_changed THEN v_new_delivery_fee ELSE COALESCE(v_b.delivery_fee, 0) END,
    'location_changed', (v_pick_side_changed OR v_ret_side_changed),
    'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct, 'loyalty_level', v_loy_level,
    'breakdown', jsonb_build_object(
      'dates_diff', v_dates_diff, 'moto_diff', v_moto_diff,
      'pickup_fee_diff', v_pickup_fee_diff, 'return_fee_diff', v_return_fee_diff,
      'pickup_fee_from', v_old_pfee, 'pickup_fee_to', v_new_pfee,
      'return_fee_from', v_old_rfee, 'return_fee_to', v_new_rfee,
      'fee_split_exact', (NOT v_split_est OR (v_pick_side_changed AND v_ret_side_changed) OR NOT (v_new_pd AND v_new_rd)),
      'gross_diff', v_gross_diff, 'discount_type', v_dtype, 'storno_pct', v_storno_pct,
      'late_pickup_from', v_old_late, 'late_pickup_to', v_new_late,
      'loyalty_discount', v_loy_disc, 'loyalty_percent', v_loy_pct
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION "public"."_apply_booking_changes_core"(uuid, uuid, date, date, uuid, text, text, double precision, double precision, numeric, text, text, double precision, double precision, numeric, text, boolean, text, time) TO service_role;

-- ── apply_booking_change_light (AI agent BEZ hesla, jen číslo rezervace) ──────
-- Živá definice (snapshot 2026-10-01, v repu dosud nebyla) + jediná změna:
-- změna místa (jádro vrací `location_changed`) už NENÍ „nulový dopad" →
-- full_verification_required (AI si vyžádá heslo a jde přes 3FA wrapper).
-- Signatura beze změny (GRANT anon/authenticated/service_role zůstávají).
CREATE OR REPLACE FUNCTION "public"."apply_booking_change_light"("p_booking_id" "uuid", "p_new_start" "date" DEFAULT NULL::"date", "p_new_end" "date" DEFAULT NULL::"date", "p_new_moto_id" "uuid" DEFAULT NULL::"uuid", "p_new_pickup_method" "text" DEFAULT NULL::"text", "p_new_pickup_address" "text" DEFAULT NULL::"text", "p_new_pickup_fee" numeric DEFAULT NULL::numeric, "p_new_return_method" "text" DEFAULT NULL::"text", "p_new_return_address" "text" DEFAULT NULL::"text", "p_new_return_fee" numeric DEFAULT NULL::numeric, "p_new_pickup_time" time without time zone DEFAULT NULL::time without time zone, "p_reason" "text" DEFAULT NULL::"text", "p_dry_run" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_b bookings%ROWTYPE;
  v_mods_today int := 0;
  v_preview jsonb;
  v_zero boolean;
  v_net numeric;
BEGIN
  IF p_booking_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'missing_inputs'); END IF;
  SELECT * INTO v_b FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'not_found'); END IF;
  IF COALESCE(v_b.booking_source,'') <> 'web' THEN RETURN jsonb_build_object('success', false, 'error', 'not_web_booking'); END IF;
  IF v_b.status NOT IN ('reserved','active') THEN RETURN jsonb_build_object('success', false, 'error', 'wrong_status'); END IF;
  IF v_b.payment_status NOT IN ('paid','partial_refund','refund_pending') THEN RETURN jsonb_build_object('success', false, 'error', 'not_paid'); END IF;

  SELECT count(*) INTO v_mods_today
  FROM jsonb_array_elements(COALESCE(v_b.modification_history,'[]'::jsonb)) e
  WHERE COALESCE(e->>'source','') = 'ai_agent' AND (e->>'at')::timestamptz::date = current_date;
  IF NOT p_dry_run AND v_mods_today >= 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'daily_limit_reached');
  END IF;

  -- VŽDY nejdřív dry-run přes jádro → dopad počítá server
  v_preview := public._apply_booking_changes_core(
    v_b.user_id, p_booking_id, p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, NULL, NULL, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, NULL, NULL, p_new_return_fee,
    COALESCE(p_reason,'light_preview'), true, 'ai_agent', p_new_pickup_time);

  IF COALESCE((v_preview->>'success')::boolean, false) IS NOT TRUE THEN
    RETURN v_preview;  -- overlap / license_insufficient / no_change / active_* ...
  END IF;

  v_net := COALESCE((v_preview->>'net_diff')::numeric, 0);
  v_zero := (v_net = 0)
        AND COALESCE((v_preview->>'payment_required')::boolean, false) = false
        AND COALESCE((v_preview->>'refund_amount')::numeric, 0) = 0;

  -- 2026-10-01: změna MÍSTA (přistavení/odvoz, adresa) jen po plném ověření
  -- (heslo/3FA) — bez něj by kdokoli se znalostí čísla rezervace mohl
  -- přesměrovat odvoz cizí rezervace (při nulovém rozdílu ceny).
  v_zero := v_zero AND COALESCE((v_preview->>'location_changed')::boolean, false) = false;

  IF p_dry_run THEN
    RETURN v_preview || jsonb_build_object('light', true, 'light_allowed', v_zero);
  END IF;

  IF NOT v_zero THEN
    RETURN jsonb_build_object('success', false, 'error', 'full_verification_required',
      'net_diff', v_net,
      'payment_required', COALESCE((v_preview->>'payment_required')::boolean, false),
      'refund_amount', COALESCE((v_preview->>'refund_amount')::numeric, 0));
  END IF;

  -- nulový dopad → reálně proveď
  RETURN public._apply_booking_changes_core(
    v_b.user_id, p_booking_id, p_new_start, p_new_end, p_new_moto_id,
    p_new_pickup_method, p_new_pickup_address, NULL, NULL, p_new_pickup_fee,
    p_new_return_method, p_new_return_address, NULL, NULL, p_new_return_fee,
    COALESCE(p_reason,'light_edit'), false, 'ai_agent', p_new_pickup_time);
END; $$;



NOTIFY pgrst, 'reload schema';
