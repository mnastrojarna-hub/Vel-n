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

-- Test users aa…01–aa…60 (data wiped on every run).
set session_replication_role = replica;
insert into auth.users (id, email, aud, role, created_at)
select t_rides.u(n), 'rides' || n || '@test.cz', 'authenticated', 'authenticated', now() from generate_series(1, 60) n
on conflict do nothing;
insert into public.profiles (id, full_name, email)
select t_rides.u(n), 'Rides Test ' || n, 'rides' || n || '@test.cz' from generate_series(1, 60) n
on conflict do nothing;
delete from public.user_rides where user_id in (select t_rides.u(n) from generate_series(1, 60) n);
-- (replica role: FK cascades do not fire → kiosk rows of the test bookings explicitly)
delete from public.booking_kiosk_returns where booking_id in (select t_rides.bk(n) from generate_series(1, 60) n);
delete from public.bookings where id in (select t_rides.bk(n) from generate_series(1, 60) n);
-- SOS replacement bookings of the SW block (bc…NN)
delete from public.bookings where id in (select ('bc000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid
                                           from generate_series(1, 60) n);
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
  perform t_rides.chk('B2 closed_by return', x.stats_state->>'closed_by' = 'return', x.stats_state::text);
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
  perform t_rides.chk('D5 closed_by cron', x.stats_state->>'closed_by' = 'cron', x.stats_state::text);
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
  perform t_rides.chk('E4 closed_by start', x.stats_state->>'closed_by' = 'start', x.stats_state::text);
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

-- ───────────── P: clock glitches (4.1.3 point from the future, year > 2100) ─────────────
do $$
declare u uuid := t_rides.u(21); e float8 := t_rides.ep('2026-10-22 08:00'); r jsonb; v_id uuid; x public.user_rides;
  km0 numeric; pts jsonb;
begin
  perform t_rides.at(u, e);
  v_id := (public.start_user_ride(null, 49.5, 16.7)->>'id')::uuid;            -- 4.1.3 own ride
  perform t_rides.feed(u, v_id, t_rides.line(49.5005, 40, 0.0005, e + 5, 5, 40));
  km0 := (t_rides.ride(v_id)).distance_km;
  perform t_rides.at(u, e + 210);
  r := public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.5205, 16.6, e + 205 + 31536000, 40)), null);
  perform t_rides.chk('P1 point +1 year stored (as live)', r->>'success' = 'true' and (r->>'dropped')::int = 0, r::text);
  perform t_rides.chk('P1 last_fix_at not in the future', (t_rides.ride(v_id)).last_fix_at <= to_timestamp(e + 210),
        (t_rides.ride(v_id)).last_fix_at::text);
  pts := t_rides.line(49.521, 101, 0.0005, e + 210, 5, 40);
  perform t_rides.at(u, e + 720);
  r := public.append_ride_track(v_id, pts, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('P2 next 101 points NOT dropped as duplicates', r->>'success' = 'true' and (r->>'dropped')::int = 0
        and x.distance_km > km0 + 5 and x.last_fix_at = to_timestamp(e + 710), r::text);
  r := public.append_ride_track(v_id, pts, null);
  perform t_rides.chk('P3 retry of the same batch is still a duplicate', (r->>'dropped')::int = 101
        and (t_rides.ride(v_id)).distance_km = x.distance_km, r::text);
  perform t_rides.at(u, e + 800);
  r := public.append_ride_track(v_id, '[[49.6, 16.6, 99999999999999999999, 40], [49.6, 16.6, 4102444801, 40]]'::jsonb
        || t_rides.line(49.5717, 2, 0.0005, e + 715, 5, 40), null);
  perform t_rides.chk('P4 ts beyond 2100 = bad point (no out-of-range error)', r->>'success' = 'true'
        and (r->>'dropped')::int = 2 and (t_rides.ride(v_id)).last_fix_at = to_timestamp(e + 720), r::text);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('P5 finish: ends at the last real point', r->>'success' = 'true' and x.ended_at <= to_timestamp(e + 840)
        and x.ended_at >= to_timestamp(e + 720) and x.distance_km > 7, coalesce(x.ended_at::text, 'deleted') || ' ' || r::text);
end $$;

-- ───────────── R: armed reset never wipes a real (sparse) first leg ─────────────
do $$
declare u uuid := t_rides.u(22); e float8 := t_rides.ep('2026-10-22 08:00'); r jsonb; v_id uuid; x public.user_rides; t2 float8;
begin
  perform t_rides.at(u, e);
  v_id := (public.start_user_trip(null)->>'id')::uuid;
  -- throttled background GPS: 21 fixes 4 min / 4 km apart (60 km/h) → only gaps, 0 km
  perform t_rides.at(u, e + 60 + 20 * 240 + 5);
  perform public.append_ride_track(v_id, t_rides.line(49.0, 21, 0.036, e + 60, 240, 60), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('R1 sparse first leg = gap, 0 km (setup)', x.gap_sec >= 4700 and x.distance_km = 0
        and jsonb_array_length(x.track) = 21, format('gap %s km %s', x.gap_sec, x.distance_km));
  t2 := e + 60 + 20 * 240 + 600;
  perform t_rides.at(u, t2 + 120);
  r := public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.7201, 16.6, t2, -1))
                                      || t_rides.line(49.7206, 20, 0.0005, t2 + 5, 5, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('R2 first pause marker after a real leg: no reset', x.started_at = to_timestamp(e)
        and jsonb_array_length(x.track) = 42 and x.gap_sec >= 4700 and x.pause_sec >= 500,
        format('start %s pts %s gap %s pause %s', x.started_at, jsonb_array_length(x.track), x.gap_sec, x.pause_sec));
end $$;

-- ───────────── S: offline on the return day → late points still land in the rental ride ─────────────
do $$
declare u uuid := t_rides.u(23); e1 float8 := t_rides.ep('2026-10-24 09:00'); d2 float8 := t_rides.ep('2026-10-25 08:00');
  b uuid; r jsonb; v_id uuid; x public.user_rides; late jsonb; km1 numeric; end1 timestamptz; ep record;
begin
  b := t_rides.booking(23, u, '2026-10-24', '2026-10-25');
  perform t_rides.at(u, e1);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.at(u, e1 + 6);
  perform public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.6, 16.8, e1 + 5, 0)), null);
  perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(49.6001, 16.8, e1 + 200, -1))
                                || t_rides.line(49.6006, 60, 0.0005, e1 + 205, 5, 40));
  x := t_rides.ride(v_id); km1 := x.distance_km;
  -- day 2 offline: points stay in the phone; kiosk return d2 + 20 min; cron 11 min later
  late := jsonb_build_array(jsonb_build_array(49.6302, 16.8, d2, -1)) || t_rides.line(49.6307, 120, 0.0005, d2 + 5, 5, 40);
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(d2 + 1200) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(null, d2 + 1200 + 660);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id); end1 := x.ended_at;
  perform t_rides.chk('S1 cron closed the silent rental (closed_by cron, day 1 only)', not x.is_recording
        and x.stats_state->>'closed_by' = 'cron' and x.name = '24.10.2026' and x.distance_km = km1,
        format('%s %s %s', x.stats_state->>'closed_by', x.name, x.ended_at));
  -- back online 2 h after the return: whole buffer (+ 2 car points after the return) in one append
  perform t_rides.at(u, d2 + 1200 + 7200);
  r := public.append_ride_track(v_id, late || t_rides.line(49.70, 2, 0.0005, d2 + 1300, 10, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('S2 answer stays ride_finished (+ reason booking_ended)', r->>'error' = 'ride_finished'
        and r->>'finished' = 'true' and r->>'reason' = 'booking_ended' and r->>'success' = 'false', r::text);
  perform t_rides.chk('S2 day 2 kept, car points not', not x.is_recording and t_rides.near(x.distance_km, km1 + 119 * 0.0555975, 0.02),
        format('km %s (day 1 %s)', x.distance_km, km1));
  perform t_rides.chk('S2 re-closed: end = last point + 2 min (≤ return), name 2 days, 2 stages',
        x.ended_at = to_timestamp(d2 + 600 + 120) and x.name = '24.10.–25.10.2026' and jsonb_array_length(x.stages) = 2
        and x.pause_sec > 12 * 3600 and x.stats_state->>'closed_by' = 'cron',
        format('%s %s %s %s', x.ended_at, x.name, jsonb_array_length(x.stages), x.pause_sec));
  select lat, happened_at into ep from public.user_ride_points where ride_id = v_id and kind = 'end';
  perform t_rides.chk('S2 end point moved to the return day', ep.happened_at = to_timestamp(d2 + 720)
        and t_rides.near(ep.lat::numeric, 49.6307 + 119 * 0.0005, 0.00001), ep::text);
  perform t_rides.chk('S2 duration = on the way without pauses', abs(x.duration_min * 60
        - (extract(epoch from x.ended_at - x.started_at) - x.pause_sec)) <= 60 and x.idle_sec < 600,
        format('dur %s idle %s', x.duration_min, x.idle_sec));
  r := public.append_ride_track(v_id, late, null);
  perform t_rides.chk('S3 same late batch again: nothing added, no reason', r->>'error' = 'ride_finished'
        and not (r ? 'reason') and (t_rides.ride(v_id)).distance_km = x.distance_km, r::text);
end $$;

do $$
declare u uuid := t_rides.u(24); e1 float8 := t_rides.ep('2026-10-24 09:00'); d2 float8 := t_rides.ep('2026-10-25 08:00');
  b uuid; r jsonb; v_id uuid; x public.user_rides; km1 numeric;
begin
  -- S4: the same via finish_user_ride (watcher saw the return and stops with the buffer)
  b := t_rides.booking(24, u, '2026-10-24', '2026-10-25');
  perform t_rides.at(u, e1);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(49.5, 16.8, e1 + 5, 0), jsonb_build_array(49.5001, 16.8, e1 + 200, -1))
                                || t_rides.line(49.5006, 60, 0.0005, e1 + 205, 5, 40));
  km1 := (t_rides.ride(v_id)).distance_km;
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(d2 + 1200) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(null, d2 + 1900);  perform public.close_stale_user_rides();
  perform t_rides.at(u, d2 + 5000);
  r := public.finish_user_ride(v_id, jsonb_build_array(jsonb_build_array(49.53, 16.8, d2, -1))
                                     || t_rides.line(49.5305, 120, 0.0005, d2 + 5, 5, 40), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('S4 finish after the cron: late points kept, already_finished values updated',
        r->>'already_finished' = 'true' and (r->>'distance_km')::numeric = round(x.distance_km, 1)
        and x.distance_km > km1 + 6 and x.ended_at = to_timestamp(d2 + 720), r::text);
  -- S5: own trip closed by the cron (72 h offline) → newer points re-open it (SPEC §23, C5)
  perform t_rides.at(u, d2 + 86400);
  v_id := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(49.4, 16.8, d2 + 86405, 0), jsonb_build_array(49.4001, 16.8, d2 + 86500, -1))
                                || t_rides.line(49.4006, 40, 0.0005, d2 + 86505, 5, 40));
  perform t_rides.at(null, d2 + 86400 + 74 * 3600);  perform public.close_stale_user_rides();
  km1 := (t_rides.ride(v_id)).distance_km;
  perform t_rides.at(u, d2 + 86400 + 75 * 3600);
  r := public.append_ride_track(v_id, t_rides.line(49.43, 20, 0.0005, d2 + 86800, 5, 40), null);
  perform t_rides.chk('S5 own trip closed by cron: newer points re-open it', r->>'success' = 'true' and r->>'reopened' = 'true'
        and (t_rides.ride(v_id)).is_recording and (t_rides.ride(v_id)).distance_km > km1, r::text);
  perform public.finish_user_ride(v_id, '[]'::jsonb, null);
end $$;

