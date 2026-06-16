-- =============================================================================
-- MIGRACE: Vozík (přívěs) jako příslušenství + samostatně z flotily (FÁZE 1)
-- Datum: 2026-06-16
-- Branch: claude/gracious-dirac-v6xi1c
--
-- Vozík půjde půjčit DVĚMA způsoby:
--   a) SAMOSTATNĚ jako kus flotily (běžná rezervace na jeho moto_id, kat. „Ostatní"),
--   b) jako GEAR ADD-ON k rezervaci motorky (web 400 Kč/den = fáze 2, app zdarma).
-- V OBOU případech se obsazenost MUSÍ promítnout do kalendáře vozíku a vozík se
-- propíše do ZF/DP/příp. dobropisu i do smlouvy (generate-invoice / generate-document
-- už itemizují všechny booking_extras → řádek „Vozík" se vypíše sám).
--
-- Tato migrace je idempotentní (IF NOT EXISTS / CREATE OR REPLACE / DROP IF EXISTS)
-- a je kanonickým zdrojem těchto objektů. Obsahuje:
--   1) motorcycles.is_trailer        — označení vozíkových kusů (Velín Fleet detail)
--   2) bookings.trailer_moto_id       — přiřazený kus vozíku u gear add-onu + index
--   3) get_moto_booked_dates          — UNION větev trailer_moto_id (sdílený kalendář)
--   4) get_trailer_availability RPC   — auto-výběr prvního volného kusu vozíku
--   5) check_trailer_overlap trigger  — zákaz dvojí rezervace téhož vozíku
-- =============================================================================

-- 1) motorcycles.is_trailer ---------------------------------------------------
ALTER TABLE public.motorcycles
  ADD COLUMN IF NOT EXISTS is_trailer boolean NOT NULL DEFAULT false;

-- 2) bookings.trailer_moto_id -------------------------------------------------
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS trailer_moto_id uuid
    REFERENCES public.motorcycles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_trailer_moto_id
  ON public.bookings (trailer_moto_id)
  WHERE trailer_moto_id IS NOT NULL;

-- 3) get_moto_booked_dates — sdílený kalendář vozíku --------------------------
-- Kalendář kusu (i vozíku) je obsazený jeho přímými rezervacemi (moto_id),
-- gear-přiřazeními (trailer_moto_id) i servisem.
CREATE OR REPLACE FUNCTION public.get_moto_booked_dates(p_moto_id uuid)
RETURNS TABLE (
  start_date  date,
  end_date    date,
  status      text,
  created_at  timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Přímé rezervace (kus jako motorka i jako samostatně půjčený vozík)
  SELECT b.start_date::date, b.end_date::date, b.status::text, b.created_at
  FROM bookings b
  WHERE b.moto_id = p_moto_id
    AND b.status IN ('pending','reserved','active')

  UNION ALL

  -- Gear add-on: tento vozík je přiřazený jako příslušenství k rezervaci motorky
  SELECT b.start_date::date, b.end_date::date, b.status::text, b.created_at
  FROM bookings b
  WHERE b.trailer_moto_id = p_moto_id
    AND b.status IN ('pending','reserved','active')

  UNION ALL

  -- Servis blokuje POUZE rozsah service_date → scheduled_date.
  SELECT
    m.service_date::date,
    COALESCE(m.scheduled_date, m.service_date)::date,
    'service'::text,
    m.created_at
  FROM maintenance_log m
  WHERE m.moto_id = p_moto_id
    AND m.service_date IS NOT NULL
    AND m.completed_date IS NULL
    AND COALESCE(m.status,'') NOT IN ('completed','cancelled')
    AND COALESCE(m.scheduled_date, m.service_date) >= CURRENT_DATE;
$$;

GRANT EXECUTE ON FUNCTION public.get_moto_booked_dates(uuid) TO anon, authenticated, service_role;

-- 4) get_trailer_availability — auto-výběr prvního volného kusu ----------------
-- Vrací { available_count: int, trailer_id: uuid|null } pro daný termín.
-- Obsazenost počítá z přímých rezervací (moto_id), gear-přiřazení (trailer_moto_id)
-- i servisu. trailer_id = první volný kus (ORDER BY created_at), který se přiřadí.
CREATE OR REPLACE FUNCTION public.get_trailer_availability(
  p_start date,
  p_end   date,
  p_exclude_booking uuid DEFAULT NULL
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
  SELECT jsonb_build_object(
    'available_count', (SELECT count(*) FROM free),
    'trailer_id',      (SELECT id FROM free LIMIT 1)
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_trailer_availability(date, date, uuid)
  TO anon, authenticated, service_role;

-- 5) check_trailer_overlap — zákaz dvojí rezervace téhož vozíku ----------------
-- BEFORE INSERT/UPDATE na bookings: pokud má řádek přiřazený vozík (trailer_moto_id)
-- a koliduje s jinou rezervací téhož kusu (ať už jako moto_id standalone, nebo jako
-- trailer_moto_id gear), zápis se odmítne. Řeší i kolizi standalone × gear.
CREATE OR REPLACE FUNCTION public.check_trailer_overlap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.trailer_moto_id IS NOT NULL
     AND NEW.status IN ('pending','reserved','active') THEN
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

DROP TRIGGER IF EXISTS trg_check_trailer_overlap ON public.bookings;
CREATE TRIGGER trg_check_trailer_overlap
  BEFORE INSERT OR UPDATE OF trailer_moto_id, start_date, end_date, status
  ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.check_trailer_overlap();

NOTIFY pgrst, 'reload schema';
