-- MotoGo24 — Duplicitní místa ve Velíně: nástroj ukazoval jen POLOVINU nálezů
-- ---------------------------------------------------------------------------
-- `admin_poi_duplicate_groups` (20260920f) hledala dvojice aktivních bodů do
-- X metrů, u kterých je shodný `norm_name` NEBO shodná `category`. Vypadá to
-- rozumně, jenže přesně ten typ dvojice, kvůli kterému ta záložka vznikla,
-- skrz ten filtr propadne — má totiž jiný název I jinou kategorii:
--
--   „Rozhledna Doubravka“  lookout  norm_name „doubravka“
--   „Doubravská Hora“      castle   norm_name „doubravska hora“     36 m
--
-- Změřeno nad reálným katalogem (CZ): do 60 m je 608 dvojic a filtr jich vrátí
-- 309, tedy polovinu. Do 100 m 1 199 / 553, do 150 m 1 970 / 852.
--
-- Přibývá parametr `p_all`. U RUČNÍHO slučování rozhoduje ÚPLNOST, ne přesnost:
-- vybírá člověk a poražený se jen deaktivuje, nemaže. AUTOMATICKÉ slučování
-- (20260920m) zůstává přísné — tam se shoda názvu i kategorie vyžaduje dál,
-- protože tam nikdo nekontroluje, co se slilo.
--
-- Proč nová migrace a ne úprava `20260920f`: ta už je v `main`, takže ji
-- `deploy-sql.yml` má zaevidovanou v `public._git_migrations` podle NÁZVU
-- souboru a znovu by ji nespustil — změna v ní by se na živou databázi
-- nikdy nedostala.
--
-- Idempotentní: `drop function if exists` + `create or replace`.

-- Starou třífázovou signaturu je nutné DROPNOUT, jinak by v DB zůstaly dvě
-- funkce stejného jména a PostgREST by si vybíral podle toho, kolik argumentů
-- zrovna dorazí (Velín po téhle migraci posílá čtyři).
drop function if exists public.admin_poi_duplicate_groups(int, text, int);

create or replace function public.admin_poi_duplicate_groups(
  p_radius_m int default 150,
  p_country  text default 'CZ',
  p_limit    int default 200,
  p_all      boolean default false
) returns jsonb language plpgsql stable security definer
  set search_path = public
  set statement_timeout to '55s' as $fn$
declare
  res jsonb;
  d   double precision := greatest(p_radius_m, 10) / 111320.0;
begin
  if not is_admin() then
    raise exception 'Jen pro administrátory';
  end if;
  with pairs as (
    select a.id as a_id, b.id as b_id,
           round((111320.0 * sqrt(
             power(a.lat - b.lat, 2) +
             power((a.lng - b.lng) * cos(radians((a.lat + b.lat) / 2)), 2)))::numeric, 0) as m
      from public.points_of_interest a
      join public.points_of_interest b
        -- Jen souřadnicové okno (rozsahy, ne abs()), ať ho plánovač vezme
        -- z idx_poi_catalog_latlng. `b.id > a.id` schválně AŽ ve WHERE —
        -- v JOIN podmínce z něj plánovač udělal přístupovou cestu přes pkey
        -- a dotaz spadl z 2 s na 51 s.
        on b.lat between a.lat - d and a.lat + d
       and b.lng between a.lng - d / greatest(cos(radians(a.lat)), 0.2)
                     and a.lng + d / greatest(cos(radians(a.lat)), 0.2)
       and b.is_active
     where a.is_active
       and b.id > a.id
       and (p_all or b.norm_name = a.norm_name or b.category = a.category)
       and (p_country is null or a.country = p_country)
  ), lim as (
    select * from pairs where m <= p_radius_m order by m limit greatest(p_limit, 1)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'distance_m', l.m,
           'a', to_jsonb(pa) - 'translations' - 'images' - 'image_alts' - 'norm_name',
           'b', to_jsonb(pb) - 'translations' - 'images' - 'image_alts' - 'norm_name')
         order by l.m), '[]'::jsonb)
    into res
    from lim l
    join public.points_of_interest pa on pa.id = l.a_id
    join public.points_of_interest pb on pb.id = l.b_id;
  return res;
end $fn$;
grant execute on function public.admin_poi_duplicate_groups(int, text, int, boolean) to authenticated;

comment on function public.admin_poi_duplicate_groups(int, text, int, boolean) is
  'Podezřelé duplicity v katalogu míst pro Velín. p_all = true vrátí VŠECHNY dvojice v okruhu (to Velín posílá standardně), false jen ty se shodným norm_name nebo category — ten filtr propustí zhruba polovinu. Ruční slučování potřebuje úplnost; automatické (20260920m) zůstává přísné.';