do $$
declare u uuid := t_rides.u(26); e1 float8 := t_rides.ep('2026-10-24 09:00'); b uuid; r jsonb; v_id uuid; x public.user_rides; km1 numeric;
begin
  -- S6: rental stopped by the rider (Stop) → no late points afterwards
  b := t_rides.booking(26, u, '2026-10-24', '2026-10-26');
  perform t_rides.at(u, e1);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(49.3, 16.8, e1 + 5, 0), jsonb_build_array(49.3001, 16.8, e1 + 200, -1))
                                || t_rides.line(49.3006, 40, 0.0005, e1 + 205, 5, 40));
  perform t_rides.at(u, e1 + 600);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id); km1 := x.distance_km;
  perform t_rides.chk('S6 Stop marks closed_by user', x.stats_state->>'closed_by' = 'user', x.stats_state::text);
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(e1 + 7200) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(u, e1 + 9000);
  r := public.append_ride_track(v_id, t_rides.line(49.32, 20, 0.0005, e1 + 3600, 5, 40), null);
  perform t_rides.chk('S6 late points after Stop ignored', r->>'error' = 'ride_finished' and not (r ? 'reason')
        and (t_rides.ride(v_id)).distance_km = km1, r::text);
end $$;

-- ───────────── GK: gear-only bookings (booking_kind = 'gear') are not motorcycle rentals ─────────────
create function t_rides.gear(p_n int, p_uid uuid, p_start date, p_end date) returns uuid language plpgsql as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  insert into public.bookings (id, user_id, booking_kind, moto_id, start_date, end_date, status, picked_up_at,
                               gear_lines, gear_per_day)
  values (t_rides.bk(p_n), p_uid, 'gear', null, p_start::timestamptz, p_end::timestamptz, 'active', p_start::timestamptz,
          '[]'::jsonb, 100);
  perform set_config('session_replication_role', 'origin', true);
  return t_rides.bk(p_n);
end $$;
do $$
declare e float8 := t_rides.ep('2026-10-21 09:00'); r jsonb; v_id uuid; v2 uuid; x public.user_rides;
  g27 uuid; m28 uuid; g25 uuid; g29 uuid; g30 uuid;
begin
  -- GK1: 4.1.3 manual ride on a day with ONLY a gear rental = own ride (3 h rule, no resume next day)
  g27 := t_rides.gear(21, t_rides.u(27), '2026-10-20', '2026-10-23');
  perform t_rides.at(t_rides.u(27), e);
  v_id := (public.start_user_ride(null, 49.2, 16.6)->>'id')::uuid;
  perform t_rides.chk('GK1 4.1.3 manual start: not paired with the gear booking', (t_rides.ride(v_id)).booking_id is null
        and (t_rides.ride(v_id)).moto_id is null);
  perform t_rides.feed(t_rides.u(27), v_id, t_rides.line(49.2005, 40, 0.0005, e + 5, 5, 40));
  perform t_rides.at(null, e + 200 + 3 * 3600 + 300);  perform public.close_stale_user_rides();
  perform t_rides.chk('GK1 closed after 3 h silence (own legacy rule)', not (t_rides.ride(v_id)).is_recording);
  perform t_rides.at(t_rides.u(27), e + 86400);
  r := public.start_user_ride(null, 49.3, 16.6);
  perform t_rides.chk('GK1 next morning: new ride, nothing resumed', r->>'resumed' = 'false' and (r->>'id')::uuid <> v_id
        and r->>'booking_id' is null, r::text);
  perform public.finish_user_ride((r->>'id')::uuid, '[]'::jsonb, null);
  -- GK2: new app start_user_trip(gear) → booking_inactive, nothing created
  perform t_rides.at(t_rides.u(27), e + 90000);
  r := public.start_user_trip(g27);
  perform t_rides.chk('GK2 start_user_trip(gear) → booking_inactive, no row', r->>'error' = 'booking_inactive'
        and not exists (select 1 from public.user_rides where user_id = t_rides.u(27) and is_recording), r::text);
  -- GK3: moto rental + gear rental the same days → 4.1.3 manual ride pairs with the MOTORCYCLE
  m28 := t_rides.booking(22, t_rides.u(28), '2026-10-19', '2026-10-24');
  g25 := t_rides.gear(25, t_rides.u(28), '2026-10-20', '2026-10-23');
  perform t_rides.at(t_rides.u(28), e);
  v2 := (public.start_user_ride(null, 49.2, 16.6)->>'id')::uuid;
  perform t_rides.chk('GK3 pairs with the moto rental, not the gear one', (t_rides.ride(v2)).booking_id = m28,
        (t_rides.ride(v2)).booking_id::text);
  -- GK4: Velín live map of the gear booking: no ride
  perform t_rides.at('d0000000-0000-0000-0000-00000000000d', e + 60);
  r := public.admin_booking_live_ride(g25);
  perform t_rides.chk('GK4 admin_booking_live_ride(gear) → has_ride false', r->>'ok' = 'true' and r->>'has_ride' = 'false', r::text);
  -- GK5: 4.1.3 auto start with a gear booking id → booking_inactive (does not record), no row
  g29 := t_rides.gear(27, t_rides.u(29), '2026-10-20', '2026-10-23');
  perform t_rides.at(t_rides.u(29), e);
  r := public.start_user_ride(g29, 49.2, 16.6);
  perform t_rides.chk('GK5 start_user_ride(gear id) → booking_inactive, no row', r->>'success' = 'false'
        and r->>'error' = 'booking_inactive' and not exists (select 1 from public.user_rides where user_id = t_rides.u(29)), r::text);
  -- GK6: a ride already linked to a gear booking (before the fix): gear return neither cuts nor keeps it open
  g30 := t_rides.gear(28, t_rides.u(30), '2026-10-20', '2026-10-23');
  perform set_config('session_replication_role', 'replica', true);
  insert into public.user_rides (user_id, booking_id, source, track, is_recording, started_at, last_fix_at, updated_at)
  values (t_rides.u(30), g30, 'auto', '[]', true, to_timestamp(e), to_timestamp(e), to_timestamp(e)) returning id into v_id;
  update public.bookings set returned_at = to_timestamp(e + 100) where id = g30;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(t_rides.u(30), e + 400);
  r := public.append_ride_track(v_id, t_rides.line(49.1, 40, 0.0005, e + 150, 5, 40), null);
  perform t_rides.chk('GK6 points after the GEAR return accepted', r->>'success' = 'true' and (r->>'dropped')::int = 0, r::text);
  perform t_rides.at(null, e + 100 + 700);  perform public.close_stale_user_rides();
  perform t_rides.chk('GK6 gear return does not close it (cron)', (t_rides.ride(v_id)).is_recording);
  perform t_rides.at(t_rides.u(30), e + 1000);
  r := public.start_user_ride(null, 49.12, 16.6);
  x := t_rides.ride(v_id);
  perform t_rides.chk('GK6 start_user_ride detaches the gear booking and resumes', r->>'resumed' = 'true'
        and (r->>'id')::uuid = v_id and x.booking_id is null, r::text);
  -- (samoléčení posunulo updated_at → 3 h od e + 1000)
  perform t_rides.at(null, e + 1000 + 3 * 3600 + 300);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id);
  perform t_rides.chk('GK6 then closed by the own 3 h rule at the last point', not x.is_recording
        and x.ended_at >= x.last_fix_at and x.ended_at <= x.last_fix_at + interval '120 seconds', coalesce(x.ended_at::text, 'deleted'));
end $$;

-- ───────────── Q: public list = finished rides only, no linking keys ─────────────
do $$
declare v_fin uuid; v_open uuid; j jsonb; e float8 := t_rides.ep('2026-10-26 09:00');
begin
  select id into v_fin from public.user_rides where user_id = t_rides.u(21) and not is_recording limit 1;
  select id into v_open from public.user_rides where user_id = t_rides.u(22) and is_recording limit 1;
  perform t_rides.at(t_rides.u(21), e);  perform public.update_user_ride(v_fin, null, null, 'public', null);
  perform t_rides.at(t_rides.u(22), e);  perform public.update_user_ride(v_open, null, null, 'public', null);
  update public.user_rides set trip_id = gen_random_uuid(), trip_name = 'Cesta' where id = v_fin;
  j := public.get_public_rides(100, 0);
  perform t_rides.chk('Q1 finished public ride listed', exists (select 1 from jsonb_array_elements(j) x where x->>'id' = v_fin::text), j::text);
  perform t_rides.chk('Q2 recording public ride NOT listed (live position)', not exists (
        select 1 from jsonb_array_elements(j) x where x->>'id' = v_open::text));
  perform t_rides.chk('Q3 no linking/state keys', not exists (select 1 from jsonb_array_elements(j) x
        where x ?| array['user_id', 'booking_id', 'moto_id', 'trip_id', 'last_fix_at', 'pause_aware', 'is_recording'])
        and (select bool_and(x ? 'track' and x ? 'stages' and x ? 'pause_sec') from jsonb_array_elements(j) x),
        (select string_agg(k, ',') from jsonb_object_keys(j->0) k));
end $$;

-- ───────────── H3: stored points with text instead of numbers do not break cap / close / Velín ─────────────
do $$
declare u uuid := t_rides.u(25); e float8 := t_rides.ep('2026-10-22 06:00'); b uuid; v_id uuid; tr jsonb; c jsonb; r jsonb;
begin
  tr := '[["x", "y", 0, 40]]'::jsonb || t_rides.line(48.9, 5000, 0.0005, e, 5, 40) || '[["49.1", "abc", 1, 40]]'::jsonb;
  c := public._ride_track_cap(tr, 4000);
  perform t_rides.chk('H3 cap with text coordinates: no error, ≤ 4000', jsonb_array_length(c) <= 4000, jsonb_array_length(c)::text);
  b := t_rides.booking(29, u, '2026-10-22', '2026-10-24');
  perform set_config('session_replication_role', 'replica', true);
  insert into public.user_rides (user_id, booking_id, source, track, is_recording, started_at, last_fix_at, distance_km, moving_sec)
  values (u, b, 'auto', '[["x", "y", 0, 40]]'::jsonb || t_rides.line(48.9, 1500, 0.0005, e, 5, 40) || '[["a", "b", 1, 40]]'::jsonb,
          true, to_timestamp(e), to_timestamp(e + 7495), 83.3, 7495) returning id into v_id;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at('d0000000-0000-0000-0000-00000000000d', e + 7600);
  r := public.admin_booking_live_ride(b);
  perform t_rides.chk('H3 Velín live map: ok, track ≤ 1200', r->>'ok' = 'true' and r->>'has_ride' = 'true'
        and jsonb_array_length(r->'track') <= 1200, left(r::text, 200));
  r := public._ride_finalize(v_id, null);
  perform t_rides.chk('H3 close with text coordinates: ok, start point from text skipped', r->>'success' = 'true'
        and r->>'discarded' = 'false' and not exists (select 1 from public.user_ride_points where ride_id = v_id and kind = 'start'), r::text);
end $$;

-- ───────────── K: kiosk — an early return only „parks" the bike (G3), overnight bay parking (D1) ─────────────
create function t_rides.kiosk(p_b uuid, p_state text, p_closed float8, p_out float8) returns void language plpgsql as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  insert into public.booking_kiosk_returns (booking_id, state, closed_at, out_at)
  values (p_b, p_state, to_timestamp(p_closed), to_timestamp(p_out))
  on conflict (booking_id) do update set state = excluded.state, closed_at = excluded.closed_at, out_at = excluded.out_at;
  perform set_config('session_replication_role', 'origin', true);
end $$;
create function t_rides.bike(p_lat float8, p_lng float8, p_e float8, p_n int) returns jsonb language sql immutable as $$
  select jsonb_build_array(jsonb_build_array(p_lat, p_lng, p_e + 5, 0), jsonb_build_array(p_lat + 0.0001, p_lng, p_e + 200, -1))
         || (select coalesce(jsonb_agg(jsonb_build_array(round((p_lat + 0.0006 + i * 0.0005)::numeric, 7), p_lng, p_e + 205 + i * 5, 40)
                                       order by i), '[]'::jsonb) from generate_series(0, p_n - 1) i) $$;

do $$
declare u uuid := t_rides.u(46); e float8 := t_rides.ep('2026-11-20 08:00'); b uuid; r jsonb; v_id uuid; x public.user_rides;
  p float8; bkm numeric; n int;
