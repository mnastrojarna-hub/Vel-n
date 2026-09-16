-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — RPC pro „Moje jízdy" (tabulky viz 20260916c_user_rides.sql).
-- Appka NIKDY nesahá na tabulky přímo — všechno jde přes tyto SECURITY
-- DEFINER funkce (ověření vlastníka + rezervace server-side).
--   start_user_ride / append_ride_track / finish_user_ride
--   create_manual_ride / update_user_ride / delete_user_ride
--   save_ride_point / delete_ride_point
--   get_my_rides / get_booking_rides / get_public_rides
-- Idempotentní (create or replace).
-- ════════════════════════════════════════════════════════════════════

-- Pomocná: délka stopy [[lat,lng],…] v km (haversine, bez PostGIS).
create or replace function public._ride_track_km(p_track jsonb)
returns numeric language plpgsql immutable as $$
declare
  v_prev_lat double precision; v_prev_lng double precision;
  v_lat double precision; v_lng double precision;
  v_sum double precision := 0; v_pt jsonb;
begin
  if jsonb_typeof(p_track) is distinct from 'array' then return 0; end if;
  for v_pt in select * from jsonb_array_elements(p_track) loop
    if jsonb_typeof(v_pt) <> 'array' or jsonb_array_length(v_pt) < 2 then continue; end if;
    v_lat := (v_pt->>0)::double precision;
    v_lng := (v_pt->>1)::double precision;
    if v_prev_lat is not null then
      v_sum := v_sum + 6371 * 2 * asin(sqrt(
        power(sin(radians(v_lat - v_prev_lat) / 2), 2) +
        cos(radians(v_prev_lat)) * cos(radians(v_lat)) *
        power(sin(radians(v_lng - v_prev_lng) / 2), 2)));
    end if;
    v_prev_lat := v_lat; v_prev_lng := v_lng;
  end loop;
  return round(v_sum::numeric, 1);
end;
$$;

-- Pomocná: prořídne stopu na max N bodů (každý k-tý), ať jsonb neroste bez konce.
create or replace function public._ride_track_cap(p_track jsonb, p_max int default 4000)
returns jsonb language sql immutable as $$
  select case
    when jsonb_typeof(p_track) is distinct from 'array'
      or jsonb_array_length(p_track) <= p_max then coalesce(p_track, '[]'::jsonb)
    else (
      select coalesce(jsonb_agg(t.pt order by t.ord), '[]'::jsonb)
      from (
        select pt, ord from jsonb_array_elements(p_track) with ordinality as e(pt, ord)
        where (ord - 1) % ceil(jsonb_array_length(p_track)::numeric / p_max)::int = 0
           or ord = jsonb_array_length(p_track)
      ) t
    )
  end;
$$;

-- Pomocná: jízda + její body jako jsonb (jeden tvar pro všechny čtecí RPC).
create or replace function public._ride_json(p_ride public.user_rides)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', p_ride.id, 'booking_id', p_ride.booking_id, 'moto_id', p_ride.moto_id,
    'moto_name', p_ride.moto_name, 'name', p_ride.name, 'description', p_ride.description,
    'source', p_ride.source, 'track', p_ride.track,
    'start_lat', p_ride.start_lat, 'start_lng', p_ride.start_lng,
    'end_lat', p_ride.end_lat, 'end_lng', p_ride.end_lng,
    'started_at', p_ride.started_at, 'ended_at', p_ride.ended_at,
    'distance_km', p_ride.distance_km, 'duration_min', p_ride.duration_min,
    'max_speed_kmh', p_ride.max_speed_kmh, 'is_recording', p_ride.is_recording,
    'visibility', p_ride.visibility, 'status', p_ride.status,
    'cover_image', p_ride.cover_image, 'created_at', p_ride.created_at,
    'points', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', pt.id, 'kind', pt.kind, 'name', pt.name, 'note', pt.note,
        'lat', pt.lat, 'lng', pt.lng, 'photos', to_jsonb(pt.photos),
        'route_poi_id', pt.route_poi_id, 'user_poi_id', pt.user_poi_id, 'poi_id', pt.poi_id,
        'happened_at', pt.happened_at, 'sort_order', pt.sort_order
      ) order by pt.sort_order, pt.created_at), '[]'::jsonb)
      from public.user_ride_points pt where pt.ride_id = p_ride.id)
  );
$$;

