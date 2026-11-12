#!/usr/bin/env bash
# psql.sh <db> [psql args...]
#   psql into database <db> of the local test cluster; stdin is passed through
#   (the postgres OS user cannot read the scratchpad, so feed files via stdin):
#     psql.sh mydb -c 'select 1'
#     psql.sh mydb -v ON_ERROR_STOP=1 < /path/to/test.sql
#     psql.sh mydb -At -f - < file.sql
#   Connects as the role postgres (NOT a superuser, like the Supabase SQL editor
#   and the deploy). For a superuser session:  PGU=supabase_admin psql.sh <db> ...
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; shift; valid_db "$db"; ensure_up
PSQL -d "$db" "$@"
