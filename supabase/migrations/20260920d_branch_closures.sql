-- =============================================================================
-- ZAVŘENÁ POBOČKA = ŽÁDNÁ REZERVACE JEJÍCH MOTOREK
-- Migrace: 20260920d_branch_closures.sql
--
-- Zadání (uživatel 2026-09-20):
--   „Pokud bude motorka na pobočce, která je v Pobočkách nastavená jako zavřená,
--    nelze ji vůbec zarezervovat. U pobočky je nutná možnost nastavit zavření
--    od–do (např. zimní sezona) — v daném termínu jsou VŠECHNY motorky té
--    pobočky nedostupné pro rezervace."
--
-- Dva nezávislé důvody zavření:
--   1) TRVALE — `branches.is_open = false` (přepínač OTEVŘENÁ/ZAVŘENÁ ve Velíně).
--      Dosud šlo jen o zobrazovaný štítek; nově BLOKUJE rezervace na celém
--      kalendáři. POZOR: sloupec má DEFAULT false — pobočka, která je omylem
--      vedená jako zavřená, po této migraci nic nepronajme (Velín → Pobočky to
--      nově hlásí červeným pruhem „motorky nelze rezervovat“).
--   2) SEZÓNNĚ — nová tabulka `branch_closures` (libovolný počet období od–do,
--      Velín → Pobočky → detail → záložka „Zavírací období“).
--
-- Jeden zdroj pravdy = `branch_is_closed(branch, from, to)`; na něj se věší:
--   * get_moto_booked_dates  → dny zavření jdou do kalendáře jako status
--     'branch_closed' (web katalog-detail i rezervační kalendář, appka detail
--     + odznak „dnes dostupné“ — všichni tři berou jakýkoli řádek jako obsazeno),
--   * check_moto_availability → false (appka: filtr katalogu, posun termínu,
--     výměna motorky, obnova storna; extend_booking),
--   * get_available_motos, get_trailer_availability → kus se nenabídne,
--   * trigger `trg_check_booking_branch_open` na `bookings` = TVRDÁ POJISTKA
--     (appka dělá přímý INSERT, Velín/AI/web jdou přes RPC — všechny padnou).
--
-- Rozsah zavření je INKLUZIVNÍ (shodně s dny pronájmu a `20260911_booking_
-- overlap_inclusive_days.sql`): zavřeno 1. 11. – 31. 3. blokuje oba krajní dny.
-- Již existující rezervace migrace NERUŠÍ (Velín na kolize upozorní při ukládání
-- období) a storno/dokončení rezervace na zavřené pobočce zůstává možné.
-- Idempotentní (IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER + CREATE).
-- =============================================================================

-- ─── 1) Tabulka zavíracích období ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.branch_closures (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id   uuid NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  closed_from date NOT NULL,
  closed_to   date NOT NULL,
  reason      text,
  created_by  uuid,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT branch_closures_range_chk CHECK (closed_to >= closed_from)
);

CREATE INDEX IF NOT EXISTS idx_branch_closures_branch
  ON public.branch_closures (branch_id, closed_from, closed_to);

COMMENT ON TABLE public.branch_closures IS
  'Zavírací období pobočky (od–do, inkluzivně). V termínu nelze rezervovat žádnou motorku dané pobočky.';
COMMENT ON COLUMN public.branch_closures.reason IS
  'Volitelný důvod (zimní sezona, rekonstrukce, dovolená…) — jen pro Velín, zákazníkovi se nezobrazuje.';

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_branch_closures_touch ON public.branch_closures;
CREATE TRIGGER trg_branch_closures_touch BEFORE UPDATE ON public.branch_closures
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- RLS: čtení veřejné (stejně jako `branches` — kalendáře webu i appky běží pod
-- anon a nejde o citlivá data), zápis jen admin (Velín).
ALTER TABLE public.branch_closures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS branch_closures_public_read ON public.branch_closures;
CREATE POLICY branch_closures_public_read ON public.branch_closures
  FOR SELECT USING (true);
