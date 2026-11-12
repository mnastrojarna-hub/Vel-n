#!/usr/bin/env bash
# fndiff.sh <dbA> <dbB> [name regex]
#   Unified diff of the full definitions (pg_get_functiondef + owner + ACL +
#   SET config) of all public functions and views between two databases, e.g.
#       fndiff.sh base mydb            what my migrations changed against live
#       fndiff.sh base mydb 'ride|trip'
#   "base" is the shared pristine copy of the live template. Every hunk header
#   names the function it belongs to. Use it to prove that a replaced object =
#   live body of today + exactly the intended change. Exit 0 = no difference.
#   (Run it BEFORE t_shim(): the fake clock rewrites function bodies.)
#   Env: FNDIFF_OPTS  extra diff options, e.g. --strip-trailing-cr or -U10
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
a="$1"; b="$2"; re="${3:-.}"; valid_db "$a"; valid_db "$b"; ensure_up
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
dump() {
  SUPSQL -d "$1" -q -At -v ON_ERROR_STOP=1 -v re="$re" <<'SQL'
select d from (
  select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as k,
         '@@ FUNCTION public.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
         || E'\n-- owner: ' || pg_get_userbyid(p.proowner)
         || E'\n-- acl: ' || coalesce((select string_agg(a::text, ', ' order by a::text) from unnest(p.proacl) a), '(default)')
         || coalesce(E'\n-- comment md5: ' || md5(obj_description(p.oid, 'pg_proc')), '')
         || E'\n' || pg_get_functiondef(p.oid) || E'\n' as d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') and p.proname ~ :'re'
  union all
  select '~view ' || c.relname, '@@ VIEW public.' || c.relname || E'\n-- options: ' || coalesce(array_to_string(c.reloptions, ','), '')
         || E'\n' || pg_get_viewdef(c.oid, true) || E'\n'
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('v', 'm') and c.relname ~ :'re'
) s order by k collate "C";
SQL
}
dump "$a" > "$tmp/$a.sql"; dump "$b" > "$tmp/$b.sql"
if diff -u ${FNDIFF_OPTS:-} -F '^@@ ' --label "$a" --label "$b" "$tmp/$a.sql" "$tmp/$b.sql"; then
  echo "no difference in public functions/views matching '$re' between $a and $b"
else
  if [ -z "${FNDIFF_OPTS:-}" ]; then
    n1=$(diff "$tmp/$a.sql" "$tmp/$b.sql" | grep -c '^[<>]' || true)
    n2=$(diff --strip-trailing-cr "$tmp/$a.sql" "$tmp/$b.sql" | grep -c '^[<>]' || true)
    [ "$n1" = "$n2" ] || echo "NOTE: $((n1-n2)) of the $n1 changed lines differ only by the line ending (CRLF on one side - several live bodies were saved with CRLF). FNDIFF_OPTS=--strip-trailing-cr shows the content changes only; a migration should keep the live line endings or state the normalisation."
  fi
  exit 1
fi
