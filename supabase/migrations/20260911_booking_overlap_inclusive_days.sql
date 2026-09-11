-- ============================================================================
-- Dvojrezervace motorky na stejný den — pojistky DB počítaly s POLOOTEVŘENÝM
-- intervalem, jednodenní rezervace tak nikdy s ničím nekolidovala
-- Migrace: 20260911_booking_overlap_inclusive_days.sql
--   (navazuje na 20260823_check_booking_overlap_rls_fix, 20260726b, 20260616)
--
-- INCIDENT 2026-09-11: Honda CRF 1000 Africa Twin 8J6873 — Mikásek (WEB)
-- 12.–13. 9. 2026 (2 dny) + Konopa (APPKA) 13.–13. 9. 2026 (1 den), obě
-- ZAPLACENO. Obě rezervace sdílejí 13. 9.
--
-- PŘÍČINA (chyba v DB pojistkách, ne v UI):
--   * trigger check_booking_overlap porovnával
--       tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
--     = výchozí meze '[)' (horní mez VYLOUČENÁ). Sloupce jsou timestamptz o půlnoci
--     (appka posílá 'YYYY-MM-DD'), takže:
--       - jednodenní rezervace (start = end) je PRÁZDNÝ rozsah → `empty && cokoliv`
--         = false → trigger ji NIKDY neodmítl, ať už byla motorka obsazená jakkoliv;
--       - rezervace navazující na hraniční den (A končí 13. 9., B začíná 13. 9.)
--         se nepovažovaly za kolizi, ačkoliv den pronájmu je INKLUZIVNÍ
--         (cena i kalendář počítají start i end jako půjčené dny — 12.–13. = 2 dny).
--     Appka dělá do `bookings` PŘÍMÝ INSERT (payment_screen.dart) a spoléhá
--     na tento trigger → rezervace Konopa 13.–13. 9. prošla.
--     Web (create_web_booking) používá tstzrange(...,'[]') a chráněný byl;
--     check_user_booking_overlap, check_trailer_overlap, reschedule_booking_free,
--     split_booking_moto_swap i kalendář get_moto_booked_dates pracují s
--     inkluzivními dny — trigger byl jediná výjimka.
--   * check_moto_availability (appka: posun termínu / výměna motorky / filtr
--     katalogu; extend_booking) měla stejnou chybu (`start_date < p_end AND
--     end_date > p_start`) A navíc nebyla SECURITY DEFINER → pod RLS zákazník
--     viděl jen SVOJE rezervace, cizí obsazenost tedy nikdy neodhalila.
--   * get_available_motos (nepoužívá se, ponecháno konzistentní): stejné ostré
--     porovnání + chyběl status 'reserved'.
--
-- OPRAVA:
--   1. check_booking_overlap: kolize = inkluzivní DNY
--        b.start_date::date <= NEW.end_date::date AND b.end_date::date >= NEW.start_date::date
--      (shodné s ostatními pojistkami a kalendářem). Souběžné zápisy na stejnou
--      motorku (web + appka ve stejný okamžik — EXISTS v READ COMMITTED sám
--      o sobě dvojí insert nezachytí) serializuje pg_advisory_xact_lock na moto_id.
--      Trigger nově hlídá i UPDATE OF status: znovu-aktivace stornované /
--      ukončené rezervace (cancelled/completed → pending/reserved/active) se
--      kontroluje jako nový zápis. UPDATE, který nemění termín, motorku ani
--      neaktivuje řádek (např. reserved → active při předání, změna poznámky
--      přes modal, který posílá i nezměněné datumy), se NEkontroluje — starší
--      kolizní dvojice v DB tak neblokují běžný provoz; řeší se ručně
--      (přesun/storno jedné z rezervací).
--      SOS náhrada (sos_replacement) zůstává vyjmutá; is_test se NEvyjímá
--      (testovací seed má kalendář obsazovat).
--   2. check_moto_availability: inkluzivní dny + SECURITY DEFINER + search_path.
--      Signatura a sémantika návratu beze změny (true = volná).
--   3. get_available_motos: inkluzivní dny, status pending/reserved/active,
--      SECURITY DEFINER.
-- Idempotentní (CREATE OR REPLACE, DROP TRIGGER IF EXISTS + CREATE).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_booking_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date := NEW.start_date::date;
  v_end   date := NEW.end_date::date;
  v_self  uuid := COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);
