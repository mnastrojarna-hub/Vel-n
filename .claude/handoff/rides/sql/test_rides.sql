-- ════════════════════════════════════════════════════════════════════
-- Scenario tests for the ride drafts 01–06 (LOCAL PG16 test cluster only).
-- Run via run_tests.sh: it applies the drafts twice, runs t_shim() (fake
-- clock: t_set(at, uid)), and injects 06_rides_backfill.sql at the line
-- "-- @@BACKFILL@@". Re-runnable: every run deletes its own test users' data.
-- Results: table t_rides.res; the script fails (exception) if any check fails.
-- Expected numbers come from SPEC.md §3.7 (vectors) and §16.1.
-- ════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop schema if exists t_rides cascade;
create schema t_rides;
create table t_rides.res (n serial primary key, name text, ok boolean, got text, exp text);
create function t_rides.chk(p_name text, p_ok boolean, p_got text default null, p_exp text default null)
returns void language sql as $$
  insert into t_rides.res (name, ok, got, exp) values (p_name, coalesce(p_ok, false), p_got, p_exp) $$;
create function t_rides.near(a numeric, b numeric, tol numeric) returns boolean language sql immutable as $$
  select a is not null and b is not null and abs(a - b) <= tol $$;
create function t_rides.line(p_lat0 float8, p_n int, p_dlat float8, p_t0 float8, p_dt float8, p_kmh float8)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_array(round((p_lat0 + i * p_dlat)::numeric, 7), 16.6,
                                              p_t0 + i * p_dt, p_kmh) order by i), '[]'::jsonb)
    from generate_series(0, p_n - 1) i $$;
create function t_rides.ep(p text) returns float8 language sql stable as $$
  select extract(epoch from (p::timestamp at time zone 'Europe/Prague'))::float8 $$;
create function t_rides.at(p_uid uuid, p_at float8) returns void language sql as $$
  select public.t_set(to_timestamp(p_at), p_uid) $$;
create function t_rides.ride(p_id uuid) returns public.user_rides language sql as $$
  select * from public.user_rides where id = p_id $$;
