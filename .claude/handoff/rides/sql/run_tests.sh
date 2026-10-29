#!/usr/bin/env bash
# Ride-recording SQL drafts — full verification on a FRESH local PG16 cluster.
#   run_tests.sh            -> wipe /var/tmp/pg-rides, re-create DB from the live
#                              snapshot (pg/setup.sh), record ride-RPC signatures,
#                              apply 01..06 TWICE (single transaction each),
#                              t_shim, run test_rides.sql TWICE (06 injected at
#                              @@BACKFILL@@), concurrent start_user_trip race,
#                              signature diff, write stats_vectors.json.
#   FRESH=0 run_tests.sh    -> keep the cluster/DB, only re-apply + test.
# Never points at the live DB (unix socket of the local test cluster only).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PGT="$HERE/../pg"
BIN=/usr/lib/postgresql/16/bin
PGD=${PGD:-/var/tmp/pg-rides}
PORT=${PGPORT_RIDES:-5499}
OUT="$HERE/out"; mkdir -p "$OUT"
PSQL() { runuser -u postgres -- $BIN/psql -X -q -h $PGD/sock -p $PORT -U postgres -d rides -v ON_ERROR_STOP=1 "$@"; }
SIGQ="select p.proname || '(' || pg_get_function_arguments(p.oid) || ') -> ' || pg_get_function_result(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.proname like '%ride%' or p.proname like '%user_trip%') order by 1"

if [ "${FRESH:-1}" = 1 ]; then
  runuser -u postgres -- $BIN/pg_ctl -D $PGD/data -m fast stop >/dev/null 2>&1 || true
  rm -rf "$PGD"
  PGD="$PGD" PGPORT_RIDES="$PORT" bash "$PGT/setup.sh"
  PSQL -At -c "$SIGQ" > "$OUT/sig_before.txt"
  # Data fix (04): a ride linked to a GEAR-only booking before deployment must be detached.
  PSQL -c "set session_replication_role = replica;
    insert into auth.users (id, email, aud, role, created_at) values ('ab000000-0000-0000-0000-0000000000ab','gearfix@test.cz','authenticated','authenticated', now());
    insert into public.bookings (id, user_id, booking_kind, moto_id, start_date, end_date, status, gear_lines, gear_per_day)
      values ('ab000000-0000-0000-0000-0000000000b1','ab000000-0000-0000-0000-0000000000ab','gear',null,'2026-10-23','2026-10-25','active','[]',100);
    insert into public.user_rides (id, user_id, booking_id, track, is_recording, distance_km)
      values ('ab000000-0000-0000-0000-0000000000c1','ab000000-0000-0000-0000-0000000000ab','ab000000-0000-0000-0000-0000000000b1','[]',false,5);"
fi

t0=$(date +%s.%N)
for round in 1 2; do
  for f in "$HERE"/0[1-6]*.sql; do
    PSQL -1 -f - < "$f" > "$OUT/apply_${round}_$(basename "$f" .sql).log" 2>&1 \
      || { echo "APPLY FAILED round $round: $f"; cat "$OUT/apply_${round}_$(basename "$f" .sql).log"; exit 1; }
  done
  echo "applied all drafts ($(cd "$HERE" && ls 0[1-6]*.sql | tr "\n" " ")) round $round OK"
done
echo "apply time (2 rounds): $(echo "$(date +%s.%N) - $t0" | bc) s"
PSQL -At -c "$SIGQ" > "$OUT/sig_after.txt"
PSQL -At -c "select 'shimmed: ' || public.t_shim()"
GFIX=$(PSQL -At -c "select count(*) from public.user_rides where id = 'ab000000-0000-0000-0000-0000000000c1' and booking_id is null")
GLEFT=$(PSQL -At -c "select count(*) from public.user_rides r join public.bookings b on b.id = r.booking_id where b.booking_kind = 'gear'")
if [ "${FRESH:-1}" = 1 ]; then
  [ "$GFIX" = 1 ] && [ "$GLEFT" = 0 ] && echo "GEAR DATA FIX OK (pre-existing gear-linked ride detached, 0 left)" \
    || { echo "GEAR DATA FIX FAILED ($GFIX / $GLEFT)"; exit 1; }
fi

