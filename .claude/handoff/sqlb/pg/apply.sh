#!/usr/bin/env bash
# apply.sh <db> <file.sql>...
#   Apply each file exactly like .github/workflows/deploy-sql.yml does:
#     psql -v ON_ERROR_STOP=1 --single-transaction -f <file>
#   as the role postgres (the deploy role; not a superuser), one transaction per
#   file, stop at the first failure (exit 1). NOTICE/WARNING lines are printed,
#   and on an error psql prints the failing statement (ECHO=errors).
#   The file is fed through stdin; "<stdin>" in messages is replaced by its name.
#   Env: PGU=supabase_admin  apply as superuser (only to tell a privilege
#                            problem of the rig from a real error)
#        QUIET=1             do not print NOTICEs (errors are still printed)
#        ALLOW_TXN=1         apply a file although it holds BEGIN;/COMMIT;
#   LINT lines are warnings about statements whose result on live can differ
#   from this rig; a file with BEGIN;/COMMIT; is refused (repo rule).
set -uo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; shift; writable_db "$db" || exit 1; ensure_up
# Non-fatal lint: statements whose outcome on live can differ from this rig
# (live: PG17, role postgres without superuser + supautils; rig: PG16 stubs).
lint() {
  local f="$1" hit
  chk() { hit=$(grep -n -i -E -- "$1" "$f" | grep -v -E '^[0-9]+:[[:space:]]*--' | head -3 | cut -c1-140); [ -z "$hit" ] || printf 'LINT      %s\n%s\n' "$2" "$(printf '%s\n' "$hit" | sed 's/^/            line /')"; }
  chk '^[[:space:]]*(BEGIN|COMMIT|ROLLBACK|START TRANSACTION)[[:space:]]*;' 'FORM VIOLATION: explicit transaction control inside a file that the deploy already wraps in one transaction (psql only warns, the file would lose its all-or-nothing property)'
  [ -z "$hit" ] || formbad=1
  chk 'CREATE[[:space:]]+(UNIQUE[[:space:]]+)?INDEX[[:space:]]+CONCURRENTLY|DROP[[:space:]]+INDEX[[:space:]]+CONCURRENTLY|^[[:space:]]*VACUUM|REINDEX[[:space:]].*CONCURRENTLY' 'cannot run inside a transaction block'
  chk 'ALTER[[:space:]]+TYPE[[:space:]].*ADD[[:space:]]+VALUE' 'ALTER TYPE ... ADD VALUE: the new value cannot be used in the same transaction'
  chk 'ALTER[[:space:]]+TABLE[[:space:]]+(ONLY[[:space:]]+)?(IF[[:space:]]+EXISTS[[:space:]]+)?"?(auth|storage|realtime|cron|net|vault)"?\.|CREATE[[:space:]]+(UNIQUE[[:space:]]+)?INDEX[^;]*[[:space:]]ON[[:space:]]+"?(auth|storage|realtime)"?\.' 'DDL on a Supabase-owned table: the rig allows it, live refuses (postgres is not the owner)'
  chk 'CREATE[[:space:]]+EXTENSION|ALTER[[:space:]]+SYSTEM|CREATE[[:space:]]+EVENT[[:space:]]+TRIGGER|ALTER[[:space:]]+ROLE|CREATE[[:space:]]+ROLE|SECURITY[[:space:]]+LABEL' 'needs privileges / extensions that differ between the rig and live'
  chk 'ALTER[[:space:]]+PUBLICATION' 'publication membership is NOT in the snapshot (rig starts empty) - guard with pg_publication_tables'
  chk 'cron\.unschedule' 'cron.job is empty in the rig (live jobs unknown); unschedule of a missing job raises on live too - guard with EXISTS (SELECT FROM cron.job ...)'
  return 0
}
for f in "$@"; do
  [ -r "$f" ] || { echo "apply.sh: cannot read $f" >&2; exit 1; }
  base=$(basename "$f")
  echo "APPLYING  $base"
  formbad=0; lint "$f"
  if [ "$formbad" = 1 ] && [ "${ALLOW_TXN:-0}" != 1 ]; then
    echo "FAILED    $base (BEGIN/COMMIT in the file; not applied. ALLOW_TXN=1 applies it anyway, as the deploy would)"; exit 1
  fi
  t0=$(date +%s.%N)
  out=$(PGOPTIONS="-c statement_timeout=120s" PSQL -d "$db" -v ON_ERROR_STOP=1 -v ECHO=errors --single-transaction -f - < "$f" 2>&1)
  rc=$?
  out=$(printf '%s\n' "$out" | sed "s|psql:<stdin>:|psql:$base:|")
  if [ $rc -ne 0 ]; then
    printf '%s\n' "$out"
    echo "FAILED    $base (psql exit $rc; transaction rolled back, nothing of this file is applied)"
    exit 1
  fi
  if [ "${QUIET:-0}" = 1 ]; then printf '%s\n' "$out" | grep -E 'ERROR|WARNING' || true; else printf '%s\n' "$out" | grep -v '^$' || true; fi
  printf 'OK        %s (%.2f s)\n' "$base" "$(echo "$(date +%s.%N) - $t0" | bc)"
done
