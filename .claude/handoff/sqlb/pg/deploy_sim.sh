#!/usr/bin/env bash
# deploy_sim.sh <db> [--again] [--only <substring>]
#   Simulate the merge-to-main deploy for the new migrations: every file
#   /home/user/Vel-n/supabase/migrations/20261112*.sql in LC_ALL=C sort order
#   goes through apply.sh (one transaction per file, stop at first failure) and
#   its name is recorded in public._git_migrations exactly like the workflow.
#   Files already recorded are skipped (workflow behaviour).
#   --again   re-apply ALL matching files a second time regardless of the
#             evidence (idempotency proof). Compares sig.sh and datasig.sh
#             before/after: exit 1 on error, exit 2 when the schema signature
#             changed, exit 3 when only table data changed (review the list).
#   --only S  restrict to file names containing S (like the workflow input).
#   Env: MIG_GLOB (default 20261112*.sql), MIG_DIR (default repo migrations dir)
set -uo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; shift; writable_db "$db" || exit 1; ensure_up
again=0; only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --again) again=1 ;;
    --only) shift; only="${1:-}" ;;
    *) echo "unknown argument $1" >&2; exit 1 ;;
  esac; shift
done
dir="${MIG_DIR:-$REPO/supabase/migrations}"; glob="${MIG_GLOB:-20261112*.sql}"
files=$(cd "$dir" && ls $glob 2>/dev/null | LC_ALL=C sort)
[ -n "$files" ] || { echo "no files match $dir/$glob"; exit 0; }
q() { PSQL -d "$db" -v ON_ERROR_STOP=1 -qtA -c "$1"; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [ $again = 1 ]; then "$RIG/sig.sh" "$db" > "$tmp/sig1"; "$RIG/datasig.sh" "$db" > "$tmp/dat1"; fi
applied=0; skipped=0
for base in $files; do
  if [ -n "$only" ] && [[ "$base" != *"$only"* ]]; then continue; fi
  exists=$(q "select count(*) from public._git_migrations where filename='$base'")
  if [ "$exists" != 0 ] && [ $again = 0 ]; then skipped=$((skipped+1)); continue; fi
  "$RIG/apply.sh" "$db" "$dir/$base" || { echo "DEPLOY STOPPED at $base (later files are blocked)"; exit 1; }
  q "insert into public._git_migrations(filename) values ('$base')
     on conflict (filename) do update set applied_at = now(), baseline = false" >/dev/null
  applied=$((applied+1))
done
echo "Hotovo: zpracovano=$applied, preskoceno(uz aplikovane)=$skipped"
if [ $again = 1 ]; then
  "$RIG/sig.sh" "$db" > "$tmp/sig2"; "$RIG/datasig.sh" "$db" > "$tmp/dat2"
  rc=0
  if diff "$tmp/sig1" "$tmp/sig2" > "$tmp/sigdiff"; then echo "IDEMPOTENT (schema): signature identical after the second run"
  else echo "NOT IDEMPOTENT (schema): the second run changed the signature:"; cat "$tmp/sigdiff"; rc=2; fi
  if diff "$tmp/dat1" "$tmp/dat2" > "$tmp/datdiff"; then echo "IDEMPOTENT (data): every table has the same content hash after the second run"
  else echo "DATA CHANGED by the second run (table, rows, content hash):"; cat "$tmp/datdiff"; [ $rc = 0 ] && rc=3; fi
  exit $rc
fi
