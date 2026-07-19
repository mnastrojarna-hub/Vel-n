-- =============================================================================
-- RE-ISSUE: get_moto_booked_dates s vozíkovou větví (trailer_moto_id)
-- Datum: 2026-07-19 — APLIKOVÁNO RUČNĚ v SQL editoru (ověřeno SELECTem),
-- tento soubor zajišťuje evidenci v _git_migrations (idempotentní re-aplikace).
--
-- Důvod: původní definice žije v supabase/functions/migrations/
-- 20260616_trailer_addon.sql — adresář, který deploy-sql.yml NEHLÍDÁ
-- (watchuje jen supabase/migrations/**). Na živé DB proto zůstala stará
-- verze bez UNION větve trailer_moto_id → web katalog-detail (buildBookedDays)
-- neukazoval vozík jako obsazený, když byl přiřazený jako příslušenství
-- k rezervaci motorky. Velín od 2026-07-19 čte bookings přímo (vč.
-- trailer_moto_id), zákaznický web/appka stojí na této RPC.
-- =============================================================================

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

NOTIFY pgrst, 'reload schema';