-- 1) START NAHRÁVÁNÍ ---------------------------------------------------
-- Rezervaci a motorku si funkce dohledá SAMA (klient nic nepodvrhne):
-- běžící výpůjčka volajícího (dnešek v rozsahu, status reserved/active).
create or replace function public.start_user_ride(
  p_booking_id uuid default null,
  p_lat double precision default null,
  p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_booking uuid; v_moto uuid; v_moto_name text; v_track jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  -- už něco běží → vrátíme to (idempotentní start po restartu appky)
  select id into v_id from user_rides where user_id = auth.uid() and is_recording limit 1;
  if v_id is not null then
    return jsonb_build_object('success', true, 'id', v_id, 'resumed', true);
  end if;

  select b.id, b.moto_id into v_booking, v_moto
  from bookings b
  where b.user_id = auth.uid()
    and (p_booking_id is null or b.id = p_booking_id)
    and b.status in ('reserved','active')
    and b.start_date::date <= current_date and b.end_date::date >= current_date
  order by b.start_date desc limit 1;

  if v_moto is not null then
    select nullif(trim(coalesce(m.brand,'') || ' ' || coalesce(m.model,'')), '')
      into v_moto_name from motorcycles m where m.id = v_moto;
  end if;

  if p_lat is not null and p_lng is not null then
    v_track := jsonb_build_array(jsonb_build_array(p_lat, p_lng));
  end if;

  insert into user_rides (user_id, booking_id, moto_id, moto_name, source,
                          track, start_lat, start_lng, is_recording)
  values (auth.uid(), v_booking, v_moto, v_moto_name, 'auto',
          v_track, p_lat, p_lng, true)
  returning id into v_id;

  return jsonb_build_object('success', true, 'id', v_id, 'resumed', false,
                            'booking_id', v_booking, 'moto_name', v_moto_name);
end;
$$;
grant execute on function public.start_user_ride(uuid, double precision, double precision) to authenticated;

-- 2) PŘIDÁNÍ GPS BODŮ --------------------------------------------------
create or replace function public.append_ride_track(
  p_ride_id uuid, p_points jsonb,
  p_max_speed_kmh numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_track jsonb; v_last jsonb; v_km numeric;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if jsonb_typeof(p_points) is distinct from 'array' then
    return jsonb_build_object('success', false, 'error', 'points_required');
  end if;

  select track into v_track from user_rides
   where id = p_ride_id and user_id = auth.uid() for update;
  if v_track is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  v_track := _ride_track_cap(v_track || p_points);
  v_km := _ride_track_km(v_track);
  if jsonb_array_length(v_track) > 0 then
    v_last := v_track -> (jsonb_array_length(v_track) - 1);
  end if;

  update user_rides set
    track = v_track,
    distance_km = v_km,
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    start_lat = coalesce(start_lat, (v_track->0->>0)::double precision),
    start_lng = coalesce(start_lng, (v_track->0->>1)::double precision),
    duration_min = greatest(0, (extract(epoch from (now() - started_at)) / 60)::int),
    max_speed_kmh = greatest(coalesce(max_speed_kmh, 0), coalesce(p_max_speed_kmh, 0))
  where id = p_ride_id and user_id = auth.uid();

  return jsonb_build_object('success', true, 'points', jsonb_array_length(v_track),
                            'distance_km', v_km);
end;
$$;
grant execute on function public.append_ride_track(uuid, jsonb, numeric) to authenticated;

-- 3) UKONČENÍ JÍZDY ----------------------------------------------------
-- Krátká jízda (< 1 km) se zahodí — ať se deník neplní parkováním.
-- Ze stopy se založí body „start" a „cíl" (zastávky si jezdec přidá sám).
create or replace function public.finish_user_ride(
  p_ride_id uuid, p_points jsonb default null, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_track jsonb; v_km numeric; v_last jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  select * into v_r from user_rides where id = p_ride_id and user_id = auth.uid() for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  v_track := v_r.track;
  if jsonb_typeof(p_points) = 'array' then v_track := _ride_track_cap(v_track || p_points); end if;
  v_km := _ride_track_km(v_track);

  if v_km < 1.0 then
    delete from user_rides where id = p_ride_id;
    return jsonb_build_object('success', true, 'discarded', true, 'distance_km', v_km);
  end if;

  v_last := v_track -> (jsonb_array_length(v_track) - 1);
  update user_rides set
    track = v_track, distance_km = v_km, is_recording = false, ended_at = now(),
    duration_min = greatest(1, (extract(epoch from (now() - started_at)) / 60)::int),
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    name = case when coalesce(trim(p_name), '') <> '' then left(trim(p_name), 120)
                when coalesce(trim(name), '') <> '' then name
                else to_char(started_at at time zone 'Europe/Prague', 'DD.MM.YYYY') end
  where id = p_ride_id;

  -- start / cíl jako body jízdy (jen když tam ještě nejsou)
  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'start', (v_track->0->>0)::double precision,
         (v_track->0->>1)::double precision, v_r.started_at, 0
  where jsonb_array_length(v_track) > 0 and (v_track->0->>0) is not null
    and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'start');

  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'end', (v_last->>0)::double precision,
         (v_last->>1)::double precision, now(), 9999
  where v_last is not null and (v_last->>0) is not null
    and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'end');

  return jsonb_build_object('success', true, 'discarded', false,
                            'id', p_ride_id, 'distance_km', v_km);
