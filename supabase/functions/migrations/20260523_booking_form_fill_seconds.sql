-- =============================================================================
-- MIGRACE: doba vyplňování rezervačního formuláře
-- Datum: 2026-05-23
-- Branch: claude/vigilant-noether-of6R1
--
-- Cíl: měřit, jak dlouho zákazníkovi trvalo vyplnit webovou rezervaci — od
-- otevření formuláře (MG._rezInit) po vytvoření rezervace v DB (create_web_booking).
--
-- Web ukládá start do sessionStorage `mg_rez_started_at` a po úspěšném
-- create_web_booking volá set_booking_form_seconds(booking_id, seconds)
-- (obalené try/catch — jako set_booking_language; když RPC ještě neexistuje,
-- rezervaci to nerozbije). Velín zobrazuje dobu v detailu rezervace.
--
-- Nový sloupec bookings.form_fill_seconds + post-create helper RPC.
-- =============================================================================

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS form_fill_seconds integer;

COMMENT ON COLUMN public.bookings.form_fill_seconds IS
  'Doba (v sekundách) vyplňování webového rezervačního formuláře: od otevření flow po vytvoření rezervace. Plní set_booking_form_seconds z webu.';

CREATE OR REPLACE FUNCTION public.set_booking_form_seconds(
  p_booking_id uuid,
  p_seconds integer
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $func$
  UPDATE public.bookings
     SET form_fill_seconds = p_seconds
   WHERE id = p_booking_id
     AND booking_source = 'web'
     AND form_fill_seconds IS NULL          -- první naměření vyhrává (resume/Zpět nepřepíše)
     AND p_seconds IS NOT NULL
     AND p_seconds >= 0
     AND p_seconds < 86400;                 -- sanity cap 24 h
$func$;

REVOKE ALL ON FUNCTION public.set_booking_form_seconds(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_booking_form_seconds(uuid, integer) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
