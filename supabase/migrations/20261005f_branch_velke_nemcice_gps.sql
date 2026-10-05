-- 2026-10-05 — přesná poloha samoobslužné pobočky Velké Němčice (zadání majitele: „na webu, v appce a všude zpřesni
-- místo pobočky“): 49.0043289 N, 16.6721237 E (https://mapy.com/s/rakutujopa). Dosud 49.0046725, 16.6721528
-- (20260923_branch_brno_velke_nemcice.sql) — cca 38 m vedle. Z DB polohu berou web (potvrzení, úprava rezervace,
-- kontakt), appka (K vyzvednutí, detail rezervace, seznam poboček), AI agenti (maps_url), Velín. Natvrdo v kódu
-- (mění se ve stejném commitu): web data/pobocky.php `map`, appka branches_info_provider.dart (oba stromy).
-- Adresa (Boudky, 691 63) beze změny. Idempotentní: mění jen řádek s jinými souřadnicemi.
DO $$
DECLARE
  c_id  constant uuid    := '22222222-2222-2222-2222-222222222222';
  c_lat constant numeric := 49.0043289;
  c_lng constant numeric := 16.6721237;
  n integer;
BEGIN
  UPDATE public.branches
     SET gps_lat = c_lat, gps_lng = c_lng,
         -- point bez pevné konvence os: zachovat pořadí, které řádek má (x > 40 = (lat, lng))
         coordinates = CASE WHEN coordinates IS NULL THEN NULL
                            WHEN coordinates[0] > 40 THEN point(c_lat, c_lng) ELSE point(c_lng, c_lat) END,
         updated_at = now()
   WHERE (id = c_id OR (address = 'Boudky' AND city ~* 'n[eě]m[cč]ic'))
     AND (gps_lat IS DISTINCT FROM c_lat OR gps_lng IS DISTINCT FROM c_lng
          OR (coordinates IS NOT NULL AND NOT (coordinates ~= point(c_lat, c_lng) OR coordinates ~= point(c_lng, c_lat))));
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'Velké Němčice GPS → %, %: upraveno % řádek/ů', c_lat, c_lng, n;
END $$;
