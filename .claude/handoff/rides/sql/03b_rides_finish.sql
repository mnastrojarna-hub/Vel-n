-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (4/7)
-- Uzavření jízdy a čtení. Podpisy i klíče odpovědí beze změny (4.1.3 OK).
--   finish_user_ride / _ride_finalize — konec nejvýš 2 min po posledním
--       bodu (pozdní Stop už nepřidá „stání"), duration_min = na cestě
--       BEZ pauz, zastávky = zbytek, název s rozsahem dat, uzavření
--       poslední etapy, odpověď navíc pause_sec a days; u staré appky se
--       rozběhnuté stání/chůze na konci (≥ 5 min) do jízdy nepočítá.
--   _ride_json — navíc pause_sec, pause_aware, trip_id, trip_name, stages.
-- Idempotentní (create or replace se stejnými podpisy → práva zůstávají).
-- ════════════════════════════════════════════════════════════════════

create or replace function public.finish_user_ride(p_ride_id uuid, p_points jsonb default null::jsonb, p_name text default null::text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r user_rides; v_end timestamptz := now(); v_ret timestamptz; v_res jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  select * into v_r from user_rides where id = p_ride_id and user_id = auth.uid() for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  if v_r.is_recording and jsonb_typeof(p_points) = 'array' and jsonb_array_length(p_points) > 0 then
    v_res := _ride_append_core(p_ride_id, p_points);
    if v_res ? 'booking_ended' then return v_res->'finalize'; end if;
  end if;
  if coalesce(trim(p_name), '') <> '' then
    update user_rides set name = left(trim(p_name), 120) where id = p_ride_id;
  end if;
  if not v_r.is_recording then return _ride_finalize(p_ride_id, null); end if;   -- already_finished
  -- Konec výpůjčky nesmí být později než vrácení motorky (start mohl posunout „připraveno").
  if v_r.booking_id is not null then
    select returned_at into v_ret from bookings where id = v_r.booking_id;
    if v_ret is not null and v_ret < v_end then
      select greatest(v_ret, started_at) into v_end from user_rides where id = p_ride_id;
    end if;
  end if;
  return _ride_finalize(p_ride_id, v_end);
end;
$$;

create or replace function public._ride_finalize(p_ride_id uuid, p_ended_at timestamptz default null::timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r user_rides; v_end timestamptz; v_track jsonb; v_sf float8; v_last jsonb; v_first jsonb;
  v_km numeric; v_move int; v_gap int; v_pause int; v_active float8; v_idle int; v_dur int; v_avg numeric;
  v_stages jsonb; v_n int; v_days int; v_name text; d1 date; d2 date;
begin
  select * into v_r from user_rides where id = p_ride_id for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  if not v_r.is_recording then                       -- uzavřená se nepřepočítává
    return jsonb_build_object('success', true, 'discarded', false, 'already_finished', true,
      'id', v_r.id, 'distance_km', round(coalesce(v_r.distance_km, 0), 1),
      'duration_min', v_r.duration_min, 'moving_sec', v_r.moving_sec,
      'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec, 'pause_sec', v_r.pause_sec);
  end if;

  v_end := coalesce(p_ended_at, v_r.last_fix_at, v_r.updated_at, now());
  -- Konec nejvýš 2 min po posledním bodu (pozdní Stop / úklid nepřidá stání).
  if v_r.last_fix_at is not null then v_end := least(v_end, v_r.last_fix_at + interval '120 seconds'); end if;
  v_track := case when jsonb_typeof(v_r.track) = 'array' then v_r.track else '[]'::jsonb end;
  -- Stará appka: rozběhnuté stání/chůze na konci (≥ 5 min) do jízdy nepatří.
  v_sf := (v_r.stats_state->>'still_from')::float8;
  if not v_r.pause_aware and v_sf is not null and extract(epoch from v_end) - v_sf >= 300 then
    v_end := to_timestamp(v_sf);
    select coalesce(jsonb_agg(e.pt order by e.ord), '[]'::jsonb) into v_track
      from jsonb_array_elements(v_track) with ordinality e(pt, ord)
     where case when jsonb_typeof(e.pt) <> 'array' then true
                when jsonb_array_length(e.pt) < 3 then true
                when not ((e.pt->>2) ~ '^[0-9]+(\.[0-9]+)?$') then true
                else (e.pt->>2)::float8 <= v_sf end;
  end if;
  if v_end < v_r.started_at then v_end := v_r.started_at; end if;

  v_km := coalesce(v_r.distance_km, 0);
  v_move := coalesce(v_r.moving_sec, 0); v_gap := coalesce(v_r.gap_sec, 0); v_pause := coalesce(v_r.pause_sec, 0);
  -- Stopa BEZ časových značek (prastarý klient) → km aspoň ze stopy (beze změny).
  if v_km = 0 and not exists (
       select 1 from jsonb_array_elements(v_track) e
        where case when jsonb_typeof(e) <> 'array' then false
                   when jsonb_array_length(e) < 3 then false
                   else (e->>2) ~ '^[0-9]+(\.[0-9]+)?$' end) then
    v_km := _ride_track_km(v_track);
  end if;
  -- Kratší než kilometr = parkování, deník se tím neplní (beze změny).
  if v_km < 1.0 then
    delete from user_rides where id = p_ride_id;
    return jsonb_build_object('success', true, 'discarded', true, 'distance_km', round(v_km, 1));
  end if;

  -- Na cestě = start → konec BEZ pauz; zastávky = zbytek po jízdě a mezerách.
  v_active := greatest(60, extract(epoch from (v_end - v_r.started_at)) - v_pause);
  v_idle := greatest(0, round(v_active - v_move - v_gap))::int;
  v_dur := greatest(1, round(v_active / 60))::int;
  v_avg := nullif(least(case when v_move >= 60 then round(v_km / (v_move::numeric / 3600), 1)
                             when v_active - v_gap > 0 then round(v_km / ((v_active - v_gap)::numeric / 3600), 1)
                        end, 200.1), 200.1);

  v_stages := case when jsonb_typeof(v_r.stages) = 'array' then v_r.stages else '[]'::jsonb end;
  v_n := jsonb_array_length(v_stages);
  if v_n > 0 and jsonb_typeof(v_stages->(v_n - 1)) = 'object' then
    v_stages := jsonb_set(v_stages, array[(v_n - 1)::text, 't'],
      to_jsonb(round(least((v_stages->(v_n - 1)->>'t')::numeric, extract(epoch from v_end)::numeric), 1)));
  end if;
  v_days := _ride_stage_days(v_stages);

  d1 := (v_r.started_at at time zone 'Europe/Prague')::date; d2 := (v_end at time zone 'Europe/Prague')::date;
  v_name := case when coalesce(trim(v_r.name), '') <> '' then v_r.name
                 when d1 = d2 then to_char(d1, 'DD.MM.YYYY')
                 when extract(year from d1) = extract(year from d2) then to_char(d1, 'DD.MM.') || '–' || to_char(d2, 'DD.MM.YYYY')
                 else to_char(d1, 'DD.MM.YYYY') || '–' || to_char(d2, 'DD.MM.YYYY') end;

  v_track := _ride_track_cap(v_track, least(12000, 4000 + 2000 * greatest(0, v_n - 1)));
  v_first := v_track -> 0;
  v_last := case when jsonb_array_length(v_track) > 0 then v_track -> (jsonb_array_length(v_track) - 1) end;

  update user_rides set
    is_recording = false, ended_at = v_end, track = v_track, stages = v_stages,
    distance_km = v_km, duration_min = v_dur, moving_sec = v_move, idle_sec = v_idle,
    avg_speed_kmh = v_avg,
    max_speed_kmh = nullif(greatest(coalesce(max_speed_kmh, 0), coalesce(v_avg, 0)), 0),
    end_lat = coalesce((v_last->>0)::double precision, end_lat),
    end_lng = coalesce((v_last->>1)::double precision, end_lng),
    name = v_name
  where id = p_ride_id;

  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'start', (v_first->>0)::double precision, (v_first->>1)::double precision, v_r.started_at, 0
   where v_first is not null and (v_first->>0) is not null
     and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'start');
  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'end', (v_last->>0)::double precision, (v_last->>1)::double precision, v_end, 9999
   where v_last is not null and (v_last->>0) is not null
     and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'end');

  return jsonb_build_object('success', true, 'discarded', false, 'id', p_ride_id,
    'distance_km', round(v_km, 1), 'duration_min', v_dur, 'moving_sec', v_move,
    'idle_sec', v_idle, 'gap_sec', v_gap, 'pause_sec', v_pause, 'days', v_days);
end;
$$;

create or replace function public._ride_json(p_ride public.user_rides)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', p_ride.id, 'booking_id', p_ride.booking_id, 'moto_id', p_ride.moto_id,
    'moto_name', p_ride.moto_name, 'name', p_ride.name, 'description', p_ride.description,
    'source', p_ride.source, 'track', p_ride.track,
    'start_lat', p_ride.start_lat, 'start_lng', p_ride.start_lng,
    'end_lat', p_ride.end_lat, 'end_lng', p_ride.end_lng,
    'started_at', p_ride.started_at, 'ended_at', p_ride.ended_at,
    'distance_km', round(p_ride.distance_km, 1),
    'duration_min', p_ride.duration_min,
    'moving_sec', p_ride.moving_sec, 'idle_sec', p_ride.idle_sec,
    'gap_sec', p_ride.gap_sec, 'last_fix_at', p_ride.last_fix_at,
    'pause_sec', p_ride.pause_sec, 'pause_aware', p_ride.pause_aware,
    'trip_id', p_ride.trip_id, 'trip_name', p_ride.trip_name, 'stages', p_ride.stages,
    'avg_speed_kmh', p_ride.avg_speed_kmh, 'max_speed_kmh', p_ride.max_speed_kmh,
    'elevation_gain_m', p_ride.elevation_gain_m,
    'is_recording', p_ride.is_recording,
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

revoke all on function public._ride_finalize(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public._ride_finalize(uuid, timestamptz) to service_role;

notify pgrst, 'reload schema';