end;
$$;
grant execute on function public.finish_user_ride(uuid, jsonb, text) to authenticated;

-- 4) RUČNĚ VYTVOŘENÁ JÍZDA (start, cíl, zastávky) ----------------------
-- p_points = [{kind,name,note,lat,lng,photos[],sort_order}] — stopa se
-- složí ze souřadnic bodů (rovné spojnice; mapa v appce je dokreslí).
create or replace function public.create_manual_ride(
  p_name text, p_description text default null, p_points jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_track jsonb; v_km numeric;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if jsonb_typeof(p_points) is distinct from 'array' or jsonb_array_length(p_points) < 2 then
    return jsonb_build_object('success', false, 'error', 'points_required');
  end if;
  if (select count(*) from user_rides where user_id = auth.uid()) >= 500 then
    return jsonb_build_object('success', false, 'error', 'limit_reached');
  end if;

  select coalesce(jsonb_agg(jsonb_build_array((p->>'lat')::double precision,
                                              (p->>'lng')::double precision)
                  order by coalesce((p->>'sort_order')::int, 0)), '[]'::jsonb)
    into v_track
  from jsonb_array_elements(p_points) p
  where p->>'lat' is not null and p->>'lng' is not null;

  v_km := _ride_track_km(v_track);

  insert into user_rides (user_id, name, description, source, track,
                          start_lat, start_lng, end_lat, end_lng,
                          distance_km, is_recording, ended_at)
  values (auth.uid(), left(coalesce(trim(p_name), ''), 120),
          nullif(trim(coalesce(p_description, '')), ''), 'manual', v_track,
          (v_track->0->>0)::double precision, (v_track->0->>1)::double precision,
          (v_track->(jsonb_array_length(v_track)-1)->>0)::double precision,
          (v_track->(jsonb_array_length(v_track)-1)->>1)::double precision,
          v_km, false, now())
  returning id into v_id;

  insert into user_ride_points (ride_id, kind, name, note, lat, lng, photos, sort_order)
  select v_id,
         case when p->>'kind' in ('start','end','stop') then p->>'kind' else 'stop' end,
         left(coalesce(p->>'name', ''), 120), nullif(trim(coalesce(p->>'note','')), ''),
         (p->>'lat')::double precision, (p->>'lng')::double precision,
         coalesce((select array_agg(ph.photo) from jsonb_array_elements_text(
            case when jsonb_typeof(p->'photos') = 'array' then p->'photos' else '[]'::jsonb end
          ) as ph(photo)), '{}'),
         coalesce((p->>'sort_order')::int, 0)
  from jsonb_array_elements(p_points) p
  where p->>'lat' is not null and p->>'lng' is not null;

  return jsonb_build_object('success', true, 'id', v_id, 'distance_km', v_km);
end;
$$;
grant execute on function public.create_manual_ride(text, text, jsonb) to authenticated;

-- 5) ÚPRAVA JÍZDY (název, popis, sdílení, titulní fotka) ---------------
create or replace function public.update_user_ride(
  p_id uuid, p_name text default null, p_description text default null,
  p_visibility text default null, p_cover_image text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  update user_rides set
    name = case when p_name is null then name else left(trim(p_name), 120) end,
    description = case when p_description is null then description
                       else nullif(trim(p_description), '') end,
    visibility = case when p_visibility in ('private','public') then p_visibility else visibility end,
    cover_image = coalesce(p_cover_image, cover_image)
  where id = p_id and user_id = auth.uid();
  return jsonb_build_object('success', found);
end;
$$;
grant execute on function public.update_user_ride(uuid, text, text, text, text) to authenticated;

-- 6) SMAZÁNÍ JÍZDY -----------------------------------------------------
create or replace function public.delete_user_ride(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  delete from user_rides where id = p_id and user_id = auth.uid();
  return jsonb_build_object('success', found);
end;
$$;
grant execute on function public.delete_user_ride(uuid) to authenticated;

-- 7) ZASTÁVKA / BOD ZÁJMU NA JÍZDĚ (vložení i úprava) ------------------
create or replace function public.save_ride_point(
  p_ride_id uuid, p_id uuid default null, p_kind text default 'stop',
  p_name text default null, p_note text default null,
  p_lat double precision default null, p_lng double precision default null,
  p_photos text[] default null, p_sort_order int default null,
  p_happened_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_owned boolean;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  select true into v_owned from user_rides
   where id = p_ride_id and user_id = auth.uid();
  if v_owned is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;

  if p_id is not null then
    update user_ride_points set
      name = left(coalesce(p_name, name), 120),
      note = case when p_note is null then note else nullif(trim(p_note), '') end,
      lat = coalesce(p_lat, lat), lng = coalesce(p_lng, lng),
      photos = coalesce(p_photos, photos),
      sort_order = coalesce(p_sort_order, sort_order),
      happened_at = coalesce(p_happened_at, happened_at)
    where id = p_id and ride_id = p_ride_id
    returning id into v_id;
    if v_id is null then return jsonb_build_object('success', false, 'error', 'point_not_found'); end if;
    return jsonb_build_object('success', true, 'id', v_id);
  end if;

  if p_lat is null or p_lng is null then
    return jsonb_build_object('success', false, 'error', 'coords_required');
  end if;
  if (select count(*) from user_ride_points where ride_id = p_ride_id) >= 200 then
    return jsonb_build_object('success', false, 'error', 'limit_reached');
  end if;

  insert into user_ride_points (ride_id, kind, name, note, lat, lng, photos,
                                sort_order, happened_at)
  values (p_ride_id,
          case when p_kind in ('start','end','stop') then p_kind else 'stop' end,
          left(coalesce(p_name, ''), 120), nullif(trim(coalesce(p_note, '')), ''),
          p_lat, p_lng, coalesce(p_photos, '{}'),
          coalesce(p_sort_order, 100), coalesce(p_happened_at, now()))
  returning id into v_id;
  return jsonb_build_object('success', true, 'id', v_id);
end;
$$;
grant execute on function public.save_ride_point(uuid, uuid, text, text, text,
  double precision, double precision, text[], int, timestamptz) to authenticated;

-- 8) SMAZÁNÍ BODU ------------------------------------------------------
create or replace function public.delete_ride_point(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  delete from user_ride_points pt using user_rides r
   where pt.id = p_id and pt.ride_id = r.id and r.user_id = auth.uid();
  return jsonb_build_object('success', found);
end;
$$;
grant execute on function public.delete_ride_point(uuid) to authenticated;

-- 9) MOJE JÍZDY --------------------------------------------------------
create or replace function public.get_my_rides(p_limit int default 100)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(s.j order by s.started_at desc), '[]'::jsonb)
  from (select r.started_at, public._ride_json(r) as j
          from public.user_rides r
         where r.user_id = auth.uid()
         order by r.started_at desc
         limit least(greatest(coalesce(p_limit, 100), 1), 300)) s;
