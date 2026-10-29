-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (4/8)
-- Uzavření jízdy a čtení. Podpisy i klíče odpovědí beze změny (4.1.3 OK).
--   _ride_close(id, konec, kdo, znovu) — NOVÉ interní jádro uzavření (bez
--       DEFAULT, žádné přetížení): konec nejvýš 2 min po posledním bodu
--       (pozdní Stop už nepřidá „stání"), duration_min = na cestě BEZ pauz,
--       zastávky = zbytek, název s rozsahem dat, uzavření poslední etapy;
--       u staré appky se rozběhnuté stání/chůze na konci (≥ 5 min) do jízdy
--       nepočítá. `kdo` → stats_state.closed_by (user | return | cron |
--       start; NULL = nezapisuje se; jízda bez stats_state ho nedostane).
--       `znovu` = přepočet UŽ uzavřené jízdy po pozdě doručených bodech
--       (výpůjčka offline v den vrácení): nic se nemaže, automatický název
--       i bod „cíl" se posunou s novým koncem. Existující bod „cíl" (přepočet,
--       cesta znovuotevřená úklidem — 03c) se posune vždy.
--   _ride_finalize — stejný podpis, = _ride_close(id, konec, NULL, false).
--   _ride_json — navíc pause_sec, pause_aware, trip_id, trip_name, stages.
--   get_public_rides — stejný podpis; jen UZAVŘENÉ jízdy (nahrávaná jízda
--       by prozradila živou polohu) a bez trip_id, last_fix_at,
--       pause_aware, is_recording (spojení jízd / stav nahrávání).
-- Idempotentní (create or replace; nové funkce bez přetížení).
-- ════════════════════════════════════════════════════════════════════

create or replace function public._ride_auto_name(p_from date, p_to date)
returns text language sql stable set search_path = public as $$
  select case when p_from is null then null
              when p_to is null or p_to <= p_from then to_char(p_from, 'DD.MM.YYYY')
              when extract(year from p_from) = extract(year from p_to)
                then to_char(p_from, 'DD.MM.') || '–' || to_char(p_to, 'DD.MM.YYYY')
              else to_char(p_from, 'DD.MM.YYYY') || '–' || to_char(p_to, 'DD.MM.YYYY') end
$$;

create or replace function public._ride_close(p_ride_id uuid, p_ended_at timestamptz, p_by text, p_reclose boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_r user_rides; v_end timestamptz; v_track jsonb; v_sf float8; v_last jsonb; v_first jsonb;
  v_km numeric; v_move int; v_gap int; v_pause int; v_active float8; v_idle int; v_dur int; v_avg numeric;
  v_stages jsonb; v_n int; v_days int; v_name text; d1 date; d2 date;
  v_fla float8; v_flo float8; v_lla float8; v_llo float8; v_re boolean := coalesce(p_reclose, false);
begin
  select * into v_r from user_rides where id = p_ride_id for update;
  if v_r.id is null then return jsonb_build_object('success', false, 'error', 'ride_not_found'); end if;
  if not v_r.is_recording and not v_re then          -- uzavřená se nepřepočítává
    return jsonb_build_object('success', true, 'discarded', false, 'already_finished', true,
      'id', v_r.id, 'distance_km', round(coalesce(v_r.distance_km, 0), 1),
      'duration_min', v_r.duration_min, 'moving_sec', v_r.moving_sec,
      'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec, 'pause_sec', v_r.pause_sec);
  end if;
  if v_r.is_recording and v_re then return jsonb_build_object('success', false, 'error', 'ride_open'); end if;

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
  -- (Přepočet uzavřené jízdy nemaže nikdy — km pozdními body jen přibývají.)
  if v_km < 1.0 and not v_re then
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
  v_name := case
    -- přepočet: automatický název (datum / rozsah dat) se posune s koncem, vlastní zůstane
    when v_re and v_r.ended_at is not null
         and v_r.name = _ride_auto_name(d1, (v_r.ended_at at time zone 'Europe/Prague')::date)
      then _ride_auto_name(d1, d2)
    when coalesce(trim(v_r.name), '') <> '' then v_r.name
    else _ride_auto_name(d1, d2) end;

  v_track := _ride_track_cap(v_track, least(12000, 4000 + 2000 * greatest(0, v_n - 1)));
  v_first := v_track -> 0;
  v_last := case when jsonb_array_length(v_track) > 0 then v_track -> (jsonb_array_length(v_track) - 1) end;
  v_fla := case when jsonb_typeof(v_first->0) = 'number' then (v_first->>0)::float8 end;
  v_flo := case when jsonb_typeof(v_first->1) = 'number' then (v_first->>1)::float8 end;
  v_lla := case when jsonb_typeof(v_last->0) = 'number' then (v_last->>0)::float8 end;
  v_llo := case when jsonb_typeof(v_last->1) = 'number' then (v_last->>1)::float8 end;

  update user_rides set
    is_recording = false, ended_at = v_end, track = v_track, stages = v_stages,
    distance_km = v_km, duration_min = v_dur, moving_sec = v_move, idle_sec = v_idle,
    avg_speed_kmh = v_avg,
    max_speed_kmh = nullif(greatest(coalesce(max_speed_kmh, 0), coalesce(v_avg, 0)), 0),
    end_lat = coalesce(v_lla, end_lat), end_lng = coalesce(v_llo, end_lng),
    name = v_name,
    -- closed_by jen u jízdy počítané novým výpočtem (stats_state NULL = staré
    -- statistiky před nasazením — Velín i přepočet 06 se podle toho řídí).
    stats_state = case when p_by is null or stats_state is null then stats_state
                       else stats_state || jsonb_build_object('closed_by', p_by) end
  where id = p_ride_id;

  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'start', v_fla, v_flo, v_r.started_at, 0
   where v_fla is not null and v_flo is not null
     and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'start');
  -- Bod „cíl" už existuje jen u přepočtu nebo u cesty znovuotevřené úklidem
  -- (03c _ride_reopen) → posune se na nový konec; poprvé se jen vloží.
  if v_lla is not null and v_llo is not null then
    update user_ride_points set lat = v_lla, lng = v_llo, happened_at = v_end
     where ride_id = p_ride_id and kind = 'end';
  end if;
  insert into user_ride_points (ride_id, kind, lat, lng, happened_at, sort_order)
  select p_ride_id, 'end', v_lla, v_llo, v_end, 9999
   where v_lla is not null and v_llo is not null
     and not exists (select 1 from user_ride_points where ride_id = p_ride_id and kind = 'end');

  return jsonb_build_object('success', true, 'discarded', false, 'id', p_ride_id,
    'distance_km', round(v_km, 1), 'duration_min', v_dur, 'moving_sec', v_move,
    'idle_sec', v_idle, 'gap_sec', v_gap, 'pause_sec', v_pause, 'days', v_days);
end;
$$;

create or replace function public._ride_finalize(p_ride_id uuid, p_ended_at timestamptz default null::timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  -- Dosavadní podpis (volá ho i živé admin_finish_user_ride) — bez značky closed_by.
  return _ride_close(p_ride_id, p_ended_at, null, false);
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

create or replace function public.get_public_rides(p_limit integer default 50, p_offset integer default 0)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(s.j order by s.started_at desc), '[]'::jsonb)
  from (select r.started_at,
               public._ride_json(r) - 'booking_id' - 'moto_id' - 'trip_id' - 'last_fix_at'
                 - 'pause_aware' - 'is_recording' as j
          from public.user_rides r
         where r.visibility = 'public' and r.status = 'approved' and not r.is_recording
         order by r.started_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 100)
        offset greatest(coalesce(p_offset, 0), 0)) s;
$$;

revoke all on function public._ride_auto_name(date, date) from public, anon, authenticated;
grant execute on function public._ride_auto_name(date, date) to service_role;
revoke all on function public._ride_close(uuid, timestamptz, text, boolean) from public, anon, authenticated;
grant execute on function public._ride_close(uuid, timestamptz, text, boolean) to service_role;
revoke all on function public._ride_finalize(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public._ride_finalize(uuid, timestamptz) to service_role;

notify pgrst, 'reload schema';
