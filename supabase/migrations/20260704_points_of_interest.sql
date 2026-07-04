-- ==================================================================
-- MotoGo24 — KATALOG SAMOSTATNÝCH BODŮ ZÁJMU (points_of_interest)
-- Body zájmu nezávislé na trasách: přehrady, velké rybníky a jezera,
-- hrady a zámky, rozhledny a vyhlídky, památky, přírodní rezervace…
-- (CZ / SK / PL / AT a dále). Kategorie je EXPLICITNÍ (spolehlivý filtr).
-- Vícejazyčné popisy v jsonb `translations = {lang:{name,description}}`.
-- Appka je čte přes RPC `get_pois_catalog()` a zobrazuje v katalogu POI
-- (obrazovka „Všechny body zájmu") vedle bodů z tras a komunitních bodů.
-- ==================================================================

-- 1) TABULKA ----------------------------------------------------------
create table if not exists public.points_of_interest (
  id           uuid primary key default gen_random_uuid(),
  category     text not null
               check (category in ('food','castle','lookout','water','sights','nature','other')),
  name         text not null,                 -- kanonický název (cs)
  description  text,                           -- kanonický popis (cs)
  lat          double precision not null,
  lng          double precision not null,
  country      text,                           -- ISO: CZ/SK/PL/AT/…
  region       text,                           -- kraj / vojvodství / spolková země (volitelně)
  image_url    text,                           -- titulní fotka
  images       text[] not null default '{}',   -- galerie
  image_alts   text[] not null default '{}',   -- alt texty k fotkám
  translations jsonb,                           -- {lang:{name,description}}
  source       text,                            -- 'curated' | 'wikidata' | 'osm' | …
  is_active    boolean not null default true,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_poi_catalog_active  on public.points_of_interest(is_active);
create index if not exists idx_poi_catalog_cat     on public.points_of_interest(category);
create index if not exists idx_poi_catalog_country on public.points_of_interest(country);

-- 2) RLS + trigger + práva -------------------------------------------
alter table public.points_of_interest enable row level security;

drop policy if exists poi_catalog_public_read on public.points_of_interest;
create policy poi_catalog_public_read on public.points_of_interest
  for select to anon, authenticated
  using (is_active = true or is_admin());

drop policy if exists poi_catalog_admin_all on public.points_of_interest;
create policy poi_catalog_admin_all on public.points_of_interest
  for all to authenticated using (is_admin()) with check (is_admin());

drop trigger if exists trg_poi_catalog_updated on public.points_of_interest;
create trigger trg_poi_catalog_updated before update on public.points_of_interest
  for each row execute function public.set_updated_at();

grant select on public.points_of_interest to anon, authenticated;
grant insert, update, delete on public.points_of_interest to authenticated;

-- 3) HODNOCENÍ i pro katalogové body ---------------------------------
-- Rozšíříme poi_ratings o cíl `poi_id` (dosud jen route_poi / user_poi).
alter table public.poi_ratings
  add column if not exists poi_id uuid references public.points_of_interest(id) on delete cascade;
create index if not exists idx_poi_ratings_poi on public.poi_ratings(poi_id);

alter table public.poi_ratings drop constraint if exists poi_ratings_one_target;
alter table public.poi_ratings add constraint poi_ratings_one_target
  check (num_nonnulls(route_poi_id, user_poi_id, poi_id) = 1);

alter table public.poi_ratings drop constraint if exists poi_ratings_uniq_poi;
alter table public.poi_ratings add constraint poi_ratings_uniq_poi unique (user_id, poi_id);

-- rate_poi: přidán cíl p_poi_id (stará 3-arg verze se zahazuje kvůli přetížení)
drop function if exists public.rate_poi(uuid, uuid, int);
create or replace function public.rate_poi(
  p_route_poi_id uuid, p_user_poi_id uuid, p_rating int, p_poi_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id, p_poi_id) <> 1 then
    raise exception 'exactly one poi target required';
  end if;
  if p_rating < 1 or p_rating > 5 then
    delete from poi_ratings where user_id = auth.uid()
      and route_poi_id is not distinct from p_route_poi_id
      and user_poi_id  is not distinct from p_user_poi_id
      and poi_id       is not distinct from p_poi_id;
    return;
  end if;
  if p_route_poi_id is not null then
    insert into poi_ratings(user_id, route_poi_id, rating)
    values (auth.uid(), p_route_poi_id, p_rating)
    on conflict (user_id, route_poi_id) do update set rating = excluded.rating, updated_at = now();
  elsif p_user_poi_id is not null then
    insert into poi_ratings(user_id, user_poi_id, rating)
    values (auth.uid(), p_user_poi_id, p_rating)
    on conflict (user_id, user_poi_id) do update set rating = excluded.rating, updated_at = now();
  else
    insert into poi_ratings(user_id, poi_id, rating)
    values (auth.uid(), p_poi_id, p_rating)
    on conflict (user_id, poi_id) do update set rating = excluded.rating, updated_at = now();
  end if;
end;
$$;
grant execute on function public.rate_poi(uuid, uuid, int, uuid) to authenticated;

-- poi_rating_summary: přidán cíl p_poi_id (stará 2-arg verze se zahazuje)
drop function if exists public.poi_rating_summary(uuid, uuid);
create or replace function public.poi_rating_summary(
  p_route_poi_id uuid, p_user_poi_id uuid, p_poi_id uuid default null)
returns table(avg_rating numeric, rating_count int, my_rating int)
language sql stable security definer set search_path = public as $$
  select round(avg(r.rating)::numeric, 1),
         count(*)::int,
         max(case when r.user_id = auth.uid() then r.rating end)::int
  from poi_ratings r
  where r.route_poi_id is not distinct from p_route_poi_id
    and r.user_poi_id  is not distinct from p_user_poi_id
    and r.poi_id       is not distinct from p_poi_id;
$$;
grant execute on function public.poi_rating_summary(uuid, uuid, uuid) to anon, authenticated;

-- 4) RPC: katalog bodů zájmu pro appku -------------------------------
create or replace function public.get_pois_catalog()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.name, 'description', p.description,
    'lat', p.lat, 'lng', p.lng,
    'image_url', p.image_url, 'images', to_jsonb(p.images),
    'translations', p.translations, 'category', p.category,
    'country', p.country, 'is_catalog', true,
    'avg_rating',   (select round(avg(rating)::numeric,1) from poi_ratings r where r.poi_id = p.id),
    'rating_count', (select count(*) from poi_ratings r where r.poi_id = p.id)
  ) order by p.sort_order, p.name), '[]'::jsonb)
  from public.points_of_interest p
  where p.is_active = true;
$$;
grant execute on function public.get_pois_catalog() to anon, authenticated;
