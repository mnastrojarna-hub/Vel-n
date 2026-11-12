#!/usr/bin/env bash
# datasig.sh <db> [schema ...]
#   One line per table: "<schema>.<table> rows=<n> hash=<md5 of all rows>".
#   Default schema: public (+ cron.job, storage.buckets). The evidence table
#   public._git_migrations is left out. Use it to prove that a second run of a
#   data/text migration changes no row:  datasig.sh db > a; apply...; datasig.sh db > b; diff a b
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="$1"; shift; valid_db "$db"; ensure_up
schemas="${*:-public}"
inlist=$(printf "'%s'," $schemas); inlist="${inlist%,}"
SUPSQL -d "$db" -q -At -v ON_ERROR_STOP=1 <<SQL | SUPSQL -d "$db" -q -At -v ON_ERROR_STOP=1 -f - | LC_ALL=C sort
select format('select %L || '' rows='' || count(*) || '' hash='' || coalesce(md5(string_agg(md5(t::text), '''' order by md5(t::text))), ''-'') from %I.%I t;',
              n.nspname || '.' || c.relname, n.nspname, c.relname)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('r', 'p') and not c.relispartition
   and ((n.nspname in ($inlist) and not (n.nspname = 'public' and c.relname = '_git_migrations'))
        or (n.nspname, c.relname) in (('cron', 'job'), ('storage', 'buckets')))
 order by 1;
SQL
