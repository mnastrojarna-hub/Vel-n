#!/usr/bin/env bash
# build_tpl.sh - (re)build the template database live_tpl = live schema of the
# snapshot commit. Run by the rig owner only; other agents use newdb.sh.
#   build_tpl.sh            build (refuses when live_tpl already exists)
#   build_tpl.sh --force    drop and rebuild live_tpl (clones are not touched)
# Load logs: $RIG/load/*.log ; summary: $RIG/load/summary.txt
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
ensure_up
L="$RIG/load"; mkdir -p "$L" "$RIG/snap"
for f in roles schema_system schema_public triggers; do
  [ -s "$RIG/snap/$f.sql" ] || git -C "$REPO" show "$SNAP_COMMIT:supabase/_snapshot/$f.sql" > "$RIG/snap/$f.sql"
done
exists=$(SUPSQL -d postgres -Atc "select count(*) from pg_database where datname='$TPL'")
if [ "$exists" != 0 ]; then
  [ "${1:-}" = "--force" ] || { echo "$TPL exists (use --force to rebuild)"; exit 1; }
  SUPSQL -d postgres -q -c "alter database $TPL with is_template false allow_connections false" \
         -c "drop database $TPL with (force)"
fi
SUPSQL -d postgres -q -v ON_ERROR_STOP=1 < "$RIG/stubs_roles.sql" > "$L/00_roles.log" 2>&1
SUPSQL -d postgres -q -v ON_ERROR_STOP=1 -c "create database $TPL owner postgres template template0 encoding 'UTF8'"
# PG17-only privilege MAINTAIN is cut out of the GRANT lists (live is PG17, rig is PG16).
strip17() { sed -E '/^GRANT /s/,MAINTAIN//; /^GRANT /s/MAINTAIN,//'; }
python3 -I "$RIG/split_sql.py" defer "$RIG/snap/schema_system.sql" "$L/system_pre.sql" "$L/system_post.sql" > "$L/split.txt"
load() { # load <label> <file> [strict]
  local label="$1" file="$2" strict="${3:-}"
  if [ -n "$strict" ]; then
    SUPSQL -d "$TPL" -q -v ON_ERROR_STOP=1 < "$file" > "$L/$label.log" 2>&1 || { echo "FAILED $label"; cat "$L/$label.log"; exit 1; }
  else
    strip17 < "$file" | SUPSQL -d "$TPL" -q > "$L/$label.log" 2>&1 || true
  fi
  printf '%-22s errors: %s\n' "$label" "$(grep -c 'ERROR:' "$L/$label.log" || true)"
}
{
load 01_stubs_pre     "$RIG/stubs_pre.sql" strict
load 02_roles_snap    "$RIG/snap/roles.sql"
load 03_system_pre    "$L/system_pre.sql"
load 04_schema_public "$RIG/snap/schema_public.sql"
load 05_system_post   "$L/system_post.sql"
load 06_triggers      "$RIG/snap/triggers.sql"
load 07_stubs_post    "$RIG/stubs_post.sql" strict
} | tee "$L/summary.txt"
# Evidence of applied migrations = file list of the snapshot commit (all live).
git -C "$REPO" ls-tree --name-only "$SNAP_COMMIT" supabase/migrations/ | sed 's#.*/##' | grep '\.sql$' \
  | sed "s/'/''/g; s/.*/insert into public._git_migrations(filename, baseline) values ('&', true) on conflict do nothing;/" \
  | SUPSQL -d "$TPL" -q -v ON_ERROR_STOP=1
SUPSQL -d "$TPL" -q -c "analyze"
SUPSQL -d postgres -q -c "alter database $TPL with is_template true allow_connections false"
SUPSQL -d postgres -q -c "drop database if exists $BASE with (force)" -c "create database $BASE owner postgres template $TPL" \
       -c "alter database $BASE set default_transaction_read_only = on"
echo "template $TPL ready; pristine read-only reference database: $BASE" | tee -a "$L/summary.txt"
