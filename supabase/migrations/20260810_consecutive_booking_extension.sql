-- ============================================================================
-- 20260810_consecutive_booking_extension.sql
-- NAVAZUJÍCÍ REZERVACE = PRODLOUŽENÍ (jen jiná prezentace, žádný zásah do flow)
--
-- Když si TENTÝŽ zákazník vytvoří rezervaci na TUTÉŽ motorku, která datumově
-- NAVAZUJE na jeho existující rezervaci (začíná den po jejím konci, nebo končí
-- den před jejím začátkem — bez ohledu na časy), označí se nová rezervace
-- odkazem `extends_booking_id` na tu původní.
--
-- Co s tím systém dělá (vše ostatní beze změny — platby, faktury, kódy, storna):
--   • send-booking-email: místo šablony (web_)booking_reserved VYRENDERUJE
--     šablonu (web_)booking_modified s payloadem prodloužení (původní vs.
--     spojený termín, doplatek = cena navazující části). Do message_log se dál
--     loguje slug (web_)booking_reserved → dedup cronu
--     send_missing_booking_reserved_emails zůstává funkční.
--   • Velín: seznam rezervací + detail ukazují badge „PRODLOUŽENÍ" s odkazem
--     na původní rezervaci (místo dojmu „nová rezervace").
--
-- POZOR: záměrně NEpoužíváme continues_booking_id — ten je vyhrazený pro
-- výměnu motorky (swap/handoff) a věší se na něj logika kalendáře a kódů.
--
-- Idempotentní. Trigger je exception-safe — detekce NIKDY nesmí zablokovat
-- vytvoření rezervace.
-- ============================================================================

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS extends_booking_id uuid REFERENCES public.bookings(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_extends_booking_id
  ON public.bookings (extends_booking_id)
  WHERE extends_booking_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.detect_consecutive_booking()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev uuid;
BEGIN
  BEGIN
    -- Jen reálné nové rezervace s kompletními údaji
    IF NEW.user_id IS NULL OR NEW.moto_id IS NULL
       OR NEW.start_date IS NULL OR NEW.end_date IS NULL THEN
      RETURN NEW;
    END IF;
    -- Nesahat na swap/handoff pokračování (výměna motorky má vlastní flow)
    -- ani na řádky, kde už je vazba nastavená explicitně.
    IF NEW.extends_booking_id IS NOT NULL OR NEW.continues_booking_id IS NOT NULL THEN
      RETURN NEW;
    END IF;
    IF COALESCE(NEW.status::text, 'pending') NOT IN ('pending', 'reserved', 'active') THEN
      RETURN NEW;
    END IF;

    -- Navazující = stejný zákazník + stejná motorka + termíny na sebe navazují
    -- den po dni (sdílený den blokuje check_user_booking_overlap, čas nehraje
    -- roli). Původní rezervace musí být živá (reserved/active) — po vrácení
    -- motorky (completed) nebo stornu jde o běžnou novou rezervaci.
    SELECT b.id INTO v_prev
      FROM public.bookings b
     WHERE b.user_id = NEW.user_id
       AND b.moto_id = NEW.moto_id
       AND b.id IS DISTINCT FROM NEW.id
       AND b.status IN ('reserved', 'active')
       AND (b.end_date::date + 1 = NEW.start_date::date
            OR NEW.end_date::date + 1 = b.start_date::date)
     ORDER BY (b.end_date::date + 1 = NEW.start_date::date) DESC, b.end_date DESC
     LIMIT 1;

    IF v_prev IS NOT NULL THEN
      NEW.extends_booking_id := v_prev;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Detekce nikdy nesmí shodit INSERT rezervace — při chybě jen zaloguj.
    BEGIN
      INSERT INTO public.debug_log (source, action, status, error_message, request_data)
      VALUES ('detect_consecutive_booking', 'detect_failed', 'error', SQLERRM,
              jsonb_build_object('user_id', NEW.user_id, 'moto_id', NEW.moto_id,
                                 'start_date', NEW.start_date, 'end_date', NEW.end_date));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_detect_consecutive_booking ON public.bookings;
CREATE TRIGGER trg_detect_consecutive_booking
  BEFORE INSERT ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.detect_consecutive_booking();
