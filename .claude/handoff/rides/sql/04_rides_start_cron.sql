-- ════════════════════════════════════════════════════════════════════
-- MotoGo24 — „Moje jízdy": pauza, auto-pauza, vícedenní cesty (5/7)
-- Start, obnova a úklid nahrávek — cesta se už nedělí přes noc.
--   start_user_trip(p_booking_id) — NOVÉ RPC pro novou appku (bez DEFAULT,
--       žádné přetížení): založí/převezme jízdu s pause_aware = true;
--       výpůjčka jen převzatá a nevrácená (jinak booking_inactive, nic
--       nevznikne); bez párování podle data (ruční jízda ≠ výpůjčka);
--       vrací i serverový čas `now` (oprava hodin telefonu).
--   start_user_ride — stejný podpis/klíče; rozjetá jízda s AKTIVNÍ
--       výpůjčkou se obnoví v jakémkoli stáří (4.1.3 už výpůjčku nedělí),
--       vlastní jízda nové appky do 72 h, jinak dál 3 h (4.1.3 beze změny).
--   close_stale_user_rides — výpůjčka se uzavře až jejím koncem (vrácení,
--       zrušení, 2 dny po konci, 60 dní), k času vrácení; vlastní cesta
--       nové appky po 72 h bez jízdy / 30 dnech; stará appka 3 h / 36 h.
--   admin_booking_live_ride — + pause_aware, pause_sec, is_standing.
-- Idempotentní (create or replace; nové funkce bez přetížení).
-- ════════════════════════════════════════════════════════════════════