begin
  -- K1 (G3): bike locked in the kiosk bay a day early (kiosk only „parks"), car home at 120 km/h
  b := t_rides.booking(46, u, '2026-11-20', '2026-11-21');
  perform t_rides.at(u, e);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.bike(49.3, 16.6, e, 200));
  bkm := (t_rides.ride(v_id)).distance_km;
  p := e + 1300;
  perform t_rides.kiosk(b, 'parked', p, null);
  perform t_rides.at(u, p + 800);
  r := public.append_ride_track(v_id, t_rides.line(49.5, 100, 0.0015, p + 300, 5, 120), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('K1 car after the bay parking → ride_finished/booking_ended', r->>'error' = 'ride_finished'
        and r->>'reason' = 'booking_ended', r::text);
  perform t_rides.chk('K1 closed at the bike end: bike km and max only, closed_by return', not x.is_recording
        and x.distance_km = bkm and x.max_speed_kmh <= 45 and x.ended_at <= to_timestamp(p)
        and x.stats_state->>'closed_by' = 'return', format('km %s (bike %s) max %s end %s', x.distance_km, bkm, x.max_speed_kmh, x.ended_at));
  r := public.start_user_trip(b);
  perform t_rides.chk('K1 start_user_trip while parked → booking_inactive', r->>'error' = 'booking_inactive', r::text);
  r := public.start_user_trip_from(b, e + 10);
  perform t_rides.chk('K1 start_user_trip_from while parked (ride exists) → booking_inactive', r->>'error' = 'booking_inactive', r::text);
  r := public.start_user_ride(b, 49.5, 16.6);
  select count(*) into n from public.user_rides where user_id = u;
  perform t_rides.chk('K1 4.1.3 start_user_ride while parked → success false, no new ride', r->>'success' = 'false'
        and r->>'error' = 'booking_inactive' and n = 1, format('%s n=%s', r, n));
  r := public.start_user_ride(null, 49.5, 16.6);
  perform t_rides.chk('K1 4.1.3 manual ride the same day is NOT paired with the parked rental', r->>'success' = 'true'
        and (t_rides.ride((r->>'id')::uuid)).booking_id is null, r::text);
  perform public.finish_user_ride((r->>'id')::uuid, '[]'::jsonb, null);
  -- next day kiosk_process_returns completes the booking (returned_at back-dated to the bay close)
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(p), status = 'completed' where id = b;
  update public.booking_kiosk_returns set state = 'completed' where booking_id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(null, e + 86400 + 6 * 3600);  perform public.close_stale_user_rides();
  perform t_rides.chk('K1 completion next day changes nothing', (t_rides.ride(v_id)).distance_km = bkm
        and (t_rides.ride(v_id)).ended_at = x.ended_at);
end $$;

do $$
declare u uuid := t_rides.u(47); e float8 := t_rides.ep('2026-11-20 08:00'); b uuid; r jsonb; v_id uuid; x public.user_rides;
  p float8; bkm numeric; bmv int; bmax numeric; ep record;
begin
  -- K2 (G3, kiosk offline): the bay close arrives AFTER the car points were stored → the cron trims them
  b := t_rides.booking(47, u, '2026-11-20', '2026-11-21');
  perform t_rides.at(u, e);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.bike(49.3, 16.7, e, 200));
  x := t_rides.ride(v_id); bkm := x.distance_km; bmv := x.moving_sec; bmax := x.max_speed_kmh;
  p := e + 1300;
  perform t_rides.feed(u, v_id, t_rides.line(49.5, 100, 0.0015, p + 300, 5, 120));
  x := t_rides.ride(v_id);
  perform t_rides.chk('K2 before the kiosk event the car drive is stored', x.is_recording and x.distance_km > bkm + 10
        and x.max_speed_kmh > 100, format('km %s max %s', x.distance_km, x.max_speed_kmh));
  perform t_rides.kiosk(b, 'parked', p, null);
  perform t_rides.at('d0000000-0000-0000-0000-00000000000d', p + 300 + 495 + 1000);
  r := public.admin_booking_live_ride(b);
  perform t_rides.chk('K2 Velín: a rental parked in the bay is not „standing"', r->>'is_standing' = 'false'
        and r->>'is_recording' = 'true', r::text);
  perform t_rides.at(null, p + 3000);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id);
  perform t_rides.chk('K2 cron closes at the bay close and trims the car drive (km, max, last fix)', not x.is_recording
        and x.stats_state->>'closed_by' = 'cron' and t_rides.near(x.distance_km, bkm, 0.02) and x.max_speed_kmh = bmax
        and x.ended_at <= to_timestamp(p) and x.last_fix_at <= to_timestamp(p + 30),
        format('km %s (bike %s) max %s end %s fix %s', x.distance_km, bkm, x.max_speed_kmh, x.ended_at, x.last_fix_at));
  perform t_rides.chk('K2 duration ≥ moving + gap, moving = bike only, 1 stage', x.duration_min * 60 + 30 >= x.moving_sec + x.gap_sec
        and abs(x.moving_sec - bmv) <= 10 and x.idle_sec >= 0 and jsonb_array_length(x.stages) = 1,
        format('dur %s mv %s (bike %s) gap %s idle %s', x.duration_min, x.moving_sec, bmv, x.gap_sec, x.idle_sec));
  select lat, happened_at into ep from public.user_ride_points where ride_id = v_id and kind = 'end';
  perform t_rides.chk('K2 end point = last bike point, track without car points',
        t_rides.near(ep.lat::numeric, 49.3006 + 199 * 0.0005, 0.00001)
        and not exists (select 1 from jsonb_array_elements(x.track) t where (t->>0)::float8 >= 49.5), ep::text);
end $$;

do $$
declare u uuid := t_rides.u(48); e float8 := t_rides.ep('2026-11-20 08:00'); b uuid; r jsonb; v_id uuid; x public.user_rides;
  p float8; bkm numeric;
begin
  -- K3: returned but not completed (skipped, e.g. unpaid) → Stop with the car points keeps the bike only
  b := t_rides.booking(48, u, '2026-11-20', '2026-11-21');
  perform t_rides.at(u, e);  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.bike(49.3, 16.8, e, 200));
  bkm := (t_rides.ride(v_id)).distance_km;
  p := e + 1300;  perform t_rides.kiosk(b, 'skipped', p, null);
  perform t_rides.at(u, p + 1200);
  r := public.finish_user_ride(v_id, t_rides.line(49.5, 100, 0.0015, p + 300, 5, 120), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('K3 Stop while the bike is in the bay (skipped): bike km only, ended at the bike end', r->>'success' = 'true'
        and not x.is_recording and x.distance_km = bkm and x.ended_at <= to_timestamp(p), format('%s km %s', r, x.distance_km));
  -- K3b: the bike left the bay before (closed_at < out_at) → not ended, recording goes on
  perform t_rides.kiosk(b, 'skipped', p - 600, p - 300);
  perform t_rides.chk('K3b closed before the last ride-out = not a return', public._ride_booking_end(b) is null);
end $$;

do $$
declare u uuid := t_rides.u(49); d1 float8 := t_rides.ep('2026-11-20 09:00'); d2 float8 := t_rides.ep('2026-11-21 08:00');
  b uuid; r jsonb; v_id uuid; x public.user_rides; p1 float8; km1 numeric; n int;
begin
  -- K4 (D1): 3-day rental, bike in the kiosk bay overnight, out again next morning → ONE ride
  b := t_rides.booking(49, u, '2026-11-20', '2026-11-22');
  perform t_rides.at(u, d1);  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.bike(49.2, 16.6, d1, 200));
  km1 := (t_rides.ride(v_id)).distance_km;
  p1 := d1 + 1300;  perform t_rides.kiosk(b, 'parked', p1, null);
  perform t_rides.at(u, p1 + 1500);
  r := public.append_ride_track(v_id, t_rides.line(49.4, 20, 0.0015, p1 + 600, 5, 110), null);   -- taxi to the hotel
  perform t_rides.chk('K4 taxi after the bay parking not recorded (ride closed at the parking)', r->>'reason' = 'booking_ended'
        and not (t_rides.ride(v_id)).is_recording and (t_rides.ride(v_id)).distance_km = km1, r::text);
  perform t_rides.at(u, d1 + 4 * 3600);
  perform t_rides.chk('K4 start during the night → booking_inactive', public.start_user_trip(b)->>'error' = 'booking_inactive');
  perform t_rides.kiosk(b, 'out', p1, d2);
  perform t_rides.at(u, d2 + 60);
  r := public.start_user_trip(b);
  x := t_rides.ride(v_id);
  perform t_rides.chk('K4 bike out of the bay → the SAME ride re-opened (resumed + reopened)', r->>'success' = 'true'
        and (r->>'id')::uuid = v_id and r->>'resumed' = 'true' and r->>'reopened' = 'true' and x.is_recording
        and x.ended_at is null and not (x.stats_state ? 'closed_by') and x.name = '', r::text);
  perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(49.3002, 16.6, d2 + 70, -1))
          || t_rides.line(49.3007, 200, 0.0005, d2 + 75, 5, 40));
  perform t_rides.at(u, d2 + 2000);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  select count(*) into n from public.user_rides where user_id = u;
  perform t_rides.chk('K4 one ride for the rental: 2 days, 2 stages, the night is a pause', n = 1 and not x.is_recording
        and jsonb_array_length(x.stages) = 2 and (r->>'days')::int = 2 and x.pause_sec >= 12 * 3600
        and x.name = '20.11.–21.11.2026' and t_rides.near(x.distance_km, km1 + 200 * 0.0555975, 0.05)
        and x.stats_state->>'closed_by' = 'user', format('n %s %s', n, r));
  -- a ride the rider stopped himself is never re-opened by a later ride-out
  perform t_rides.kiosk(b, 'parked', d2 + 2100, null);
  perform t_rides.kiosk(b, 'out', d2 + 2100, d2 + 9000);
  perform t_rides.at(u, d2 + 9100);
  r := public.start_user_trip(b);
  perform t_rides.chk('K4 after Stop a ride-out starts a NEW ride (no re-open)', r->>'success' = 'true'
        and (r->>'id')::uuid <> v_id and not (r ? 'reopened') and not (t_rides.ride(v_id)).is_recording, r::text);
  perform public.finish_user_ride((r->>'id')::uuid, '[]'::jsonb, null);
end $$;

do $$
declare u uuid := t_rides.u(50); d1 float8 := t_rides.ep('2026-11-20 09:00'); d2 float8 := t_rides.ep('2026-11-21 08:00');
  b uuid; r jsonb; v_id uuid; x public.user_rides; p1 float8; km1 numeric; n int;
begin
  -- K4b: the same with the released app 4.1.3 (start_user_ride), closed by the cron
  b := t_rides.booking(50, u, '2026-11-20', '2026-11-22');
  perform t_rides.at(u, d1);  v_id := (public.start_user_ride(b, 49.1, 16.6)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.line(49.1005, 200, 0.0005, d1 + 5, 5, 40));
  km1 := (t_rides.ride(v_id)).distance_km;
  p1 := d1 + 1300;  perform t_rides.kiosk(b, 'parked', p1, null);
  perform t_rides.at(null, p1 + 900);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id);
  perform t_rides.chk('K4b 4.1.3: the cron closes the parked rental (closed_by cron)', not x.is_recording
        and x.stats_state->>'closed_by' = 'cron', format('%s %s', x.is_recording, x.stats_state));
  perform t_rides.at(u, d1 + 5 * 3600);
  r := public.start_user_ride(b, 49.2, 16.9);
  perform t_rides.chk('K4b 4.1.3 start while parked → success false', r->>'success' = 'false', r::text);
  perform t_rides.kiosk(b, 'out', p1, d2);
  perform t_rides.at(u, d2 + 60);
  r := public.start_user_ride(b, 49.2, 16.9);
  perform t_rides.chk('K4b 4.1.3 after the ride-out → the same ride resumed', r->>'success' = 'true'
        and (r->>'id')::uuid = v_id and r->>'resumed' = 'true' and (t_rides.ride(v_id)).is_recording, r::text);
  perform t_rides.feed(u, v_id, t_rides.line(49.2, 200, 0.0005, d2 + 65, 5, 40));
  perform t_rides.at(u, d2 + 2000);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  select count(*) into n from public.user_rides where user_id = u;
  perform t_rides.chk('K4b 4.1.3: one ride over the night, the night is a pause', n = 1 and x.pause_sec >= 12 * 3600
        and jsonb_array_length(x.stages) = 2 and x.distance_km > km1 + 10, format('n %s %s pause %s', n, r, x.pause_sec));