inject() {
  sed -n '1,/^-- @@BACKFILL@@/p' "$HERE/test_rides.sql"
  cat "$HERE/06_rides_backfill.sql"
  sed -n '/^-- @@BACKFILL@@/,$p' "$HERE/test_rides.sql" | tail -n +2
}
for run in 1 2; do
  t1=$(date +%s.%N)
  inject | PSQL -f - > "$OUT/test_run$run.log" 2>&1 || { echo "TEST RUN $run FAILED"; tail -60 "$OUT/test_run$run.log"; exit 1; }
  echo "test run $run: $(grep -E '^ *SUMMARY' "$OUT/test_run$run.log" | head -1)  ($(echo "$(date +%s.%N) - $t1" | bc) s)"
done

# Race: two sessions start_user_trip for a user with no open ride; session A
# inserts an open ride inside an open transaction first, B must wait on the
# unique index and then return the committed ride as resumed (no error).
UR='aa000000-0000-0000-0000-000000000099'
PSQL -c "set session_replication_role = replica;
  insert into auth.users (id, email, aud, role, created_at) values ('$UR','race@test.cz','authenticated','authenticated', now()) on conflict do nothing;
  delete from public.user_rides where user_id = '$UR';"
( printf "begin;\ninsert into public.user_rides (user_id, source, is_recording, pause_aware) values ('%s','auto',true,true);\nselect pg_sleep(2);\ncommit;\n" "$UR" | PSQL -f - >/dev/null ) &
sleep 0.7
RACE=$(PSQL -At -c "select public.t_set(now(), '$UR'); select public.start_user_trip(null);" | tail -1)
wait
echo "race result: $RACE"
NOPEN=$(PSQL -At -c "select count(*) from public.user_rides where user_id = '$UR' and is_recording")
echo "$RACE" | grep -q '"resumed": true' && [ "$NOPEN" = 1 ] && echo "RACE OK (resumed, 1 open ride)" || { echo "RACE FAILED"; exit 1; }

# Re-open race (SPEC §23): an own trip closed by the cron; session A inserts
# another open ride inside an open transaction, B sends newer points to the
# closed trip → B waits on the unique index, then must NOT re-open it (no
# error, ride_finished) and A's ride stays the only open one.
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
echo "reopen race result: $REO"
OPEN_OLD=$(PSQL -At -c "select is_recording from public.user_rides where id = '$OLD'")
NOPEN=$(PSQL -At -c "select count(*) from public.user_rides where user_id = '$UO' and is_recording")
echo "$REO" | grep -q '"ride_finished"' && [ "$OPEN_OLD" = f ] && [ "$NOPEN" = 1 ] \
  && echo "REOPEN RACE OK (closed trip stays closed, 1 open ride, no error)" || { echo "REOPEN RACE FAILED ($OPEN_OLD / $NOPEN)"; exit 1; }
# without the competing ride the same batch re-opens it
REO2=$(PSQL -At -c "select public.t_set('2026-10-04 10:00+00', '$UO'); delete from public.user_rides where user_id = '$UO' and id <> '$OLD';
  select public.append_ride_track('$OLD', $NEW, null);" | tail -1)
echo "$REO2" | grep -q '"reopened": true' && echo "REOPEN OK after the competing ride is gone" || { echo "REOPEN FAILED: $REO2"; exit 1; }

if [ -s "$OUT/sig_before.txt" ]; then
  echo "--- signature diff (existing ride functions; '>' = new names only) ---"
  diff "$OUT/sig_before.txt" "$OUT/sig_after.txt" || true
  if diff "$OUT/sig_before.txt" "$OUT/sig_after.txt" | grep -q '^<'; then echo "SIGNATURE CHANGED"; exit 1; fi
  echo "no existing signature changed"
fi

PSQL -At -c "select jsonb_pretty(jsonb_agg(jsonb_build_object('id', id, 'points', points, 'legacy', legacy,
  'expect', jsonb_build_object('dist_km', (got->>'dist_km')::numeric, 'moving_sec', (got->>'moving_sec')::int,
  'gap_sec', (got->>'gap_sec')::int, 'pause_sec', (got->>'pause_sec')::int)) order by ord))
  from t_rides.vectors" > "$HERE/stats_vectors.json"
echo "stats_vectors.json: $(grep -c '"id"' "$HERE/stats_vectors.json") vectors"
