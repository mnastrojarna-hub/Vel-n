-- =============================================================================
-- DB pojistka: zákaznický zápis nesmí z přidání přistavení udělat vratku
-- Migrace: 20261001e_booking_delivery_guard.sql (navazuje na 20261001d)
--
-- 20261001d opravuje výpočet v `_apply_booking_changes_core` (web, AI agent).
-- Appka ale úpravu místa počítá SAMA a zapisuje přímým UPDATE bookings
-- (delivery_fee, total_price) a vratku si pak vyžádá z process-refund — staré
-- buildy v telefonech zákazníků se nedají opravit zpětně a mají chyby stejné
-- třídy (přepnutí na přistavení bez zadané adresy = přistavení zdarma, znovu
-- zadaná stejná adresa = vratka z rovného dělení delivery_fee). Tento trigger
-- je poslední pojistka na úrovni DB pro VŠECHNY klienty:
--
-- Platí jen pro ZÁKAZNICKÉ zápisy (JWT role authenticated/anon, ne admin
-- Velína; service_role/webhook, cron a přímé DB sezení beze změny) a jen pro
-- zaplacené rezervace ve stavu reserved/active (rozpracovaný koncept webu
-- `create_web_booking` ve stavu pending se netýká). Pak:
--  1) prázdný čas vyzvednutí se nezapíše (web ho u aktivní rezervace mazal —
--     incident 2026-10-01: 22:10 → NULL, detail ukazoval „v 09:00");
--  2) aktivní rezervace: místo vyzvednutí je neměnné (vyzvednutí proběhlo);
--  3) delivery_fee nesmí být záporné;
--  4) přesunutá strana (jiná adresa / GPS > ~50 m) — delivery_fee aspoň
--     její podlaha `_delivery_fee_floor` (1 000 Kč + 40 Kč × vzdušná
--     vzdálenost od Mezné − 2 km; bez GPS 1 000 Kč);
--  5) když se žádná strana nepřepnula z přistavení na pobočku ani nepřesunula,
--     delivery_fee nesmí klesnout; každá nově přidaná strana přistavení ho
--     musí zvýšit aspoň o svou podlahu.
-- Porušení = výjimka → zápis se neprovede (appka po neúspěšném UPDATE vratku
-- nevolá; jádro po opravě 20261001d pravidla splňuje). Přistavení = metoda
-- 'delivery' NEBO vyplněná adresa (shodně s jádrem a generate-document).
-- Pořadí: trigger `trg_guard_booking_delivery` běží před
-- `trg_track_booking_content_changes` (abecedně), takže historie neuvidí
-- vrácený NULL čas. Idempotentní.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._guard_booking_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role     text;
  v_old_pd   boolean;
  v_new_pd   boolean;
  v_old_rd   boolean;
  v_new_rd   boolean;
  v_p_moved  boolean;
  v_r_moved  boolean;
  v_df_old   numeric;
  v_df_new   numeric;
  v_need     numeric := 0;
  v_need_mv  numeric := 0;