end $$;

do $$
declare u uuid := t_rides.u(51); e float8 := t_rides.ep('2026-11-20 08:00'); b uuid; r jsonb; v_id uuid; x public.user_rides;
  p float8; km1 numeric;
begin
  -- K5: phone offline before the bay parking; cron closed it; the late bike points still land, the car does not
  b := t_rides.booking(51, u, '2026-11-20', '2026-11-21');
  perform t_rides.at(u, e);  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_id, t_rides.bike(49.3, 16.6, e, 100));
  km1 := (t_rides.ride(v_id)).distance_km;
  p := e + 3600;  perform t_rides.kiosk(b, 'parked', p, null);
  perform t_rides.at(null, p + 900);  perform public.close_stale_user_rides();
  perform t_rides.at(u, p + 7200);
  r := public.append_ride_track(v_id, t_rides.line(49.3506, 100, 0.0005, e + 1500, 5, 40)
                                     || t_rides.line(49.6, 5, 0.0015, p + 600, 5, 120), null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('K5 late bike points stored after the cron close, car not (re-closed ≤ bay close)',
        r->>'error' = 'ride_finished' and r->>'reason' = 'booking_ended' and t_rides.near(x.distance_km, km1 + 100 * 0.0555975, 0.1)
        and x.max_speed_kmh <= 45 and x.ended_at <= to_timestamp(p) and x.stats_state->>'closed_by' = 'cron',
        format('%s km %s (first %s)', r, x.distance_km, km1));
end $$;

do $$
declare u uuid := t_rides.u(52); e float8 := t_rides.ep('2026-11-22 10:00'); r jsonb; v_id uuid; x public.user_rides; km1 numeric;
begin
  -- K6: own 4.1.3 ride, phone clock 4 min fast — Stop never trims (no booking end → no cut, as before)
  perform t_rides.at(u, e);
  v_id := (public.start_user_ride(null, 49.05, 16.6)->>'id')::uuid;
  perform t_rides.at(u, e + 600);
  perform public.append_ride_track(v_id, t_rides.line(49.0505, 120, 0.0005, e + 240, 5, 40), null);
  km1 := (t_rides.ride(v_id)).distance_km;
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('K6 own ride, clock ahead: Stop keeps all points and km', x.distance_km = km1
        and jsonb_array_length(x.track) = 121 and x.duration_min * 60 + 30 >= x.moving_sec + x.gap_sec,
        format('km %s/%s pts %s dur %s mv %s', x.distance_km, km1, jsonb_array_length(x.track), x.duration_min, x.moving_sec));
end $$;

-- ───────────── T: start_user_trip_from — recording started offline, retro rental ─────────────
do $$
declare u uuid := t_rides.u(53); u2 uuid := t_rides.u(54); e float8 := t_rides.ep('2026-11-05 08:00');
  r jsonb; v1 uuid; v2 uuid; x public.user_rides; pts jsonb;
begin
  -- T1: own trip started OFFLINE at 08:00, the server ride is created only at 12:00
  pts := t_rides.bike(49.0, 16.6, e, 200)
         || jsonb_build_array(jsonb_build_array(49.1002, 16.6, e + 3 * 3600, -1))
         || t_rides.line(49.1007, 200, 0.0005, e + 3 * 3600 + 5, 5, 40);
  perform t_rides.at(u, e + 4 * 3600);
  r := public.start_user_trip_from(null, e + 5);
  v1 := (r->>'id')::uuid;
  perform t_rides.chk('T1 start_user_trip_from: new trip starts at the first offline point', r->>'success' = 'true'
        and r->>'resumed' = 'false' and (t_rides.ride(v1)).started_at = to_timestamp(e + 5)
        and (t_rides.ride(v1)).pause_aware and not (r ? 'retro'), r::text);
  r := public.append_ride_track(v1, pts, null);
  x := t_rides.ride(v1);
  perform t_rides.chk('T1 the offline hours are stored (nothing dropped as a stale ride)', r->>'success' = 'true'
        and (r->>'dropped')::int = 0 and t_rides.near(x.distance_km, 400 * 0.0555975, 0.1)
        and x.started_at = to_timestamp(e + 200), r::text);
  -- T1b: the plain start (no first ts) keeps today's rule: > 1 h before the start = previous ride
  perform t_rides.at(u2, e + 4 * 3600);
  v2 := (public.start_user_trip(null)->>'id')::uuid;
  r := public.append_ride_track(v2, pts, null);
  perform t_rides.chk('T1b start_user_trip without first ts: stale rule unchanged', (r->>'dropped')::int = 202, r::text);
end $$;

do $$
declare u uuid := t_rides.u(55); e float8 := t_rides.ep('2026-11-06 12:00'); r jsonb; v uuid; x public.user_rides;
begin
  -- T2: implausible first ts → clamped (≤ 7 days back, never in the future, junk ignored)
  perform t_rides.at(u, e);
  r := public.start_user_trip_from(null, e - 10 * 86400);
  perform t_rides.chk('T2 first ts 10 days ago → 7 days', (t_rides.ride((r->>'id')::uuid)).started_at = to_timestamp(e - 7 * 86400), r::text);
  delete from public.user_rides where user_id = u;
  r := public.start_user_trip_from(null, 'NaN'::float8);
  perform t_rides.chk('T2 NaN → now', (t_rides.ride((r->>'id')::uuid)).started_at = to_timestamp(e), r::text);
  delete from public.user_rides where user_id = u;
  r := public.start_user_trip_from(null, e + 30 * 86400);
  perform t_rides.chk('T2 future → now', (t_rides.ride((r->>'id')::uuid)).started_at = to_timestamp(e), r::text);
  delete from public.user_rides where user_id = u;
  r := public.start_user_trip_from(null, 0);
  perform t_rides.chk('T2 0 → now', (t_rides.ride((r->>'id')::uuid)).started_at = to_timestamp(e), r::text);
  delete from public.user_rides where user_id = u;
  -- T3: a resumed, still EMPTY ride moves back to the first offline point; a ride with points does not
  v := (public.start_user_trip(null)->>'id')::uuid;
  r := public.start_user_trip_from(null, e - 7200);
  perform t_rides.chk('T3 resumed empty ride starts at the first offline point', r->>'resumed' = 'true' and (r->>'id')::uuid = v
        and (t_rides.ride(v)).started_at = to_timestamp(e - 7200), r::text);
  perform t_rides.at(u, e + 20);
  perform public.append_ride_track(v, jsonb_build_array(jsonb_build_array(49.0, 17.3, e + 10, 0)), null);
  r := public.start_user_trip_from(null, e - 18000);
  perform t_rides.chk('T3 resumed ride with points keeps its start', r->>'resumed' = 'true'
        and (t_rides.ride(v)).started_at = to_timestamp(e - 7200), r::text);
  delete from public.user_rides where user_id = u;
end $$;

do $$
declare u uuid := t_rides.u(56); b uuid; d1 float8 := t_rides.ep('2026-11-03 09:00'); ret float8 := t_rides.ep('2026-11-04 17:00');
  r jsonb; v_id uuid; x public.user_rides; pts jsonb; n int;
begin
  -- T4: rental recorded fully offline, returned BEFORE the first successful start → created retro
  b := t_rides.booking(56, u, '2026-11-03', '2026-11-04');
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(ret), status = 'completed' where id = b;
  perform set_config('session_replication_role', 'origin', true);
  pts := t_rides.bike(49.0, 16.6, d1, 200)
         || jsonb_build_array(jsonb_build_array(49.1002, 16.6, ret - 3600, -1)) || t_rides.line(49.1007, 100, 0.0005, ret - 3595, 5, 40)
         || t_rides.line(49.3, 10, 0.0015, ret + 600, 5, 120);
  perform t_rides.at(u, ret + 7200);
  r := public.start_user_trip(b);
  perform t_rides.chk('T4 returned rental, plain start → booking_inactive (unchanged)', r->>'error' = 'booking_inactive', r::text);
  r := public.start_user_trip_from(b, ret + 60);
  perform t_rides.chk('T4 first point after the return → booking_inactive', r->>'error' = 'booking_inactive', r::text);
  r := public.start_user_trip_from(b, d1 + 5);
  v_id := (r->>'id')::uuid;  x := t_rides.ride(v_id);
  perform t_rides.chk('T4 offline rental returned before the first start → ride created retro', r->>'success' = 'true'
        and r->>'retro' = 'true' and r->>'resumed' = 'false' and x.booking_id = b and x.started_at = to_timestamp(d1 + 5)
        and x.moto_name = 'Honda CB 500 X' and x.is_recording, r::text);
  r := public.append_ride_track(v_id, pts, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('T4 buffer: both rental days stored, the car after the return dropped', r->>'success' = 'true'
        and (r->>'dropped')::int = 10 and t_rides.near(x.distance_km, 300 * 0.0555975, 0.1), r::text);
  perform t_rides.at(null, ret + 7200 + 1200);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id);
  perform t_rides.chk('T4 the cron closes it ≤ the return (2 days, closed_by cron)', not x.is_recording and x.ended_at <= to_timestamp(ret)
        and x.stats_state->>'closed_by' = 'cron' and x.name = '03.11.–04.11.2026', format('%s %s %s', x.ended_at, x.name, x.stats_state));
  perform t_rides.at(u, ret + 7200 + 1300);
  r := public.start_user_trip_from(b, d1 + 5);
  select count(*) into n from public.user_rides where user_id = u;
  perform t_rides.chk('T4 second retro start (ride exists) → booking_inactive, still 1 ride', r->>'error' = 'booking_inactive' and n = 1, r::text);
end $$;

do $$
declare e float8 := t_rides.ep('2026-11-10 12:00'); r jsonb; b uuid; v uuid;
begin
  -- T5: retro only within 7 days after the return, never for a cancelled booking
  b := t_rides.booking(57, t_rides.u(57), '2026-11-01', '2026-11-02');
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(e - 8 * 86400), status = 'completed' where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(t_rides.u(57), e);
  r := public.start_user_trip_from(b, e - 9 * 86400);
  perform t_rides.chk('T5 returned 8 days ago → booking_inactive', r->>'error' = 'booking_inactive', r::text);
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = null, status = 'cancelled' where id = b;
  perform set_config('session_replication_role', 'origin', true);
  r := public.start_user_trip_from(b, e - 3600);
  perform t_rides.chk('T5 cancelled booking → booking_inactive', r->>'error' = 'booking_inactive', r::text);
  -- T6: bike parked in the kiosk bay (not completed yet) → retro works the same
  b := t_rides.booking(58, t_rides.u(58), '2026-11-10', '2026-11-11');
  perform t_rides.kiosk(b, 'parked', e - 3600, null);
  perform t_rides.at(t_rides.u(58), e);
  r := public.start_user_trip_from(b, e - 4 * 3600);
  perform t_rides.chk('T6 parked in the bay, first point before → retro ride', r->>'success' = 'true' and r->>'retro' = 'true', r::text);
  -- T7: a rental never starts before the pickup (− 10 min)
  b := t_rides.booking(59, t_rides.u(59), '2026-11-10', '2026-11-12');
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set picked_up_at = to_timestamp(e - 3600) where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(t_rides.u(59), e + 4 * 3600);
  r := public.start_user_trip_from(b, e - 4 * 3600);
  v := (r->>'id')::uuid;
  perform t_rides.chk('T7 first ts before the pickup → pickup − 10 min', r->>'success' = 'true' and not (r ? 'retro')
        and (t_rides.ride(v)).started_at = to_timestamp(e - 3600 - 600) and (t_rides.ride(v)).booking_id = b, r::text);
  perform public.finish_user_ride(v, '[]'::jsonb, null);
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
      'public._ride_prague_night(double precision,double precision)', 'public._ride_stage_days(jsonb)',
      'public._ride_close(uuid,timestamp with time zone,text,boolean)', 'public._ride_append_late(uuid,jsonb)',
      'public._ride_auto_name(date,date)', 'public._ride_reopen(uuid,jsonb)',
      'public.start_user_trip_from(uuid,double precision)', 'public._ride_booking_end(uuid)',
      'public._ride_start_trip(uuid,uuid,double precision)', 'public._ride_reopen_parked(uuid,uuid,boolean)',
      'public._ride_trip_json(public.user_rides,boolean,timestamp with time zone)'] loop
    perform t_rides.chk('I2 anon cannot execute ' || f, not has_function_privilege('anon', f, 'execute'));
  end loop;
  foreach f in array array['public._ride_stats_v2(jsonb,jsonb,jsonb)', 'public._ride_append_core(uuid,jsonb)',
      'public._ride_prague_night(double precision,double precision)', 'public._ride_finalize(uuid,timestamp with time zone)',
      'public._ride_stage_days(jsonb)', 'public._ride_close(uuid,timestamp with time zone,text,boolean)',
      'public._ride_append_late(uuid,jsonb)', 'public._ride_auto_name(date,date)', 'public._ride_reopen(uuid,jsonb)',
      'public._ride_booking_end(uuid)', 'public._ride_start_trip(uuid,uuid,double precision)',
      'public._ride_reopen_parked(uuid,uuid,boolean)',
      'public._ride_trip_json(public.user_rides,boolean,timestamp with time zone)'] loop
    perform t_rides.chk('I3 authenticated cannot execute ' || f, not has_function_privilege('authenticated', f, 'execute'));
  end loop;
  foreach f in array array['public.start_user_trip(uuid)', 'public.set_user_rides_trip(jsonb)',
      'public.start_user_trip_from(uuid,double precision)',
      'public.start_user_ride(uuid,double precision,double precision)', 'public.append_ride_track(uuid,jsonb,numeric)',
      'public.finish_user_ride(uuid,jsonb,text)', 'public.get_my_rides(integer)', 'public.get_public_rides(integer,integer)'] loop
    perform t_rides.chk('I4 authenticated can execute ' || f, has_function_privilege('authenticated', f, 'execute'));
  end loop;
  perform t_rides.chk('I6 feature flag ride_autopause', exists (select 1 from public.feature_flags where key = 'ride_autopause'
        and enabled and conditions->>'stop_min' = '5'));
