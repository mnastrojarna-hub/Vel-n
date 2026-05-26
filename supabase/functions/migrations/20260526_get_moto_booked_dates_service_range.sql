-- 2026-05-26 — get_moto_booked_dates: servis blokuje jen service_date → scheduled_date
--
-- Předtím se na webovém kalendáři v detailu motorky servis jevil jako obsazený
-- „od dneška" (RPC brala created_at jako začátek servisu). Nově servis blokuje
-- POUZE rozsah service_date → COALESCE(scheduled_date, service_date) a jen pokud
-- ještě není dokončený/zrušený a jeho konec je dnes nebo v budoucnu.

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
  -- Rezervace, které blokují kalendář
  SELECT b.start_date::date, b.end_date::date, b.status::text, b.created_at
  FROM bookings b
  WHERE b.moto_id = p_moto_id
    AND b.status IN ('pending','reserved','active')

  UNION ALL

  -- Servis blokuje POUZE rozsah service_date → scheduled_date.
  -- Jednodenní servis (scheduled_date NULL) = jen service_date.
  -- Dokončený/zrušený servis už neblokuje. NIKDY se nebere created_at
  -- jako začátek, jinak je motorka „obsazená" už ode dne zadání.
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
