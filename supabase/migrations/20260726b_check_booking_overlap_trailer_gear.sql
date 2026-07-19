-- =============================================================================
-- check_booking_overlap: přímá rezervace kusu koliduje i s jeho gear-přiřazením
-- Datum: 2026-07-19 — APLIKOVÁNO RUČNĚ v SQL editoru, soubor = evidence
-- v _git_migrations (idempotentní re-aplikace).
--
-- Díra: trigger check_trailer_overlap (20260616_trailer_addon.sql) hlídá jen
-- NOVÉ řádky s trailer_moto_id. Opačný směr chráněný nebyl — když je vozík už
-- přiřazený jako příslušenství (bookings.trailer_moto_id) a někdo ho poté
-- zarezervuje NAPŘÍMO jako kus flotily (moto_id = vozík), původní
-- check_booking_overlap porovnával jen moto_id vs. moto_id → dvojrezervace
-- prošla. UI to sice přes kalendáře nedovolí, DB pojistka ale chyběla.
-- Trigger trg_check_booking_overlap zůstává beze změny (volá tuto funkci).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_booking_overlap()
RETURNS TRIGGER AS $$
BEGIN
  -- SOS replacement bookings are exempt from moto overlap check
  IF NEW.sos_replacement = true THEN
    RETURN NEW;
  END IF;

  -- Skip cancelled/completed bookings
  IF NEW.status IN ('cancelled', 'completed') THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Překrývající se rezervace pro moto_id %', NEW.moto_id;
  END IF;

  -- NOVÉ: kus je v termínu přiřazený jako vozík-příslušenství jiné rezervace
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE trailer_moto_id = NEW.moto_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND status NOT IN ('cancelled', 'completed')
      AND tstzrange(start_date, end_date) && tstzrange(NEW.start_date, NEW.end_date)
  ) THEN
    RAISE EXCEPTION 'Kus % je v tomto termínu přiřazen jako vozík k jiné rezervaci', NEW.moto_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