end $$;

-- ───────────── SW: SOS bike swap (sos_swap: original completed + ended_by_sos, NO returned_at) ─────────────
create function t_rides.bkr(n int) returns uuid language sql immutable as $$
  select ('bc000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
-- As sos_swap_bookings: original → completed, ended_by_sos, end_date = swap day (returned_at stays NULL);
-- replacement booking (replacement_for_booking_id) created and picked up at p_at.
create function t_rides.sos_swap(p_orig uuid, p_n int, p_uid uuid, p_at float8) returns uuid language plpgsql as $$
declare v_end timestamptz; v_day timestamptz := ((to_timestamp(p_at) at time zone 'Europe/Prague')::date)::timestamptz;
begin
  perform set_config('session_replication_role', 'replica', true);
  select end_date into v_end from public.bookings where id = p_orig;
  update public.bookings set original_end_date = end_date::date, end_date = v_day, status = 'completed', ended_by_sos = true
   where id = p_orig;
  insert into public.bookings (id, user_id, moto_id, start_date, end_date, status, picked_up_at, sos_replacement,
                               replacement_for_booking_id, pickup_time, created_at)
  values (t_rides.bkr(p_n), p_uid, 'e0000000-0000-0000-0000-00000000000e', v_day, v_end, 'active', to_timestamp(p_at),
          true, p_orig, '09:00', to_timestamp(p_at));
  perform set_config('session_replication_role', 'origin', true);
  return t_rides.bkr(p_n);
end $$;

do $$
declare u uuid := t_rides.u(42); e float8 := t_rides.ep('2026-12-01 09:00'); t float8; b uuid; b2 uuid; r jsonb;
  v_a uuid; v_b uuid; x public.user_rides; km1 numeric;
begin
  -- SW1: new app ONLINE — breakdown, SOS swap; the replacement bike never lands in the broken bike's ride
  b := t_rides.booking(42, u, '2026-12-01', '2026-12-04');
  perform t_rides.at(u, e);
  v_a := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_a, t_rides.bike(49.1, 16.9, e, 60));
  km1 := (t_rides.ride(v_a)).distance_km;
  t := e + 1800;
  b2 := t_rides.sos_swap(b, 42, u, t);
  perform t_rides.chk('SW1 _ride_booking_end(original) = replacement created (swap)', public._ride_booking_end(b) = to_timestamp(t)
        and public._ride_booking_end(b2) is null, coalesce(public._ride_booking_end(b)::text, 'NULL'));
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set created_at = to_timestamp(t - 30 * 86400) where id = b2;   -- e.g. inserted without created_at
  perform t_rides.chk('SW0 swap = later of created_at / picked_up_at', public._ride_booking_end(b) = to_timestamp(t),
        coalesce(public._ride_booking_end(b)::text, 'NULL'));
  update public.bookings set created_at = to_timestamp(t), picked_up_at = null where id = b2;
  perform t_rides.chk('SW0 swap without picked_up_at = created_at', public._ride_booking_end(b) = to_timestamp(t),
        coalesce(public._ride_booking_end(b)::text, 'NULL'));
  update public.bookings set picked_up_at = to_timestamp(t) where id = b2;
  insert into public.bookings (id, user_id, moto_id, start_date, end_date, status, picked_up_at, ended_by_sos)
  values (t_rides.bkr(59), u, 'e0000000-0000-0000-0000-00000000000e', '2026-11-20', '2026-11-22', 'completed',
          '2026-11-20 08:00+00', true);
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.chk('SW0 SOS end without a replacement booking → NULL (as before)', public._ride_booking_end(t_rides.bkr(59)) is null);
  -- batch across the swap: broken bike up to swap + 30 s kept, the rest dropped (ride still open)
  perform t_rides.at(u, t + 60);
  r := public.append_ride_track(v_a, t_rides.line(49.14, 20, 0.00002, t - 50, 5, 2), null);
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW1 batch across the swap: ≤ swap + 30 s kept, later dropped', r->>'success' = 'true'
        and (r->>'dropped')::int = 3 and x.is_recording and x.last_fix_at = to_timestamp(t + 30), r::text);
  -- replacement bike points (van arrived) → ride_finished/booking_ended, closed at the swap, no replacement km
  perform t_rides.at(u, t + 900);
  r := public.append_ride_track(v_a, t_rides.line(49.2, 20, 0.0005, t + 600, 5, 40), null);
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW1 replacement points → ride_finished/booking_ended', r->>'error' = 'ride_finished'
        and r->>'reason' = 'booking_ended', r::text);
  perform t_rides.chk('SW1 broken bike ride closed ≤ swap (closed_by return), its km only', not x.is_recording
        and x.ended_at <= to_timestamp(t) and x.stats_state->>'closed_by' = 'return' and x.distance_km < km1 + 0.1
        and x.distance_km >= km1, format('end %s km %s (bike %s)', x.ended_at, x.distance_km, km1));
  r := public.start_user_trip(b);
  perform t_rides.chk('SW1 start_user_trip(original) → booking_inactive', r->>'error' = 'booking_inactive', r::text);
  r := public.start_user_trip(b2);
  v_b := (r->>'id')::uuid;
  perform t_rides.chk('SW1 start_user_trip(replacement) → new ride paired with the replacement', r->>'success' = 'true'
        and r->>'resumed' = 'false' and (r->>'booking_id')::uuid = b2 and v_b <> v_a, r::text);
  r := public.append_ride_track(v_b, t_rides.line(49.2, 20, 0.0005, t + 600, 5, 40), null);
  perform t_rides.chk('SW1 replacement points land in the replacement ride', r->>'success' = 'true'
        and (r->>'dropped')::int = 0 and (t_rides.ride(v_b)).distance_km > 1, r::text);
  perform public.finish_user_ride(v_b, '[]'::jsonb, null);
end $$;

do $$
declare u uuid := t_rides.u(43); e float8 := t_rides.ep('2026-12-01 09:00'); t float8; b uuid; b2 uuid; r jsonb;
  v_a uuid; v_b uuid; x public.user_rides; km1 numeric; pre jsonb; post jsonb;
begin
  -- SW2: new app OFFLINE from 1 h before the breakdown until the evening (V4): the cron closes the
  -- broken bike's ride, its late points still land in it, the replacement's do not
  b := t_rides.booking(43, u, '2026-12-01', '2026-12-04');
  perform t_rides.at(u, e);
  v_a := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.feed(u, v_a, t_rides.bike(49.3, 16.9, e, 60));
  km1 := (t_rides.ride(v_a)).distance_km;
  pre := t_rides.line(49.33, 120, 0.0005, e + 1000, 5, 40);           -- broken bike, offline (e+1000…e+1595)
  t := e + 3600;
  b2 := t_rides.sos_swap(b, 43, u, t);
  post := t_rides.line(49.5, 120, 0.0005, t + 5400, 5, 40);           -- replacement bike, offline
  perform t_rides.at(null, t + 900);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW2 cron closes the swapped rental ≤ swap (closed_by cron)', not x.is_recording
        and x.stats_state->>'closed_by' = 'cron' and x.ended_at <= to_timestamp(t) and x.distance_km = km1,
        format('%s %s %s', x.is_recording, x.stats_state->>'closed_by', x.ended_at));
  perform t_rides.at(u, t + 5400 + 600 + 3600);                       -- evening: hotel Wi-Fi, whole buffer
  r := public.append_ride_track(v_a, pre || post, null);
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW2 late points → ride_finished + reason booking_ended', r->>'error' = 'ride_finished'
        and r->>'reason' = 'booking_ended', r::text);
  perform t_rides.chk('SW2 broken bike km kept (late), replacement km not in it', not x.is_recording
        and t_rides.near(x.distance_km, km1 + 119 * 0.0555975, 0.05) and x.last_fix_at = to_timestamp(e + 1595)
        and x.ended_at = to_timestamp(e + 1595 + 120), format('km %s (online %s) fix %s end %s', x.distance_km, km1, x.last_fix_at, x.ended_at));
  r := public.append_ride_track(v_a, post, null);
  perform t_rides.chk('SW2 only replacement points → nothing added to the broken bike ride', r->>'error' = 'ride_finished'
        and not (r ? 'reason') and (t_rides.ride(v_a)).distance_km = x.distance_km, r::text);
  -- the replacement ride (started offline from its first point) takes the replacement points
  perform t_rides.at(u, t + 5400 + 600 + 3600 + 60);
  r := public.start_user_trip_from(b2, t + 5400);
  v_b := (r->>'id')::uuid;
  perform t_rides.chk('SW2 replacement ride from its first offline point', r->>'success' = 'true' and (r->>'booking_id')::uuid = b2
        and (t_rides.ride(v_b)).started_at = to_timestamp(t + 5400), r::text);
  r := public.append_ride_track(v_b, post, null);
  perform t_rides.chk('SW2 replacement km in the replacement ride', r->>'success' = 'true' and (r->>'dropped')::int = 0
        and t_rides.near((t_rides.ride(v_b)).distance_km, 119 * 0.0555975, 0.05), r::text);
  perform public.finish_user_ride(v_b, '[]'::jsonb, null);
end $$;

do $$
declare u uuid := t_rides.u(44); e float8 := t_rides.ep('2026-12-01 09:00'); t float8; b uuid; b2 uuid; r jsonb;
  v_a uuid; v_b uuid; x public.user_rides; km1 numeric;
