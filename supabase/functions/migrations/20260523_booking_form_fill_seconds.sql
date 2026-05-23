-- =============================================================================
-- MIGRACE: doba vyplňování rezervačního formuláře (2 metriky)
-- Datum: 2026-05-23
-- Branch: claude/vigilant-noether-of6R1
--
-- Cíl: u webové rezervace měřit DVĚ doby (od otevření formuláře = MG._rezInit):
--   1) form_fill_seconds    — start → vytvoření rezervace (samotné vyplnění)
--   2) payment_fill_seconds — start → úspěšná platba (celý proces vč. dokladů)
--
-- Web ukládá start do sessionStorage `mg_rez_started_at` a po úspěšném
-- create_web_booking pošle ISO timestamp startu přes set_booking_form_seconds.
-- RPC uloží `form_started_at` + dopočte `form_fill_seconds` (now - start).
-- `payment_fill_seconds` dopočítá BEFORE-UPDATE trigger, jakmile rezervace
-- přejde na payment_status='paid' (z form_started_at + confirmed_at) — funguje
-- i přes Stripe redirect, protože start je uložený v DB.
--
-- Volání z webu je obalené try/catch (jako set_booking_language) — když RPC
-- ještě neexistuje, rezervaci to nerozbije.
-- =============================================================================

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS form_started_at      timestamptz,
  ADD COLUMN IF NOT EXISTS form_fill_seconds    integer,
  ADD COLUMN IF NOT EXISTS payment_fill_seconds integer;

COMMENT ON COLUMN public.bookings.form_started_at IS
  'Okamžik otevření webového rezervačního formuláře (MG._rezInit). Plní set_booking_form_seconds.';
COMMENT ON COLUMN public.bookings.form_fill_seconds IS
  'Doba (s) od otevření formuláře po vytvoření rezervace = samotné vyplňování.';
COMMENT ON COLUMN public.bookings.payment_fill_seconds IS
  'Doba (s) od otevření formuláře po úspěšnou platbu (payment_status=paid). Dopočítá trigger.';

-- Post-create helper: uloží start + dobu vyplnění (drop staré (uuid,integer) varianty)
DROP FUNCTION IF EXISTS public.set_booking_form_seconds(uuid, integer);

CREATE OR REPLACE FUNCTION public.set_booking_form_seconds(
  p_booking_id uuid,
  p_started_at timestamptz
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $func$
  UPDATE public.bookings
     SET form_started_at   = p_started_at,
         form_fill_seconds = GREATEST(0, LEAST(86400, EXTRACT(EPOCH FROM (now() - p_started_at))::int))
   WHERE id = p_booking_id
     AND booking_source = 'web'
     AND form_started_at IS NULL          -- první naměření vyhrává (resume/Zpět nepřepíše)
     AND p_started_at IS NOT NULL
     AND p_started_at <= now()
     AND p_started_at >= now() - interval '24 hours';
$func$;

REVOKE ALL ON FUNCTION public.set_booking_form_seconds(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_booking_form_seconds(uuid, timestamptz) TO anon, authenticated, service_role;

-- Trigger: po přechodu na 'paid' dopočítej dobu do zaplacení z form_started_at
CREATE OR REPLACE FUNCTION public.trg_booking_payment_fill_seconds()
RETURNS trigger
LANGUAGE plpgsql
AS $func$
BEGIN
  IF NEW.form_started_at IS NOT NULL
     AND NEW.payment_fill_seconds IS NULL
     AND NEW.payment_status = 'paid'
     AND (TG_OP = 'INSERT' OR OLD.payment_status IS DISTINCT FROM 'paid') THEN
    NEW.payment_fill_seconds := GREATEST(0, LEAST(604800,
      EXTRACT(EPOCH FROM (COALESCE(NEW.confirmed_at, now()) - NEW.form_started_at))::int));
  END IF;
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_booking_payment_fill_seconds ON public.bookings;
CREATE TRIGGER trg_booking_payment_fill_seconds
  BEFORE INSERT OR UPDATE OF payment_status, confirmed_at ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.trg_booking_payment_fill_seconds();

NOTIFY pgrst, 'reload schema';
