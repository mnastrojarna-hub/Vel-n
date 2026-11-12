-- 20261112d01_loyalty_colors_ramp.sql
-- =============================================================================
-- Barvy věrnostních ranků podle schváleného designu appky v2.2: jedna
-- plynulá škála růstu zelená → modrá/kovy → VIP → ohnivé zlato u ranku 20.
--
-- Zadání majitele 2026-10-16: „aby ten člověk měl pocit, že roste … na začátku
-- zelený, prostřední modrý, stříbro/bronz/platina můžou být … aby žádný ty
-- barvy těch ranků se nepodobaly“ (8 a 20 měly stejnou #FFD700) + 2026-10-15
-- „žádná růžová ani fialová, je to pro chlapy“.
--   Silnice 1–5   zelené (3 beze změny #4ADE80)
--   Kovy 6–9      bronz · stříbro · žluté zlato · platina
--   Drahokamy 10–16 modré, čím hlubší, tím vzácnější
--   VIP 17–19     karmín · sytě zlatá · platinová perla
--   Legenda 20    ohnivé zlato — jediný ohnivý rank
-- Rozlišitelnost CIEDE2000: každá dvojice ≥ 12,38; žádný odstín 232–345°.
--
-- Mění JEN loyalty_levels.color_hex (19 řádků). Slevy, prahy, názvy, překlady,
-- body ani ranky zákazníků se nemění. Barvu čtou get_loyalty_status /
-- admin_loyalty_status / žebříček a appka; Velín, web ani kiosk ji nepoužívají.
-- Nový vzhled appky (v2) mapuje staré barvy na tuto škálu sám (rank_palette.dart),
-- takže pro něj se nic nemění; mění se starý vzhled, appka 4.1.3 a oslava
-- level-upu.
--
-- Guard: každý UPDATE proběhne jen tehdy, když je v řádku pořád původní živá
-- barva (ověřeno REST čtením živé tabulky 2026-11-12: všech 20 řádků = původní
-- škála) → idempotentní (druhé spuštění nic nezmění) a nepřepíše barvu, kterou
-- mezitím někdo ručně změnil ve Velíně. Chybějící řádek = UPDATE 0 řádků.
-- Kontrolní blok na konci jen vypíše NOTICE, nasazení nikdy neshodí.
-- =============================================================================

UPDATE public.loyalty_levels l
   SET color_hex = v.new_hex
  FROM (VALUES
    (1,  '#9CA3AF', '#A3B8A8'),   -- Startér: šedá → šalvějová
    (2,  '#86EFAC', '#BDF6D1'),   -- Jezdec: → mátová
    (4,  '#22C55E', '#00AC7F'),   -- Stálý jezdec: → smaragdová
    (5,  '#14B8A6', '#0AA2A4'),   -- Věrný zákazník: → nefritová tyrkys
    (6,  '#CD7F32', '#C2844A'),   -- Bronzový jezdec: bronz (čitelnější)
    (7,  '#C0C0C0', '#929496'),   -- Stříbrný jezdec: stříbro (≠ platina)
    (8,  '#FFD700', '#E5D376'),   -- Zlatý jezdec: žluté zlato (≠ Legenda)
    (9,  '#E5E4E2', '#B9BEC6'),   -- Platinový jezdec: studená platina
    (10, '#7DD3FC', '#AEE9FF'),   -- Diamantový jezdec: led
    (11, '#38BDF8', '#2CD1D4'),   -- Prémiový zákazník: akvamarín
    (12, '#3B82F6', '#6EAFFF'),   -- Mistr silnic: azurová
    (13, '#6366F1', '#00A1C7'),   -- Šampion: indigo → blankytná
    (14, '#8B5CF6', '#5087D4'),   -- Veterán MotoGo: fialová → kobaltová
    (15, '#A855F7', '#117897'),   -- Elitní jezdec: purpurová → hlubinná petrolejová
    (16, '#D946EF', '#165EEB'),   -- Ambasador: magenta → královský safír
    (17, '#EF4444', '#D42020'),   -- VIP: → závodní karmín
    (18, '#D4AF37', '#EDB42D'),   -- VIP Gold: sytě zlatá
    (19, '#F1F5F9', '#F5F8FB'),   -- VIP Platinum: platinová perla
    (20, '#FFD700', '#FF8C1A')    -- Legenda MotoGo: ohnivé zlato
  ) AS v(level, old_hex, new_hex)
 WHERE l.level = v.level
   AND upper(l.color_hex) = v.old_hex;

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
     WHERE upper(ll.color_hex) IS DISTINCT FROM v.want
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
