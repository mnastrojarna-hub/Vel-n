-- 20261112c01_velin_rating_handled.sql
-- =============================================================================
-- Velín → Zprávy → Hodnocení: sdílený stav „vyřízeno“ u hodnocení jízdy.
--
-- Zadání majitele 2026-10-15: hodnocení jízdy v appce vede na recenzi Google,
-- soukromé „Napiš nám přímo, co máme zlepšit“ jde do Velínu (záložka Hodnocení).
--   • Hvězdičky = bookings.rating (1–5) + rated_at, zapisuje zákazník v appce.
--   • Soukromý text jde do zákazníkova chatu (message_threads + messages,
--     předmět se značkou #XXXXXXXX) — na to žádná změna schématu potřeba není.
--     NIKDY ne do `reviews` (veřejně čitelná, web ji zobrazuje).
--
-- Tato migrace přidává jen tabulku pro tlačítko „✓ Vyřízeno“ BEZ psaní
-- zákazníkovi: nízké hodnocení (1–3 ★) svítí ve Velíně a počítá se do odznaku,
-- dokud ho obsluha nevyřídí. Velín (useRatings.js / ratingsFetch.js) tabulku
-- sám pozná dotazem; dokud neexistuje, drží značky v localStorage prohlížeče
-- a po nasazení je jednorázově převede do DB.
--
-- Platnost značky: rated_at_seen = bookings.rated_at v okamžiku označení;
-- když zákazník hvězdičky změní (nové rated_at), Velín značku ignoruje.
-- handled_by vždy doplní trigger = přihlášený admin (klient ho neposílá).
--
-- Přístup: jen admin (RLS is_admin()), anon nic, service_role vše.
-- Realtime: přidání do supabase_realtime je hlídané (už je členem → nic;
-- chyba publikace → WARNING, migrace nepadá — Velín má i periodické načtení).
--
-- Idempotentní: CREATE TABLE / ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE,
-- DROP … IF EXISTS + CREATE, REVOKE/GRANT, hlídaný DO blok. Nová prázdná
-- tabulka → žádná data, která by mohla shodit FK/CHECK.
-- Nemění: bookings, message_threads, messages, reviews ani jejich politiky.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.booking_rating_reviews (
  booking_id    uuid PRIMARY KEY REFERENCES public.bookings(id) ON DELETE CASCADE,
  handled_at    timestamptz NOT NULL DEFAULT now(),
  handled_by    uuid DEFAULT auth.uid() REFERENCES public.admin_users(id) ON DELETE SET NULL,
  rated_at_seen timestamptz,
  note          text CHECK (note IS NULL OR char_length(note) <= 2000)
);

-- pojistka pro případ, že by tabulka vznikla dřív bez tohoto sloupce
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

REVOKE ALL ON FUNCTION public._booking_rating_reviews_stamp() FROM PUBLIC, anon, authenticated;

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

-- Výchozí práva schématu dávají nové tabulce ALL i pro anon → odebrat.
REVOKE ALL ON public.booking_rating_reviews FROM PUBLIC, anon, authenticated;
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