begin
  -- SW3: released app 4.1.3 ONLINE after the swap: keeps appending to the broken bike's ride
  b := t_rides.booking(44, u, '2026-12-01', '2026-12-04');
  perform t_rides.at(u, e);
  v_a := (public.start_user_ride(b, 49.0, 16.9)->>'id')::uuid;
  perform t_rides.feed(u, v_a, t_rides.line(49.0005, 60, 0.0005, e + 5, 5, 40));
  km1 := (t_rides.ride(v_a)).distance_km;
  t := e + 1800;
  b2 := t_rides.sos_swap(b, 44, u, t);
  perform t_rides.at(u, t + 420);
  r := public.append_ride_track(v_a, t_rides.line(49.1, 20, 0.0005, t + 300, 5, 40), null);
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW3 4.1.3: replacement points → ride_finished (4.1.3 forgets), closed ≤ swap', r->>'error' = 'ride_finished'
        and r->>'finished' = 'true' and not x.is_recording and x.ended_at <= to_timestamp(t) and x.distance_km = km1,
        format('%s end %s km %s', r, x.ended_at, x.distance_km));
  r := public.start_user_ride(b2, 49.1, 16.9);
  v_b := (r->>'id')::uuid;
  perform t_rides.chk('SW3 4.1.3: next start → new ride paired with the replacement', r->>'success' = 'true'
        and r->>'resumed' = 'false' and (r->>'booking_id')::uuid = b2 and v_b <> v_a, r::text);
  r := public.append_ride_track(v_b, t_rides.line(49.1, 20, 0.0005, t + 425, 5, 40), null);
  perform t_rides.chk('SW3 4.1.3: replacement ride records', r->>'success' = 'true' and (r->>'dropped')::int = 0, r::text);
  perform public.finish_user_ride(v_b, '[]'::jsonb, null);
end $$;

do $$
declare u uuid := t_rides.u(45); e float8 := t_rides.ep('2026-12-01 09:00'); t float8; b uuid; b2 uuid; r jsonb;
  v_a uuid; v_b uuid; x public.user_rides; km1 numeric;
begin
  -- SW4: 4.1.3 restarted after the swap while the broken bike's ride is still open (phone offline):
  -- start_user_ride(replacement) closes it at the swap and starts the replacement ride; late points
  -- (2 min clock grace) still land in the broken bike's ride
  b := t_rides.booking(45, u, '2026-12-01', '2026-12-04');
  perform t_rides.at(u, e);
  v_a := (public.start_user_ride(b, 48.9, 16.9)->>'id')::uuid;
  perform t_rides.feed(u, v_a, t_rides.line(48.9005, 60, 0.0005, e + 5, 5, 40));
  km1 := (t_rides.ride(v_a)).distance_km;
  t := e + 1800;
  b2 := t_rides.sos_swap(b, 45, u, t);
  perform t_rides.at(u, t + 600);
  r := public.start_user_ride(b2, 48.95, 16.9);
  v_b := (r->>'id')::uuid;
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW4 4.1.3 restart: broken bike ride NOT resumed, closed ≤ swap (closed_by start)', r->>'success' = 'true'
        and r->>'resumed' = 'false' and v_b <> v_a and (r->>'booking_id')::uuid = b2 and not x.is_recording
        and x.ended_at <= to_timestamp(t) and x.stats_state->>'closed_by' = 'start',
        format('%s end %s by %s', r, x.ended_at, x.stats_state->>'closed_by'));
  r := public.append_ride_track(v_a, t_rides.line(48.94, 40, 0.0005, t - 160, 5, 40), null);   -- t-160 … t+35
  x := t_rides.ride(v_a);
  perform t_rides.chk('SW4 4.1.3 late points up to the swap (+2 min) kept', r->>'error' = 'ride_finished'
        and r->>'reason' = 'booking_ended' and x.distance_km > km1 + 2 and x.last_fix_at = to_timestamp(t + 35)
        and x.ended_at <= to_timestamp(t + 155), format('km %s (%s) fix %s end %s', x.distance_km, km1, x.last_fix_at, x.ended_at));
  perform public.finish_user_ride(v_b, '[]'::jsonb, null);
end $$;

-- ───────────── SK: 4.1.3 start with lat/lng (server-stamped P0), phone clock behind the server ─────────────
create function t_rides.skew_ride(p_uid uuid, p_e float8, p_skew float8) returns uuid language plpgsql as $$
declare v_id uuid; b int;
begin
  perform t_rides.at(p_uid, p_e);
  v_id := (public.start_user_ride(null, 49.2, 16.6)->>'id')::uuid;
  -- 30 min at 54 km/h, 18 batches of 20 points every 5 s, stamped with the phone clock (server + p_skew)
  for b in 0..17 loop
    perform t_rides.at(p_uid, p_e + 5 + (b * 20 + 19) * 5 + 5);
    perform public.append_ride_track(v_id, (select jsonb_agg(jsonb_build_array(round((49.2 + (b * 20 + i) * 0.00075)::numeric, 7), 16.6,
            p_e + 5 + p_skew + (b * 20 + i) * 5, 54, 300) order by i) from generate_series(0, 19) i), null);
  end loop;
  return v_id;
end $$;

do $$
declare u uuid := t_rides.u(60); e float8 := t_rides.ep('2026-12-02 09:00'); v_id uuid; x public.user_rides; y public.user_rides; r jsonb;
begin
  v_id := t_rides.skew_ride(u, e, 0);
  y := t_rides.ride(v_id);
  perform public.finish_user_ride(v_id, '[]'::jsonb, null);
  v_id := t_rides.skew_ride(u, e + 7200, -600);
  x := t_rides.ride(v_id);
  perform t_rides.chk('SK1 4.1.3, phone 10 min behind: all km kept (as with an exact clock)', t_rides.near(x.distance_km, y.distance_km, 0.1)
        and x.distance_km > 29.5 and x.moving_sec >= 1790, format('km %s (exact clock %s) moving %s', x.distance_km, y.distance_km, x.moving_sec));
  perform t_rides.chk('SK1 server-stamped start point replaced by the phone points', jsonb_array_length(x.track) = 360
        and (x.track->0->>2)::float8 = e + 7200 + 5 - 600 and jsonb_array_length(y.track) = 361,
        format('pts %s first %s (exact %s)', jsonb_array_length(x.track), x.track->0->>2, jsonb_array_length(y.track)));
  r := public.append_ride_track(v_id, (select jsonb_agg(jsonb_build_array(round((49.2 + i * 0.00075)::numeric, 7), 16.6,
          e + 7200 + 5 - 600 + i * 5, 54, 300) order by i) from generate_series(0, 19) i), null);
  perform t_rides.chk('SK2 first batch re-sent → still a duplicate', (r->>'dropped')::int = 20
        and (t_rides.ride(v_id)).distance_km = x.distance_km, r::text);
  perform t_rides.at(u, e + 7200 + 1900);
  r := public.finish_user_ride(v_id, '[]'::jsonb, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('SK3 finish keeps the ride, duration ≥ moving', r->>'success' = 'true' and r->>'discarded' = 'false'
        and x.duration_min * 60 + 30 >= x.moving_sec, format('%s dur %s mv %s', r, x.duration_min, x.moving_sec));
end $$;

-- (O runs crons far in the future → placed after every block that still needs open rides.)
-- ───────────── O: long offline (no mobile data) — nothing lost, nothing split (SPEC §20.12, §23) ─────────────
do $$
declare u uuid := t_rides.u(31); e float8 := t_rides.ep('2026-10-23 08:00'); r jsonb; r2 jsonb; v_id uuid; x public.user_rides;
  km_on numeric; c1 jsonb := '[]'; c2 jsonb := '[]'; c3 jsonb; pts jsonb; d int; lat float8 := 49.2; st float8; ep record; ne int;
begin
  -- O1: own 5-day trip, mobile data OFF after the first hour (roaming) — the cron closes it after 72 h
  perform t_rides.at(u, e);
  v_id := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(u, v_id, jsonb_build_array(jsonb_build_array(lat, 16.6, e + 5, 0), jsonb_build_array(lat + 0.0001, 16.6, e + 200, -1))
                                || t_rides.line(lat + 0.0006, 100, 0.0005, e + 205, 5, 40));
  km_on := (t_rides.ride(v_id)).distance_km;
  lat := lat + 0.0006 + 100 * 0.0005;
  for d in 0..3 loop                                   -- 23.10 afternoon, 24., 25., 26.10 stay in the phone
    st := t_rides.ep('2026-10-23 13:00') + d * 86400;
    pts := jsonb_build_array(jsonb_build_array(lat + 0.0001, 16.6, st, -1)) || t_rides.line(lat + 0.0006, 200, 0.0005, st + 5, 5, 40);
    lat := lat + 0.0006 + 200 * 0.0005;
    if d < 2 then c1 := c1 || pts; else c2 := c2 || pts; end if;
  end loop;
  st := t_rides.ep('2026-10-27 08:00');
  c3 := jsonb_build_array(jsonb_build_array(lat + 0.0001, 16.6, st, -1)) || t_rides.line(lat + 0.0006, 80, 0.0005, st + 5, 5, 40);
  perform t_rides.at(null, e + 700 + 73 * 3600);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id);
  perform t_rides.chk('O1 cron closed the silent own trip (72 h)', not x.is_recording and x.stats_state->>'closed_by' = 'cron'
        and x.name = '23.10.2026' and x.distance_km = km_on, format('%s %s %s', x.is_recording, x.stats_state->>'closed_by', x.name));
  -- back online on 27.10: the buffer goes in 2 chunks (oldest first)
  perform t_rides.at(u, t_rides.ep('2026-10-27 09:00'));
  r := public.append_ride_track(v_id, c1, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('O1 first chunk re-opens the trip (normal success + reopened)', r->>'success' = 'true' and r->>'reopened' = 'true'
        and x.is_recording and x.ended_at is null and not (coalesce(x.stats_state, '{}') ? 'closed_by') and x.name = '', r::text);
  perform t_rides.chk('O1 offline days 1–2 counted', t_rides.near(x.distance_km, km_on + 2 * 200 * 0.0555975, 0.05),
        format('km %s online %s', x.distance_km, km_on));
  r := public.append_ride_track(v_id, c2, null);
  perform t_rides.chk('O1 second chunk: plain success (no reopen needed)', r->>'success' = 'true' and not (r ? 'reopened'), r::text);
  r2 := public.append_ride_track(v_id, c2, null);
  perform t_rides.chk('O1 same chunk again: dropped, nothing doubled', (r2->>'dropped')::int = jsonb_array_length(c2)
        and (r2->>'distance_km')::numeric = (r->>'distance_km')::numeric, r2::text);
  perform t_rides.at(u, t_rides.ep('2026-10-27 09:00') + 60);
  perform public.close_stale_user_rides();
  perform t_rides.chk('O1 reopened trip not closed again by the next cron pass', (t_rides.ride(v_id)).is_recording);
  r := public.finish_user_ride(v_id, c3, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('O1 one ride, all days kept (Σ km = truth)', (select count(*) from public.user_rides where user_id = u) = 1
        and t_rides.near(x.distance_km, km_on + 4 * 200 * 0.0555975 + 80 * 0.0555975, 0.08),
        format('km %s', x.distance_km));
  perform t_rides.chk('O1 Stop: closed_by user, name 23.10.–27.10.2026, 5 days', not x.is_recording and x.stats_state->>'closed_by' = 'user'
        and x.name = '23.10.–27.10.2026' and (r->>'days')::int = 5 and r->>'discarded' = 'false', r::text);
  perform t_rides.chk('O1 nights are pauses, duration = elapsed − pauses', x.pause_sec >= 3 * 12 * 3600 and x.idle_sec < 600
        and abs(x.duration_min * 60 - (extract(epoch from x.ended_at - x.started_at) - x.pause_sec)) <= 60,
        format('pause %s idle %s dur %s', x.pause_sec, x.idle_sec, x.duration_min));
  select count(*) into ne from public.user_ride_points where ride_id = v_id and kind = 'end';
  select p.lat, p.happened_at into ep from public.user_ride_points p where p.ride_id = v_id and p.kind = 'end';
  perform t_rides.chk('O1 one end point, moved to the real end', ne = 1 and ep.happened_at = x.ended_at
        and t_rides.near(ep.lat::numeric, (lat + 0.0006 + 79 * 0.0005)::numeric, 0.00001), format('%s %s', ne, ep::text));
  r := public.append_ride_track(v_id, c1, null);
  perform t_rides.chk('O1 after Stop the trip never re-opens', r->>'error' = 'ride_finished' and not (t_rides.ride(v_id)).is_recording, r::text);
end $$;

do $$
declare e float8 := t_rides.ep('2026-10-20 08:00'); r jsonb; v1 uuid; v2 uuid; x public.user_rides; km1 numeric; n2 int;
  late jsonb := t_rides.line(49.5, 20, 0.0005, t_rides.ep('2026-10-20 08:00') + 3000, 5, 40);
begin
  -- O2: cron-closed own trip, but the rider already has ANOTHER open ride → no re-open (unique index safe)
  perform t_rides.at(t_rides.u(32), e);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(32), v1, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40));
  perform t_rides.at(null, e + 400 + 73 * 3600);  perform public.close_stale_user_rides();
  km1 := (t_rides.ride(v1)).distance_km;
  perform t_rides.at(t_rides.u(32), e + 74 * 3600);  v2 := (public.start_user_trip(null)->>'id')::uuid;
  perform public.append_ride_track(v2, jsonb_build_array(jsonb_build_array(49.6, 16.6, e + 74 * 3600 - 5, 0)), null);
  n2 := jsonb_array_length((t_rides.ride(v2)).track);
  perform t_rides.at(t_rides.u(32), e + 75 * 3600);
  r := public.append_ride_track(v1, late, null);
  x := t_rides.ride(v1);
  perform t_rides.chk('O2 other open ride → old trip stays closed (ride_finished)', r->>'error' = 'ride_finished' and not x.is_recording
        and x.distance_km = km1 and (t_rides.ride(v2)).is_recording and v2 <> v1
        and jsonb_array_length((t_rides.ride(v2)).track) = n2, r::text);
  perform public.finish_user_ride(v2, '[]'::jsonb, null);
  -- O3: own trip ended by the rider (Stop) never re-opens
  perform t_rides.at(t_rides.u(33), e);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(33), v1, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40));
  perform t_rides.at(t_rides.u(33), e + 900);  perform public.finish_user_ride(v1, '[]'::jsonb, null);
  km1 := (t_rides.ride(v1)).distance_km;
  perform t_rides.at(t_rides.u(33), e + 75 * 3600);
  r := public.append_ride_track(v1, late, null);
  perform t_rides.chk('O3 own trip stopped by the rider: newer points ignored', r->>'error' = 'ride_finished'
        and not (t_rides.ride(v1)).is_recording and (t_rides.ride(v1)).distance_km = km1, r::text);
  -- O4: 4.1.3 own ride (not pause-aware) closed by the 3 h rule: unchanged, no re-open
  perform t_rides.at(t_rides.u(34), e);  v1 := (public.start_user_ride(null, 49.4, 16.6)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(34), v1, t_rides.line(49.4005, 40, 0.0005, e + 10, 5, 40));
  perform t_rides.at(null, e + 400 + 3 * 3600 + 600);  perform public.close_stale_user_rides();
  km1 := (t_rides.ride(v1)).distance_km;
  perform t_rides.at(t_rides.u(34), e + 4 * 3600);
  r := public.append_ride_track(v1, late, null);
  perform t_rides.chk('O4 4.1.3 own ride closed by cron: ride_finished as today', r->>'error' = 'ride_finished'
        and not (r ? 'reason') and not (t_rides.ride(v1)).is_recording and (t_rides.ride(v1)).distance_km = km1
        and (t_rides.ride(v1)).stats_state->>'closed_by' = 'cron', r::text);
  -- O5: started more than 30 days ago → no re-open
  perform t_rides.at(t_rides.u(35), e);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(35), v1, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40));
  perform t_rides.at(null, e + 400 + 73 * 3600);  perform public.close_stale_user_rides();
  perform t_rides.at(t_rides.u(35), e + 31 * 86400);
  r := public.append_ride_track(v1, late, null);
  perform t_rides.chk('O5 trip older than 30 days: no re-open', r->>'error' = 'ride_finished' and not (t_rides.ride(v1)).is_recording, r::text);
  -- O6: only already stored (repeated) or future points → no re-open; O7: foreign caller → not found
  perform t_rides.at(t_rides.u(36), e);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(36), v1, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40));
  perform t_rides.at(null, e + 400 + 73 * 3600);  perform public.close_stale_user_rides();
  km1 := (t_rides.ride(v1)).distance_km;
  perform t_rides.at(t_rides.u(36), e + 75 * 3600);
  r := public.append_ride_track(v1, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40), null);
  perform t_rides.chk('O6 repeated old batch: no re-open', r->>'error' = 'ride_finished' and not (t_rides.ride(v1)).is_recording
        and (t_rides.ride(v1)).distance_km = km1, r::text);
  r := public.append_ride_track(v1, t_rides.line(49.45, 5, 0.0005, e + 76 * 3600, 5, 40), null);
  perform t_rides.chk('O6 points from the future only: no re-open', r->>'error' = 'ride_finished' and not (t_rides.ride(v1)).is_recording, r::text);
  perform t_rides.at(t_rides.u(37), e + 75 * 3600);
  r := public.append_ride_track(v1, late, null);
  perform t_rides.chk('O7 another user cannot touch it', r->>'error' = 'ride_not_found' and not (t_rides.ride(v1)).is_recording
        and (t_rides.ride(v1)).stats_state->>'closed_by' = 'cron', r::text);
  -- O8: Stop (finish) with the offline buffer re-opens, stores it and closes as the rider's Stop
  perform t_rides.at(t_rides.u(38), e);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.feed(t_rides.u(38), v1, t_rides.line(49.4, 40, 0.0005, e + 10, 5, 40));
  perform t_rides.at(null, e + 400 + 73 * 3600);  perform public.close_stale_user_rides();
  km1 := (t_rides.ride(v1)).distance_km;
  perform t_rides.at(t_rides.u(38), e + 75 * 3600);
  r := public.finish_user_ride(v1, t_rides.line(49.4202, 100, 0.0005, e + 3000, 5, 40), null);
  x := t_rides.ride(v1);
  perform t_rides.chk('O8 finish with the buffer: re-opened, km added, closed_by user', r->>'success' = 'true'
        and r->>'discarded' = 'false' and not (r ? 'already_finished') and not x.is_recording
        and x.stats_state->>'closed_by' = 'user' and x.distance_km > km1 + 5
        and (select count(*) from public.user_ride_points where ride_id = v1 and kind = 'end') = 1, r::text);
