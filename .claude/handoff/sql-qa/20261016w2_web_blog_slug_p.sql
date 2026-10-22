-- =============================================================================
-- 20261016w2_web_blog_slug_p.sql   (NÁVRH ke schválení majitelem — neaplikováno)
-- Datová migrace (bez změn schématu): článek „Proč je MotoGo24 nejlepší motopůjčovna v ČR“
-- (cms_pages 5ec9affa-…) má od 28. 6. 2026 slug „p“ → URL /blog/p (SEO: bez klíčových slov, vypadá jako chyba).
-- Nový slug: proc-je-motogo24-nejlepsi-motopujcovna-v-cr.
-- Web (pages/blog-detail.php, $legacySlugs) od QA 2026-10-16 přesměruje /blog/p 301 na nový slug,
-- ale JEN když „p“ v DB už neexistuje — do aplikace této migrace se článek zobrazuje dál pod /blog/p.
-- Nahrát PHP web nejpozději spolu s touto migrací (jinak by /blog/p po přejmenování vracel 404).
--
-- Bezpečnost: mění jen přesně tento řádek se slugem „p“ a jen když nový slug ještě nikdo nepoužívá.
-- Idempotentní. Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- =============================================================================
DO $$
DECLARE
  cnt integer;
BEGIN
  IF EXISTS (SELECT 1 FROM public.cms_pages WHERE slug = 'proc-je-motogo24-nejlepsi-motopujcovna-v-cr') THEN
    RAISE NOTICE 'blog slug: nový slug už existuje — beze změny';
    RETURN;
  END IF;
  UPDATE public.cms_pages
     SET slug = 'proc-je-motogo24-nejlepsi-motopujcovna-v-cr', updated_at = now()
   WHERE id = '5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc' AND slug = 'p';
  GET DIAGNOSTICS cnt = ROW_COUNT;
  RAISE NOTICE 'blog slug: přejmenováno % řádků', cnt;
END $$;