DROP POLICY IF EXISTS branch_closures_admin ON public.branch_closures;
CREATE POLICY branch_closures_admin ON public.branch_closures
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ─── 2) Jeden zdroj pravdy ───────────────────────────────────────────────────
-- true = pobočka je v termínu [p_start..p_end] zavřená (trvale nebo obdobím).
-- Motorka bez pobočky (branch_id NULL) se nikdy neblokuje.
CREATE OR REPLACE FUNCTION public.branch_is_closed(
  p_branch_id uuid,
  p_start date,
  p_end   date
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE WHEN p_branch_id IS NULL THEN false ELSE
      -- trvale zavřená (přepínač ve Velíně)
      COALESCE((SELECT b.is_open IS NOT TRUE FROM branches b WHERE b.id = p_branch_id), false)
      -- nebo termín zasahuje do některého zavíracího období (inkluzivně)
      OR EXISTS (
        SELECT 1 FROM branch_closures c
        WHERE c.branch_id = p_branch_id
          AND c.closed_from <= COALESCE(p_end, p_start)
          AND c.closed_to   >= COALESCE(p_start, p_end)
      )
    END;
$$;

COMMENT ON FUNCTION public.branch_is_closed(uuid, date, date) IS
  'true = pobočka je v termínu zavřená (branches.is_open=false NEBO branch_closures). Zdroj pravdy pro všechny kontroly dostupnosti.';

-- Totéž nad motorkou (pohodlnější v kontrolách) — NULL, když kus neexistuje.
CREATE OR REPLACE FUNCTION public.moto_branch_closed(
  p_moto_id uuid,
  p_start date,
  p_end   date
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.branch_is_closed(m.branch_id, p_start, p_end)
  FROM motorcycles m WHERE m.id = p_moto_id;
$$;

GRANT EXECUTE ON FUNCTION public.branch_is_closed(uuid, date, date)   TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.moto_branch_closed(uuid, date, date) TO anon, authenticated, service_role;

-- ─── 3) Kalendář: dny zavření jako blokovaný rozsah ──────────────────────────
-- Vychází z živé verze (20260726_reissue_get_moto_booked_dates_trailer.sql),
-- beze změny přidává dvě UNION větve. Web (buildBookedDays / _rezRenderCal)
-- i appka (BookedDateRange) berou každý vrácený řádek jako obsazený den.
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
    AND COALESCE(m.scheduled_date, m.service_date) >= CURRENT_DATE

  UNION ALL

  -- Pobočka trvale zavřená → blokuje celý viditelný kalendář (5 let dopředu)
  SELECT CURRENT_DATE, (CURRENT_DATE + INTERVAL '5 years')::date, 'branch_closed'::text, now()
  FROM motorcycles mo
  JOIN branches br ON br.id = mo.branch_id
  WHERE mo.id = p_moto_id
    AND br.is_open IS NOT TRUE

  UNION ALL

  -- Zavírací období pobočky (zimní sezona…) — jen to, co ještě neskončilo
  SELECT GREATEST(c.closed_from, CURRENT_DATE), c.closed_to, 'branch_closed'::text, c.created_at
  FROM motorcycles mo
  JOIN branch_closures c ON c.branch_id = mo.branch_id
  WHERE mo.id = p_moto_id
    AND c.closed_to >= CURRENT_DATE;
$$;

GRANT EXECUTE ON FUNCTION public.get_moto_booked_dates(uuid) TO anon, authenticated, service_role;

-- ─── 4) check_moto_availability — zavřená pobočka = nedostupná ───────────────
-- Tělo z 20260911_booking_overlap_inclusive_days.sql + kontrola pobočky.
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
  IF COALESCE(public.moto_branch_closed(p_moto_id, p_start::date, p_end::date), false) THEN
    RETURN false;
  END IF;

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

-- ─── 5) get_available_motos — kus ze zavřené pobočky se nenabídne ────────────
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
    AND NOT COALESCE(public.branch_is_closed(m.branch_id, p_start::date, p_end::date), false)
    AND NOT EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.moto_id = m.id
        AND b.status IN ('pending', 'reserved', 'active')
        AND b.start_date::date <= p_end::date
        AND b.end_date::date   >= p_start::date
    );
END;
$$;

-- ─── 6) get_trailer_availability — vozík ze zavřené pobočky je nedostupný ────
-- Tělo z 20260616_trailer_addon.sql (adresář supabase/functions/migrations,
-- který deploy-sql.yml nehlídá) + filtr pobočky.
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
      AND NOT COALESCE(public.branch_is_closed(branch_id, p_start, p_end), false)
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

-- ─── 7) Tvrdá pojistka na zápisu rezervace ───────────────────────────────────
-- Appka vkládá do `bookings` PŘÍMÝM insertem (payment_screen.dart), web/AI/Velín
-- jdou přes RPC — jediné místo, které pokryje všechny, je trigger.
-- Nekontroluje: storno/dokončení, SOS náhradu (stejná výjimka jako u překryvu)
-- a UPDATE, který nemění motorku ani termín a řádek neaktivuje (aby rezervace
-- vzniklé PŘED zavřením pobočky šlo dál normálně odbavit).
CREATE OR REPLACE FUNCTION public.check_booking_branch_open()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start  date := NEW.start_date::date;
  v_end    date := NEW.end_date::date;
  v_branch uuid;
  v_name   text;
BEGIN
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.moto_id IS NOT DISTINCT FROM NEW.moto_id
     AND OLD.trailer_moto_id IS NOT DISTINCT FROM NEW.trailer_moto_id
     AND OLD.start_date::date = v_start
     AND OLD.end_date::date   = v_end
     AND OLD.status NOT IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.moto_id;
  IF public.branch_is_closed(v_branch, v_start, v_end) THEN
    SELECT b.name INTO v_name FROM branches b WHERE b.id = v_branch;
    RAISE EXCEPTION 'Pobočka % je v termínu % – % zavřená, motorku nelze rezervovat.',
      COALESCE(v_name, 'motorky'), to_char(v_start, 'DD.MM.YYYY'), to_char(v_end, 'DD.MM.YYYY')
      USING ERRCODE = '23514';
  END IF;

  IF NEW.trailer_moto_id IS NOT NULL THEN
    SELECT m.branch_id INTO v_branch FROM motorcycles m WHERE m.id = NEW.trailer_moto_id;
    IF public.branch_is_closed(v_branch, v_start, v_end) THEN
      SELECT b.name INTO v_name FROM branches b WHERE b.id = v_branch;
      RAISE EXCEPTION 'Pobočka % je v termínu % – % zavřená, vozík nelze půjčit.',
        COALESCE(v_name, 'vozíku'), to_char(v_start, 'DD.MM.YYYY'), to_char(v_end, 'DD.MM.YYYY')
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_booking_branch_open ON public.bookings;
CREATE TRIGGER trg_check_booking_branch_open
  BEFORE INSERT OR UPDATE OF start_date, end_date, moto_id, trailer_moto_id, status
  ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.check_booking_branch_open();

NOTIFY pgrst, 'reload schema';
