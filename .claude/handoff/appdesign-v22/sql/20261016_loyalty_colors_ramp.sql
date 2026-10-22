-- 20261016_loyalty_colors_ramp.sql
-- =============================================================================
-- NÁVRH — NEcommitovat do supabase/migrations/ bez schválení majitele
-- (merge do main = automatické nasazení na živou DB přes deploy-sql.yml).
-- NAHRAZUJE návrh 20261015_loyalty_colors_no_purple.sql (ten NEcommitovat).
--
-- Zadání majitele 2026-10-16: „aby ten člověk měl pocit, že roste … na začátku
-- zelený, prostřední modrý, stříbro/bronz/platina můžou být … aby žádný ty
-- barvy těch ranků se nepodobaly“ (13 vypadal jako 20, 8 a 20 měly dokonce
-- stejnou #FFD700) + 2026-10-15 „žádná růžová ani fialová, je to pro chlapy“.
--
-- Nová škála (jeden plynulý růst hodnoty):
--   Silnice 1–5   zelené:  1 šalvěj · 2 máta · 3 svěží zelená (beze změny) · 4 smaragd · 5 nefritová tyrkys
--   Kovy 6–9      dle názvů: 6 bronz · 7 stříbro · 8 žluté zlato · 9 platina
--   Drahokamy 10–16 modré, čím hlubší, tím vzácnější: led → akvamarín → azur → blankyt → kobalt → hlubinný petrolej → královský safír
--   VIP 17–19     17 závodní karmín · 18 sytě zlatá · 19 platinová perla
--   Legenda 20    ohnivé zlato — JEDINÝ ohnivý rank (v appce dál gradient #FFD700 → #FF6B00)
--
-- Rozlišitelnost (CIEDE2000): každá dvojice ≥ 12,38, sousední ranky ≥ 15,60
-- (dnes: 8 = 20 = 0,0 · 9↔19 4,9 · 14↔15 5,0 · 3↔4 6,8 …).
-- Odstín: žádná barva v pásmu 232–345° (fialová / purpurová / růžová).
-- Kontrast (WCAG 2.x): prstenec loga na hlavičce #0A1A10 ≥ 3,28 : 1;
-- text NA barvě ranku ≥ 4,89 : 1 (tmavý #0F1A14 nebo bílý — podle kontrastu,
-- appka musí brát lepší z obou, viz research/rank_ramp.md §6).
--
-- Mění JEN loyalty_levels.color_hex (19 řádků; level 3 zůstává #4ADE80).
-- Slevy, prahy, názvy, překlady, body ani ranky zákazníků se nemění.
-- Barvu čtou get_loyalty_status / admin_loyalty_status / žebříček a appka
-- přímo z tabulky → prstenec MG loga, čip, Moje ranky, žebříček i level-up se
-- přebarví samy při dalším načtení. Velín, web ani kiosk barvy ranků nepoužívají.
--
-- POŘADÍ NASAZENÍ: až S/PO vydání appky s opravou textu na barvě ranku
-- (_onColor podle kontrastu + zesvětlený text ranku na tmavém pozadí,
-- research/rank_ramp.md §6). Bez ní jsou názvy ranků 14–17 na tmavém štítku
-- karty ranku 2,6–3,9 : 1 (dnešní 12–17 mají 3,2–4,2 : 1).
--
-- Guard: každý UPDATE proběhne jen tehdy, když je v řádku pořád PŮVODNÍ
-- živá barva (u 13–16 i barva z nenasazeného návrhu 20261015) →
-- idempotentní (druhé spuštění nic nezmění) a nepřepíše barvu, kterou mezitím
-- někdo ručně změnil ve Velíně. Bez BEGIN/COMMIT — deploy-sql.yml pouští
-- soubor s --single-transaction.
-- =============================================================================

UPDATE public.loyalty_levels SET color_hex = '#A3B8A8'
 WHERE level = 1  AND upper(color_hex) = '#9CA3AF';                -- Startér: šedá → šalvějová

UPDATE public.loyalty_levels SET color_hex = '#BDF6D1'
 WHERE level = 2  AND upper(color_hex) = '#86EFAC';                -- Jezdec: zelená → mátová

-- level 3 Motorkář zůstává #4ADE80 (beze změny)

UPDATE public.loyalty_levels SET color_hex = '#00AC7F'
 WHERE level = 4  AND upper(color_hex) = '#22C55E';                -- Stálý jezdec: zelená → smaragdová

UPDATE public.loyalty_levels SET color_hex = '#0AA2A4'
 WHERE level = 5  AND upper(color_hex) = '#14B8A6';                -- Věrný zákazník: tyrkys → nefritová tyrkys

UPDATE public.loyalty_levels SET color_hex = '#C2844A'
 WHERE level = 6  AND upper(color_hex) = '#CD7F32';                -- Bronzový jezdec: bronz → bronz (čitelnější)

UPDATE public.loyalty_levels SET color_hex = '#929496'
 WHERE level = 7  AND upper(color_hex) = '#C0C0C0';                -- Stříbrný jezdec: stříbro (odliší se od platiny)

UPDATE public.loyalty_levels SET color_hex = '#E5D376'
 WHERE level = 8  AND upper(color_hex) = '#FFD700';                -- Zlatý jezdec: žluté zlato (≠ Legenda)

UPDATE public.loyalty_levels SET color_hex = '#B9BEC6'
 WHERE level = 9  AND upper(color_hex) = '#E5E4E2';                -- Platinový jezdec: studená platina (≠ VIP Platinum)

UPDATE public.loyalty_levels SET color_hex = '#AEE9FF'
 WHERE level = 10 AND upper(color_hex) = '#7DD3FC';                -- Diamantový jezdec: led / diamant

UPDATE public.loyalty_levels SET color_hex = '#2CD1D4'
 WHERE level = 11 AND upper(color_hex) = '#38BDF8';                -- Prémiový zákazník: akvamarín

UPDATE public.loyalty_levels SET color_hex = '#6EAFFF'
 WHERE level = 12 AND upper(color_hex) = '#3B82F6';                -- Mistr silnic: azurová

UPDATE public.loyalty_levels SET color_hex = '#00A1C7'
 WHERE level = 13 AND upper(color_hex) IN ('#6366F1', '#FF5A0C');  -- Šampion: indigo → blankytná

UPDATE public.loyalty_levels SET color_hex = '#5087D4'
 WHERE level = 14 AND upper(color_hex) IN ('#8B5CF6', '#8A9A3B');  -- Veterán MotoGo: fialová → kobaltová

UPDATE public.loyalty_levels SET color_hex = '#117897'
 WHERE level = 15 AND upper(color_hex) IN ('#A855F7', '#B39E7E');  -- Elitní jezdec: purpurová → hlubinná petrolejová

UPDATE public.loyalty_levels SET color_hex = '#165EEB'
 WHERE level = 16 AND upper(color_hex) IN ('#D946EF', '#19A2B4');  -- Ambasador: magenta → královský safír

UPDATE public.loyalty_levels SET color_hex = '#D42020'
 WHERE level = 17 AND upper(color_hex) = '#EF4444';                -- VIP: červená → závodní karmín

UPDATE public.loyalty_levels SET color_hex = '#EDB42D'
 WHERE level = 18 AND upper(color_hex) = '#D4AF37';                -- VIP Gold: sytě zlatá

UPDATE public.loyalty_levels SET color_hex = '#F5F8FB'
 WHERE level = 19 AND upper(color_hex) = '#F1F5F9';                -- VIP Platinum: platinová perla

UPDATE public.loyalty_levels SET color_hex = '#FF8C1A'
 WHERE level = 20 AND upper(color_hex) = '#FFD700';                -- Legenda MotoGo: ohnivé zlato (≠ Zlatý jezdec)

-- Kontrola v logu nasazení: vypíše ranky, které nemají očekávanou barvu
-- (např. ji někdo předtím ručně změnil ve Velíně), a případné duplicitní
-- barvy — nasazení tím NEPADÁ.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT ll.level, ll.name, ll.color_hex, v.want
      FROM public.loyalty_levels ll
      JOIN (VALUES (1, '#A3B8A8'), (2, '#BDF6D1'), (3, '#4ADE80'), (4, '#00AC7F'), (5, '#0AA2A4'),
                   (6, '#C2844A'), (7, '#929496'), (8, '#E5D376'), (9, '#B9BEC6'), (10, '#AEE9FF'),
                   (11, '#2CD1D4'), (12, '#6EAFFF'), (13, '#00A1C7'), (14, '#5087D4'), (15, '#117897'),
                   (16, '#165EEB'), (17, '#D42020'), (18, '#EDB42D'), (19, '#F5F8FB'), (20, '#FF8C1A')) AS v(level, want)
        ON v.level = ll.level
     WHERE upper(ll.color_hex) <> v.want
  LOOP
    RAISE NOTICE 'loyalty_levels %, %: color_hex = % (čekáno %) — ponecháno, zkontrolovat ve Velíně',
      r.level, r.name, r.color_hex, r.want;
  END LOOP;
  FOR r IN
    SELECT upper(color_hex) AS hex, string_agg(level::text, ', ' ORDER BY level) AS levels
      FROM public.loyalty_levels GROUP BY upper(color_hex) HAVING count(*) > 1
  LOOP
    RAISE NOTICE 'loyalty_levels: barvu % sdílí více ranků (%)', r.hex, r.levels;
  END LOOP;
END $$;

-- Ověření po nasazení (musí vrátit 0 řádků):
--   SELECT level, name, color_hex FROM public.loyalty_levels
--    WHERE upper(color_hex) IN ('#9CA3AF','#86EFAC','#22C55E','#14B8A6','#CD7F32','#C0C0C0','#FFD700','#E5E4E2','#7DD3FC',
--                               '#38BDF8','#3B82F6','#6366F1','#8B5CF6','#A855F7','#D946EF','#EF4444','#D4AF37','#F1F5F9');
--
-- Rollback (ručně, jen kdyby majitel chtěl zpět — vrací živý stav k 2026-10-16):
--   UPDATE public.loyalty_levels l SET color_hex = o.old
--     FROM (VALUES (1,'#9CA3AF','#A3B8A8'),(2,'#86EFAC','#BDF6D1'),(4,'#22C55E','#00AC7F'),(5,'#14B8A6','#0AA2A4'),
--                  (6,'#CD7F32','#C2844A'),(7,'#C0C0C0','#929496'),(8,'#FFD700','#E5D376'),(9,'#E5E4E2','#B9BEC6'),
--                  (10,'#7DD3FC','#AEE9FF'),(11,'#38BDF8','#2CD1D4'),(12,'#3B82F6','#6EAFFF'),(13,'#6366F1','#00A1C7'),
--                  (14,'#8B5CF6','#5087D4'),(15,'#A855F7','#117897'),(16,'#D946EF','#165EEB'),(17,'#EF4444','#D42020'),
--                  (18,'#D4AF37','#EDB42D'),(19,'#F1F5F9','#F5F8FB'),(20,'#FFD700','#FF8C1A')) AS o(level, old, new)
--    WHERE l.level = o.level AND upper(l.color_hex) = o.new;
--
-- Po nasazení (CLAUDE.md pravidlo 4): SUPABASE_BACKEND_STATE_6.md changelog
-- + v SUPABASE_BACKEND_STATE_2.md u loyalty_levels.color_hex poznámka
-- „2026-10-16 nová škála 1–20 (zelené → kovy → modré → VIP → ohnivé zlato),
-- bez fialové/růžové, CIEDE2000 ≥ 12“. STATE_1 řádek hex hodnoty neuvádí.
-- Appka: _fallbackLevels v loyalty_levels_provider.dart (OBA stromy) na nové barvy.