create function t_rides.u(n int) returns uuid language sql immutable as $$
  select ('aa000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
create function t_rides.bk(n int) returns uuid language sql immutable as $$
  select ('bb000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
-- Append a list of points in 4.1.3-style batches of 20, clock = last ts of the batch + 5 s.
create function t_rides.feed(p_uid uuid, p_ride uuid, p_pts jsonb) returns jsonb language plpgsql as $$
declare i int := 0; n int := jsonb_array_length(p_pts); b jsonb; r jsonb;
begin
  while i < n loop
    select jsonb_agg(e order by o) into b from jsonb_array_elements(p_pts) with ordinality x(e, o)
     where o > i and o <= i + 20;
    perform t_rides.at(p_uid, (b->(jsonb_array_length(b) - 1)->>2)::float8 + 5);
    r := public.append_ride_track(p_ride, b, null);
    if r->>'success' is distinct from 'true' then return r; end if;
    i := i + 20;
  end loop;
  return r;
end $$;
create function t_rides.booking(p_n int, p_uid uuid, p_start date, p_end date) returns uuid language plpgsql as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  insert into public.bookings (id, user_id, moto_id, start_date, end_date, status, picked_up_at)
  values (t_rides.bk(p_n), p_uid, 'e0000000-0000-0000-0000-00000000000e', p_start::timestamptz, p_end::timestamptz,
          'active', p_start::timestamptz);
  perform set_config('session_replication_role', 'origin', true);
  return t_rides.bk(p_n);
end $$;

-- Test users aa…01–aa…20 (data wiped on every run).
set session_replication_role = replica;
insert into auth.users (id, email, aud, role, created_at)
select t_rides.u(n), 'rides' || n || '@test.cz', 'authenticated', 'authenticated', now() from generate_series(1, 20) n
on conflict do nothing;
insert into public.profiles (id, full_name, email)
select t_rides.u(n), 'Rides Test ' || n, 'rides' || n || '@test.cz' from generate_series(1, 20) n
on conflict do nothing;
delete from public.user_rides where user_id in (select t_rides.u(n) from generate_series(1, 20) n);
delete from public.bookings where id in (select t_rides.bk(n) from generate_series(1, 20) n);
reset session_replication_role;

-- ───────────────────────── V: stats vectors (SPEC §3.7) ─────────────────────────
create table t_rides.vectors (ord int, id text, legacy boolean, points jsonb, got jsonb);
insert into t_rides.vectors (ord, id, legacy, points) values
 (1, 'V1', false, t_rides.line(49.2, 4, 0.001, 1792000000, 8, 50)),
 (2, 'V2', false, t_rides.line(49.2, 6, 0.0001, 1792000000, 10, 4)),
 (3, 'V3', false, t_rides.line(49.2, 6, 0.0005, 1792000000, 60, 0)),
 (4, 'V4', false, t_rides.line(49.2, 4, 0.001, 1792000000, 10, 0)),
 (5, 'V5', false, '[[49.2,16.6,1792000000,0],[49.2001,16.6,1792003600,-1]]'),
 (6, 'V6', false, '[[49.2,16.6,1792000000,30],[49.209,16.6,1792007200,30]]'),
 (7, 'V7', false, '[[49.2,16.6,1792000000,60],[49.22,16.6,1792000240,60]]'),
 (8, 'V8', false, '[[49.2,16.6,1792000000,0],[49.2005,16.6,1792000240,0]]'),
 (9, 'V9a', false, '[[49.2,16.6,1792000000,50],[49.200625,16.6,1792000005,50],[49.20125,16.6,1792000010,120]]'),
 (10, 'V9b', false, '[[49.2,16.6,1792000000,50],[49.200625,16.6,1792000005,50],[49.20125,16.6,1792000010,90]]'),
 (11, 'V10', false, '[[49.2,16.6,1792000000,60],[49.204,16.6,1792000005,60]]'),
 (12, 'V11', true, t_rides.line(49.2, 2, 0.001, 1792000000, 8, 50)
                   || t_rides.line(49.2016, 8, 0.0006, 1792000068, 60, 4)
                   || t_rides.line(49.2068, 2, 0.001, 1792000496, 8, 50)),
 (13, 'V12', false, t_rides.line(49.2, 31, 0.01, t_rides.ep('2026-10-14 21:00'), 60, 66)
                   || jsonb_build_array(jsonb_build_array(49.5001, 16.6, t_rides.ep('2026-10-15 07:00'), -1))
                   || t_rides.line(49.5101, 30, 0.01, t_rides.ep('2026-10-15 07:01'), 60, 66)),
 (14, 'V13', false, t_rides.line(49.2, 31, 0.01, t_rides.ep('2026-10-14 11:30'), 60, 66)
                   || jsonb_build_array(jsonb_build_array(49.5001, 16.6, t_rides.ep('2026-10-14 13:00'), -1))
                   || t_rides.line(49.5101, 30, 0.01, t_rides.ep('2026-10-14 13:01'), 60, 66)),
 (15, 'V14', false, (select jsonb_agg(jsonb_build_array(round((49.2 + i * 0.001)::numeric, 7), 16.6, 1792000000 + 8 * i, 50,
                                  case when i % 2 = 0 then 100 else 110 end) order by i) from generate_series(0, 30) i)),
 (16, 'V15', false, (select jsonb_agg(jsonb_build_array(round((49.2 + i * 0.001)::numeric, 7), 16.6, 1792000000 + 8 * i, 50, 2 * i)
                                  order by i) from generate_series(0, 30) i));
update t_rides.vectors set got = public._ride_stats_v2(points, jsonb_build_object('legacy', legacy), '[]'::jsonb);

do $$
declare g jsonb;
begin
  -- (id, dist, moving, gap, pause, max) — max null = not checked
  perform t_rides.chk(v.id || ' ' || v.k,
     case v.k when 'dist' then (g2->>'dist_km')::numeric = v.e
              when 'moving' then (g2->>'moving_sec')::numeric = v.e
              when 'gap' then (g2->>'gap_sec')::numeric = v.e
              when 'pause' then (g2->>'pause_sec')::numeric = v.e
              when 'max' then (g2->>'max_kmh')::numeric = v.e
              when 'gain' then abs((g2->>'gain_m')::numeric - v.e) <= 1
              when 'nodop' then (g2->>'nodop_max_kmh')::numeric = v.e end,
     g2::text, v.e::text)
  from (values ('V1','dist',0.334),('V1','moving',24),('V1','gap',0),('V1','pause',0),('V1','max',50.0),
               ('V2','dist',0),('V2','moving',0),
               ('V3','dist',0),('V3','moving',0),
               ('V4','dist',0.334),('V4','moving',30),('V4','max',0),('V4','nodop',0),
               ('V5','pause',3600),('V5','dist',0),
               ('V6','pause',7200),('V6','dist',0),('V6','gap',0),
               ('V7','gap',240),('V7','dist',0),('V7','pause',0),
               ('V8','dist',0),('V8','moving',0),('V8','gap',0),('V8','pause',0),
               ('V9a','moving',10),('V9a','max',50.0),('V9b','max',90.0),
               ('V10','dist',0),('V10','moving',0),('V10','gap',0),('V10','pause',0),
               ('V11','pause',420),('V11','moving',84),('V11','dist',0.400),
               ('V12','pause',34200),('V13','pause',3600),
               ('V14','gain',0),('V15','gain',54)) v(id, k, e)
  cross join lateral (select got as g2 from t_rides.vectors where id = v.id) x;
  select got into g from t_rides.vectors where id = 'V4';
  perform t_rides.chk('VV4 has_dop false', (g->'state'->>'has_dop')::boolean = false, g->>'state');
  select got into g from t_rides.vectors where id = 'V11';
  perform t_rides.chk('VV11 trims [[w1,w8]]', g->'trims' = '[[1792000068.0, 1792000488.0]]'::jsonb, g->>'trims');
  select got into g from t_rides.vectors where id = 'V12';
  perform t_rides.chk('VV12 2 stages', jsonb_array_length(g->'stages') = 2, g->>'stages');
  perform t_rides.chk('VV12 days 2', public._ride_stage_days(g->'stages') = 2, public._ride_stage_days(g->'stages')::text);
  perform t_rides.chk('VV12 stage mv 1800/1800', (g->'stages'->0->>'mv')::int = 1800 and (g->'stages'->1->>'mv')::int = 1800, g->>'stages');
  select got into g from t_rides.vectors where id = 'V13';
  perform t_rides.chk('VV13 1 stage, ps 3600', jsonb_array_length(g->'stages') = 1 and (g->'stages'->0->>'ps')::int = 3600, g->>'stages');
  perform t_rides.chk('VV13 days 1', public._ride_stage_days(g->'stages') = 1);
  perform t_rides.chk('VV prague night 23:00-01:00', public._ride_prague_night(t_rides.ep('2026-10-14 23:00'), t_rides.ep('2026-10-15 01:00')));
  perform t_rides.chk('VV prague night 03:00-04:00', public._ride_prague_night(t_rides.ep('2026-10-15 03:00'), t_rides.ep('2026-10-15 04:00')));
  perform t_rides.chk('VV prague no night 06:00-23:00', not public._ride_prague_night(t_rides.ep('2026-10-15 06:00'), t_rides.ep('2026-10-15 23:00')));
  -- stage cap: 61 boundaries (7 h breaks) → at most 60 stages
  g := public._ride_stats_v2((select jsonb_agg(p order by o) from (
          select o, jsonb_build_array(49.2 + o * 0.001, 16.6, 1792000000 + (o / 2) * 25200 + (o % 2) * 8,
                                      case when o % 2 = 0 and o > 0 then -1 else 50 end) p
            from generate_series(0, 123) o) z), '{"legacy": false}', '[]');
  perform t_rides.chk('VV stage cap 60', jsonb_array_length(g->'stages') = 60 and (g->>'pause_sec')::int = 61 * (25200 - 8),
        jsonb_array_length(g->'stages')::text || ' / ' || (g->>'pause_sec'));
  -- wrapper keeps the old keys
  g := public._ride_stats((select points from t_rides.vectors where id = 'V1'));
  perform t_rides.chk('VW _ride_stats keys unchanged',
    (select array_agg(k order by k) from jsonb_object_keys(g) k) = array['dist_km','gain_m','gap_sec','idle_sec','max_kmh','moving_sec'], g::text);
  perform t_rides.chk('VW _ride_stats V1 values', (g->>'dist_km')::numeric = 0.334 and (g->>'moving_sec')::int = 24 and (g->>'max_kmh')::numeric = 50, g::text);
end $$;

-- ───────────── A: own trip, new app (armed start, retry, pause marker, late Stop) ─────────────
do $$
declare u uuid := t_rides.u(1); e float8 := t_rides.ep('2026-10-14 08:00'); r jsonb; v_id uuid;
  x public.user_rides; pts jsonb; j jsonb;
begin
  perform t_rides.at(u, e);
  r := public.start_user_trip(null);
  perform t_rides.chk('A1 start_user_trip new', r->>'success' = 'true' and r->>'resumed' = 'false'
        and r->>'pause_aware' = 'true' and (r->>'stages_n')::int = 0, r::text);
  perform t_rides.chk('A1 now = server clock', abs((r->>'now')::float8 - e) < 1, r->>'now', e::text);
  v_id := (r->>'id')::uuid;
  perform t_rides.chk('A1 row pause_aware, no booking', (t_rides.ride(v_id)).pause_aware and (t_rides.ride(v_id)).booking_id is null);
  perform t_rides.at(u, e + 6);
  r := public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.3, 16.6, e + 5, 0)), null);
  perform t_rides.chk('A2 P0 accepted', r->>'success' = 'true' and (r->>'points')::int = 1 and (r->>'stages_n')::int = 1, r::text);
  perform t_rides.chk('A2 last_fix_at = P0', (t_rides.ride(v_id)).last_fix_at = to_timestamp(e + 5));
  -- first point after departure carries the pause marker → armed reset
  pts := jsonb_build_array(jsonb_build_array(49.3001, 16.6, e + 200, -1)) || t_rides.line(49.3006, 20, 0.0005, e + 205, 5, 40);
  perform t_rides.at(u, e + 300);
  r := public.append_ride_track(v_id, pts, 99);
  x := t_rides.ride(v_id);
  perform t_rides.chk('A3 armed reset: started_at = departure', x.started_at = to_timestamp(e + 200), x.started_at::text);
  perform t_rides.chk('A3 armed reset: P0 dropped, 21 pts', jsonb_array_length(x.track) = 21 and (x.track->0->>3)::numeric = -1, jsonb_array_length(x.track)::text);
  perform t_rides.chk('A3 km 1.112, moving 100, pause 0', x.distance_km = 1.112 and x.moving_sec = 100 and x.pause_sec = 0,
        format('%s %s %s', x.distance_km, x.moving_sec, x.pause_sec));
  perform t_rides.chk('A3 p_max_speed ignored, max = Doppler 40', x.max_speed_kmh = 40.0, x.max_speed_kmh::text);
  perform t_rides.chk('A3 start point = departure', x.start_lat = 49.3001, x.start_lat::text);
  -- same batch again (lost response) → nothing double counted
  perform t_rides.at(u, e + 310);
  r := public.append_ride_track(v_id, pts, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('A4 retry: dropped 21, stats unchanged', (r->>'dropped')::int = 21 and x.distance_km = 1.112
        and x.moving_sec = 100 and jsonb_array_length(x.track) = 21, r::text);
  perform t_rides.at(u, e + 420);
  r := public.append_ride_track(v_id, t_rides.line(49.3106, 20, 0.0005, e + 305, 5, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('A5 km 2.224 moving 200', t_rides.near(x.distance_km, 2.224, 0.001) and x.moving_sec = 200,
        format('%s %s', x.distance_km, x.moving_sec));
  -- 1 h break: first point after it flagged −1 at the same spot
  perform t_rides.at(u, e + 4060);
  r := public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.3201, 16.6, e + 4000, -1))
                                      || t_rides.line(49.3206, 10, 0.0005, e + 4005, 5, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('A6 marker → pause 3600', x.pause_sec = 3600 and (r->>'pause_sec')::int = 3600, r::text);
  perform t_rides.chk('A6 moving 250, idle 0 (remainder), gap 0', x.moving_sec = 250 and x.idle_sec = 0 and x.gap_sec = 0,
        format('%s %s %s', x.moving_sec, x.idle_sec, x.gap_sec));
  perform t_rides.chk('A6 duration_min = without pauses (4)', x.duration_min = 4, x.duration_min::text);
  perform t_rides.chk('A6 one stage, ps 3600', jsonb_array_length(x.stages) = 1 and (x.stages->0->>'ps')::int = 3600, x.stages::text);
  perform t_rides.chk('A6 response keys', r ?& array['success','points','distance_km','moving_sec','idle_sec','gap_sec','pause_sec','stages_n','dropped','now'], r::text);
  -- Stop pressed 2.5 h after arriving home
  perform t_rides.at(u, e + 4050 + 9000);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('A7 late Stop: ended_at = last fix + 120 s', x.ended_at = to_timestamp(e + 4170), x.ended_at::text);
  perform t_rides.chk('A7 finish values', r->>'success' = 'true' and r->>'discarded' = 'false' and (r->>'duration_min')::int = 6
        and (r->>'idle_sec')::int = 120 and (r->>'pause_sec')::int = 3600 and (r->>'days')::int = 1
        and (r->>'distance_km')::numeric = 2.8, r::text);
  perform t_rides.chk('A7 name = date', x.name = '14.10.2026', x.name);
  perform t_rides.chk('A7 start/end points', (select count(*) from public.user_ride_points where ride_id = v_id and kind in ('start','end')) = 2);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  perform t_rides.chk('A8 already_finished path', r->>'already_finished' = 'true' and r->>'success' = 'true'
        and (r->>'pause_sec')::int = 3600 and r ? 'distance_km', r::text);
  j := public.get_my_rides(10);
  perform t_rides.chk('A9 get_my_rides new keys', (j->0) ?& array['pause_sec','pause_aware','trip_id','trip_name','stages','duration_min','idle_sec','gap_sec'], (j->0)::text);
end $$;

-- ───────────── A2: 3-day own trip, cron at night → ONE ride, 3 stages ─────────────
do $$
declare u uuid := t_rides.u(2); e1 float8 := t_rides.ep('2026-10-14 09:00'); r jsonb; v_id uuid; x public.user_rides; d int;
  starts float8[] := array[t_rides.ep('2026-10-14 09:02'), t_rides.ep('2026-10-15 08:00'), t_rides.ep('2026-10-16 08:30')];
  lat float8 := 49.4;
begin
  perform t_rides.at(u, e1);
  v_id := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.at(u, e1 + 6);
  perform public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(lat, 16.6, e1 + 5, 0)), null);
  for d in 1..3 loop
    perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(lat + 0.0001, 16.6, starts[d], -1))
                                  || t_rides.line(lat + 0.0006, 120, 0.0005, starts[d] + 5, 5, 40));
    lat := lat + 0.0001 + 120 * 0.0005;
    if d < 3 then
      perform t_rides.at(u, starts[d] + 14 * 3600);  perform public.close_stale_user_rides();
      perform t_rides.at(u, starts[d] + 20 * 3600);  perform public.close_stale_user_rides();
    end if;
  end loop;
  x := t_rides.ride(v_id);
  perform t_rides.chk('A2 still one open ride after 2 nights + cron', x.is_recording
        and (select count(*) from public.user_rides where user_id = u) = 1);
  perform t_rides.chk('A2 3 stages', jsonb_array_length(x.stages) = 3, x.stages::text);
  perform t_rides.at(u, starts[3] + 3600);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('A2 finish: days 3', (r->>'days')::int = 3, r::text);
  perform t_rides.chk('A2 km = 3 × 120 pairs', t_rides.near(x.distance_km, 3 * 120 * 0.0555975, 0.005), x.distance_km::text);
  perform t_rides.chk('A2 nights are pauses (≥ 2 × 22 h)', x.pause_sec >= 2 * 22 * 3600 and x.idle_sec < 300,
        format('pause %s idle %s', x.pause_sec, x.idle_sec));
  perform t_rides.chk('A2 duration = elapsed − pauses', abs(x.duration_min * 60
        - (extract(epoch from x.ended_at - x.started_at) - x.pause_sec)) <= 60, format('%s min', x.duration_min));
  perform t_rides.chk('A2 name = date range', x.name = '14.10.–16.10.2026', x.name);
