-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Komunitní obsah u TRAS: uživatelské návrhy tras (přes Mapy.com
-- URL), uživatelské body zájmu + hvězdičkové hodnocení bodů zájmu.
-- Návrhy od uživatelů jdou do moderace (status='pending'), admin ve Velíně
-- jen potvrdí (approved) / zamítne (rejected).
-- ════════════════════════════════════════════════════════════════════

-- 1) MODERACE TRAS ----------------------------------------------------
alter table public.routes
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists status text not null default 'approved'
      check (status in ('approved','pending','rejected')),
  add column if not exists submitted_note text;

create index if not exists idx_routes_status on public.routes(status);

-- Veřejně viditelné jen aktivní A schválené trasy (admin vidí vše).
drop policy if exists routes_public_read on public.routes;
create policy routes_public_read on public.routes
  for select to anon, authenticated
  using ((is_active = true and status = 'approved') or is_admin());

-- Přihlášený uživatel smí NAVRHNOUT trasu (pending, neaktivní, jako svoji).
drop policy if exists routes_user_submit on public.routes;
create policy routes_user_submit on public.routes
  for insert to authenticated
  with check (created_by = auth.uid() and status = 'pending' and is_active = false);

-- 2) UŽIVATELSKÉ BODY ZÁJMU -------------------------------------------
create table if not exists public.user_pois (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete set null,
  name        text not null,
  description text,
  lat         double precision not null,
  lng         double precision not null,
  image_url   text,
  status      text not null default 'pending'
              check (status in ('approved','pending','rejected')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_user_pois_status on public.user_pois(status);

alter table public.user_pois enable row level security;

drop policy if exists user_pois_public_read on public.user_pois;
create policy user_pois_public_read on public.user_pois
  for select to anon, authenticated
  using (status = 'approved' or user_id = auth.uid() or is_admin());

drop policy if exists user_pois_user_insert on public.user_pois;
create policy user_pois_user_insert on public.user_pois
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');

drop policy if exists user_pois_admin_all on public.user_pois;
create policy user_pois_admin_all on public.user_pois
  for all to authenticated using (is_admin()) with check (is_admin());

drop trigger if exists trg_user_pois_updated on public.user_pois;
create trigger trg_user_pois_updated before update on public.user_pois
  for each row execute function public.set_updated_at();

-- 3) HVĚZDIČKOVÉ HODNOCENÍ BODŮ ZÁJMU --------------------------------
-- Jeden záznam = jeden uživatel + jeden bod (route_poi NEBO user_poi).
create table if not exists public.poi_ratings (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  route_poi_id uuid references public.route_pois(id) on delete cascade,
  user_poi_id  uuid references public.user_pois(id) on delete cascade,
  rating       int not null check (rating between 1 and 5),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint poi_ratings_one_target check (num_nonnulls(route_poi_id, user_poi_id) = 1),
  constraint poi_ratings_uniq_route unique (user_id, route_poi_id),
  constraint poi_ratings_uniq_user  unique (user_id, user_poi_id)
);
create index if not exists idx_poi_ratings_route on public.poi_ratings(route_poi_id);
create index if not exists idx_poi_ratings_user_poi on public.poi_ratings(user_poi_id);

alter table public.poi_ratings enable row level security;

drop policy if exists poi_ratings_public_read on public.poi_ratings;
create policy poi_ratings_public_read on public.poi_ratings
  for select to anon, authenticated using (true);

drop policy if exists poi_ratings_owner_write on public.poi_ratings;
create policy poi_ratings_owner_write on public.poi_ratings
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists trg_poi_ratings_updated on public.poi_ratings;
create trigger trg_poi_ratings_updated before update on public.poi_ratings
  for each row execute function public.set_updated_at();

-- 4) RPC: ohodnoť bod (upsert, max 1 na uživatele; rating mimo 1–5 = zruš) ---
create or replace function public.rate_poi(
  p_route_poi_id uuid, p_user_poi_id uuid, p_rating int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'auth required'; end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id) <> 1 then
    raise exception 'exactly one poi target required';
  end if;
  if p_rating < 1 or p_rating > 5 then
    delete from poi_ratings where user_id = auth.uid()
      and route_poi_id is not distinct from p_route_poi_id
      and user_poi_id  is not distinct from p_user_poi_id;
    return;
  end if;
  if p_route_poi_id is not null then
    insert into poi_ratings(user_id, route_poi_id, rating)
    values (auth.uid(), p_route_poi_id, p_rating)
    on conflict (user_id, route_poi_id) do update set rating = excluded.rating, updated_at = now();
  else
    insert into poi_ratings(user_id, user_poi_id, rating)
    values (auth.uid(), p_user_poi_id, p_rating)
    on conflict (user_id, user_poi_id) do update set rating = excluded.rating, updated_at = now();
  end if;
end;
$$;
grant execute on function public.rate_poi(uuid, uuid, int) to authenticated;

-- 5) RPC: souhrn hodnocení bodu (průměr, počet, moje hodnocení) -------------
create or replace function public.poi_rating_summary(
  p_route_poi_id uuid, p_user_poi_id uuid)
returns table(avg_rating numeric, rating_count int, my_rating int)
language sql stable security definer set search_path = public as $$
  select round(avg(r.rating)::numeric, 1),
         count(*)::int,
         max(case when r.user_id = auth.uid() then r.rating end)::int
  from poi_ratings r
  where r.route_poi_id is not distinct from p_route_poi_id
    and r.user_poi_id  is not distinct from p_user_poi_id;
$$;
grant execute on function public.poi_rating_summary(uuid, uuid) to anon, authenticated;

-- 6) RPC: schválené uživatelské body zájmu (pro katalog v appce) -------------
create or replace function public.get_user_pois()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', u.id, 'name', u.name, 'description', u.description,
    'lat', u.lat, 'lng', u.lng, 'image_url', u.image_url,
    'avg_rating',   (select round(avg(rating)::numeric,1) from poi_ratings r where r.user_poi_id = u.id),
    'rating_count', (select count(*) from poi_ratings r where r.user_poi_id = u.id)
  ) order by u.created_at desc), '[]'::jsonb)
  from public.user_pois u where u.status = 'approved';
$$;
grant execute on function public.get_user_pois() to anon, authenticated;

-- 7) get_branch_routes: nezobrazuj nepotvrzené trasy + přidej hodnocení POI --
create or replace function public.get_branch_routes(p_branch_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(t order by t.sort_order, t.distance_km nulls last), '[]'::jsonb)
  from (
    select r.*,
      coalesce(
        (select jsonb_agg(
           to_jsonb(p) || jsonb_build_object(
             'avg_rating',   (select round(avg(rating)::numeric,1) from public.poi_ratings pr where pr.route_poi_id = p.id),
             'rating_count', (select count(*) from public.poi_ratings pr where pr.route_poi_id = p.id)
           ) order by p.sort_order)
         from public.route_pois p where p.route_id = r.id),
        '[]'::jsonb
      ) as pois
    from public.routes r
    where r.is_active = true and r.status = 'approved'
      and (p_branch_id is null or r.branch_id = p_branch_id)
  ) t;
$$;
grant execute on function public.get_branch_routes(uuid) to anon, authenticated;