end $$;

do $$
declare e float8 := t_rides.ep('2026-10-10 08:00'); u uuid := t_rides.u(39); r jsonb; v1 uuid; x public.user_rides; n int;
begin
  -- O9: own trip started on hotel Wi-Fi (P0 only on the server), then days without data:
  --     < 1 km → the 72 h rule does NOT delete it; the buffer lands later
  perform t_rides.at(u, e);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.at(u, e + 6);
  perform public.append_ride_track(v1, jsonb_build_array(jsonb_build_array(49.1, 16.6, e + 5, 0)), null);
  perform t_rides.at(null, e + 73 * 3600);  perform public.close_stale_user_rides();
  perform t_rides.at(null, e + 10 * 86400); perform public.close_stale_user_rides();
  perform t_rides.chk('O9 own trip < 1 km kept open past 72 h (offline right after the start)',
        (t_rides.ride(v1)).is_recording, coalesce((t_rides.ride(v1)).id::text, 'deleted'));
  perform t_rides.at(u, e + 10 * 86400 + 60);
  r := public.append_ride_track(v1, jsonb_build_array(jsonb_build_array(49.1001, 16.6, e + 600, -1))
                                    || t_rides.line(49.1006, 200, 0.0005, e + 605, 5, 40)
                                    || jsonb_build_array(jsonb_build_array(49.2001, 16.6, e + 86400, -1))
                                    || t_rides.line(49.2006, 200, 0.0005, e + 86405, 5, 40), null);
  x := t_rides.ride(v1);
  perform t_rides.chk('O9 late buffer stored (2 days, ~22 km)', r->>'success' = 'true' and x.is_recording
        and t_rides.near(x.distance_km, 2 * 200 * 0.0555975, 0.05) and x.started_at = to_timestamp(e + 600), r::text);
  perform t_rides.at(null, e + 10 * 86400 + 73 * 3600);  perform public.close_stale_user_rides();
  x := t_rides.ride(v1);
  perform t_rides.chk('O9 then closed by cron as a normal trip (kept, 2 days)', not x.is_recording and x.distance_km >= 1
        and x.stats_state->>'closed_by' = 'cron' and x.name = '10.10.–11.10.2026', coalesce(x.name, 'deleted'));
  -- O9b: < 1 km own trip still empty after 30 days → deleted as before (junk)
  perform t_rides.at(u, e + 15 * 86400);  v1 := (public.start_user_trip(null)->>'id')::uuid;
  perform t_rides.at(u, e + 15 * 86400 + 6);
  perform public.append_ride_track(v1, jsonb_build_array(jsonb_build_array(49.1, 16.6, e + 15 * 86400 + 5, 0)), null);
  perform t_rides.at(null, e + 44 * 86400);  perform public.close_stale_user_rides();
  perform t_rides.chk('O9b still empty after 29 days → open', (t_rides.ride(v1)).is_recording);
  perform t_rides.at(null, e + 46 * 86400);  r := public.close_stale_user_rides();
  select count(*) into n from public.user_rides where id = v1;
  perform t_rides.chk('O9b empty own trip after 30 days → deleted (discarded)', n = 0 and (r->>'discarded')::int >= 1, r::text);
end $$;

do $$
declare u uuid := t_rides.u(40); e1 float8 := t_rides.ep('2026-10-24 09:00'); d2 float8 := t_rides.ep('2026-10-25 08:00');
  ret float8 := t_rides.ep('2026-10-25 18:00'); b uuid; r jsonb; v_id uuid; x public.user_rides; late jsonb; n int;
