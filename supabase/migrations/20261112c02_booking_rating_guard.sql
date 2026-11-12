-- 20261112c02_booking_rating_guard.sql
-- =============================================================================
-- Hodnocení jízdy (bookings.rating / rated_at): serverová pojistka.
--
-- Souvisí se zadáním majitele 2026-10-15 (hodnocení jízdy → recenze Google,
-- nízká hodnocení vyřizuje obsluha ve Velínu → Zprávy → Hodnocení).
-- Zákazník zapisuje hodnocení přímo UPDATE na bookings (appka rateBooking:
-- {rating, rated_at = čas z hodin ZAŘÍZENÍ}; appka 4.1.3 posílá místní čas bez
-- zóny → v DB posun o 1–2 h). Politika bookings_user_update už zajišťuje, že
-- zákazník hodnotí JEN SVOU rezervaci, ale:
--   • rated_at bere z hodin telefonu (řazení ve Velínu, odvozené „vyřízeno“),
--   • rated_at jde přepsat i bez změny hvězdiček,
--   • přes API jde ohodnotit i zrušenou nebo budoucí rezervaci.
-- Trigger u zákaznického JWT (ne admin, ne service role / cron / SQL bez JWT):
--   • změna rating u zrušené rezervace nebo jízdy, která ještě neskončila
--     → tiše zahozena (rating i rated_at zůstanou původní),
--   • jinak změna rating → rated_at = now() serveru (NULL při smazání hodnocení),
--   • změna jen rated_at → zahozena.
-- „Jízda skončila“ = zrcadlo appky (ResStatus.dokoncene: status completed NEBO
-- ended_by_sos NEBO konec nájmu minul) s rezervou: datum konce (Praha) <= dnešek
-- (Praha) — server pouští už v den konce, aby nikdy nezahodil hodnocení, které
-- appka nabídla. Stav / konec / ended_by_sos se čtou z původního řádku (OLD), aby je
-- zákazník nemohl „ukončit“ týmž zápisem (např. ended_by_sos = true).
-- Admin (Velín, update_test_booking_fields) a service role beze změny. Žádná
-- chyba se nevyhazuje (stávající appky beze změny), jiný sloupec se nemění.
--
-- Idempotentní (CREATE OR REPLACE, DROP TRIGGER IF EXISTS + CREATE). Jen nový
-- trigger BEFORE UPDATE OF rating, rated_at — nesahá na žádný existující trigger
-- ani funkci bookings; data se nemění (žádný backfill).
-- =============================================================================

CREATE OR REPLACE FUNCTION public._bookings_rating_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- Hodnotit jde jen skončenou nezrušenou jízdu (zrcadlo appky, viz hlavička); stav,
  -- konec a SOS se berou z OLD (zákazník je nepřepíše týmž zápisem).
  IF NEW.rating IS DISTINCT FROM OLD.rating
     AND NEW.rating IS NOT NULL
     AND (OLD.status::text = 'cancelled'
          OR NOT (OLD.status::text = 'completed'
                  OR COALESCE(OLD.ended_by_sos, false)
                  OR (OLD.end_date AT TIME ZONE 'Europe/Prague')::date
                     <= (now() AT TIME ZONE 'Europe/Prague')::date)) THEN
    NEW.rating := OLD.rating;
    NEW.rated_at := OLD.rated_at;
    RETURN NEW;
  END IF;
  IF NEW.rating IS DISTINCT FROM OLD.rating THEN
    NEW.rated_at := CASE WHEN NEW.rating IS NULL THEN NULL ELSE now() END;
  ELSIF NEW.rated_at IS DISTINCT FROM OLD.rated_at THEN
    NEW.rated_at := OLD.rated_at;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._bookings_rating_guard() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._bookings_rating_guard() IS
  'BEFORE UPDATE OF rating, rated_at na bookings: u zákaznického JWT hodnocení jen skončené nezrušené jízdy (jinak tiše beze změny), rated_at = now() serveru při změně hvězdiček, jinak rated_at beze změny.';

DROP TRIGGER IF EXISTS trg_bookings_rating_guard ON public.bookings;
CREATE TRIGGER trg_bookings_rating_guard
  BEFORE UPDATE OF rating, rated_at ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._bookings_rating_guard();
