-- =============================================================================
-- MIGRACE 2026-06-18: Sleva 50 % na 1. den při pozdním vyzvednutí
--
-- Pravidlo (schváleno zákazníkem): pokud je čas vyzvednutí 12:00 NEBO později
-- A rezervace je na 2 a více kalendářních dní (start+end včetně), napočítá se
-- sleva = round(50 % ceny prvního dne). Platí pro WEB i APP.
--
-- Model (zrcadlí věrnostní slevu, mig. 20260611_loyalty_ranks.sql):
--   - nový sloupec bookings.late_pickup_discount_amount (oddělený od
--     discount_amount [promo/voucher] i loyalty_discount_amount)
--   - helper _late_pickup_discount() = jediný autoritativní výpočet
--   - create_web_booking ji počítá server-side (web)
--   - BEFORE INSERT trigger trg_validate_late_pickup ji RE-VALIDUJE pro VŠECHNY
--     rezervace (web i app) — klientovi se nevěří, případný rozdíl se opraví
--     a dorovná total_price
--   - generate-invoice / KF ji vykáží jako samostatný záporný řádek
--
-- OVĚŘENO 2026-06-18 v živé DB (helper vrací 50 % ceny prvního dne; před 12:00
-- a u 1denní rezervace vrací 0).
--
-- MILESTONE 1 = jen vytváření rezervace. Přepočet při úpravě (DP/dobropis)
-- přijde v navazující migraci (Milestone 2).
-- =============================================================================

-- ── 1) Sloupec ───────────────────────────────────────────────────────────────
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS late_pickup_discount_amount numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.bookings.late_pickup_discount_amount IS
  'Sleva 50 % na 1. den při pozdním vyzvednutí (>=12:00) a rezervaci >=2 dny. '
  'Oddělená od discount_amount (promo/voucher) a loyalty_discount_amount. '
  'Autoritativně počítá _late_pickup_discount() + trigger trg_validate_late_pickup.';

-- ── 2) Helper: autoritativní výpočet slevy ───────────────────────────────────
-- Vrací 0 když podmínka neplatí. Cena prvního dne s trojím fallbackem
-- (price_<dow> → price_weekend [So/Ne] → price_weekday), aby seděla bez ohledu
-- na to, který per-day sloupec je vyplněný.
CREATE OR REPLACE FUNCTION public._late_pickup_discount(
  p_moto_id     uuid,
  p_start       timestamptz,
  p_end         timestamptz,
  p_pickup_time time
) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_moto        motorcycles%ROWTYPE;
  v_days        int;
  v_dow         int;
  v_first_price numeric;
BEGIN
  IF p_moto_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_pickup_time IS NULL THEN
    RETURN 0;
  END IF;

  -- Podmínka A: vyzvednutí 12:00 nebo později
  IF p_pickup_time < TIME '12:00' THEN
    RETURN 0;
  END IF;

  -- Podmínka B: rezervace na 2 a více kalendářních dní (start i end včetně)
  v_days := (p_end::date - p_start::date) + 1;
  IF v_days < 2 THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_moto FROM motorcycles WHERE id = p_moto_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  v_dow := EXTRACT(ISODOW FROM p_start::date)::int; -- 1=Po .. 7=Ne
  v_first_price := CASE v_dow
    WHEN 1 THEN COALESCE(v_moto.price_mon, v_moto.price_weekday, 0)
    WHEN 2 THEN COALESCE(v_moto.price_tue, v_moto.price_weekday, 0)
    WHEN 3 THEN COALESCE(v_moto.price_wed, v_moto.price_weekday, 0)
    WHEN 4 THEN COALESCE(v_moto.price_thu, v_moto.price_weekday, 0)
    WHEN 5 THEN COALESCE(v_moto.price_fri, v_moto.price_weekday, 0)
    WHEN 6 THEN COALESCE(v_moto.price_sat, v_moto.price_weekend, v_moto.price_weekday, 0)
    WHEN 7 THEN COALESCE(v_moto.price_sun, v_moto.price_weekend, v_moto.price_weekday, 0)
  END;

  RETURN ROUND(COALESCE(v_first_price, 0) * 0.5);
END;
$$;
REVOKE ALL ON FUNCTION public._late_pickup_discount(uuid, timestamptz, timestamptz, time) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._late_pickup_discount(uuid, timestamptz, timestamptz, time) TO authenticated, service_role;

-- ── 3) BEFORE INSERT trigger: anti-cheat „clamp-down" (NEpřidává slevu sám) ──
-- DŮLEŽITÉ: trigger slevu NIKDY sám nepřidá — jen OŘEŽE, pokud klient pošle
-- VÍC, než povoluje pravidlo (a dorovná total_price nahoru). Tím:
--   - web (create_web_booking) i app slevu reálně aplikují ve své cestě,
--   - business riziko (over-discount od zmanipulovaného klienta) je pokryto,
--   - ostatní flow (Velín admin, SOS náhrada, default booking_source='app')
--     zůstávají NEtknuté — žádná tichá sleva na rezervacích, které ji nemají
--     mít. Podhodnocení (klient pošle míň/0) není business riziko (zákazník
--     by jen zaplatil víc), proto se nedorovnává dolů.
-- EXCEPTION safe — nikdy neshodí insert rezervace.
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

DROP TRIGGER IF EXISTS trg_validate_late_pickup ON public.bookings;
CREATE TRIGGER trg_validate_late_pickup
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_late_pickup_discount();
-- ── 4) create_web_booking ────────────────────────────────────────────────────
-- POZOR: create_web_booking se NEŘEŠÍ zde. Produkční je 39-arg verze (web posílá
-- 31 parametrů vč. p_consent_*/p_passenger_*/p_existing_booking_id/...), kterou
-- s late slevou (Model B) řeší migrace `20260619_fix_create_web_booking_overload.sql`.
-- Dřívější 26-arg verze zde byla mrtvý kód (web ji nikdy nevolal) → odstraněna,
-- aby re-run této migrace neobnovil duplicitní overload.
