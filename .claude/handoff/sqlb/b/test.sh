#!/usr/bin/env bash
# test.sh <db>  — group b (ride recording) tests on a database where the whole
# bundle (supabase/migrations/20261112b01..b08 and anything else) is applied.
# Loads timeshim + fixtures when missing, runs t_shim(), runs test_rides.sql
# TWICE (b08 backfill injected at "-- @@BACKFILL@@"), the two concurrency
# races, an optional gear data-fix check (only if seed_gearfix was loaded before
# the bundle: GEARFIX=1), and compares the stats vectors with the reference.
# Exit 0 = all passed. Local test cluster only (psql.sh = unix socket).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RIG="$HERE/../pg"
DB="${1:?usage: test.sh <db>}"
MIG="${MIG:-/home/user/Vel-n/supabase/migrations/20261112b08_rides_backfill.sql}"
OUT="$HERE/out/$DB"; mkdir -p "$OUT"
PSQL() { "$RIG/psql.sh" "$DB" -X -q -v ON_ERROR_STOP=1 "$@"; }

if [ "$(PSQL -At -c "select count(*) from pg_proc where proname = 't_shim'")" = 0 ]; then
  PSQL < "$RIG/timeshim.sql" >/dev/null
  PSQL < "$RIG/fixtures.sql" >/dev/null
fi
[ "$(PSQL -At -c "select count(*) from pg_proc where proname = 'start_user_trip'")" = 1 ] \
  || { echo "bundle b not applied in $DB"; exit 1; }
PSQL -At -c "select 'shimmed: ' || public.t_shim()"

if [ "${GEARFIX:-0}" = 1 ]; then
  G1=$(PSQL -At -c "select count(*) from public.user_rides where id = 'ab000000-0000-0000-0000-0000000000c1' and booking_id is null")
  G2=$(PSQL -At -c "select count(*) from public.user_rides r join public.bookings b on b.id = r.booking_id where b.booking_kind = 'gear'")
  [ "$G1" = 1 ] && [ "$G2" = 0 ] && echo "GEAR DATA FIX OK" || { echo "GEAR DATA FIX FAILED ($G1/$G2)"; exit 1; }
fi

inject() {
  sed -n '1,/^-- @@BACKFILL@@/p' "$HERE/test_rides.sql"
  cat "$MIG"
  sed -n '/^-- @@BACKFILL@@/,$p' "$HERE/test_rides.sql" | tail -n +2
}
for run in 1 2; do
  inject | PSQL -f - > "$OUT/test_run$run.log" 2>&1 || { echo "TEST RUN $run FAILED"; tail -40 "$OUT/test_run$run.log"; exit 1; }
  S=$(grep -E '^ *SUMMARY' "$OUT/test_run$run.log" | head -1)
  echo "test run $run: $S"
  echo "$S" | grep -qE 'SUMMARY ([0-9]+)/\1 passed' || { grep -E '\| FAIL' "$OUT/test_run$run.log" | head; exit 1; }
done

UR='aa000000-0000-0000-0000-000000000099'
PSQL -c "set session_replication_role = replica;
  insert into auth.users (id, email, aud, role, created_at) values ('$UR','race@test.cz','authenticated','authenticated', now()) on conflict do nothing;
  delete from public.user_rides where user_id = '$UR';"
( printf "begin;\ninsert into public.user_rides (user_id, source, is_recording, pause_aware) values ('%s','auto',true,true);\nselect pg_sleep(2);\ncommit;\n" "$UR" | PSQL -f - >/dev/null ) &
sleep 0.7
RACE=$(PSQL -At -c "select public.t_set(now(), '$UR'); select public.start_user_trip(null);" | tail -1)
wait
NOPEN=$(PSQL -At -c "select count(*) from public.user_rides where user_id = '$UR' and is_recording")
echo "$RACE" | grep -q '"resumed": true' && [ "$NOPEN" = 1 ] && echo "RACE OK (resumed, 1 open ride)" || { echo "RACE FAILED: $RACE"; exit 1; }

UO='aa000000-0000-0000-0000-000000000098'
PTS="(select jsonb_agg(jsonb_build_array(49.3 + i * 0.0005, 16.6, extract(epoch from timestamptz '2026-10-01 08:00+00') + 10 + i * 5, 40) order by i) from generate_series(0, 39) i)"
NEW="(select jsonb_agg(jsonb_build_array(49.4 + i * 0.0005, 16.6, extract(epoch from timestamptz '2026-10-01 09:00+00') + i * 5, 40) order by i) from generate_series(0, 19) i)"
PSQL -c "set session_replication_role = replica;
  insert into auth.users (id, email, aud, role, created_at) values ('$UO','reopen@test.cz','authenticated','authenticated', now()) on conflict do nothing;
  delete from public.user_rides where user_id = '$UO';"
OLD=$(PSQL -At -c "select public.t_set('2026-10-01 08:00+00', '$UO'); select public.start_user_trip(null)->>'id';" | tail -1)
PSQL -At -c "select public.t_set('2026-10-01 08:04+00', '$UO'); select public.append_ride_track('$OLD', $PTS, null)->>'success';
  select public.t_set('2026-10-04 09:00+00'); select public.close_stale_user_rides();" >/dev/null
( printf "begin;\ninsert into public.user_rides (user_id, source, is_recording, pause_aware) values ('%s','auto',true,true);\nselect pg_sleep(2);\ncommit;\n" "$UO" | PSQL -f - >/dev/null ) &
sleep 0.7
REO=$(PSQL -At -c "select public.t_set('2026-10-04 10:00+00', '$UO'); select public.append_ride_track('$OLD', $NEW, null);" | tail -1)
wait
OPEN_OLD=$(PSQL -At -c "select is_recording from public.user_rides where id = '$OLD'")
NOPEN=$(PSQL -At -c "select count(*) from public.user_rides where user_id = '$UO' and is_recording")
echo "$REO" | grep -q '"ride_finished"' && [ "$OPEN_OLD" = f ] && [ "$NOPEN" = 1 ] \
  && echo "REOPEN RACE OK" || { echo "REOPEN RACE FAILED ($REO / $OPEN_OLD / $NOPEN)"; exit 1; }
REO2=$(PSQL -At -c "select public.t_set('2026-10-04 10:00+00', '$UO'); delete from public.user_rides where user_id = '$UO' and id <> '$OLD';
  select public.append_ride_track('$OLD', $NEW, null);" | tail -1)
echo "$REO2" | grep -q '"reopened": true' && echo "REOPEN OK after the competing ride is gone" || { echo "REOPEN FAILED: $REO2"; exit 1; }

PSQL -At -c "select jsonb_pretty(jsonb_agg(jsonb_build_object('id', id, 'points', points, 'legacy', legacy,
  'expect', jsonb_build_object('dist_km', (got->>'dist_km')::numeric, 'moving_sec', (got->>'moving_sec')::int,
  'gap_sec', (got->>'gap_sec')::int, 'pause_sec', (got->>'pause_sec')::int)) order by ord))
  from t_rides.vectors" > "$OUT/stats_vectors.json"
python3 -I -c "import json,sys; a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2])); sys.exit(0 if a==b else 1)" \
  "$OUT/stats_vectors.json" "$HERE/stats_vectors.ref.json" \
  && echo "STATS VECTORS identical to reference ($(grep -c '"id"' "$OUT/stats_vectors.json"))" || { echo "STATS VECTORS DIFFER"; diff "$HERE/stats_vectors.ref.json" "$OUT/stats_vectors.json" | head; exit 1; }
echo "ALL GROUP B TESTS PASSED"
