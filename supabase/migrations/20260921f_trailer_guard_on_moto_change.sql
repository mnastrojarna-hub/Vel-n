-- =============================================================================
-- MIGRACE: Vozík × změna motorky — pojistka i pro PŘÍMÉ zápisy (appka)
-- Datum: 2026-09-21
-- Branch: claude/samoobsluzna-pobocka-vozik-2mdsxo
--
-- PROČ: adversariální review ukázalo, že `20260921e` hlídá `apply_booking_changes`,
-- jenže **appka tohle RPC vůbec nevolá** — moto změnu commituje přímým
-- `UPDATE bookings SET moto_id = …` (`reservation_edit_screen.dart`, po platbě
-- pak `payment_screen.dart`). A `20260921c` `moto_id` z `UPDATE OF` odebralo,
-- takže na živé DB pro appku neplatí ŽÁDNÁ serverová kontrola. Starší build
-- z obchodu (bez klientské zábrany) tak rezervaci s vozíkem přehodí na motorku
-- ze samoobslužné pobočky zcela bez námitky. Přesně tu populaci („starší verze
-- z obchodů") uvádí hlavička `20260921b` jako důvod, proč pojistka musí být v DB.
--
-- PROČ TO `20260921c` ODEBRALO A PROČ TO TEĎ JDE VRÁTIT: tehdy by kontrola
-- shodila výměnu motorky AŽ PO zaplacení (obě „zaplať a pak zapiš" cesty).
-- Tenhle problém je mezitím uzavřený PŘED platbou na všech peněžních cestách:
--   * web „Změna motorky"  → `apply_booking_changes` dry-run  (20260921e)
--   * web „Výměna motorky" → `split_booking_moto_swap` dry-run (20260921d)
--   * appka s doplatkem    → `process-payment` app-format validátor (tato dávka)
-- Zbývají tedy jen zápisy, u kterých žádné peníze netečou, a tam je tvrdé
-- odmítnutí správné.
--
-- DVĚ VÝJIMKY:
--   * `is_admin()` — Velín mění `moto_id` přímým UPDATE a obsluha smí přehodit
--     vědomě (UI ji varuje, `BookingModifyModal`). Blokovat personál by jen
--     přesunulo problém na telefon.
--   * `sos_replacement` — SOS náhrada je všude záměrně výjimka (shodně
--     s `check_booking_branch_open`, 20260920d).
--
-- Kontrola na PŘIŘAZENÍ vozíku (`20260921c`) zůstává beze změny; tahle migrace
-- přidává druhý případ: vozík zůstává a MĚNÍ SE MOTORKA pod ním.
-- Idempotentní (CREATE OR REPLACE / DROP TRIGGER + CREATE).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_trailer_overlap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Přiřazuje se vozík právě teď? (20260921c)
  v_assigning boolean;
  -- Mění se motorka pod už přiřazeným vozíkem? (tato migrace)
  v_moto_moved boolean;
BEGIN
  IF NEW.trailer_moto_id IS NOT NULL
     AND NEW.status IN ('pending','reserved','active') THEN

    IF TG_OP = 'INSERT' THEN
      v_assigning  := true;
      v_moto_moved := false;
    ELSE
      v_assigning  := OLD.trailer_moto_id IS DISTINCT FROM NEW.trailer_moto_id;
      v_moto_moved := OLD.moto_id IS DISTINCT FROM NEW.moto_id;
    END IF;

    -- a) Vozík jen k motorce z OBSLUŽNÉ pobočky — při přiřazení vozíku
    --    i při výměně motorky pod ním. Obsluha (Velín) a SOS jsou výjimka.
    IF (v_assigning OR v_moto_moved)
       AND COALESCE(NEW.sos_replacement, false) = false
       AND NOT public.is_admin()
       AND public.moto_is_self_service(NEW.moto_id) THEN
      RAISE EXCEPTION 'Vozík lze půjčit jen k motorce z obslužné pobočky — tato stojí na samoobslužné (moto_id=%).',
        NEW.moto_id
        USING ERRCODE = '23514';
    END IF;

    -- b) Dvojí rezervace téhož kusu vozíku (standalone i gear add-on).
    --    Tělo z 20260616_trailer_addon.sql, BEZE ZMĚNY.
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

-- `moto_id` se do UPDATE OF VRACÍ (20260921c ho odebralo) — bez něj by se
-- UPDATE, který mění jen motorku, triggeru vyhnul úplně.
DROP TRIGGER IF EXISTS trg_check_trailer_overlap ON public.bookings;
CREATE TRIGGER trg_check_trailer_overlap
  BEFORE INSERT OR UPDATE OF trailer_moto_id, moto_id, start_date, end_date, status
  ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.check_trailer_overlap();

NOTIFY pgrst, 'reload schema';