create or replace function public.start_user_trip(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_now timestamptz := now(); v_b bookings; v_o user_rides;
  v_last timestamptz; v_ret timestamptz; v_moto_name text; v_id uuid;
begin
  if v_uid is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;
  if p_booking_id is not null then
    select * into v_b from bookings where id = p_booking_id and user_id = v_uid;
    if v_b.id is null or v_b.status not in ('reserved', 'active') or v_b.returned_at is not null then
      return jsonb_build_object('success', false, 'error', 'booking_inactive',
                                'now', round(extract(epoch from v_now)::numeric, 3));
    end if;
  end if;

  select * into v_o from user_rides where user_id = v_uid and is_recording limit 1 for update;
  if v_o.id is not null then
    v_last := greatest(coalesce(v_o.last_fix_at, v_o.started_at), v_o.updated_at);
    if v_o.booking_id is not distinct from p_booking_id
       and (p_booking_id is not null or v_last > v_now - interval '72 hours') then
      -- Převzetí jízdy založené starou cestou: rozběhnuté stání se zahodí.
      -- (Už převzatou nepřepisujeme — updated_at se nesmí posunout, jinak
      -- by každé otevření appky oddálilo uzavření po 72 h bez jízdy.)
      if not v_o.pause_aware then
        update user_rides set pause_aware = true,
               stats_state = coalesce(stats_state, '{}'::jsonb) - 'still_from' - 'still_pt'
         where id = v_o.id returning * into v_o;
      end if;
      return jsonb_build_object('success', true, 'id', v_o.id, 'resumed', true,
        'booking_id', v_o.booking_id, 'moto_name', v_o.moto_name, 'pause_aware', true,
        'started_at', v_o.started_at, 'distance_km', round(coalesce(v_o.distance_km, 0), 1),
        'moving_sec', v_o.moving_sec, 'pause_sec', v_o.pause_sec,
        'stages_n', jsonb_array_length(coalesce(v_o.stages, '[]'::jsonb)),
        'now', round(extract(epoch from v_now)::numeric, 3));
    end if;
    if v_o.booking_id is not null then select returned_at into v_ret from bookings where id = v_o.booking_id; end if;
    perform _ride_finalize(v_o.id, case when v_ret is not null then least(v_last, v_ret) else v_last end);
  end if;

  if v_b.moto_id is not null then
    select nullif(trim(coalesce(m.brand, '') || ' ' || coalesce(m.model, '')), '')
      into v_moto_name from motorcycles m where m.id = v_b.moto_id;
  end if;
  begin
    insert into user_rides (user_id, booking_id, moto_id, moto_name, source, pause_aware,
                            track, stats_state, stages, is_recording)
    values (v_uid, p_booking_id, v_b.moto_id, v_moto_name, 'auto', true,
            '[]'::jsonb, '{}'::jsonb, '[]'::jsonb, true)
    returning id into v_id;
  exception when unique_violation then
    -- Souběžný start (dva požadavky naráz): vrátí se ta, která vznikla.
    update user_rides set pause_aware = true where user_id = v_uid and is_recording returning * into v_o;
    if v_o.id is null then raise; end if;
    return jsonb_build_object('success', true, 'id', v_o.id, 'resumed', true,
      'booking_id', v_o.booking_id, 'moto_name', v_o.moto_name, 'pause_aware', true,
      'started_at', v_o.started_at, 'distance_km', round(coalesce(v_o.distance_km, 0), 1),
      'moving_sec', v_o.moving_sec, 'pause_sec', v_o.pause_sec,
      'stages_n', jsonb_array_length(coalesce(v_o.stages, '[]'::jsonb)),
      'now', round(extract(epoch from v_now)::numeric, 3));
  end;
  return jsonb_build_object('success', true, 'id', v_id, 'resumed', false,
    'booking_id', p_booking_id, 'moto_name', v_moto_name, 'pause_aware', true,
    'started_at', (select started_at from user_rides where id = v_id),
    'distance_km', 0, 'moving_sec', 0, 'pause_sec', 0, 'stages_n', 0,
    'now', round(extract(epoch from v_now)::numeric, 3));
end;
$$;

create or replace function public.start_user_ride(p_booking_id uuid default null::uuid,
  p_lat double precision default null::double precision, p_lng double precision default null::double precision)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_booking uuid; v_moto uuid; v_moto_name text; v_track jsonb := '[]'::jsonb;
  v_stale timestamptz; v_obk uuid; v_paw boolean; v_bst text; v_bret timestamptz; v_resume boolean;
begin
  if auth.uid() is null then return jsonb_build_object('success', false, 'error', 'not_authenticated'); end if;

  -- Rozjetá nahrávka: výpůjčka s aktivní rezervací se obnoví v jakémkoli stáří
  -- (přes noc se nedělí), vlastní cesta nové appky do 72 h, jinak 3 h jako dřív.
  select id, booking_id, pause_aware, greatest(coalesce(last_fix_at, started_at), updated_at)
    into v_id, v_obk, v_paw, v_stale
    from user_rides where user_id = auth.uid() and is_recording limit 1;
  if v_id is not null then
    if v_obk is not null then select status, returned_at into v_bst, v_bret from bookings where id = v_obk; end if;
    v_resume := case
      when v_obk is not null and v_bst in ('reserved', 'active') and v_bret is null
           and (p_booking_id is null or p_booking_id = v_obk) then true
      when v_paw and v_obk is null then v_stale > now() - interval '72 hours'
      else v_stale > now() - interval '3 hours' end;
    if v_resume then
      return jsonb_build_object('success', true, 'id', v_id, 'resumed', true);
    end if;
    perform _ride_finalize(v_id, case when v_bret is not null then least(v_stale, v_bret) else v_stale end);
    v_id := null;
  end if;

  -- Beze změny: s id rezervace párování podle id, bez id podle dnešního dne.
  select b.id, b.moto_id into v_booking, v_moto
  from bookings b
  where b.user_id = auth.uid()
    and b.status in ('reserved','active')
    and (b.id = p_booking_id
         or (p_booking_id is null
             and b.start_date::date <= current_date and b.end_date::date >= current_date))
  order by b.start_date desc limit 1;

  if v_moto is not null then
    select nullif(trim(coalesce(m.brand,'') || ' ' || coalesce(m.model,'')), '')
      into v_moto_name from motorcycles m where m.id = v_moto;
  end if;

  if p_lat is not null and p_lng is not null then
    v_track := jsonb_build_array(jsonb_build_array(p_lat, p_lng, round(extract(epoch from now()))));
  end if;

  insert into user_rides (user_id, booking_id, moto_id, moto_name, source,
                          track, start_lat, start_lng, end_lat, end_lng,
                          is_recording, last_fix_at)
  values (auth.uid(), v_booking, v_moto, v_moto_name, 'auto',
          v_track, p_lat, p_lng, p_lat, p_lng, true,
          case when p_lat is not null then now() end)
  returning id into v_id;

  return jsonb_build_object('success', true, 'id', v_id, 'resumed', false,
                            'booking_id', v_booking, 'moto_name', v_moto_name);
end;
$$;

create or replace function public.close_stale_user_rides()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_at timestamptz; v_res jsonb; v_closed int := 0; v_dropped int := 0;
begin
  for v_id, v_at in
    select r.id,
           least(greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at),
                 coalesce(case when r.booking_id is not null then b.returned_at end, 'infinity'::timestamptz))
      from user_rides r
      left join bookings b on b.id = r.booking_id
     where r.is_recording
       and case
         -- Výpůjčka (jakákoli appka): jen konec výpůjčky, ne ticho přes noc.
         when r.booking_id is not null then
              b.id is null or b.status in ('completed', 'cancelled')
           or b.returned_at < now() - interval '10 minutes'
           or b.end_date::date < (now() at time zone 'Europe/Prague')::date - 1
           or r.started_at < now() - interval '60 days'
         -- Vlastní cesta nové appky (pauzuje sama): 72 h bez jízdy, max 30 dní.
         when r.pause_aware then
              greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at) < now() - interval '72 hours'
           or r.started_at < now() - interval '30 days'
         -- Stará appka (4.1.3): beze změny 3 h bez bodu / 36 h celkem.
         else greatest(coalesce(r.last_fix_at, r.started_at), r.updated_at) < now() - interval '3 hours'
           or r.started_at < now() - interval '36 hours'
       end
     order by r.started_at
     limit 500
  loop
    begin
      v_res := _ride_finalize(v_id, v_at);
      if v_res->>'discarded' = 'true' then v_dropped := v_dropped + 1;
      else v_closed := v_closed + 1; end if;
    exception when others then
      raise warning 'close_stale_user_rides: jízda % selhala: %', v_id, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('closed', v_closed, 'discarded', v_dropped);
