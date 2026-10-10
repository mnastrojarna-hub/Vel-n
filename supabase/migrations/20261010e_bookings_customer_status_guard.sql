-- ============================================================================
-- ZÁKAZNÍK SI NESMÍ SÁM „ZAPLATIT“ / POTVRDIT REZERVACI (2026-10-10)
--
-- Nález při auditu přístupových kódů (incident #5AED3469): RLS
-- `bookings_user_insert` / `bookings_user_update` kontroluje jen vlastníka.
-- Přihlášený zákazník tak mohl přímým REST zápisem (PostgREST, anon klíč +
-- vlastní JWT) založit rezervaci rovnou jako `reserved` / `paid`, nebo
-- přepnout svou nezaplacenou rezervaci na `reserved` → trigger
-- `auto_generate_door_codes` vydal přístupové kódy BEZ PLATBY.
--
-- Appka zapisuje přímo jen `pending` + `unpaid` (nová rezervace, obnovení
-- zrušené) a `cancelled` (zrušení nezaplaceného konceptu); web jde přes RPC.
-- Potvrzení platby, aktivace, dokončení i storna s vratkou dělají SECURITY
-- DEFINER RPC / edge funkce (service role) / Velín (admin) — ty pojistka
-- nebrzdí: kontroluje se `current_user` PŘÍMÉHO zápisu (anon / authenticated),
-- ne `auth.uid()` (ten je vyplněný i uvnitř RPC volaných zákazníkem).
-- Funkce je záměrně SECURITY INVOKER (jinak by current_user byl vlastník).
-- ============================================================================

CREATE OR REPLACE FUNCTION public._guard_customer_booking_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('anon', 'authenticated') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'pending';
    NEW.payment_status := 'unpaid';
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status NOT IN ('pending', 'cancelled') THEN
    NEW.status := OLD.status;
  END IF;
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NEW.payment_status IS DISTINCT FROM 'unpaid' THEN
    NEW.payment_status := OLD.payment_status;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._guard_customer_booking_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._guard_customer_booking_status() TO anon, authenticated, service_role;

-- Jméno začíná „_“ → BEFORE trigger běží PŘED ostatními (abecední pořadí),
-- takže kontroly překryvu / poboček i auto-generování kódů vidí už opravený stav.
DROP TRIGGER IF EXISTS _trg_guard_customer_booking_status ON public.bookings;
CREATE TRIGGER _trg_guard_customer_booking_status
  BEFORE INSERT OR UPDATE OF status, payment_status ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._guard_customer_booking_status();
