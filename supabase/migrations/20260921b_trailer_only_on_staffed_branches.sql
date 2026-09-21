-- =============================================================================
-- MIGRACE: Vozík (přívěs) jen na OBSLUŽNÉ pobočce
-- Datum: 2026-09-21
-- Branch: claude/samoobsluzna-pobocka-vozik-2mdsxo
--
-- ZADÁNÍ: samoobslužná pobočka (`branches.type = 'samoobslužná'`) vozík nevydává —
-- nemá ho kde mít (pevná sestava 7 kójí + šatna + venek) ani kdo ho předat
-- (výdej 24/7 kódem, bez obsluhy). Web ani appka proto NESMÍ vozík k motorce
-- ze samoobslužné pobočky vůbec nabídnout — ani zdarma (appka), ani za 400 Kč/den
-- (web). Vozík zůstává k dispozici POUZE u motorek z obslužné pobočky.
--
-- Backend je jediný zdroj pravdy (web, appka i budoucí klienti):
--   1) branch_is_self_service / moto_is_self_service — dvojice jako
--      branch_is_closed / moto_branch_closed (20260920d), aby se literál
--      'samoobslužná' nemusel opakovat v každém dotazu.
--   2) get_trailer_availability — nový argument `p_moto_id`: pro motorku ze
--      samoobslužné pobočky vrací {available_count: 0, trailer_id: null}
--      → dlaždice „Vozík" se nikde nezobrazí. Rozhoduje VÝHRADNĚ pobočka
--      rezervované motorky; pool kusů zůstává společný pro celou firmu
--      (beze změny od 20260616), aby se na obslužné pobočce vozík nabídl vždy.
--   3) check_trailer_overlap — TVRDÁ POJISTKA na zápisu. Appka vkládá do
--      `bookings` přímým insertem (payment_screen.dart) a starší verze z obchodů
--      `p_moto_id` neposílají, takže jediné místo, které pokryje všechny klienty,
--      je trigger (stejná úvaha jako u trg_check_booking_branch_open, 20260920d).
--      Výjimky (aby už existující rezervace šlo dál odbavit): storno/dokončení
--      a UPDATE, který vozík ani motorku ani termín nemění.
--
-- Rezervace vzniklé PŘED touto migrací migrace NERUŠÍ — vozík u nich zůstává.
-- Idempotentní (CREATE OR REPLACE / DROP IF EXISTS + CREATE).
-- =============================================================================

-- ─── 1) Je pobočka samoobslužná? ─────────────────────────────────────────────
-- Jediný zdroj pravdy pro literál 'samoobslužná' (Velín ho píše z BranchModal.jsx,
-- konstanta SELF_SERVICE_TYPE v BranchHelpers.jsx). NULL pobočka (kus bez pobočky)
-- → false, stejně jako branch_is_closed. SECURITY DEFINER, aby kontrola nezávisela
-- na RLS volajícího (check_trailer_overlap běží i pod anon/authenticated).
CREATE OR REPLACE FUNCTION public.branch_is_self_service(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT b.type = 'samoobslužná' FROM branches b WHERE b.id = p_branch_id),
    false
  );
$$;

COMMENT ON FUNCTION public.branch_is_self_service(uuid) IS
  'TRUE = pobočka je samoobslužná (branches.type = ''samoobslužná''). Jediný zdroj pravdy pro tento literál v DB.';

GRANT EXECUTE ON FUNCTION public.branch_is_self_service(uuid)
  TO anon, authenticated, service_role;

-- Pohodlný obal nad pobočkou konkrétní motorky (obdoba moto_branch_closed).
CREATE OR REPLACE FUNCTION public.moto_is_self_service(p_moto_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.branch_is_self_service(
    (SELECT m.branch_id FROM motorcycles m WHERE m.id = p_moto_id)
  );
$$;

COMMENT ON FUNCTION public.moto_is_self_service(uuid) IS
  'TRUE = motorka stojí na samoobslužné pobočce. Neexistující kus → false.';

GRANT EXECUTE ON FUNCTION public.moto_is_self_service(uuid)
  TO anon, authenticated, service_role;

-- ─── 2) get_trailer_availability — nový argument p_moto_id ───────────────────
-- Signatura se mění (3 → 4 argumenty), proto DROP + CREATE: dva overloady vedle
-- sebe by PostgREST u volání {p_start, p_end} nerozlišil (ambiguous function).
-- Starší klienti (appka z obchodu) posílají dál jen {p_start, p_end} → default
-- NULL → chovají se jako dosud; jejich zápis odchytí trigger v bodě 3.
DROP FUNCTION IF EXISTS public.get_trailer_availability(date, date, uuid);

