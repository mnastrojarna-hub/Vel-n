-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy" (zážitkový deník jezdce, appka → Moje zážitky):
--   1) user_rides        — jedna projetá / vytvořená jízda. Vzniká AUTOMATICKY
--                          při aktivní výpůjčce, když má zákazník povolenou
--                          polohu (stopa GPS + motorka + rezervace), nebo
--                          ručně („nová trasa": start, cíl, zastávky).
--   2) user_ride_points  — body na jízdě (start / cíl / zastávka = bod zájmu)
--                          s fotkami a popiskem; zákazník je edituje i maže.
-- Soukromí: `visibility` default 'private' — jízda se NIKOMU nezobrazuje,
-- dokud ji jezdec sám nezveřejní (`public`); admin může skrýt (`status`).
-- Idempotentní. RLS: vlastník + admin; zveřejněné jízdy jen přes RPC.
-- RPC jsou v 20260916c_user_rides_rpc.sql.
-- ════════════════════════════════════════════════════════════════════

-- 1) JÍZDY -------------------------------------------------------------
create table if not exists public.user_rides (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  booking_id    uuid references public.bookings(id) on delete set null,
  moto_id       uuid references public.motorcycles(id) on delete set null,
  moto_name     text,                       -- snapshot („Honda CB 500 X")
  name          text not null default '',
  description   text,
  source        text not null default 'auto'
                check (source in ('auto','manual')),  -- auto = záznam GPS při výpůjčce
  track         jsonb not null default '[]'::jsonb,   -- [[lat,lng],…] zjednodušená stopa
  start_lat     double precision,
  start_lng     double precision,
  end_lat       double precision,
  end_lng       double precision,
  started_at    timestamptz not null default now(),
  ended_at      timestamptz,
  distance_km   numeric(7,1) not null default 0,
  duration_min  int,
  max_speed_kmh numeric(5,1),
  is_recording  boolean not null default false,       -- právě se nahrává
  visibility    text not null default 'private'
                check (visibility in ('private','public')),
  status        text not null default 'approved'
                check (status in ('approved','hidden')),  -- moderace Velínem
  cover_image   text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_user_rides_user
  on public.user_rides(user_id, started_at desc);
create index if not exists idx_user_rides_booking
  on public.user_rides(booking_id);
create index if not exists idx_user_rides_public
  on public.user_rides(started_at desc) where visibility = 'public' and status = 'approved';
-- Jen JEDNA rozjetá nahrávka na uživatele (chrání před duplicitami při
-- restartu appky / dvojím startu).
create unique index if not exists uq_user_rides_recording
  on public.user_rides(user_id) where is_recording;

alter table public.user_rides enable row level security;

drop policy if exists user_rides_owner on public.user_rides;
create policy user_rides_owner on public.user_rides
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Zveřejněné jízdy se ČTOU VÝHRADNĚ přes SECURITY DEFINER RPC
-- `get_public_rides` (bez údaje o autorovi) — přímé čtení tabulky proto
-- anonymní ani cizí přihlášený uživatel NEMÁ (jinak by z ní šlo vyčíst
-- `user_id` / `booking_id` a spárovat jízdu s konkrétním zákazníkem).
drop policy if exists user_rides_public_read on public.user_rides;

drop policy if exists user_rides_admin_all on public.user_rides;
create policy user_rides_admin_all on public.user_rides
  for all to authenticated using (is_admin()) with check (is_admin());

drop trigger if exists trg_user_rides_updated on public.user_rides;
create trigger trg_user_rides_updated before update on public.user_rides
  for each row execute function public.set_updated_at();

grant select, insert, update, delete on public.user_rides to authenticated;
revoke select on public.user_rides from anon;

-- 2) BODY NA JÍZDĚ -----------------------------------------------------
-- kind: start / end = krajní body stopy, stop = zastávka (bod zájmu jezdce).
-- Volitelný odkaz do katalogů bodů zájmu (když zastávka vznikla z POI).
create table if not exists public.user_ride_points (
  id           uuid primary key default gen_random_uuid(),
  ride_id      uuid not null references public.user_rides(id) on delete cascade,
  kind         text not null default 'stop' check (kind in ('start','end','stop')),
  name         text not null default '',
  note         text,
  lat          double precision not null,
  lng          double precision not null,
  photos       text[] not null default '{}',   -- bucket `media`, prefix rides/
  route_poi_id uuid references public.route_pois(id) on delete set null,
  user_poi_id  uuid references public.user_pois(id) on delete set null,
  poi_id       uuid references public.points_of_interest(id) on delete set null,
  happened_at  timestamptz,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_user_ride_points_ride
  on public.user_ride_points(ride_id, sort_order);

alter table public.user_ride_points enable row level security;

drop policy if exists user_ride_points_owner on public.user_ride_points;
create policy user_ride_points_owner on public.user_ride_points
  for all to authenticated
  using (exists (select 1 from public.user_rides r
                  where r.id = ride_id and r.user_id = auth.uid()))
  with check (exists (select 1 from public.user_rides r
                  where r.id = ride_id and r.user_id = auth.uid()));

-- Body zveřejněné jízdy chodí ven také jen přes `get_public_rides`.
drop policy if exists user_ride_points_public_read on public.user_ride_points;

drop policy if exists user_ride_points_admin_all on public.user_ride_points;
create policy user_ride_points_admin_all on public.user_ride_points
  for all to authenticated using (is_admin()) with check (is_admin());

drop trigger if exists trg_user_ride_points_updated on public.user_ride_points;
create trigger trg_user_ride_points_updated before update on public.user_ride_points
  for each row execute function public.set_updated_at();

grant select, insert, update, delete on public.user_ride_points to authenticated;
revoke select on public.user_ride_points from anon;

-- 3) STORAGE — fotky zastávek do bucketu `media`, prefix `rides/<uid>/…` ---
-- (čtení je public přes existující politiku bucketu `media`)
drop policy if exists media_ride_upload on storage.objects;
create policy media_ride_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = 'rides');

drop policy if exists media_ride_delete on storage.objects;
create policy media_ride_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = 'rides'
         and ((storage.foldername(name))[2] = auth.uid()::text or public.is_admin()));
