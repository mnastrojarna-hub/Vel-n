#!/usr/bin/env bash
# Reusable PG16 test cluster for ride-recording SQL work (MotoGo24).
#   setup.sh            -> init (once) + start cluster, (re)create DB `rides`
#                          from the LIVE schema snapshot + stubs + time shim
#   setup.sh start      -> just start the cluster
#   setup.sh stop       -> stop it
#   setup.sh psql [...] -> psql into DB rides (as postgres superuser)
# Cluster: /var/tmp/pg-rides (owner postgres), port 5499, socket /var/tmp/pg-rides/sock
#   (override: PGD=/var/tmp/pg-xyz PGPORT_RIDES=5498 — separate cluster for parallel work)
# Schema source: git show origin/supabase-live-snapshot:supabase/_snapshot/*.sql
#   (copied to $HERE/snap/, refresh with SNAP_REFRESH=1).
# Load a draft (postgres cannot read the scratchpad, so feed via stdin):
#   setup.sh psql -v ON_ERROR_STOP=1 < draft.sql   (twice = idempotency check)
#   setup.sh psql -c 'select public.t_shim()'      (fake clock for new/changed *ride* functions)
# Scenario replays (real RPCs, new + 4.1.3 client emulation):
#   python3 -I $HERE/sim/scenarios.py [S1 S2 ...]  -> report + sim/results.json
# Never point anything here at the live DB.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/home/user/Vel-n
BIN=/usr/lib/postgresql/16/bin
PGD=${PGD:-/var/tmp/pg-rides}
PORT=${PGPORT_RIDES:-5499}
SOCK=$PGD/sock
DB=rides
as_pg() { runuser -u postgres -- "$@"; }
PSQL() { as_pg $BIN/psql -X -h $SOCK -p $PORT -U postgres "$@"; }

start() {
  if [ ! -f $PGD/data/PG_VERSION ]; then
    mkdir -p $PGD/data $SOCK && chown -R postgres $PGD
    as_pg $BIN/initdb -D $PGD/data -U postgres --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null
    echo "timezone = 'UTC'" >> $PGD/data/postgresql.conf
    echo "fsync = off" >> $PGD/data/postgresql.conf
  fi
  if ! as_pg $BIN/pg_ctl -D $PGD/data status >/dev/null 2>&1; then
    as_pg $BIN/pg_ctl -D $PGD/data -l $PGD/log -o "-p $PORT -k $SOCK -c listen_addresses=''" -w start >/dev/null
  fi
}

case "${1:-setup}" in
  start) start; exit 0 ;;
  stop) as_pg $BIN/pg_ctl -D $PGD/data -m fast stop; exit 0 ;;
  psql) shift; start; PSQL -d $DB "$@"; exit $? ;;
esac

start
mkdir -p $HERE/snap
if [ "${SNAP_REFRESH:-0}" = 1 ] || [ ! -s $HERE/snap/schema_public.sql ]; then
  (cd $REPO && git fetch -q origin supabase-live-snapshot || true)
  for f in schema_public triggers; do
    (cd $REPO && git show origin/supabase-live-snapshot:supabase/_snapshot/$f.sql) > $HERE/snap/$f.sql
  done
fi
PSQL -d postgres -q -c "drop database if exists $DB" -c "create database $DB"
PSQL -d $DB -q -v ON_ERROR_STOP=1 < $HERE/stubs.sql
# Live public schema. Errors are listed (expected: none that touch rides).
PSQL -d $DB -q < $HERE/snap/schema_public.sql > $PGD/load_public.log 2>&1 || true
PSQL -d $DB -q < $HERE/snap/triggers.sql > $PGD/load_triggers.log 2>&1 || true
echo "schema_public errors: $(grep -c ERROR $PGD/load_public.log || true)  triggers errors: $(grep -c ERROR $PGD/load_triggers.log || true)"
PSQL -d $DB -q -v ON_ERROR_STOP=1 < $HERE/timeshim.sql
PSQL -d $DB -q -v ON_ERROR_STOP=1 < $HERE/fixtures.sql
PSQL -d $DB -At -c "select 'shimmed functions: ' || public.t_shim()"
echo "ready: $0 psql  (db=$DB port=$PORT socket=$SOCK)"
