-- =============================================================================
-- MIGRACE: Zúžení pojistky na vozík — jen NOVÉ přiřazení (oprava 20260921b)
-- Datum: 2026-09-21
-- Branch: claude/samoobsluzna-pobocka-vozik-2mdsxo
--
-- PROČ SAMOSTATNÝ SOUBOR: `20260921b_trailer_only_on_staffed_branches.sql` se
-- už aplikoval (deploy-sql.yml běh #96, 2026-09-21 10:48, po merge PR #2059).
-- Evidence `public._git_migrations` je podle NÁZVU souboru, takže jeho úprava
-- na místě by se nikdy nenasadila — opravu je nutné vydat jako nový soubor.
--
-- CO SE OPRAVUJE: adversariální review našlo u triggeru z 20260921b dvě reálné
-- regrese. Kontrola pobočky se spouštěla i když se vozík vůbec nepřiřazoval:
--
--   1) LEGACY DATA. `v_check_branch` se nastavoval na true i při změně
--      start_date/end_date a při reaktivaci stornované rezervace. Rezervace,
--      které vozík na samoobslužné pobočce dostaly ještě PŘED pravidlem
--      (právě to byla ta chyba, kterou 20260921b opravuje), pak nešlo posunout,
--      obnovit ani odbavit. Migrace 20260921b žádný backfill nedělá, takže
--      takové řádky v DB reálně jsou.
--
--   2) PLATBA PŘED ZÁPISEM. `moto_id` v `UPDATE OF` znamenalo, že výměna
--      motorky spadne na 23514. Jenže web „Výměna motorky“
--      (`pages-upravit-rezervaci-swap.js` → `split_booking_moto_swap`) i appka
--      (`reservation_edit_screen.dart` → `PaymentContext.pendingEditChanges`)
--      dělají krok 1 jako `p_dry_run=true` (nic nezapíše → projde), pošlou
--      zákazníka na Stripe a skutečný zápis provedou až PO zaplacení. Výsledek:
--      peníze strženy, změna neprovedena, a hláška by se do UI dostala
--      nepřeložená včetně UUID (swapErr mapa pro 23514 záznam nemá).
--
-- NOVÝ ZÁBĚR: kontrola pobočky běží VÝHRADNĚ když se vozík PRÁVĚ přiřazuje —
-- INSERT s vozíkem, nebo UPDATE měnící `trailer_moto_id`. To pokrývá celý účel
-- pojistky (klient, který `p_moto_id` neposílá — appky z obchodů), a ničeho
-- dalšího se nedotkne. Ochrana proti dvojí rezervaci téhož kusu je BEZE ZMĚNY.
--
-- VĚDOMÁ ZBÝVAJÍCÍ MEZERA: výměna motorky pod existujícím vozíkem na
-- samoobslužnou pobočku projde. Patří vyřešit ve výběru motorek v těch flow
-- (dnes filtrují jen `branch_id`, ne `type`), ne tvrdým pádem v DB — jinak se
-- vrací problém 2).
--
-- Body 1) a 2) migrace 20260921b (helpery + get_trailer_availability s
-- p_moto_id) zůstávají PLATNÉ a tato migrace se jich nedotýká.
-- Idempotentní (CREATE OR REPLACE / DROP TRIGGER + CREATE).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_trailer_overlap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  -- Přiřazuje se vozík právě teď? Jen tehdy se kontroluje pobočka.
  v_assigning boolean;
BEGIN
  IF NEW.trailer_moto_id IS NOT NULL
     AND NEW.status IN ('pending','reserved','active') THEN

    -- a) NOVÝ vozík jen k motorce z OBSLUŽNÉ pobočky (20260921b, zúženo).
    IF TG_OP = 'INSERT' THEN
      v_assigning := true;
    ELSE
      v_assigning := OLD.trailer_moto_id IS DISTINCT FROM NEW.trailer_moto_id;
    END IF;

    IF v_assigning AND public.moto_is_self_service(NEW.moto_id) THEN
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

-- `moto_id` se ze seznamu sloupců ODEBÍRÁ (přidalo ho 20260921b) — viz důvod 2)
-- v hlavičce. Seznam je tím zase shodný s původním 20260616_trailer_addon.sql.
DROP TRIGGER IF EXISTS trg_check_trailer_overlap ON public.bookings;
CREATE TRIGGER trg_check_trailer_overlap
  BEFORE INSERT OR UPDATE OF trailer_moto_id, start_date, end_date, status
  ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.check_trailer_overlap();

NOTIFY pgrst, 'reload schema';
