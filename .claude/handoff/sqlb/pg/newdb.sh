#!/usr/bin/env bash
# newdb.sh <name> [--shim]
#   Drop database <name> (if it exists, open sessions are terminated) and create
#   it again as a copy of the template live_tpl (= live schema of the snapshot).
#   --shim  additionally loads timeshim.sql + fixtures.sql (fake clock helpers
#           t_now/t_set/t_shim and the minimal users / admin / motorcycle).
#   <name> must match ^[a-z][a-z0-9_]{0,40}$ and is yours alone (use your group
#   prefix, e.g. a_pay1). The database owner is the role postgres, as on live.
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; writable_db "$db"; ensure_up
PGOPTIONS="-c client_min_messages=warning" SUPSQL -d postgres -q -v ON_ERROR_STOP=1 \
  -c "drop database if exists \"$db\" with (force)" \
  -c "create database \"$db\" owner postgres template $TPL"
if [ "${2:-}" = "--shim" ]; then
  PSQL -d "$db" -q -v ON_ERROR_STOP=1 < "$RIG/timeshim.sql"
  PSQL -d "$db" -q -v ON_ERROR_STOP=1 < "$RIG/fixtures.sql"
fi
echo "database $db ready (copy of $TPL, snapshot $SNAP_COMMIT)"
