-- =============================================================================
-- DB pojistka: zákaznický zápis nesmí z přidání přistavení udělat vratku
-- Migrace: 20261001e_booking_delivery_guard.sql (navazuje na 20261001d)
--
-- 20261001d opravuje výpočet v `_apply_booking_changes_core` (web, AI agent).
-- Appka ale úpravu místa počítá SAMA a zapisuje přímým UPDATE bookings
-- (delivery_fee, total_price) a vratku si pak vyžádá z process-refund — staré
-- buildy v telefonech zákazníků se nedají opravit zpětně a mají chyby stejné
-- třídy (přepnutí na přistavení bez zadané adresy = přistavení zdarma, znovu
-- zadaná stejná adresa = vratka z rovného dělení delivery_fee). Tato migrace
-- je poslední pojistka na úrovni DB pro VŠECHNY klienty:
--
-- 1) `_delivery_guard_violation(OLD, NEW)` — pravidla (NULL = v pořádku):
--    • aktivní rezervace: místo vyzvednutí neměnné (vyzvednutí proběhlo);
--    • delivery_fee nikdy záporné;
--    • ZMĚNA delivery_fee ≥ Σ podlah NOVĚ přidaných stran − podíl ODEBRANÝCH
--      stran (podlaha `_delivery_fee_floor` = 1000 Kč + 40 Kč × vzdušná km od
--      Mezné − 2 km; podíl jako v jádře: přesný z historie `fee_split_exact`,
--      jinak nejvýš podlaha odebrané strany) → přidání přistavení poplatek
--      vždy zvýší, bez odebrané strany poplatek neklesne, odebrání jedné ze
--      dvou stran vrátí nejvýš to, co vrátí server (staré buildy appky dělily
--      poplatek napůl → přeplatek se zablokuje);
--    • přesunutá strana (`_delivery_place_moved`, stejně jako jádro) stojí
--      aspoň svou podlahu (vč. poplatku webu v booking_extras).
--    Přistavení = metoda 'delivery' NEBO adresa; výslovné přepnutí metody
--    z 'delivery' jinam je odebrání i se starou adresou.
-- 2) trigger `trg_guard_booking_delivery` (BEFORE UPDATE):
--    • VŠEM zapisovatelům: strana výslovně přepnutá z 'delivery' jinam se
--      starou adresou → adresa + GPS NULL (staré buildy appky i webhook
--      adresu nemazaly, doklady i Velín pak stranu dál četly jako přistavení);
--    • jen ZÁKAZNICKÉ zápisy (JWT authenticated/anon, ne admin Velína —
--      platí i uvnitř SECURITY DEFINER RPC volaných zákazníkem; service_role,
--      cron, DB sezení beze změny) na zaplacených rezervacích reserved/active:
--      NULL čas vyzvednutí se nezapíše (ponechá se uložený — web ho u aktivní
--      rezervace mazal, incident 2026-10-01) a porušení pravidel = výjimka
--      (zápis se neprovede; appka po neúspěšném UPDATE vratku nevolá).
-- 3) `check_booking_delivery_change(booking, změna jsonb)` — tatáž pravidla pro
--    doplatkovou změnu appky PŘED platbou (process-payment; webhook ji pak
--    zapisuje jako service_role mimo trigger). Jen service_role.
-- Pořadí: trigger běží abecedně před `trg_track_booking_content_changes`.
-- Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._delivery_guard_violation(o public.bookings, n public.bookings)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_pd  boolean := (o.pickup_method = 'delivery' OR public._addr_norm(o.pickup_address) IS NOT NULL);
  v_old_rd  boolean := (o.return_method = 'delivery' OR public._addr_norm(o.return_address) IS NOT NULL);
  v_new_pd  boolean;
  v_new_rd  boolean;
  v_p_mv    boolean := false;
  v_r_mv    boolean := false;
  v_df_old  numeric := COALESCE(o.delivery_fee, 0);
  v_df_new  numeric := COALESCE(n.delivery_fee, 0);
  v_need    numeric := 0;
  v_lb_kept numeric := 0;
  v_u_rem   numeric := 0;
  v_mv_need numeric := 0;
  v_mv_ext  numeric := 0;
  v_hp      numeric;
  v_hr      numeric;
