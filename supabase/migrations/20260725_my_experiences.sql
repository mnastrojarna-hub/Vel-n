-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje zážitky" v appce (záložka Trasy):
--   1) user_saved_routes    — vlastní uložené trasy JEN PRO SEBE (ne návrh
--                             ostatním; to zůstává přes routes.status='pending')
--   2) user_visited_places  — objevená místa: bod zájmu se při dojezdu
--                             navigací automaticky označí jako navštívený
-- RPC: save_user_route / delete_user_route / get_my_saved_routes /
--      mark_place_visited / get_my_places
-- Idempotentní. RLS: vlastník; admin read pro podporu.
-- ════════════════════════════════════════════════════════════════════

-- 1) MOJE TRASY --------------------------------------------------------
create table if not exists public.user_saved_routes (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  description     text,
  source_route_id uuid references public.routes(id) on delete set null,
  waypoints       jsonb not null default '[]'::jsonb, -- [{lat,lng,label,order}]
  poi_refs        jsonb not null default '[]'::jsonb, -- snapshot bodů [{id,kind,name,lat,lng,image_url}]
  profile         text not null default 'recommended'
                  check (profile in ('recommended','fastest','shortest')),
  distance_km     numeric(6,1),
  duration_min    int,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_user_saved_routes_user
  on public.user_saved_routes(user_id, created_at desc);

alter table public.user_saved_routes enable row level security;

drop policy if exists user_saved_routes_owner on public.user_saved_routes;
create policy user_saved_routes_owner on public.user_saved_routes
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists user_saved_routes_admin_read on public.user_saved_routes;
create policy user_saved_routes_admin_read on public.user_saved_routes
  for select to authenticated using (is_admin());

drop trigger if exists trg_user_saved_routes_updated on public.user_saved_routes;
create trigger trg_user_saved_routes_updated before update on public.user_saved_routes
  for each row execute function public.set_updated_at();

grant select, insert, update, delete on public.user_saved_routes to authenticated;

-- 2) MOJE (OBJEVENÁ) MÍSTA --------------------------------------------
-- Jeden řádek = jeden uživatel + jeden bod (route_poi NEBO user_poi NEBO
-- katalogový poi) — stejný trojcílový vzor jako poi_ratings.
create table if not exists public.user_visited_places (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  route_poi_id     uuid references public.route_pois(id) on delete cascade,
  user_poi_id      uuid references public.user_pois(id) on delete cascade,
  poi_id           uuid references public.points_of_interest(id) on delete cascade,
  name             text not null,          -- snapshot názvu (rychlý výpis bez joinů)
  lat              double precision,
  lng              double precision,
  route_id         uuid references public.routes(id) on delete set null, -- na jaké trase objeveno
  first_visited_at timestamptz not null default now(),
  last_visited_at  timestamptz not null default now(),
  visit_count      int not null default 1,
  constraint user_visited_one_target check (num_nonnulls(route_poi_id, user_poi_id, poi_id) = 1),
  constraint uvp_uniq_route_poi unique (user_id, route_poi_id),
  constraint uvp_uniq_user_poi  unique (user_id, user_poi_id),
  constraint uvp_uniq_poi       unique (user_id, poi_id)
);
create index if not exists idx_user_visited_places_user
  on public.user_visited_places(user_id, last_visited_at desc);

alter table public.user_visited_places enable row level security;

drop policy if exists user_visited_places_owner on public.user_visited_places;
create policy user_visited_places_owner on public.user_visited_places
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists user_visited_places_admin_read on public.user_visited_places;
create policy user_visited_places_admin_read on public.user_visited_places
  for select to authenticated using (is_admin());

grant select, insert, update, delete on public.user_visited_places to authenticated;

-- 3) RPC: ulož vlastní trasu ------------------------------------------
create or replace function public.save_user_route(
  p_name text, p_description text default null,
  p_source_route_id uuid default null,
  p_waypoints jsonb default '[]'::jsonb, p_poi_refs jsonb default '[]'::jsonb,
  p_profile text default 'recommended',
  p_distance_km numeric default null, p_duration_min int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('success', false, 'error', 'name_required'); end if;
  if jsonb_typeof(p_waypoints) is distinct from 'array'
     or jsonb_array_length(p_waypoints) < 1 then
    return jsonb_build_object('success', false, 'error', 'waypoints_required');
  end if;
  -- pojistka proti zahlcení (běžný jezdec jich má jednotky)
  if (select count(*) from user_saved_routes where user_id = auth.uid()) >= 200 then
    return jsonb_build_object('success', false, 'error', 'limit_reached');
  end if;
  insert into user_saved_routes
    (user_id, name, description, source_route_id, waypoints, poi_refs,
     profile, distance_km, duration_min)
  values
    (auth.uid(), left(trim(p_name), 120), nullif(trim(coalesce(p_description,'')), ''),
     p_source_route_id, p_waypoints, coalesce(p_poi_refs, '[]'::jsonb),
     case when p_profile in ('recommended','fastest','shortest') then p_profile else 'recommended' end,
     p_distance_km, p_duration_min)
  returning id into v_id;
  return jsonb_build_object('success', true, 'id', v_id);
end;
$$;
grant execute on function public.save_user_route(text, text, uuid, jsonb, jsonb, text, numeric, int) to authenticated;

-- 4) RPC: smaž vlastní trasu ------------------------------------------
create or replace function public.delete_user_route(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  delete from user_saved_routes where id = p_id and user_id = auth.uid();
  return jsonb_build_object('success', found);
end;
$$;
grant execute on function public.delete_user_route(uuid) to authenticated;

-- 5) RPC: moje uložené trasy ------------------------------------------
create or replace function public.get_my_saved_routes()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'name', s.name, 'description', s.description,
    'source_route_id', s.source_route_id,
    'waypoints', s.waypoints, 'poi_refs', s.poi_refs,
    'profile', s.profile, 'distance_km', s.distance_km,
    'duration_min', s.duration_min, 'created_at', s.created_at
  ) order by s.created_at desc), '[]'::jsonb)
  from public.user_saved_routes s
  where s.user_id = auth.uid();