CREATE OR REPLACE FUNCTION public.get_trailer_availability(
  p_start           date,
  p_end             date,
  p_exclude_booking uuid DEFAULT NULL,
  p_moto_id         uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH trailers AS (
    SELECT id, created_at
    FROM motorcycles
    WHERE is_trailer = true
      AND COALESCE(status,'active') = 'active'
      AND NOT COALESCE(public.branch_is_closed(branch_id, p_start, p_end), false)
      -- POZOR: pool vozíků zůstává SPOLEČNÝ pro celou firmu (beze změny od
      -- 20260616). Rozhoduje VÝHRADNĚ pobočka rezervované motorky (p_moto_id
      -- níže) — na obslužné pobočce se vozík nabídnout MÁ, i kdyby konkrétní
      -- kus byl v evidenci veden na jiné (třeba samoobslužné) pobočce.
  ),
  busy AS (
    SELECT t.id
    FROM trailers t
    WHERE EXISTS (
            SELECT 1 FROM bookings b
            WHERE b.status IN ('pending','reserved','active')
              AND (p_exclude_booking IS NULL OR b.id <> p_exclude_booking)
              AND (b.moto_id = t.id OR b.trailer_moto_id = t.id)
              AND tstzrange(b.start_date, b.end_date, '[]')
                  && tstzrange(p_start::timestamptz, p_end::timestamptz, '[]')
          )
       OR EXISTS (
            SELECT 1 FROM maintenance_log m
            WHERE m.moto_id = t.id
              AND m.service_date IS NOT NULL
              AND m.completed_date IS NULL
              AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
              AND daterange(m.service_date,
                            COALESCE(m.scheduled_date, m.service_date) + 1, '[)')
                  && daterange(p_start, p_end + 1, '[)')
          )
  ),
  free AS (
    SELECT id FROM trailers
    WHERE id NOT IN (SELECT id FROM busy)
    ORDER BY created_at
  )
  SELECT CASE
    -- Motorka ze samoobslužné pobočky → vozík se vůbec nenabízí.
    WHEN p_moto_id IS NOT NULL AND public.moto_is_self_service(p_moto_id)
      THEN jsonb_build_object('available_count', 0, 'trailer_id', NULL)
    ELSE jsonb_build_object(
      'available_count', (SELECT count(*) FROM free),
      'trailer_id',      (SELECT id FROM free LIMIT 1)
    )
  END;
$$;

COMMENT ON FUNCTION public.get_trailer_availability(date, date, uuid, uuid) IS
  'Volné kusy vozíku v termínu {available_count, trailer_id}. p_moto_id = motorka, ke které se vozík přidává — ze samoobslužné pobočky vrací 0 (vozík je jen na obslužné).';

GRANT EXECUTE ON FUNCTION public.get_trailer_availability(date, date, uuid, uuid)
  TO anon, authenticated, service_role;

-- ─── 3) check_trailer_overlap — + zákaz vozíku na samoobslužné pobočce ───────
-- Tělo z 20260616_trailer_addon.sql (adresář supabase/functions/migrations, který
-- deploy-sql.yml nehlídá) + nová kontrola pobočky; zbytek funkce BEZE ZMĚNY.
-- Kontrolu pobočky dělá SECURITY DEFINER helper moto_is_self_service, takže
-- nezávisí na RLS volajícího ani u přímého insertu z appky.
CREATE OR REPLACE FUNCTION public.check_trailer_overlap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Přidává/mění se právě teď vozík, motorka nebo termín? Jen tehdy se kontroluje
  -- pobočka — rezervace vzniklé PŘED tímto pravidlem musí jít dál normálně
  -- odbavit (změna statusu, doplacení, storno…).
  v_check_branch boolean;
BEGIN
  IF NEW.trailer_moto_id IS NOT NULL
     AND NEW.status IN ('pending','reserved','active') THEN

    -- a) Vozík jen k motorce z OBSLUŽNÉ pobočky.
    IF TG_OP = 'INSERT' THEN
      v_check_branch := true;
    ELSIF OLD.trailer_moto_id IS DISTINCT FROM NEW.trailer_moto_id
       OR OLD.moto_id         IS DISTINCT FROM NEW.moto_id
       OR OLD.start_date      IS DISTINCT FROM NEW.start_date
       OR OLD.end_date        IS DISTINCT FROM NEW.end_date
       OR OLD.status NOT IN ('pending','reserved','active') THEN
      v_check_branch := true;
    ELSE
      v_check_branch := false;
    END IF;

    IF v_check_branch AND public.moto_is_self_service(NEW.moto_id) THEN
      RAISE EXCEPTION 'Vozík lze půjčit jen k motorce z obslužné pobočky — tato stojí na samoobslužné (moto_id=%).',
        NEW.moto_id
        USING ERRCODE = '23514';
    END IF;

    -- b) Dvojí rezervace téhož kusu vozíku (standalone i gear add-on) — beze změny.
    IF EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.id <> NEW.id
        AND b.status IN ('pending','reserved','active')
        AND (b.moto_id = NEW.trailer_moto_id OR b.trailer_moto_id = NEW.trailer_moto_id)
        AND tstzrange(b.start_date, b.end_date, '[]')
            && tstzrange(NEW.start_date, NEW.end_date, '[]')
    ) THEN
      RAISE EXCEPTION 'Vozík je v tomto termínu již obsazen (trailer_moto_id=%).',
        NEW.trailer_moto_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Do UPDATE OF přibyl `moto_id`: výměna motorky za kus ze samoobslužné pobočky
-- u rezervace s vozíkem se jinak triggeru vyhnula.
DROP TRIGGER IF EXISTS trg_check_trailer_overlap ON public.bookings;
CREATE TRIGGER trg_check_trailer_overlap
  BEFORE INSERT OR UPDATE OF trailer_moto_id, moto_id, start_date, end_date, status
  ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.check_trailer_overlap();

NOTIFY pgrst, 'reload schema';