BEGIN
  v_new_pd := CASE WHEN o.pickup_method = 'delivery' AND n.pickup_method IS DISTINCT FROM 'delivery' THEN false
                   ELSE (n.pickup_method = 'delivery' OR public._addr_norm(n.pickup_address) IS NOT NULL) END;
  v_new_rd := CASE WHEN o.return_method = 'delivery' AND n.return_method IS DISTINCT FROM 'delivery' THEN false
                   ELSE (n.return_method = 'delivery' OR public._addr_norm(n.return_address) IS NOT NULL) END;
  IF v_old_pd AND v_new_pd THEN
    v_p_mv := public._delivery_place_moved(o.pickup_address, o.pickup_lat, o.pickup_lng,
                                           n.pickup_address, n.pickup_lat, n.pickup_lng);
  END IF;
  IF v_old_rd AND v_new_rd THEN
    v_r_mv := public._delivery_place_moved(o.return_address, o.return_lat, o.return_lng,
                                           n.return_address, n.return_lat, n.return_lng);
  END IF;

  IF o.status = 'active' AND (v_new_pd IS DISTINCT FROM v_old_pd OR v_p_mv) THEN
    RETURN 'active_pickup_locked: vyzvednutí už proběhlo, místo vyzvednutí nelze změnit';
  END IF;
  IF v_df_new < 0 THEN
    RETURN 'delivery_fee_guard: poplatek za přistavení nesmí být záporný';
  END IF;

  -- Přidané strany: aspoň jejich podlaha.
  IF NOT v_old_pd AND v_new_pd THEN v_need := v_need + public._delivery_fee_floor(n.pickup_lat, n.pickup_lng, 2); END IF;
  IF NOT v_old_rd AND v_new_rd THEN v_need := v_need + public._delivery_fee_floor(n.return_lat, n.return_lng, 2); END IF;
  -- Odebrané strany smí snížit poplatek nejvýš o svůj podíl — stejně jako
  -- jádro (20261001d): odebírá-li se JEDNA ze dvou stran, platí přesný podíl
  -- z poslední úpravy v historii (`fee_split_exact`, součet = delivery_fee),
  -- jinak nejvýš podlaha odebrané strany a zároveň staré delivery_fee −
  -- podlaha strany, která zůstává (ta jen když delivery_fee pokrývá obě
  -- strany; jinak 0 — např. web rezervace s poplatkem v booking_extras).
  -- Odebírá-li se jediná / obě strany, smí poplatek klesnout celý.
  IF (v_old_pd AND NOT v_new_pd) OR (v_old_rd AND NOT v_new_rd) THEN
    IF v_old_pd AND v_old_rd AND (v_new_pd OR v_new_rd) THEN
      BEGIN
        SELECT (x.e->>'pickup_fee_to')::numeric, (x.e->>'return_fee_to')::numeric
          INTO v_hp, v_hr
          FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.modification_history) = 'array'
                                         THEN o.modification_history ELSE '[]'::jsonb END)
               WITH ORDINALITY AS x(e, i)
         WHERE jsonb_typeof(x.e) = 'object' AND x.e ? 'pickup_fee_to' AND x.e ? 'return_fee_to'
           AND x.e->>'fee_split_exact' = 'true'
         ORDER BY x.i DESC LIMIT 1;
      EXCEPTION WHEN OTHERS THEN
        v_hp := NULL; v_hr := NULL;
      END;
      IF v_hp IS NOT NULL AND v_hr IS NOT NULL AND v_hp >= 0 AND v_hr >= 0
         AND v_hp + v_hr = GREATEST(v_df_old, 0) THEN
        v_u_rem := CASE WHEN v_new_pd THEN v_hr ELSE v_hp END;
      ELSE
        IF v_df_old >= public._delivery_fee_floor(o.pickup_lat, o.pickup_lng, 2)
                       + public._delivery_fee_floor(o.return_lat, o.return_lng, 2) THEN
          v_lb_kept := CASE WHEN v_new_pd THEN public._delivery_fee_floor(o.pickup_lat, o.pickup_lng, 2)
                            ELSE public._delivery_fee_floor(o.return_lat, o.return_lng, 2) END;
        END IF;
        v_u_rem := LEAST(GREATEST(0, v_df_old - v_lb_kept),
                         CASE WHEN v_new_pd THEN public._delivery_fee_floor(o.return_lat, o.return_lng, 2)
                              ELSE public._delivery_fee_floor(o.pickup_lat, o.pickup_lng, 2) END);
      END IF;
    ELSE
      v_u_rem := GREATEST(0, v_df_old);
    END IF;
  END IF;
  IF v_df_new - v_df_old < v_need - v_u_rem THEN
    IF v_need - v_u_rem > 0 THEN
      RETURN format('delivery_fee_guard: přidání přistavení/odvozu musí zvýšit poplatek aspoň o %s Kč (změna %s)',
                    v_need - v_u_rem, v_df_new - v_df_old);
    END IF;
    RETURN format('delivery_fee_guard: poplatek za přistavení nelze snížit o %s Kč (nejvýš o %s)',
                  v_df_old - v_df_new, v_u_rem - v_need);
  END IF;

  -- Přesunutá strana stojí aspoň svou podlahu (poplatek webu v booking_extras
  -- se počítá — web rezervace mají delivery_fee 0).
  IF v_p_mv THEN
    v_mv_need := v_mv_need + public._delivery_fee_floor(n.pickup_lat, n.pickup_lng, 2);
    v_mv_ext  := v_mv_ext + public._booking_extras_delivery(o.id, 'pickup');
  END IF;
  IF v_r_mv THEN
    v_mv_need := v_mv_need + public._delivery_fee_floor(n.return_lat, n.return_lng, 2);
    v_mv_ext  := v_mv_ext + public._booking_extras_delivery(o.id, 'return');
  END IF;
  IF v_df_new + v_mv_ext < v_mv_need THEN
    RETURN format('delivery_fee_guard: poplatek za přesunuté přistavení/odvoz musí být aspoň %s Kč (je %s)',
                  v_mv_need, v_df_new + v_mv_ext);
  END IF;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._delivery_guard_violation(public.bookings, public.bookings) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._guard_booking_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_err  text;
