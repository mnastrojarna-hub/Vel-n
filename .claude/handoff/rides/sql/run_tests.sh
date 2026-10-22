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
PGD=/var/tmp/pg-rides
OUT="$HERE/out"; mkdir -p "$OUT"
PSQL() { runuser -u postgres -- $BIN/psql -X -q -h $PGD/sock -p 5499 -U postgres -d rides -v ON_ERROR_STOP=1 "$@"; }
SIGQ="select p.proname || '(' || pg_get_function_arguments(p.oid) || ') -> ' || pg_get_function_result(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.proname like '%ride%' or p.proname like '%user_trip%') order by 1"

if [ "${FRESH:-1}" = 1 ]; then
  runuser -u postgres -- $BIN/pg_ctl -D $PGD/data -m fast stop >/dev/null 2>&1 || true
  rm -rf "$PGD"
  bash "$PGT/setup.sh"
  PSQL -At -c "$SIGQ" > "$OUT/sig_before.txt"
fi

t0=$(date +%s.%N)
for round in 1 2; do
  for f in "$HERE"/0[1-6]*.sql; do
    PSQL -1 -f - < "$f" > "$OUT/apply_${round}_$(basename "$f" .sql).log" 2>&1 \
      || { echo "APPLY FAILED round $round: $f"; cat "$OUT/apply_${round}_$(basename "$f" .sql).log"; exit 1; }
  done
  echo "applied all drafts (01, 02, 03a, 03b, 04, 05, 06) round $round OK"
done
echo "apply time (2 rounds): $(echo "$(date +%s.%N) - $t0" | bc) s"
PSQL -At -c "$SIGQ" > "$OUT/sig_after.txt"
PSQL -At -c "select 'shimmed: ' || public.t_shim()"

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