BEGIN
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

  -- 1) Prázdný čas vyzvednutí se nezapisuje — ponechá se uložený.
  IF NEW.pickup_time IS NULL AND OLD.pickup_time IS NOT NULL THEN
    NEW.pickup_time := OLD.pickup_time;
  END IF;

  v_old_pd := (OLD.pickup_method = 'delivery' OR NULLIF(btrim(COALESCE(OLD.pickup_address, '')), '') IS NOT NULL);
  v_new_pd := (NEW.pickup_method = 'delivery' OR NULLIF(btrim(COALESCE(NEW.pickup_address, '')), '') IS NOT NULL);
  v_old_rd := (OLD.return_method = 'delivery' OR NULLIF(btrim(COALESCE(OLD.return_address, '')), '') IS NOT NULL);
  v_new_rd := (NEW.return_method = 'delivery' OR NULLIF(btrim(COALESCE(NEW.return_address, '')), '') IS NOT NULL);
  v_p_moved := v_old_pd AND v_new_pd AND (
       public._addr_norm(NEW.pickup_address) IS DISTINCT FROM public._addr_norm(OLD.pickup_address)
    OR (OLD.pickup_lat IS NOT NULL AND OLD.pickup_lng IS NOT NULL AND NEW.pickup_lat IS NOT NULL AND NEW.pickup_lng IS NOT NULL
        AND (abs(NEW.pickup_lat - OLD.pickup_lat) > 0.0005 OR abs(NEW.pickup_lng - OLD.pickup_lng) > 0.0005)));
  v_r_moved := v_old_rd AND v_new_rd AND (
       public._addr_norm(NEW.return_address) IS DISTINCT FROM public._addr_norm(OLD.return_address)
    OR (OLD.return_lat IS NOT NULL AND OLD.return_lng IS NOT NULL AND NEW.return_lat IS NOT NULL AND NEW.return_lng IS NOT NULL
        AND (abs(NEW.return_lat - OLD.return_lat) > 0.0005 OR abs(NEW.return_lng - OLD.return_lng) > 0.0005)));

  -- 2) Aktivní rezervace: vyzvednutí proběhlo, jeho místo se už nemění.
  IF OLD.status = 'active' AND (v_new_pd IS DISTINCT FROM v_old_pd OR v_p_moved) THEN
    RAISE EXCEPTION 'active_pickup_locked: vyzvednutí už proběhlo, místo vyzvednutí nelze změnit'
      USING ERRCODE = 'P0001';
  END IF;

  v_df_old := COALESCE(OLD.delivery_fee, 0);
  v_df_new := COALESCE(NEW.delivery_fee, 0);
  -- 3) Záporný poplatek nikdy.
  IF v_df_new < 0 THEN
    RAISE EXCEPTION 'delivery_fee_guard: poplatek za přistavení nesmí být záporný'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4) Přesunutá strana stojí aspoň svou podlahu (poplatek nesmí kvůli
  --    „přesunu o 60 m" spadnout na nulu).
  IF v_p_moved THEN v_need_mv := v_need_mv + public._delivery_fee_floor(NEW.pickup_lat, NEW.pickup_lng, 2); END IF;
  IF v_r_moved THEN v_need_mv := v_need_mv + public._delivery_fee_floor(NEW.return_lat, NEW.return_lng, 2); END IF;
  IF v_df_new < v_need_mv THEN
    RAISE EXCEPTION 'delivery_fee_guard: poplatek za přesunuté přistavení/odvoz musí být aspoň % Kč (je %)',
      v_need_mv, v_df_new
      USING ERRCODE = 'P0001';
  END IF;

  -- 5) Bez odebrané nebo přesunuté strany poplatek neklesá; přidaná strana
  --    ho zvyšuje aspoň o svou podlahu.
  IF NOT ((v_old_pd AND NOT v_new_pd) OR (v_old_rd AND NOT v_new_rd) OR v_p_moved OR v_r_moved) THEN
    IF NOT v_old_pd AND v_new_pd THEN
      v_need := v_need + public._delivery_fee_floor(NEW.pickup_lat, NEW.pickup_lng, 2);
    END IF;
    IF NOT v_old_rd AND v_new_rd THEN
      v_need := v_need + public._delivery_fee_floor(NEW.return_lat, NEW.return_lng, 2);
    END IF;
    IF v_df_new - v_df_old < v_need THEN
      IF v_need > 0 THEN
        RAISE EXCEPTION 'delivery_fee_guard: přidání přistavení/odvozu musí zvýšit poplatek aspoň o % Kč (změna %)',
          v_need, v_df_new - v_df_old
          USING ERRCODE = 'P0001';
      END IF;
      RAISE EXCEPTION 'delivery_fee_guard: bez změny místa nelze poplatek za přistavení snížit (změna %)',
        v_df_new - v_df_old
        USING ERRCODE = 'P0001';
    END IF;
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
