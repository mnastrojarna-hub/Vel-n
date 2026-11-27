-- ===== E-shop: samostatný přepínač pro web (zadání majitele 2026-11-27) =====
-- 2026-11-27, schváleno majitelem 2026-11-27.
-- „eshop ve Velíně by měl jít zapnout zvlášť pro web a zvlášť pro app“.
--  • `eshop_visible`      = e-shop v APPCE (čtou ho všechny vydané verze appky — beze změny),
--  • `eshop_visible_web`  = e-shop na WEBU (nový řádek; web: layout.php → fetchFeatureFlagOr).
-- Nový řádek převezme AKTUÁLNÍ stav `eshop_visible`, takže se nasazením na webu nic nezmění.
-- Idempotentní: řádek se založí jen když neexistuje (pozdější ruční přepnutí nepřepíše). DATOVÁ, bez schématu.
INSERT INTO public.feature_flags (key, enabled, description)
SELECT 'eshop_visible_web',
       COALESCE((SELECT enabled FROM public.feature_flags WHERE key = 'eshop_visible'), false),
       'E-shop na webu motogo24.cz (menu, patička, košík). Appka má vlastní přepínač eshop_visible.'
WHERE NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'eshop_visible_web');

UPDATE public.feature_flags
   SET description = 'E-shop v menu mobilní aplikace (web má vlastní přepínač eshop_visible_web).'
 WHERE key = 'eshop_visible'
   AND description = 'E-shop v menu webu a appky (vypnuto = skrytý, místo něj Pobočky)';
