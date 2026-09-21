-- =============================================================================
-- MIGRACE: check_trailer_overlap — návrat ŽIVÉHO těla + kontrola pobočky
-- Datum: 2026-09-21
-- Branch: claude/samoobsluzna-pobocka-vozik-2mdsxo
--
-- INCIDENT (způsobený touto sérií, nalezen ve 4. kole review):
-- Migrace 20260921b/c/f přepisovaly `check_trailer_overlap` tělem opsaným ze
-- `supabase/functions/migrations/20260616_trailer_addon.sql`. Jenže ŽIVÁ funkce
-- (dump `supabase-live-snapshot` z 2026-09-21 08:55, tj. před 20260921b) byla
-- mezitím vyvinutá v dashboardu a repo o tom nevědělo. Přepis tak od 10:48
-- ZAHODIL tři věci:
--   1) SECURITY DEFINER + SET search_path — bez něj běží EXISTS pod RLS
--      volajícího a při přímém insertu z appky nevidí pending rezervace jiných
--      účtů → dvojrezervace vozíku projde (stejná třída jako incident
--      2026-08-23 u check_booking_overlap, 20260823_check_booking_overlap_rls_fix).
--   2) INKLUZIVNÍ DNY (`::date <= / >=`) — opsané tělo mělo `tstzrange(...,'[]')`,
--      u něhož je jednodenní rezervace prázdný rozsah a nikdy nekoliduje
--      (přesně chyba incidentu CRF 1000 8J6873, 20260911_booking_overlap_
--      inclusive_days).
--   3) SAMOSTATNÉ půjčení vozíku — živé tělo přidává do kontroly i `NEW.moto_id`,
--      když je ten kus sám vozík (`is_trailer`), takže standalone × gear kolize
--      se hlídá v OBOU směrech; opsané tělo hlídalo jen `trailer_moto_id`.
-- Živé tělo také hlásí `trailer_unavailable: <uuid>` s ERRCODE 23505; žádný
-- klient na to nematchuje (ověřeno grepem), vracíme původní podobu kvůli věrnosti.
--
-- CO ZŮSTÁVÁ Z 20260921f: kontrola „vozík jen k motorce z OBSLUŽNÉ pobočky"
-- při přiřazení vozíku i při výměně motorky pod ním, s výjimkou `is_admin()`
-- (Velín varuje, ale obsluhu neblokuje) a `sos_replacement`. Její umístění
-- PŘED kontrolu obsazenosti je záměrné: hlášky se nemíchají.
--
-- POUČENÍ zapsané i do STATE_6: před re-issue jakékoli funkce porovnat s
-- `git show origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql`,
-- ne jen s posledním souborem v repu.
-- Idempotentní (CREATE OR REPLACE / DROP TRIGGER + CREATE).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_trailer_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_units uuid[] := ARRAY[]::uuid[];
  v_unit  uuid;
  -- Přiřazuje se vozík právě teď? / Mění se motorka pod už přiřazeným vozíkem?
  v_assigning  boolean;
  v_moto_moved boolean;
BEGIN
  IF NEW.status NOT IN ('pending','reserved','active') THEN RETURN NEW; END IF;

  -- ─── a) Vozík jen k motorce z OBSLUŽNÉ pobočky (20260921b/c/f) ───────────
  IF NEW.trailer_moto_id IS NOT NULL THEN
    IF TG_OP = 'INSERT' THEN
      v_assigning  := true;
      v_moto_moved := false;
    ELSE
      v_assigning  := OLD.trailer_moto_id IS DISTINCT FROM NEW.trailer_moto_id;
      v_moto_moved := OLD.moto_id IS DISTINCT FROM NEW.moto_id;
    END IF;
    IF (v_assigning OR v_moto_moved)
       AND COALESCE(NEW.sos_replacement, false) = false
       AND NOT public.is_admin()
       AND public.moto_is_self_service(NEW.moto_id) THEN
      RAISE EXCEPTION 'Vozík lze půjčit jen k motorce z obslužné pobočky — tato stojí na samoobslužné (moto_id=%).',
        NEW.moto_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  -- ─── b) Dvojí rezervace téhož kusu vozíku — ŽIVÉ tělo beze změny ─────────
  -- Kus je obsazený jak přímou rezervací (moto_id = standalone půjčení
  -- vozíku), tak gear-přiřazením (trailer_moto_id). Kontrolují se všechny
  -- vozíkové kusy, kterých se řádek týká: gear add-on i případ, kdy je sama
  -- rezervovaná „motorka" vozík. Dny INKLUZIVNĚ (20260911).
  IF NEW.trailer_moto_id IS NOT NULL THEN
    v_units := array_append(v_units, NEW.trailer_moto_id);
  END IF;
  IF NEW.moto_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM motorcycles m WHERE m.id = NEW.moto_id AND m.is_trailer = true) THEN
    v_units := array_append(v_units, NEW.moto_id);
  END IF;
  IF array_length(v_units,1) IS NULL THEN RETURN NEW; END IF;

  FOREACH v_unit IN ARRAY v_units LOOP
    IF EXISTS (
      SELECT 1 FROM bookings b
      WHERE b.id <> NEW.id
        AND (b.moto_id = v_unit OR b.trailer_moto_id = v_unit)
        AND b.status IN ('pending','reserved','active')
        AND b.start_date::date <= NEW.end_date::date
        AND b.end_date::date   >= NEW.start_date::date
    ) THEN
      RAISE EXCEPTION 'trailer_unavailable: %', v_unit USING ERRCODE = '23505';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_trailer_overlap ON public.bookings;
CREATE TRIGGER trg_check_trailer_overlap
  BEFORE INSERT OR UPDATE OF trailer_moto_id, moto_id, start_date, end_date, status
  ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.check_trailer_overlap();

NOTIFY pgrst, 'reload schema';