$$;
grant execute on function public.get_my_rides(int) to authenticated;

-- 10) JÍZDY K REZERVACI (historie výpůjčky) ---------------------------
create or replace function public.get_booking_rides(p_booking_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(s.j order by s.started_at desc), '[]'::jsonb)
  from (select r.started_at, public._ride_json(r) as j
          from public.user_rides r
         where r.booking_id = p_booking_id
           and (r.user_id = auth.uid() or public.is_admin())
         order by r.started_at desc) s;
$$;
grant execute on function public.get_booking_rides(uuid) to authenticated;

-- 11) VEŘEJNÉ JÍZDY (jen ty, které jezdec sám zveřejnil) --------------
-- Bez jakéhokoli údaje o autorovi — sdílí se zážitek, ne identita.
create or replace function public.get_public_rides(
  p_limit int default 50, p_offset int default 0)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(s.j order by s.started_at desc), '[]'::jsonb)
  from (select r.started_at,
               public._ride_json(r) - 'booking_id' - 'moto_id' as j
          from public.user_rides r
         where r.visibility = 'public' and r.status = 'approved'
         order by r.started_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 100)
        offset greatest(coalesce(p_offset, 0), 0)) s;
$$;
grant execute on function public.get_public_rides(int, int) to anon, authenticated;
