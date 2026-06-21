-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — Fíčura TRASY (doporučené motorkářské trasy od poboček)
-- Aplikováno a ověřeno 2026-06-21.
-- Frontend: app lib/features/routes/*, Velín pages/Trasy(.Modal).jsx
-- ════════════════════════════════════════════════════════════════════

-- 1) TABULKY ----------------------------------------------------------
create table if not exists public.routes (
  id            uuid primary key default gen_random_uuid(),
  branch_id     uuid references public.branches(id) on delete cascade,
  name          text not null,
  description   text,
  route_type    text not null default 'loop' check (route_type in ('loop','poi')),
  distance_km   numeric(6,1),
  duration_min  integer,
  difficulty    text check (difficulty in ('easy','medium','hard')),
  waypoints     jsonb not null default '[]'::jsonb,   -- [{lat,lng,label,order}]
  geometry      jsonb,                                -- {coordinates:[[lng,lat],…]} (cache z Mapy.com)
  mapy_url      text,
  cover_image   text,
  images        text[] not null default '{}',
  image_alts    text[] not null default '{}',
  translations  jsonb not null default '{}'::jsonb,   -- {lang:{name,description}}
  is_active     boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table if not exists public.route_pois (
  id            uuid primary key default gen_random_uuid(),
  route_id      uuid not null references public.routes(id) on delete cascade,
  name          text not null,
  description   text,
  lat           double precision,
  lng           double precision,
  image_url     text,
  images        text[] not null default '{}',
  translations  jsonb not null default '{}'::jsonb,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 2) INDEXY -----------------------------------------------------------
create index if not exists idx_routes_branch     on public.routes(branch_id);
create index if not exists idx_routes_active      on public.routes(is_active);
create index if not exists idx_routes_sort        on public.routes(sort_order);
create index if not exists idx_route_pois_route   on public.route_pois(route_id);
create index if not exists idx_route_pois_sort    on public.route_pois(sort_order);

-- 3) updated_at TRIGGER ----------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_routes_updated on public.routes;
create trigger trg_routes_updated before update on public.routes
  for each row execute function public.set_updated_at();

drop trigger if exists trg_route_pois_updated on public.route_pois;
create trigger trg_route_pois_updated before update on public.route_pois
  for each row execute function public.set_updated_at();

-- 4) RLS --------------------------------------------------------------
alter table public.routes     enable row level security;
alter table public.route_pois enable row level security;

drop policy if exists routes_public_read on public.routes;
create policy routes_public_read on public.routes
  for select to anon, authenticated
  using (is_active = true or public.is_admin());

drop policy if exists routes_admin_all on public.routes;
create policy routes_admin_all on public.routes
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists route_pois_public_read on public.route_pois;
create policy route_pois_public_read on public.route_pois
  for select to anon, authenticated
  using (exists (
    select 1 from public.routes r
    where r.id = route_id and (r.is_active = true or public.is_admin())
  ));

drop policy if exists route_pois_admin_all on public.route_pois;
create policy route_pois_admin_all on public.route_pois
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- 5) RPC pro appku (jedno volání = trasy + body zájmu) ---------------
create or replace function public.get_branch_routes(p_branch_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(t order by t.sort_order, t.distance_km nulls last), '[]'::jsonb)
  from (
    select r.*,
      coalesce(
        (select jsonb_agg(p order by p.sort_order)
         from public.route_pois p where p.route_id = r.id),
        '[]'::jsonb
      ) as pois
    from public.routes r
    where r.is_active = true
      and (p_branch_id is null or r.branch_id = p_branch_id)
  ) t;
$$;

grant execute on function public.get_branch_routes(uuid) to anon, authenticated;