BEGIN
  -- Strana výslovně přepnutá z přistavení jinam se starou adresou →
  -- adresa a GPS pryč (pro všechny zapisovatele; nekonzistentní stav).
  IF OLD.pickup_method = 'delivery' AND NEW.pickup_method IS DISTINCT FROM 'delivery'
     AND NEW.pickup_address IS NOT DISTINCT FROM OLD.pickup_address THEN
    NEW.pickup_address := NULL; NEW.pickup_lat := NULL; NEW.pickup_lng := NULL;
  END IF;
  IF OLD.return_method = 'delivery' AND NEW.return_method IS DISTINCT FROM 'delivery'
     AND NEW.return_address IS NOT DISTINCT FROM OLD.return_address THEN
    NEW.return_address := NULL; NEW.return_lat := NULL; NEW.return_lng := NULL;
  END IF;

  IF OLD.status NOT IN ('reserved', 'active')
     OR OLD.payment_status NOT IN ('paid', 'partial_refund', 'refund_pending') THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_role := COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                       NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role');
  EXCEPTION WHEN OTHERS THEN
    v_role := NULL;
  END;
  IF v_role IS NULL OR v_role NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- Prázdný čas vyzvednutí se nezapisuje — ponechá se uložený.
  IF NEW.pickup_time IS NULL AND OLD.pickup_time IS NOT NULL THEN
    NEW.pickup_time := OLD.pickup_time;
  END IF;

  v_err := public._delivery_guard_violation(OLD, NEW);
  IF v_err IS NOT NULL THEN
    RAISE EXCEPTION '%', v_err USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._guard_booking_delivery() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_guard_booking_delivery ON public.bookings;
CREATE TRIGGER trg_guard_booking_delivery
  BEFORE UPDATE OF delivery_fee, pickup_method, pickup_address, pickup_lat, pickup_lng,
                   return_method, return_address, return_lat, return_lng, pickup_time
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._guard_booking_delivery();

-- Doplatková změna appky (formát sloupců) před platbou — process-payment.
-- Vrací NULL (v pořádku) nebo text porušení; 'not_found' když rezervace není.
CREATE OR REPLACE FUNCTION public.check_booking_delivery_change(p_booking_id uuid, p_change jsonb)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o public.bookings;
  n public.bookings;
  v_ch jsonb;
BEGIN
  SELECT * INTO o FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;
  IF o.status NOT IN ('reserved', 'active') THEN
    RETURN NULL;
  END IF;
  -- jen sloupce místa a poplatku (zbytek payloadu sem nepatří)
  SELECT COALESCE(jsonb_object_agg(e.k, e.v), '{}'::jsonb) INTO v_ch
    FROM jsonb_each(CASE WHEN jsonb_typeof(p_change) = 'object' THEN p_change ELSE '{}'::jsonb END) AS e(k, v)
   WHERE e.k IN ('delivery_fee', 'pickup_method', 'pickup_address', 'pickup_lat', 'pickup_lng',
                 'return_method', 'return_address', 'return_lat', 'return_lng');
  n := jsonb_populate_record(o, v_ch);
  IF o.pickup_method = 'delivery' AND n.pickup_method IS DISTINCT FROM 'delivery'
     AND n.pickup_address IS NOT DISTINCT FROM o.pickup_address THEN
    n.pickup_address := NULL; n.pickup_lat := NULL; n.pickup_lng := NULL;
  END IF;
  IF o.return_method = 'delivery' AND n.return_method IS DISTINCT FROM 'delivery'
     AND n.return_address IS NOT DISTINCT FROM o.return_address THEN
    n.return_address := NULL; n.return_lat := NULL; n.return_lng := NULL;
  END IF;
  RETURN public._delivery_guard_violation(o, n);
END;
$$;
REVOKE ALL ON FUNCTION public.check_booking_delivery_change(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_booking_delivery_change(uuid, jsonb) TO service_role;

NOTIFY pgrst, 'reload schema';
