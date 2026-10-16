-- !!! NAHRAZENO 2026-10-16: použij 20261016_loyalty_colors_ramp.sql (celá škála 1–20). TENTO SOUBOR NECOMMITOVAT. !!!
-- 20261015_loyalty_colors_no_purple.sql
-- =============================================================================
-- NÁVRH — NEcommitovat do supabase/migrations/ bez schválení majitele
-- (merge do main = automatické nasazení na živou DB přes deploy-sql.yml).
--
-- Zadání majitele 2026-10-15: „V barvách ranků by neměla být růžová ani
-- fialová, je to pro chlapy.“ Ranky 13–16 měly indigo → fialovou → purpurovou
-- → magentu a navzájem si byly podobné (CIEDE2000 jen 5,0–8,5).
--
-- Nové barvy (bez růžové/fialové, odstín mimo 235–345°):
--   13 Šampion         #6366F1 → #FF5A0C  závodní oranžová   (ohnivý opál)
--   14 Veterán MotoGo  #8B5CF6 → #8A9A3B  olivová            (olivín)
--   15 Elitní jezdec   #A855F7 → #B39E7E  coyote / pouštní khaki (tygří oko)
--   16 Ambasador       #D946EF → #19A2B4  petrolejová        (petrolejový turmalín)
-- Rozlišitelnost: každá nová barva má vůči všem 19 ostatním rankům
-- CIEDE2000 ≥ 14,5 (nejbližší: 13↔17 VIP 14,5 · 13↔6 Bronz 14,6 ·
-- 16↔5 a 16↔11 14,7 · 15↔18 16,2 · 14↔18 17,8).
-- Kontrast (WCAG 2.x): text v barvě ranku na tmavé pilulce appky #1A2E22
-- 4,61–5,56 : 1; tmavý text #0F1A14 na barvě ranku 5,70–6,88 : 1.
-- Bílý text na těchto barvách NE (2,6–3,1 : 1) → appka musí brát tmavý text
-- (viz research/rank_colors.md, oprava `_onColor` v obou stromech appky).
--
-- Mění JEN loyalty_levels.color_hex. Slevy, prahy, názvy, překlady, body ani
-- ranky zákazníků se nemění. Barvu čtou get_loyalty_status /
-- admin_loyalty_status / žebříček a appka přímo z tabulky → prstenec MG loga,
-- čip, Moje ranky, žebříček i level-up se přebarví samy při dalším načtení.
-- Velín, web ani kiosk barvy ranků nepoužívají.
--
-- Guard: každý UPDATE proběhne jen tehdy, když je v řádku pořád PŮVODNÍ
-- barva → idempotentní (druhé spuštění nic nezmění) a nepřepíše barvu, kterou
-- mezitím někdo ručně změnil ve Velíně. Bez BEGIN/COMMIT — deploy-sql.yml
-- pouští soubor s --single-transaction.
-- =============================================================================

UPDATE public.loyalty_levels SET color_hex = '#FF5A0C'
 WHERE level = 13 AND upper(color_hex) = '#6366F1';   -- Šampion: indigo → závodní oranžová

UPDATE public.loyalty_levels SET color_hex = '#8A9A3B'
 WHERE level = 14 AND upper(color_hex) = '#8B5CF6';   -- Veterán MotoGo: fialová → olivová

UPDATE public.loyalty_levels SET color_hex = '#B39E7E'
 WHERE level = 15 AND upper(color_hex) = '#A855F7';   -- Elitní jezdec: purpurová → coyote khaki

UPDATE public.loyalty_levels SET color_hex = '#19A2B4'
 WHERE level = 16 AND upper(color_hex) = '#D946EF';   -- Ambasador: magenta → petrolejová

-- Kontrola v logu nasazení: vypíše, pokud ranky 13–16 nemají očekávanou barvu
-- (např. ji někdo předtím ručně změnil ve Velíně) — nasazení tím NEPADÁ.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT ll.level, ll.name, ll.color_hex, v.want
      FROM public.loyalty_levels ll
      JOIN (VALUES (13, '#FF5A0C'), (14, '#8A9A3B'), (15, '#B39E7E'), (16, '#19A2B4')) AS v(level, want)
        ON v.level = ll.level
     WHERE upper(ll.color_hex) <> v.want
  LOOP
    RAISE NOTICE 'loyalty_levels %, %: color_hex = % (čekáno %) — ponecháno, zkontrolovat ve Velíně',
      r.level, r.name, r.color_hex, r.want;
  END LOOP;
END $$;

-- Ověření po nasazení (nesmí vrátit žádný řádek):
--   SELECT level, name, color_hex FROM public.loyalty_levels
--    WHERE upper(color_hex) IN ('#6366F1', '#8B5CF6', '#A855F7', '#D946EF');
--
-- Rollback (ručně, jen kdyby majitel chtěl zpět):
--   UPDATE public.loyalty_levels SET color_hex = '#6366F1' WHERE level = 13 AND upper(color_hex) = '#FF5A0C';
--   UPDATE public.loyalty_levels SET color_hex = '#8B5CF6' WHERE level = 14 AND upper(color_hex) = '#8A9A3B';
--   UPDATE public.loyalty_levels SET color_hex = '#A855F7' WHERE level = 15 AND upper(color_hex) = '#B39E7E';
--   UPDATE public.loyalty_levels SET color_hex = '#D946EF' WHERE level = 16 AND upper(color_hex) = '#19A2B4';
--
-- Po nasazení (CLAUDE.md pravidlo 4): SUPABASE_BACKEND_STATE_6.md changelog
-- + v SUPABASE_BACKEND_STATE_2.md u loyalty_levels.color_hex poznámka
-- „13–16 přebarveny 2026-10-15 (bez fialové/růžové)“.
