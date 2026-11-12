#!/usr/bin/env bash
# defn.sh <db> <function name>
#   Print pg_get_functiondef for EVERY overload of the function (schema public;
#   give schema.name for another schema), each preceded by comment lines with
#   owner, ACL (grants) and the COMMENT, so the output is the full live state of
#   the object. Typical use - diff a draft against live:
#     defn.sh mydb confirm_payment > live.sql     (mydb = fresh newdb.sh copy)
#   Views:  psql.sh db -Atc "select pg_get_viewdef('public.x'::regclass, true)"
#   Triggers / policies:  sig.sh db '^(TRIGGER|POLICY) public\.<table> '
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; valid_db "$db"; ensure_up
name="$2"; schema=public
case "$name" in *.*) schema="${name%%.*}"; name="${name#*.}" ;; esac
SUPSQL -d "$db" -q -At -v ON_ERROR_STOP=1 -v fn="$name" -v sc="$schema" <<'SQL'
select '-- ' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
       || E'\n-- owner: ' || pg_get_userbyid(p.proowner)
       || E'\n-- acl:   ' || coalesce((select string_agg(a::text, ', ' order by a::text) from unnest(p.proacl) a), '(default: owner + PUBLIC execute)')
       || coalesce(E'\n-- comment: ' || replace(obj_description(p.oid, 'pg_proc'), E'\n', E'\n--          '), '')
       || E'\n' || pg_get_functiondef(p.oid) || E';\n'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = :'sc' and p.proname = :'fn' and p.prokind in ('f', 'p')
 order by pg_get_function_identity_arguments(p.oid);
SQL
cnt=$(SUPSQL -d "$db" -q -At -v fn="$name" -v sc="$schema" <<'SQL'
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = :'sc' and p.proname = :'fn';
SQL
)
[ "$cnt" != 0 ] || { echo "-- no function $schema.$name in $db" >&2; exit 1; }