end;
$$;

comment on function public.close_stale_user_rides() is
  'Uzavře nahrávky jízd: výpůjčka až koncem výpůjčky (vrácení/zrušení/2 dny po konci/60 dní, k času vrácení), vlastní cesta nové appky po 72 h bez jízdy nebo 30 dnech, stará appka po 3 h bez bodu nebo 36 h. Bez toho by uq_user_rides_recording zablokoval další jízdu.';

create or replace function public.admin_booking_live_ride(p_booking_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_r user_rides; v_b bookings; v_age int; v_track jsonb; v_app timestamptz;
begin
  if not is_admin() then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;

  select * into v_b from bookings where id = p_booking_id;
  if v_b.id is null then return jsonb_build_object('ok', false, 'error', 'booking_not_found'); end if;

  select * into v_r from user_rides
   where booking_id = p_booking_id
   order by is_recording desc, coalesce(last_fix_at, started_at) desc
   limit 1;

  select max(last_seen_at) into v_app from app_installations where user_id = v_b.user_id;

  if v_r.id is null then
    return jsonb_build_object(
      'ok', true, 'has_ride', false,
      'reason', case when v_app is null then 'no_app'
                     when v_app < now() - interval '14 days' then 'app_idle'
                     else 'no_location' end,
      'app_last_seen', v_app,
      'booking_status', v_b.status);
  end if;

  v_age := greatest(0, (extract(epoch from (now() - coalesce(v_r.last_fix_at, v_r.started_at))))::int);
  v_track := _ride_track_cap(coalesce(v_r.track, '[]'::jsonb), 1200);

  return jsonb_build_object(
    'ok', true, 'has_ride', true,
    'ride_id', v_r.id,
    'is_recording', v_r.is_recording,
    'is_live', v_r.is_recording and v_age < 900,
    -- Stojí: nahrávka běží, ale 15+ min bez bodu u probíhající výpůjčky
    -- (nová appka mezi zastávkami nic neposílá — poloha = kde zastavil).
    'is_standing', v_r.is_recording and v_age >= 900 and v_b.status in ('reserved', 'active')
                   and v_b.returned_at is null,
    'pause_aware', v_r.pause_aware, 'pause_sec', v_r.pause_sec,
    'lat', coalesce(v_r.end_lat, v_r.start_lat,
                    (v_track->(jsonb_array_length(v_track)-1)->>0)::double precision),
    'lng', coalesce(v_r.end_lng, v_r.start_lng,
                    (v_track->(jsonb_array_length(v_track)-1)->>1)::double precision),
    'last_fix_at', v_r.last_fix_at,
    'age_sec', v_age,
    'started_at', v_r.started_at, 'ended_at', v_r.ended_at,
    'distance_km', round(coalesce(v_r.distance_km, 0), 1),
    'duration_min', v_r.duration_min,
    'moving_sec', v_r.moving_sec, 'idle_sec', v_r.idle_sec, 'gap_sec', v_r.gap_sec,
    'avg_speed_kmh', v_r.avg_speed_kmh, 'max_speed_kmh', v_r.max_speed_kmh,
    'moto_name', v_r.moto_name, 'name', v_r.name,
    'points', jsonb_array_length(coalesce(v_r.track, '[]'::jsonb)),
    'track', v_track,
    'app_last_seen', v_app,
    'booking_status', v_b.status);
end;
$$;

revoke all on function public.start_user_trip(uuid) from public, anon;
grant execute on function public.start_user_trip(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
