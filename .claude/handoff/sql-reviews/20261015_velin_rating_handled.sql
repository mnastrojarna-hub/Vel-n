-- 20261015_velin_rating_handled.sql
-- =============================================================================
-- NÁVRH (čeká na schválení majitelem — CLAUDE.md pravidlo 3; NEPATŘÍ zatím do
-- supabase/migrations). Nahrazuje OPTIONAL_20261015_booking_rating_reviews.sql
-- (stejná tabulka + sloupec rated_at_seen, který Velín potřebuje).
--
-- FEAT (zadání majitele 2026-10-15): Velín → Zprávy → záložka „Hodnocení“.
--   Hvězdičky jízdy = bookings.rating (1–5) + rated_at, zapisuje zákazník v appce
--   (beze změny). Soukromý text „Napiš nám přímo, co máme zlepšit“ jde do
--   zákazníkova chatu (message_threads + messages, předmět se značkou #XXXXXXXX)
--   — na to žádná změna schématu NENÍ potřeba (RLS: zákazník smí INSERT jen do
--   svého vlákna, admin čte vše; obě tabulky už jsou v supabase_realtime).
--   NIKDY ne do `reviews` (veřejně čitelná, web ji zobrazuje).
--
-- Tato migrace přidává jen SDÍLENÝ stav „vyřízeno“: nízké hodnocení (1–3 ★)
-- svítí ve Velíně a počítá se do odznaku, dokud ho obsluha nevyřídí. Vyřízeno
-- se odvozuje i samo (odpověď admina v chatu po hodnocení / uzavřená konverzace);
-- tahle tabulka je pro tlačítko „✓ Vyřízeno“ BEZ psaní zákazníkovi.
-- Bez migrace Velín ukládá ruční „vyřízeno“ do localStorage prohlížeče (nesdílí
-- se mezi adminy). Po nasazení to Velín pozná sám (dotaz na tabulku) a lokální
-- značky jednorázově převede do DB — žádná změna frontendu potřeba.
--
-- Platnost značky: rated_at_seen = bookings.rated_at v okamžiku označení.
-- Když zákazník hvězdičky změní (nové rated_at), Velín značku ignoruje
-- a hodnocení je znovu „k vyřízení“.
--
-- Zákazník ani anon tabulku nevidí (RLS jen is_admin(), REVOKE anon).
-- Idempotentní (IF NOT EXISTS / DROP … IF EXISTS / guard publikace).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.booking_rating_reviews (
  booking_id    uuid PRIMARY KEY REFERENCES public.bookings(id) ON DELETE CASCADE,
  handled_at    timestamptz NOT NULL DEFAULT now(),
  handled_by    uuid DEFAULT auth.uid() REFERENCES public.admin_users(id) ON DELETE SET NULL,
  rated_at_seen timestamptz,
  note          text CHECK (note IS NULL OR char_length(note) <= 2000)
);

-- kdyby byl dřív aplikován starší OPTIONAL návrh bez tohoto sloupce
ALTER TABLE public.booking_rating_reviews ADD COLUMN IF NOT EXISTS rated_at_seen timestamptz;

COMMENT ON TABLE public.booking_rating_reviews IS
  'Velín → Zprávy → Hodnocení: interní „vyřízeno“ u hodnocení jízdy (bookings.rating). Jen admin. Platí, dokud rated_at_seen = bookings.rated_at.';
COMMENT ON COLUMN public.booking_rating_reviews.rated_at_seen IS
  'bookings.rated_at v okamžiku označení; změní-li zákazník hodnocení, značka přestane platit (Velín ji ignoruje).';

-- Kdo označil = vždy přihlášený admin (klient handled_by neposílá; upsert ho přepíše).
CREATE OR REPLACE FUNCTION public._booking_rating_reviews_stamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.handled_by := auth.uid();
  END IF;
  IF NEW.handled_at IS NULL THEN
    NEW.handled_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_rating_reviews_stamp ON public.booking_rating_reviews;
CREATE TRIGGER trg_booking_rating_reviews_stamp
  BEFORE INSERT OR UPDATE ON public.booking_rating_reviews
  FOR EACH ROW EXECUTE FUNCTION public._booking_rating_reviews_stamp();

ALTER TABLE public.booking_rating_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS booking_rating_reviews_admin_all ON public.booking_rating_reviews;
CREATE POLICY booking_rating_reviews_admin_all ON public.booking_rating_reviews
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

REVOKE ALL ON public.booking_rating_reviews FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.booking_rating_reviews TO authenticated;
GRANT ALL ON public.booking_rating_reviews TO service_role;

-- Realtime: odznak/záložka Hodnocení u ostatních adminů se obnoví hned po označení.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'booking_rating_reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_rating_reviews;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ALTER PUBLICATION supabase_realtime (booking_rating_reviews) selhalo: %', SQLERRM;
END $$;

-- Ověření po aplikaci (ručně, read-only):
--   SELECT relrowsecurity FROM pg_class WHERE oid = 'public.booking_rating_reviews'::regclass;  -- true
--   SELECT polname FROM pg_policy WHERE polrelid = 'public.booking_rating_reviews'::regclass;  -- 1 politika
--   SELECT has_table_privilege('anon', 'public.booking_rating_reviews', 'SELECT');             -- false
--   SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'booking_rating_reviews';
-- STATE po schválení: STATE_1 (tabulka), STATE_2 (sloupce), STATE_4 (trigger),
-- STATE_5 (RLS + realtime), STATE_6 (changelog).