$$;
grant execute on function public.get_my_saved_routes() to authenticated;

-- 6) RPC: označ místo jako objevené (dojezd navigací) -----------------
-- Název a souřadnice se dohledají server-side ze zdrojové tabulky (klient
-- posílá jen id cíle) → nejde podvrhnout cizí text. Opakovaný dojezd jen
-- zvedne visit_count a last_visited_at.
create or replace function public.mark_place_visited(
  p_route_poi_id uuid default null, p_user_poi_id uuid default null,
  p_poi_id uuid default null, p_route_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_name text; v_lat double precision; v_lng double precision;
  v_first boolean := false; v_count int; v_total int;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if num_nonnulls(p_route_poi_id, p_user_poi_id, p_poi_id) <> 1 then
    return jsonb_build_object('success', false, 'error', 'one_target_required');
  end if;

  if p_route_poi_id is not null then
    select p.name, p.lat, p.lng into v_name, v_lat, v_lng
      from route_pois p where p.id = p_route_poi_id;
  elsif p_user_poi_id is not null then
    select p.name, p.lat, p.lng into v_name, v_lat, v_lng
      from user_pois p where p.id = p_user_poi_id;
  else
    select p.name, p.lat, p.lng into v_name, v_lat, v_lng
      from points_of_interest p where p.id = p_poi_id;
  end if;
  if v_name is null then return jsonb_build_object('success', false, 'error', 'place_not_found'); end if;

  if p_route_poi_id is not null then
    insert into user_visited_places (user_id, route_poi_id, name, lat, lng, route_id)
    values (auth.uid(), p_route_poi_id, v_name, v_lat, v_lng, p_route_id)
    on conflict (user_id, route_poi_id) do update
      set last_visited_at = now(), visit_count = user_visited_places.visit_count + 1
    returning (visit_count = 1), visit_count into v_first, v_count;
  elsif p_user_poi_id is not null then
    insert into user_visited_places (user_id, user_poi_id, name, lat, lng, route_id)
    values (auth.uid(), p_user_poi_id, v_name, v_lat, v_lng, p_route_id)
    on conflict (user_id, user_poi_id) do update
      set last_visited_at = now(), visit_count = user_visited_places.visit_count + 1
    returning (visit_count = 1), visit_count into v_first, v_count;
  else
    insert into user_visited_places (user_id, poi_id, name, lat, lng, route_id)
    values (auth.uid(), p_poi_id, v_name, v_lat, v_lng, p_route_id)
    on conflict (user_id, poi_id) do update
      set last_visited_at = now(), visit_count = user_visited_places.visit_count + 1
    returning (visit_count = 1), visit_count into v_first, v_count;
  end if;

  select count(*) into v_total from user_visited_places where user_id = auth.uid();
  return jsonb_build_object('success', true, 'first_visit', v_first,
                            'visit_count', v_count, 'total_places', v_total);
end;
$$;
grant execute on function public.mark_place_visited(uuid, uuid, uuid, uuid) to authenticated;

-- 7) RPC: moje objevená místa (s fotkou ze zdrojového bodu) ------------
create or replace function public.get_my_places()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v.id,
    'route_poi_id', v.route_poi_id, 'user_poi_id', v.user_poi_id, 'poi_id', v.poi_id,
    'name', coalesce(rp.name, up.name, cp.name, v.name),
    'lat', coalesce(rp.lat, up.lat, cp.lat, v.lat),
    'lng', coalesce(rp.lng, up.lng, cp.lng, v.lng),
    'image_url', coalesce(rp.image_url, up.image_url, cp.image_url),
    'route_id', v.route_id, 'route_name', r.name,
    'first_visited_at', v.first_visited_at, 'last_visited_at', v.last_visited_at,
    'visit_count', v.visit_count
  ) order by v.last_visited_at desc), '[]'::jsonb)
  from public.user_visited_places v
  left join public.route_pois rp on rp.id = v.route_poi_id
  left join public.user_pois up on up.id = v.user_poi_id
  left join public.points_of_interest cp on cp.id = v.poi_id
  left join public.routes r on r.id = v.route_id
  where v.user_id = auth.uid();
$$;
grant execute on function public.get_my_places() to authenticated;
