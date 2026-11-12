#!/usr/bin/env bash
# sig.sh <db> [grep -E pattern]
#   Stable sorted dump (one line per object) for before/after diffs:
#     FUNCTION  every public function: arguments with defaults, result, language,
#               SECURITY DEFINER flag, volatility, SET config (search_path),
#               owner, ACL (grants) and md5 of the body
#     COMMENT   md5 of function comments
#     TRIGGER   triggers on public, auth and storage tables (definition + enabled)
#     POLICY    RLS policies on public, storage and auth tables;  RLS flags
#     INDEX, RELATION (owner + ACL + reloptions), COLUMN (type, null, default,
#     generated, column ACL), CONSTRAINT, VIEW (md5), TYPE (enum labels),
#     DEFACL (default privileges), PUBLICATION members, CRON jobs, BUCKET
#   Usage:  sig.sh db > before.txt ; apply.sh db x.sql ; sig.sh db > after.txt ; diff before.txt after.txt
#           sig.sh db '^(FUNCTION|TRIGGER) .*ride'
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; valid_db "$db"; ensure_up
if [ -n "${2:-}" ]; then SUPSQL -d "$db" -q -v ON_ERROR_STOP=1 -f - < "$RIG/sig.sql" | grep -E -- "$2" || true
else SUPSQL -d "$db" -q -v ON_ERROR_STOP=1 -f - < "$RIG/sig.sql"; fi
