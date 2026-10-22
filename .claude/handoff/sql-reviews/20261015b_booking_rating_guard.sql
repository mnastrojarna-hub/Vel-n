-- 20261015b_booking_rating_guard.sql
-- =============================================================================
-- NÁVRH (čeká na schválení majitelem — CLAUDE.md pravidlo 3). DOPORUČENÉ, ale
-- funkce „Hodnocení“ bez něj funguje.
--
-- Hodnocení jízdy zapisuje zákazník přímo UPDATE na bookings (appka
-- rateBooking: {rating, rated_at: čas z hodin ZAŘÍZENÍ}). Politika
-- bookings_user_update (user_id = auth.uid() OR is_admin()) už zajišťuje, že
-- zákazník hodnotí JEN SVOU rezervaci, ale:
--   • rated_at bere z hodin telefonu (špatně nastavené hodiny → špatné řazení
--     ve Velíně a posunuté „odpověď po hodnocení“ u odvozeného „vyřízeno“),
--   • rated_at může zákazník přepsat na libovolnou hodnotu i bez změny hvězdiček,
--   • zákazník přes API ohodnotí i zrušenou nebo budoucí rezervaci (objevila by se
--     ve Velínu → Hodnocení).
-- Tento trigger u zákaznického JWT (ne admin, ne service role/cron/SQL bez JWT):
--   • změna rating u zrušené rezervace nebo rezervace, jejíž jízda ještě neskončila
--     → změna se tiše zahodí (rating i rated_at zůstanou původní),
--   • jinak změna rating → rated_at = now() serveru (NULL při smazání hodnocení),
--   • změna jen rated_at → zahodí se (ponechá původní).
-- „Jízda skončila“ = zrcadlo appky (ResStatus.dokoncene: status completed NEBO
-- ended_by_sos NEBO konec nájmu minul) s rezervou o 1 den: datum konce
-- (Praha) <= dnešek (Praha). Appka bere den konce z UTC hodnoty a „dnes“ z hodin
-- telefonu — přísnější serverová podmínka by v den konce mohla appce hodnocení
-- tiše zahodit, proto server pouští už v den konce nájmu.
-- Admin (Velín, update_test_booking_fields) a service role beze změny.
-- Žádný jiný sloupec se nemění; žádná chyba se nevyhazuje (stávající appky beze změny).
-- Idempotentní.
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
  -- Hodnotit jde jen skončenou jízdu (zrcadlo appky ResStatus.dokoncene, viz hlavička).
  IF NEW.rating IS DISTINCT FROM OLD.rating
     AND NEW.rating IS NOT NULL
     AND (NEW.status::text = 'cancelled'
          OR NOT (NEW.status::text = 'completed'
                  OR COALESCE(NEW.ended_by_sos, false)
                  OR (NEW.end_date AT TIME ZONE 'Europe/Prague')::date
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

COMMENT ON FUNCTION public._bookings_rating_guard() IS
  'BEFORE UPDATE OF rating, rated_at na bookings: u zákaznického JWT hodnocení jen skončené nezrušené jízdy (jinak tiše beze změny), rated_at = now() serveru při změně hvězdiček, jinak rated_at beze změny.';

DROP TRIGGER IF EXISTS trg_bookings_rating_guard ON public.bookings;
CREATE TRIGGER trg_bookings_rating_guard
  BEFORE UPDATE OF rating, rated_at ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public._bookings_rating_guard();

-- Ověření po aplikaci (ručně, read-only):
--   SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.bookings'::regclass AND tgname = 'trg_bookings_rating_guard';
-- STATE po schválení: STATE_4 (trigger), STATE_2 (bookings.rated_at = čas serveru), STATE_6.