end $$;

-- ───────────── B: rental, points after the return close the ride at returned_at ─────────────
do $$
declare u uuid := t_rides.u(3); e float8 := t_rides.ep('2026-10-14 10:00'); b uuid; r jsonb; v_id uuid; x public.user_rides;
begin
  b := t_rides.booking(3, u, '2026-10-14', '2026-10-16');
  perform t_rides.at(u, e);
  r := public.start_user_trip(b);
  v_id := (r->>'id')::uuid;
  perform t_rides.chk('B1 rental ride', r->>'success' = 'true' and (r->>'booking_id')::uuid = b
        and r->>'moto_name' = 'Honda CB 500 X', r::text);
  perform t_rides.at(u, e + 220);
  perform public.append_ride_track(v_id, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40), null);
  perform t_rides.at(u, e + 270);
  perform public.append_ride_track(v_id, t_rides.line(49.42, 2, 0.0005, e + 250, 10, 40), null);
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(e + 255) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(u, e + 600);
  r := public.append_ride_track(v_id, t_rides.line(49.43, 2, 0.0005, e + 500, 10, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('B2 batch after return → ride_finished/booking_ended',
        r->>'error' = 'ride_finished' and r->>'finished' = 'true' and r->>'reason' = 'booking_ended', r::text);
  perform t_rides.chk('B2 closed at returned_at', not x.is_recording and x.ended_at = to_timestamp(e + 255), x.ended_at::text);
  perform t_rides.chk('B2 no car km (only bike points)', x.distance_km < 2.3, x.distance_km::text);
  r := public.append_ride_track(v_id, t_rides.line(49.44, 2, 0.0005, e + 700, 10, 40), null);
  perform t_rides.chk('B3 append to closed → ride_finished', r->>'error' = 'ride_finished' and not (r ? 'reason'), r::text);
  r := public.start_user_trip(b);
  perform t_rides.chk('B4 start_user_trip after return → booking_inactive, no row', r->>'error' = 'booking_inactive'
        and (select count(*) from public.user_rides where user_id = u) = 1, r::text);
end $$;

-- ───────────── B5: 4.1.3 rental — 2 min clock grace after the return, then close ─────────────
do $$
declare u uuid := t_rides.u(20); e float8 := t_rides.ep('2026-10-14 10:00'); b uuid; r jsonb; v_id uuid; x public.user_rides;
begin
  b := t_rides.booking(20, u, '2026-10-14', '2026-10-15');
  perform t_rides.at(u, e);
  v_id := (public.start_user_ride(b, 49.6, 16.6)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.line(49.6005, 20, 0.0005, e + 5, 5, 40));
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(e + 100) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(u, e + 400);
  r := public.append_ride_track(v_id, t_rides.line(49.611, 3, 0.0005, e + 160, 100, 20), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('B5 4.1.3: +60 s kept (clock grace), +160/+260 s dropped', r->>'success' = 'true'
        and (r->>'dropped')::int = 2 and x.is_recording and x.last_fix_at = to_timestamp(e + 160), r::text);
  perform t_rides.at(u, e + 600);
  r := public.append_ride_track(v_id, t_rides.line(49.62, 2, 0.0005, e + 500, 10, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('B5 4.1.3: all after return → ride_finished, closed at returned_at', r->>'error' = 'ride_finished'
        and not x.is_recording and x.ended_at = to_timestamp(e + 100), coalesce(x.ended_at::text, 'deleted'));
end $$;

-- ───────────── C: released app 4.1.3 (legacy) — walking becomes a pause, tail trimmed ─────────────
do $$
declare u uuid := t_rides.u(4); e float8 := t_rides.ep('2026-10-14 12:00'); r jsonb; v_id uuid; x public.user_rides; pts jsonb;
  errs text[] := '{}';
begin
  perform t_rides.at(u, e);
  r := public.start_user_ride(null, 49.5, 16.6);
  perform t_rides.chk('C1 4.1.3 start keys', r ?& array['success','id','resumed'] and r->>'resumed' = 'false', r::text);
  v_id := (r->>'id')::uuid;
  perform t_rides.chk('C1 legacy row', not (t_rides.ride(v_id)).pause_aware);
  pts := t_rides.line(49.5011, 20, 0.0011, e + 5, 5, 88)
      || t_rides.line(49.52218, 33, 0.00018, e + 118, 18, 4)
      || t_rides.line(49.52904, 20, 0.0011, e + 700, 5, 88);
  r := t_rides.feed(u, v_id, pts);
  x := t_rides.ride(v_id);
  perform t_rides.chk('C2 4.1.3 append keys', r ?& array['success','points','distance_km','moving_sec','idle_sec','gap_sec'], r::text);
  perform t_rides.chk('C2 walking excluded from km', t_rides.near(x.distance_km, 40 * 0.1223144 + 0.0200149, 0.003), x.distance_km::text);
  perform t_rides.chk('C2 walk → pause 576 s', x.pause_sec = 576, x.pause_sec::text);
  perform t_rides.chk('C2 moving 219', x.moving_sec = 219, x.moving_sec::text);
  perform t_rides.chk('C2 walk points trimmed (74 → 43)', jsonb_array_length(x.track) = 43, jsonb_array_length(x.track)::text);
  perform t_rides.chk('C2 max = Doppler 88 (floor: Ø 88.1 from distance)', x.max_speed_kmh between 88.0 and 88.1, x.max_speed_kmh::text);
  r := t_rides.feed(u, v_id, t_rides.line(49.55012, 24, 0.00018, e + 813, 18, 4));
  perform t_rides.at(u, e + 1300);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('C3 4.1.3 finish keys', r ?& array['success','discarded','distance_km'] and r->>'discarded' = 'false', r::text);
  perform t_rides.chk('C3 walking tail trimmed: ended at its start', x.ended_at = to_timestamp(e + 813)
        and jsonb_array_length(x.track) = 44, format('%s %s', x.ended_at, jsonb_array_length(x.track)));
  perform t_rides.chk('C3 duration 4 min, idle 0', x.duration_min = 4 and x.idle_sec = 0, format('%s %s', x.duration_min, x.idle_sec));
  -- only legacy error codes
  r := public.append_ride_track(v_id, t_rides.line(49.6, 2, 0.001, e + 2000, 5, 50), null); errs := errs || (r->>'error');
  r := public.append_ride_track(gen_random_uuid(), t_rides.line(49.6, 2, 0.001, e + 2000, 5, 50), null); errs := errs || (r->>'error');
  r := public.append_ride_track(v_id, '{"x":1}'::jsonb, null); errs := errs || (r->>'error');
  perform set_config('request.jwt.claim.sub', '', false);
  r := public.append_ride_track(v_id, '[]'::jsonb, null); errs := errs || (r->>'error');
  perform t_rides.chk('C4 append error codes = legacy set', errs = array['ride_finished','ride_not_found','points_required','not_authenticated'], errs::text);
  perform t_rides.at(u, e + 2000);
  r := public.finish_user_ride(gen_random_uuid(), '[]'::jsonb, null);
  perform t_rides.chk('C4 finish unknown → ride_not_found', r->>'error' = 'ride_not_found', r::text);
end $$;

-- ───────────── D: cron close_stale_user_rides (SPEC §16.1 table) ─────────────
do $$
declare e float8 := t_rides.ep('2026-10-14 14:00'); r jsonb;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; d6 uuid; d6b uuid; x public.user_rides; b uuid;
begin
  -- D1/D2 pause-aware own; D3 legacy own; D4 legacy rental active; D5 returned; D6 end_date −2 d; D6b −1 d
  perform t_rides.at(t_rides.u(5), e);  d1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(5), d1, t_rides.line(49.6, 30, 0.0005, e + 10, 5, 40));
  perform t_rides.at(t_rides.u(6), e);  d2 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(6), d2, t_rides.line(49.6, 30, 0.0005, e + 10, 5, 40));
  perform t_rides.at(t_rides.u(7), e);  d3 := (public.start_user_ride(null, 49.7, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(7), d3, t_rides.line(49.7005, 20, 0.0005, e + 5, 5, 40));
  b := t_rides.booking(8, t_rides.u(8), '2026-10-14', '2026-10-17');
  perform t_rides.at(t_rides.u(8), e);  d4 := (public.start_user_ride(b, 49.8, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(8), d4, t_rides.line(49.8005, 20, 0.0005, e + 5, 5, 40));
  b := t_rides.booking(9, t_rides.u(9), '2026-10-14', '2026-10-16');
  perform t_rides.at(t_rides.u(9), e);  d5 := (public.start_user_ride(b, 49.9, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(9), d5, t_rides.line(49.9005, 60, 0.0005, e + 5, 5, 40));
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(e + 200) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  b := t_rides.booking(10, t_rides.u(10), '2026-10-10', '2026-10-12');
  perform t_rides.at(t_rides.u(10), e); d6 := (public.start_user_ride(b, 50.0, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(10), d6, t_rides.line(50.0005, 20, 0.0005, e + 5, 5, 40));
  b := t_rides.booking(17, t_rides.u(17), '2026-10-10', '2026-10-13');
  perform t_rides.at(t_rides.u(17), e); d6b := (public.start_user_ride(b, 50.1, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(17), d6b, t_rides.line(50.1005, 20, 0.0005, e + 5, 5, 40));

  perform t_rides.at(null, e + 200 + 540);  perform public.close_stale_user_rides();
  perform t_rides.chk('D5 returned 9 min ago → still open', (t_rides.ride(d5)).is_recording);
  perform t_rides.chk('D6 end_date 2 days ago → closed', not (t_rides.ride(d6)).is_recording);
  perform t_rides.chk('D6b end_date yesterday → open', (t_rides.ride(d6b)).is_recording);
  perform t_rides.at(null, e + 200 + 660);  perform public.close_stale_user_rides();
  x := t_rides.ride(d5);
  perform t_rides.chk('D5 returned 11 min ago → closed at returned_at', not x.is_recording and x.ended_at = to_timestamp(e + 200), x.ended_at::text);
  perform t_rides.at(null, e + 110 + 10500); perform public.close_stale_user_rides();
  perform t_rides.chk('D3 legacy own 2 h 55 min → open', (t_rides.ride(d3)).is_recording);
  perform t_rides.at(null, e + 110 + 11100); perform public.close_stale_user_rides();
  perform t_rides.chk('D3 legacy own 3 h 05 min → closed (unchanged rule)', not (t_rides.ride(d3)).is_recording);
  perform t_rides.at(null, e + 10 * 3600);   perform public.close_stale_user_rides();
  perform t_rides.chk('D4 legacy rental silent 10 h → open', (t_rides.ride(d4)).is_recording);
  perform t_rides.at(null, e + 160 + 30 * 3600); perform public.close_stale_user_rides();
  perform t_rides.chk('D1 pause-aware own silent 30 h → open', (t_rides.ride(d1)).is_recording);
  perform t_rides.at(null, e + 40 * 3600);   perform public.close_stale_user_rides();
  perform t_rides.chk('D4 legacy rental 40 h (no 36 h split) → open', (t_rides.ride(d4)).is_recording);
  -- K: Velín live map of the standing rental (admin)
  perform t_rides.at('d0000000-0000-0000-0000-00000000000d', e + 40 * 3600);
  r := public.admin_booking_live_ride(t_rides.bk(8));
  perform t_rides.chk('K1 admin live: standing rental', r->>'ok' = 'true' and r->>'is_standing' = 'true'
        and r->>'is_live' = 'false' and r ? 'pause_aware' and r ? 'pause_sec', r::text);
  perform t_rides.at(t_rides.u(8), e + 40 * 3600);
  r := public.admin_booking_live_ride(t_rides.bk(8));
  perform t_rides.chk('K2 non-admin → forbidden', r->>'error' = 'forbidden', r::text);
  perform t_rides.at(null, e + 160 + 73 * 3600); perform public.close_stale_user_rides();
  x := t_rides.ride(d2);
  perform t_rides.chk('D2 pause-aware own silent 73 h → closed at last fix (≤ +2 min)', not x.is_recording
        and x.ended_at >= x.last_fix_at and x.ended_at <= x.last_fix_at + interval '120 seconds',
        format('%s / %s', x.ended_at, x.last_fix_at));
  perform t_rides.chk('D4 rental active day 4, end_date tomorrow-ish → still open', (t_rides.ride(d4)).is_recording
        or (now() at time zone 'Europe/Prague')::date - 1 > '2026-10-17'::date);
end $$;

-- ───────────── E: start_user_trip (adoption, 72 h rule) ─────────────
do $$
declare e float8 := t_rides.ep('2026-10-20 09:00'); r jsonb; b uuid; v_r uuid; v_r1 uuid; x public.user_rides;
begin
  perform t_rides.at(t_rides.u(12), e);
  r := public.start_user_trip(t_rides.bk(8));
  perform t_rides.chk('E1 foreign booking → booking_inactive, no row', r->>'error' = 'booking_inactive'
        and not exists (select 1 from public.user_rides where user_id = t_rides.u(12)), r::text);
  b := t_rides.booking(11, t_rides.u(11), '2026-10-20', '2026-10-23');
  perform t_rides.at(t_rides.u(11), e);
  v_r := (public.start_user_ride(b, 49.9, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(11), v_r, t_rides.line(49.9005, 20, 0.0005, e + 5, 5, 40)
                                       || t_rides.line(49.9105, 20, 0.0001, e + 120, 15, 3));
  perform t_rides.chk('E2 legacy ride has an open still-run', (t_rides.ride(v_r)).stats_state ? 'still_from'
        and (t_rides.ride(v_r)).stats_state->>'still_from' is not null);
  perform t_rides.at(t_rides.u(11), e + 3600);
  r := public.start_user_trip(b);
  x := t_rides.ride(v_r);
  perform t_rides.chk('E2 adoption of legacy rental ride', r->>'resumed' = 'true' and (r->>'id')::uuid = v_r
        and x.pause_aware and (x.stats_state->>'still_from') is null, r::text);
  perform t_rides.at(t_rides.u(12), e);
  v_r1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(12), v_r1, t_rides.line(49.95, 30, 0.0005, e + 5, 5, 40));
  perform t_rides.at(t_rides.u(12), e + 48 * 3600);
  r := public.start_user_trip(null);
  perform t_rides.chk('E3 own resume after 48 h', r->>'resumed' = 'true' and (r->>'id')::uuid = v_r1, r::text);
  perform t_rides.at(t_rides.u(12), e + 300 + 73 * 3600);
  r := public.start_user_trip(null);
  x := t_rides.ride(v_r1);
  perform t_rides.chk('E4 own after 73 h → old finalized, new created', r->>'resumed' = 'false' and (r->>'id')::uuid <> v_r1
        and not x.is_recording and x.ended_at <= x.last_fix_at + interval '120 seconds', r::text);
end $$;

-- ───────────── F: start_user_ride (4.1.3 never splits an active rental) ─────────────
do $$
declare e float8 := t_rides.ep('2026-10-21 08:00'); r jsonb; b uuid; v_r uuid;
begin
  b := t_rides.booking(13, t_rides.u(13), '2026-10-21', '2026-10-25');
  perform t_rides.at(t_rides.u(13), e);
  v_r := (public.start_user_ride(b, 50.0, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(13), v_r, t_rides.line(50.0005, 20, 0.0005, e + 5, 5, 40));
  perform t_rides.at(t_rides.u(13), e + 20 * 3600);
  r := public.start_user_ride(b, 50.0, 16.6);
  perform t_rides.chk('F1 4.1.3 rental open 20 h → resumed', r->>'resumed' = 'true' and (r->>'id')::uuid = v_r, r::text);
  r := public.start_user_ride(null, 50.0, 16.6);
  perform t_rides.chk('F1 manual start during rental → same ride', r->>'resumed' = 'true' and (r->>'id')::uuid = v_r, r::text);
  perform t_rides.at(t_rides.u(14), e);
  v_r := (public.start_user_ride(null, 50.1, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(14), v_r, t_rides.line(50.1005, 20, 0.0005, e + 5, 5, 40));
  perform t_rides.at(t_rides.u(14), e + 4 * 3600);
  r := public.start_user_ride(null, 50.1, 16.6);
  perform t_rides.chk('F2 legacy own 4 h → new ride (unchanged)', r->>'resumed' = 'false' and (r->>'id')::uuid <> v_r
        and not (t_rides.ride(v_r)).is_recording, r::text);
  perform t_rides.at(t_rides.u(15), e);
  v_r := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(15), v_r, t_rides.line(50.2, 20, 0.0005, e + 5, 5, 40));
  perform t_rides.at(t_rides.u(15), e + 48 * 3600);
  r := public.start_user_ride(null, 50.2, 16.6);
  perform t_rides.chk('F3 pause-aware own 48 h via start_user_ride → resumed', r->>'resumed' = 'true' and (r->>'id')::uuid = v_r, r::text);
end $$;

-- ───────────── G: set_user_rides_trip (merge / undo / split / foreign / bad) ─────────────
do $$
declare u uuid := t_rides.u(16); a uuid; b uuid; c uuid; f uuid; r jsonb; items jsonb; undo jsonb;
begin
  insert into public.user_rides (user_id, name, distance_km, started_at, ended_at, is_recording)
  values (u, 'a', 10, now() - interval '3 days', now() - interval '3 days' + interval '1 hour', false) returning id into a;
  insert into public.user_rides (user_id, name, distance_km, started_at, ended_at, is_recording)
  values (u, 'b', 10, now() - interval '2 days', now() - interval '2 days' + interval '1 hour', false) returning id into b;
  insert into public.user_rides (user_id, name, distance_km, started_at, ended_at, is_recording)
  values (u, 'c', 10, now() - interval '1 days', now() - interval '1 days' + interval '1 hour', false) returning id into c;
  insert into public.user_rides (user_id, name, distance_km, started_at, ended_at, is_recording)
  values (t_rides.u(18), 'foreign', 10, now(), now(), false) returning id into f;
  perform t_rides.at(u, extract(epoch from now()));
  undo := jsonb_build_array(jsonb_build_object('id', a, 'trip_id', null, 'trip_name', null),
                            jsonb_build_object('id', b, 'trip_id', null, 'trip_name', null),
                            jsonb_build_object('id', c, 'trip_id', null, 'trip_name', null));
  items := jsonb_build_array(jsonb_build_object('id', a, 'trip_id', a, 'trip_name', '  Alpy 2026  '),
                             jsonb_build_object('id', b, 'trip_id', a, 'trip_name', 'Alpy 2026'),
                             jsonb_build_object('id', c, 'trip_id', a, 'trip_name', 'Alpy 2026'));
  r := public.set_user_rides_trip(items);
  perform t_rides.chk('G1 merge 3', r->>'success' = 'true' and (r->>'updated')::int = 3
        and (select count(*) from public.user_rides where user_id = u and trip_id = a and trip_name = 'Alpy 2026') = 3, r::text);
  r := public.set_user_rides_trip(undo);
  perform t_rides.chk('G2 undo restores (null, null)', (r->>'updated')::int = 3
        and (select count(*) from public.user_rides where user_id = u and trip_id is null and trip_name is null) = 3, r::text);
  r := public.set_user_rides_trip(jsonb_build_array(jsonb_build_object('id', a, 'trip_id', a),
        jsonb_build_object('id', b, 'trip_id', b), jsonb_build_object('id', c, 'trip_id', c)));
  perform t_rides.chk('G3 split = own ids', (r->>'updated')::int = 3
        and (select count(*) from public.user_rides where user_id = u and trip_id = id) = 3, r::text);
  r := public.set_user_rides_trip(jsonb_build_array(jsonb_build_object('id', a, 'trip_id', a, 'trip_name', 'X'),
        jsonb_build_object('id', b, 'trip_id', a, 'trip_name', 'X'), jsonb_build_object('id', f, 'trip_id', a, 'trip_name', 'X')));
  perform t_rides.chk('G4 foreign id skipped (2 of 3)', (r->>'updated')::int = 2
        and (select trip_id from public.user_rides where id = f) is null, r::text);
  r := public.set_user_rides_trip(jsonb_build_array(jsonb_build_object('id', a, 'trip_id', a, 'trip_name', repeat('é', 200))));
  perform t_rides.chk('G5 name capped at 120', (select char_length(trip_name) from public.user_rides where id = a) = 120, r::text);
  perform t_rides.chk('G6 bad_items: object', public.set_user_rides_trip('{"id":"x"}')->>'error' = 'bad_items');
  perform t_rides.chk('G6 bad_items: empty', public.set_user_rides_trip('[]')->>'error' = 'bad_items');
  perform t_rides.chk('G6 bad_items: 301', public.set_user_rides_trip((select jsonb_agg(jsonb_build_object('id', a)) from generate_series(1, 301)))->>'error' = 'bad_items');
  perform t_rides.chk('G6 bad_items: invalid uuid', public.set_user_rides_trip('[{"id":"nope"}]')->>'error' = 'bad_items');
  perform t_rides.chk('G6 bad_items: trip_id number', public.set_user_rides_trip(jsonb_build_array(jsonb_build_object('id', a, 'trip_id', 5)))->>'error' = 'bad_items');
  perform t_rides.chk('G6 bad_items: trip_name number', public.set_user_rides_trip(jsonb_build_array(jsonb_build_object('id', a, 'trip_name', 5)))->>'error' = 'bad_items');
  perform set_config('request.jwt.claim.sub', '', false);
  perform t_rides.chk('G7 not_authenticated', public.set_user_rides_trip(undo)->>'error' = 'not_authenticated');
  perform t_rides.chk('G7 start_user_trip not_authenticated', public.start_user_trip(null)->>'error' = 'not_authenticated');
end $$;

-- ───────────── H: track cap (power-of-two spacing, edges, markers, speed) ─────────────
do $$
declare t jsonb := '[]'::jsonb; b jsonb; i int; k int; ms float8; best float8 := 1e9; c jsonb; t1 timestamptz;
  n_day int := 4286; day int; base float8 := 1792000000; cnts int[]; avgc float8; mk int; pred_ok boolean := true; r record;
begin
  -- H1 speed: 7 days × 1717 pts = 12 019 points, cap 12 000 → thinning runs
  select jsonb_agg(jsonb_build_array(round((49 + g * 0.0005)::numeric, 6), 16.6,
           base + g * 5 + (g / 1717) * 36000, case when g % 1717 = 0 and g > 0 then -1 else 40 end) order by g)
    into t from generate_series(0, 12018) g;
  for k in 1..9 loop
    t1 := clock_timestamp(); c := public._ride_track_cap(t, 12000);
    best := least(best, extract(epoch from clock_timestamp() - t1) * 1000);
  end loop;
  perform t_rides.chk('H1 cap 12 019 → ≤ 12 000', jsonb_array_length(c) <= 12000, jsonb_array_length(c)::text);
  perform t_rides.chk('H1 cap ≤ 50 ms at 12 000', best <= 50, round(best::numeric, 1)::text || ' ms');
  -- H2: 30 000 points in batches of 20, 7 days, marker on the first point of each day after a 10 h night
  t := '[]'::jsonb;
  for i in 0..1499 loop
    select jsonb_agg(jsonb_build_array(round((49 + g * 0.0005)::numeric, 6), round((16.6 + (g % 7) * 0.00001)::numeric, 6),
             base + g * 5 + (g / n_day) * 36000, case when g % n_day = 0 and g > 0 then -1 else 40 end, g) order by g)
      into b from generate_series(i * 20, i * 20 + 19) g;
    t := public._ride_track_cap(t || b, 12000);
  end loop;
  perform t_rides.chk('H2 30k → ≤ 12 000', jsonb_array_length(t) <= 12000, jsonb_array_length(t)::text);
  select count(*) into mk from jsonb_array_elements(t) e where (e->>3)::numeric < 0;
  perform t_rides.chk('H2 all 6 day markers kept', mk = 6, mk::text);
  for r in select o, e from jsonb_array_elements(t) with ordinality x(e, o) where (e->>3)::numeric < 0 loop
    if ((t->(r.o::int - 2))->>4)::int <> (r.e->>4)::int - 1 then pred_ok := false; end if;
  end loop;
  perform t_rides.chk('H2 marker predecessors (pause edges) kept', pred_ok);
  select array_agg(c2 order by d) into cnts from (
    select ((e->>4)::int / n_day) d, count(*)::int c2 from jsonb_array_elements(t) e group by 1) z where d between 0 and 4;
  select avg(x) into avgc from unnest(cnts) x;
  perform t_rides.chk('H2 older days evenly spaced (±25 %)',
    (select bool_and(abs(x - avgc) <= 0.25 * avgc) from unnest(cnts) x), cnts::text);
end $$;

-- ───────────── I: grants, signatures, overloads ─────────────
do $$
declare f text; n int;
begin
  select count(*) into n from (select proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and (proname like '%ride%' or proname like '%user_trip%') group by 1 having count(*) > 1) z;
  perform t_rides.chk('I1 no overloaded ride/trip function', n = 0, n::text);
  foreach f in array array['public.start_user_trip(uuid)', 'public.set_user_rides_trip(jsonb)',
      'public._ride_stats_v2(jsonb,jsonb,jsonb)', 'public._ride_append_core(uuid,jsonb)',
      'public._ride_prague_night(double precision,double precision)', 'public._ride_stage_days(jsonb)'] loop
    perform t_rides.chk('I2 anon cannot execute ' || f, not has_function_privilege('anon', f, 'execute'));
  end loop;
  foreach f in array array['public._ride_stats_v2(jsonb,jsonb,jsonb)', 'public._ride_append_core(uuid,jsonb)',
      'public._ride_prague_night(double precision,double precision)', 'public._ride_finalize(uuid,timestamp with time zone)',
      'public._ride_stage_days(jsonb)'] loop
    perform t_rides.chk('I3 authenticated cannot execute ' || f, not has_function_privilege('authenticated', f, 'execute'));
  end loop;
  foreach f in array array['public.start_user_trip(uuid)', 'public.set_user_rides_trip(jsonb)',
      'public.start_user_ride(uuid,double precision,double precision)', 'public.append_ride_track(uuid,jsonb,numeric)',
      'public.finish_user_ride(uuid,jsonb,text)', 'public.get_my_rides(integer)'] loop
    perform t_rides.chk('I4 authenticated can execute ' || f, has_function_privilege('authenticated', f, 'execute'));
  end loop;
  perform t_rides.chk('I6 feature flag ride_autopause', exists (select 1 from public.feature_flags where key = 'ride_autopause'
        and enabled and conditions->>'stop_min' = '5'));
end $$;

-- ───────────── L: backfill (06) of closed legacy rides ─────────────
do $$
declare u uuid := t_rides.u(19); e float8 := t_rides.ep('2026-09-10 08:00'); tr jsonb;
begin
  -- L1: day 1 → 10 h night without displacement (old: stání) → day 2
  tr := t_rides.line(49.0, 20, 0.001, e, 5, 60) || t_rides.line(49.02, 20, 0.001, e + 95 + 36000, 5, 60);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L1', tr, to_timestamp(e), to_timestamp(e + 36000 + 190), false, 4.3, 190, 36000, 0, 603);
  -- L2: old “gap” of 2 h with 5 km (v 2.5 km/h — e.g. carried) → pause, gap reduced
  tr := t_rides.line(49.1, 20, 0.001, e, 5, 60) || t_rides.line(49.165, 20, 0.001, e + 95 + 7200, 5, 60);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L2', tr, to_timestamp(e), to_timestamp(e + 7200 + 190), false, 4.3, 190, 0, 7200, 123);
  -- L3: a real gap (10 km in 10 min) stays a gap → no change
  tr := t_rides.line(49.2, 20, 0.001, e, 5, 60) || t_rides.line(49.31, 20, 0.001, e + 95 + 600, 5, 60);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L3', tr, to_timestamp(e), to_timestamp(e + 600 + 190), false, 4.3, 190, 0, 600, 13);
  -- L4 open legacy, L5 closed pause-aware → untouched
  insert into public.user_rides (user_id, name, track, started_at, is_recording, distance_km, moving_sec, idle_sec, duration_min)
  values (u, 'L4', t_rides.line(49.0, 20, 0.001, e, 5, 60) || t_rides.line(49.02, 20, 0.001, e + 95 + 36000, 5, 60),
          to_timestamp(e), true, 4.3, 190, 36000, 603);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, duration_min, pause_aware, stats_state)
  values (u, 'L5', t_rides.line(49.0, 20, 0.001, e, 5, 60) || t_rides.line(49.02, 20, 0.001, e + 95 + 36000, 5, 60),
          to_timestamp(e), to_timestamp(e + 36190), false, 4.3, 190, 36000, 603, true, '{}');
end $$;
-- @@BACKFILL@@
do $$
declare u uuid := t_rides.u(19); x public.user_rides;
begin
  select * into x from public.user_rides where user_id = u and name = 'L1';
  perform t_rides.chk('L1 night → pause 10 h, na cestě 3 min', x.pause_sec = 36000 and x.duration_min = 3
        and x.idle_sec = 0 and x.gap_sec = 0 and x.stats_state = '{"backfill": 1}'::jsonb and x.distance_km = 4.3,
        format('p %s d %s i %s g %s', x.pause_sec, x.duration_min, x.idle_sec, x.gap_sec));
  select * into x from public.user_rides where user_id = u and name = 'L2';
  perform t_rides.chk('L2 slow 2 h “gap” → pause, gap 0', x.pause_sec = 7200 and x.gap_sec = 0 and x.duration_min = 3,
        format('p %s g %s d %s', x.pause_sec, x.gap_sec, x.duration_min));
  select * into x from public.user_rides where user_id = u and name = 'L3';
  perform t_rides.chk('L3 real gap unchanged', x.pause_sec = 0 and x.gap_sec = 600 and x.duration_min = 13
        and x.stats_state = '{"backfill": 1}'::jsonb, format('p %s g %s d %s', x.pause_sec, x.gap_sec, x.duration_min));
  select * into x from public.user_rides where user_id = u and name = 'L4';
  perform t_rides.chk('L4 open ride untouched', x.stats_state is null and x.pause_sec = 0);
  select * into x from public.user_rides where user_id = u and name = 'L5';
  perform t_rides.chk('L5 pause-aware ride untouched', x.stats_state = '{}'::jsonb and x.pause_sec = 0);
end $$;

-- ───────────────────────────── summary ─────────────────────────────
select n, case when ok then 'ok  ' else 'FAIL' end as st, name, left(coalesce(got, ''), 160) as got, exp
  from t_rides.res order by n;
select 'SUMMARY ' || count(*) filter (where ok) || '/' || count(*) || ' passed' as summary from t_rides.res;
do $$ begin
  if exists (select 1 from t_rides.res where not ok) then
    raise exception 'RIDE TESTS FAILED: %', (select string_agg(name, ' | ' order by n) from t_rides.res where not ok);
  end if;
end $$;