begin
  -- O10: one-day roaming-off rental: no data right after pickup (P0 only), kiosk return, cron —
  --      the ride must survive until the phone reaches Wi-Fi (was: deleted 10 min after the return)
  b := t_rides.booking(40, u, '2026-10-24', '2026-10-25');
  perform t_rides.at(u, e1);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.at(u, e1 + 6);
  perform public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.7, 16.6, e1 + 5, 0)), null);
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(ret), status = 'completed' where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(null, ret + 660);  perform public.close_stale_user_rides();
  perform t_rides.at(null, ret + 3 * 86400);  perform public.close_stale_user_rides();
  perform t_rides.chk('O10 returned rental < 1 km kept open (not deleted) 3 days after the return',
        (t_rides.ride(v_id)).is_recording, coalesce((t_rides.ride(v_id)).id::text, 'deleted'));
  late := jsonb_build_array(jsonb_build_array(49.7001, 16.6, e1 + 3600, -1)) || t_rides.line(49.7006, 200, 0.0005, e1 + 3605, 5, 40)
       || jsonb_build_array(jsonb_build_array(49.8001, 16.6, d2, -1)) || t_rides.line(49.8006, 200, 0.0005, d2 + 5, 5, 40)
       || t_rides.line(49.95, 3, 0.0005, ret + 300, 10, 60);                         -- car after the return
  perform t_rides.at(u, ret + 3 * 86400 + 3600);
  r := public.append_ride_track(v_id, late, null);
  x := t_rides.ride(v_id);
  perform t_rides.chk('O10 phone online 3 days later: both rental days stored, car points not', r->>'success' = 'true'
        and (r->>'dropped')::int = 3 and t_rides.near(x.distance_km, 2 * 200 * 0.0555975, 0.05), r::text);
  perform t_rides.at(null, ret + 3 * 86400 + 4000);  perform public.close_stale_user_rides();
  x := t_rides.ride(v_id);
  perform t_rides.chk('O10 next cron pass closes it with the real km (≤ return, 2 days)', not x.is_recording
        and x.stats_state->>'closed_by' = 'cron' and x.ended_at <= to_timestamp(ret) and x.name = '24.10.–25.10.2026'
        and t_rides.near(x.distance_km, 2 * 200 * 0.0555975, 0.05), format('%s %s %s', x.ended_at, x.name, x.distance_km));
  -- O10b: P0-only rental never synced → deleted 7 days after the return (junk, as before)
  b := t_rides.booking(41, t_rides.u(41), '2026-10-24', '2026-10-25');
  perform t_rides.at(t_rides.u(41), e1);
  v_id := (public.start_user_trip(b)->>'id')::uuid;
  perform t_rides.at(t_rides.u(41), e1 + 6);
  perform public.append_ride_track(v_id, jsonb_build_array(jsonb_build_array(49.7, 16.9, e1 + 5, 0)), null);
  perform set_config('session_replication_role', 'replica', true);
  update public.bookings set returned_at = to_timestamp(ret), status = 'completed' where id = b;
  perform set_config('session_replication_role', 'origin', true);
  perform t_rides.at(null, ret + 7 * 86400 - 600);  perform public.close_stale_user_rides();
  perform t_rides.chk('O10b still open just before 7 days', (t_rides.ride(v_id)).is_recording);
  perform t_rides.at(null, ret + 7 * 86400 + 600);  r := public.close_stale_user_rides();
  select count(*) into n from public.user_rides where id = v_id;
  perform t_rides.chk('O10b deleted 7 days after the return (< 1 km)', n = 0 and (r->>'discarded')::int >= 1, r::text);
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
do $$
declare u uuid := t_rides.u(19); e float8 := t_rides.ep('2026-09-12 08:00'); tr jsonb;
begin
  -- L7: 4.1.3 night with the phone still sending points (drift < 3 km/h every minute, NO silence ≥ 5 min)
  tr := t_rides.line(49.0, 20, 0.001, e, 5, 60)
     || (select jsonb_agg(jsonb_build_array(round((49.019 + (i % 3) * 0.00003)::numeric, 7), 16.6, e + 95 + 60 * i, 0) order by i)
           from generate_series(1, 600) i)
     || t_rides.line(49.02, 20, 0.001, e + 36155, 5, 60);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L7', tr, to_timestamp(e), to_timestamp(e + 36250), false, 4.3, 310, 35940, 0, 604);
  -- L8: short stops only (4 min standing with points) → nothing to convert, values kept
  tr := t_rides.line(49.1, 20, 0.001, e, 5, 60)
     || (select jsonb_agg(jsonb_build_array(49.1195, 16.6, e + 95 + 30 * i, 0) order by i) from generate_series(1, 8) i)
     || t_rides.line(49.12, 20, 0.001, e + 365, 5, 60);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L8', tr, to_timestamp(e), to_timestamp(e + 460), false, 4.3, 220, 240, 0, 8);
end $$;
do $$
declare u uuid := t_rides.u(19); e float8 := t_rides.ep('2026-09-11 08:00'); tr jsonb;
begin
  -- Tail after the last point (old finish_user_ride closed an own ride at now() → a late Stop was „stání").
  -- L10 (S10): 1 h ride, Stop 3 h after the last point → old duration 240 min, idle 3 h
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L10', t_rides.line(49.4, 721, 0.00075, e, 5, 60), to_timestamp(e), to_timestamp(e + 14400), false,
          60, 3600, 10800, 0, 240);
  -- L11: phone clock 2 h BEHIND, 4 min stop mid-ride, Stop 1 min after the last point → nothing to move
  tr := t_rides.line(49.6, 361, 0.00075, e - 7200, 5, 60)
     || (select jsonb_agg(jsonb_build_array(49.87, 16.6, e - 7200 + 1800 + 30 * i, 0) order by i) from generate_series(1, 8) i)
     || t_rides.line(49.87, 361, 0.00075, e - 7200 + 2045, 5, 60);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L11', tr, to_timestamp(e), to_timestamp(e + 3905), false, 60, 3600, 305, 0, 65);
  -- L12: Stop 4 min after the last point (tail beyond the 2-min rule < 5 min) → stays a stop
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L12', t_rides.line(49.2, 721, 0.00075, e, 5, 60), to_timestamp(e), to_timestamp(e + 3840), false,
          60, 3600, 240, 0, 64);
  -- L13: 30 min ride, 10 min standing with points (still run → pause), Stop 1 h after the last point
  tr := t_rides.line(49.5, 361, 0.00075, e, 5, 60)
     || (select jsonb_agg(jsonb_build_array(49.77, 16.6, e + 1800 + 30 * i, 0) order by i) from generate_series(1, 20) i);
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L13', tr, to_timestamp(e), to_timestamp(e + 6000), false, 30, 1800, 4200, 0, 100);
end $$;
-- @@BACKFILL@@
do $$
declare u uuid := t_rides.u(19); x public.user_rides; j jsonb; n int;
begin
  select * into x from public.user_rides where user_id = u and name = 'L7';
  perform t_rides.chk('L7 4.1.3 night sent as standing points → pause, na cestě 5 min', x.pause_sec = 35940
        and x.duration_min = 5 and x.idle_sec = 0 and x.gap_sec = 0 and x.distance_km = 4.3 and x.moving_sec = 310
        and x.stats_state->>'backfill' = '1', format('p %s d %s i %s g %s', x.pause_sec, x.duration_min, x.idle_sec, x.gap_sec));
  select * into x from public.user_rides where user_id = u and name = 'L8';
  perform t_rides.chk('L8 short stop (< 5 min) stays a stop, values unchanged', x.pause_sec = 0 and x.idle_sec = 240
        and x.duration_min = 8 and x.stats_state->>'backfill' = '1', format('p %s d %s i %s', x.pause_sec, x.duration_min, x.idle_sec));
  -- L9: a legacy ride closed AFTER the backfill without any new batch keeps stats_state NULL
  insert into public.user_rides (user_id, name, track, started_at, ended_at, is_recording, distance_km, moving_sec,
                                 idle_sec, gap_sec, duration_min)
  values (u, 'L9', t_rides.line(49.3, 20, 0.001, t_rides.ep('2026-09-13 08:00'), 5, 60),
          to_timestamp(t_rides.ep('2026-09-13 08:00')), to_timestamp(t_rides.ep('2026-09-13 08:00') + 95), false, 2.1, 95, 0, 0, 2);
  -- stats_v2 in every ride read: same rule as Velín rideStatsV2 (recording or stats_state set)
  perform t_rides.at(u, t_rides.ep('2026-09-14 08:00'));
  j := public.get_my_rides(100);
  perform t_rides.chk('M1 stats_v2: backfilled old ride → true', (select (q->>'stats_v2')::boolean from jsonb_array_elements(j) q
        where q->>'name' = 'L7'), j::text);
  perform t_rides.chk('M2 stats_v2: old ride without stats_state → false (old labels)', (select (q->>'stats_v2')::boolean
        from jsonb_array_elements(j) q where q->>'name' = 'L9') = false);
  perform t_rides.chk('M3 stats_v2: recording ride → true', (select (q->>'stats_v2')::boolean from jsonb_array_elements(j) q
        where q->>'name' = 'L4'));
  perform t_rides.chk('M4 stats_v2 present on every ride', (select bool_and(q ? 'stats_v2') from jsonb_array_elements(j) q));
end $$;
do $$
declare u uuid := t_rides.u(19); x public.user_rides;
begin
  select * into x from public.user_rides where user_id = u and name = 'L1';
  perform t_rides.chk('L1 night → pause 10 h, na cestě 3 min', x.pause_sec = 36000 and x.duration_min = 3
        and x.idle_sec = 0 and x.gap_sec = 0 and x.stats_state->>'backfill' = '1' and x.distance_km = 4.3
        and x.stats_state->'old' = '{"duration_min": 603, "idle_sec": 36000, "gap_sec": 0}'::jsonb,
        format('p %s d %s i %s g %s', x.pause_sec, x.duration_min, x.idle_sec, x.gap_sec));
  select * into x from public.user_rides where user_id = u and name = 'L2';
  perform t_rides.chk('L2 slow 2 h “gap” → pause, gap 0', x.pause_sec = 7200 and x.gap_sec = 0 and x.duration_min = 3,
        format('p %s g %s d %s', x.pause_sec, x.gap_sec, x.duration_min));
  select * into x from public.user_rides where user_id = u and name = 'L3';
  perform t_rides.chk('L3 real gap unchanged', x.pause_sec = 0 and x.gap_sec = 600 and x.duration_min = 13
        and x.stats_state->>'backfill' = '1', format('p %s g %s d %s', x.pause_sec, x.gap_sec, x.duration_min));
  select * into x from public.user_rides where user_id = u and name = 'L4';
  perform t_rides.chk('L4 open ride untouched', x.stats_state is null and x.pause_sec = 0);
  select * into x from public.user_rides where user_id = u and name = 'L5';
  perform t_rides.chk('L5 pause-aware ride untouched', x.stats_state = '{}'::jsonb and x.pause_sec = 0);
  select * into x from public.user_rides where user_id = u and name = 'L10';
  perform t_rides.chk('L10 Stop 3 h late → pause 3 h − 2 min, na cestě 62 min, zastávky 2 min', x.pause_sec = 10680
        and x.duration_min = 62 and x.idle_sec = 120 and x.gap_sec = 0 and x.moving_sec = 3600 and x.distance_km = 60
        and x.ended_at = to_timestamp(t_rides.ep('2026-09-11 08:00') + 14400) and x.stats_state->>'backfill' = '1',
        format('p %s d %s i %s g %s', x.pause_sec, x.duration_min, x.idle_sec, x.gap_sec));
  select * into x from public.user_rides where user_id = u and name = 'L11';
  perform t_rides.chk('L11 phone clock 2 h behind: no tail pause, values unchanged', x.pause_sec = 0
        and x.duration_min = 65 and x.idle_sec = 305 and x.gap_sec = 0 and x.stats_state->>'backfill' = '1',
        format('p %s d %s i %s g %s', x.pause_sec, x.duration_min, x.idle_sec, x.gap_sec));
  select * into x from public.user_rides where user_id = u and name = 'L12';
  perform t_rides.chk('L12 Stop 4 min late stays a stop, values unchanged', x.pause_sec = 0
        and x.duration_min = 64 and x.idle_sec = 240 and x.stats_state->>'backfill' = '1',
        format('p %s d %s i %s', x.pause_sec, x.duration_min, x.idle_sec));
  select * into x from public.user_rides where user_id = u and name = 'L13';
  perform t_rides.chk('L13 standing 10 min + Stop 1 h late → pause 68 min, na cestě 32 min', x.pause_sec = 4080
        and x.duration_min = 32 and x.idle_sec = 120 and x.gap_sec = 0,
        format('p %s d %s i %s g %s', x.pause_sec, x.duration_min, x.idle_sec, x.gap_sec));
  -- návrat přepočtu (snippet z hlavičky 06) vrátí původní hodnoty
  update public.user_rides set duration_min = (stats_state->'old'->>'duration_min')::int,
    idle_sec = (stats_state->'old'->>'idle_sec')::int, gap_sec = (stats_state->'old'->>'gap_sec')::int,
    pause_sec = 0, stats_state = null where user_id = u and stats_state ? 'backfill';
  select * into x from public.user_rides where user_id = u and name = 'L1';
  perform t_rides.chk('L6 backfill revert restores old values', x.duration_min = 603 and x.idle_sec = 36000
        and x.gap_sec = 0 and x.pause_sec = 0 and x.stats_state is null, format('d %s i %s', x.duration_min, x.idle_sec));
  select * into x from public.user_rides where user_id = u and name = 'L10';
  perform t_rides.chk('L6b backfill revert restores the late-Stop ride', x.duration_min = 240 and x.idle_sec = 10800
        and x.gap_sec = 0 and x.pause_sec = 0 and x.stats_state is null, format('d %s i %s', x.duration_min, x.idle_sec));
end $$;

do $$
declare n int;
begin
  -- Z1: invariant over every closed test ride — na cestě ≥ jízda + mezery (rounding to a minute)
  select count(*) into n from public.user_rides r
   where r.user_id in (select t_rides.u(k) from generate_series(1, 60) k) and not r.is_recording
     and r.duration_min * 60 + 30 < r.moving_sec + r.gap_sec;
  perform t_rides.chk('Z1 every closed ride: duration ≥ moving + gap', n = 0, n::text);
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