BEGIN
  -- SOS náhradní rezervace jsou z kontroly překryvu motorky vyjmuté
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Stornované / ukončené rezervace nic neblokují
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- UPDATE beze změny termínu a motorky, který řádek znovu neaktivuje
  -- (OLD už byl aktivní stav) → nic nového ke kontrole
  IF TG_OP = 'UPDATE'
     AND OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id
     AND OLD.start_date::date = v_start
     AND OLD.end_date::date   = v_end
     AND OLD.status NOT IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  -- Serializace souběžných zápisů na stejnou motorku (drží se do konce transakce)
  PERFORM pg_advisory_xact_lock(hashtext('bookings_moto_overlap'), hashtext(NEW.moto_id::text));

  -- Motorka už má v některém z dnů [start..end] jinou živou rezervaci
  IF EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.moto_id = NEW.moto_id
      AND b.id <> v_self
      AND b.status NOT IN ('cancelled', 'completed')
      AND b.start_date::date <= v_end
      AND b.end_date::date   >= v_start
  ) THEN
    RAISE EXCEPTION 'Překrývající se rezervace pro moto_id % (% – %)', NEW.moto_id, v_start, v_end;
  END IF;

  -- Kus je v některém z dnů přiřazený jako vozík-příslušenství jiné rezervace
  IF EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.trailer_moto_id = NEW.moto_id
      AND b.id <> v_self
      AND b.status NOT IN ('cancelled', 'completed')
      AND b.start_date::date <= v_end
      AND b.end_date::date   >= v_start
  ) THEN
    RAISE EXCEPTION 'Kus % je v tomto termínu přiřazen jako vozík k jiné rezervaci', NEW.moto_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_booking_overlap ON public.bookings;
CREATE TRIGGER trg_check_booking_overlap
  BEFORE INSERT OR UPDATE OF start_date, end_date, moto_id, status
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.check_booking_overlap();

-- ----------------------------------------------------------------------------
-- check_moto_availability — inkluzivní dny + DEFINER (pod RLS viděla jen vlastní)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_moto_availability(
  p_moto_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_booking_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  conflict_count integer;
BEGIN
  SELECT COUNT(*) INTO conflict_count
  FROM bookings b
  WHERE b.moto_id = p_moto_id
    AND b.status IN ('pending', 'reserved', 'active')
    AND b.id IS DISTINCT FROM p_exclude_booking_id
    AND b.start_date::date <= p_end::date
    AND b.end_date::date   >= p_start::date;
  RETURN conflict_count = 0;
END;
$$;

-- ----------------------------------------------------------------------------
-- get_available_motos — inkluzivní dny + status reserved (v repu nevoláno)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_available_motos(
  p_start timestamptz,
  p_end timestamptz,
  p_category text DEFAULT NULL,
  p_license public.license_group DEFAULT NULL,
  p_branch_id uuid DEFAULT NULL
)
RETURNS SETOF public.motorcycles
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT m.*
  FROM motorcycles m
  WHERE m.status = 'active'
    AND (p_category IS NULL OR m.category = p_category)
    AND (p_license IS NULL OR m.license_required = p_license)
    AND (p_branch_id IS NULL OR m.branch_id = p_branch_id)
    AND NOT EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.moto_id = m.id
        AND b.status IN ('pending', 'reserved', 'active')
        AND b.start_date::date <= p_end::date
        AND b.end_date::date   >= p_start::date
    );
END;
$$;
