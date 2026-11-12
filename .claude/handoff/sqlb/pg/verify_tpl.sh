#!/usr/bin/env bash
# verify_tpl.sh [db]
#   Proof that the template holds everything the snapshot defines: counts the
#   CREATE statements of the snapshot files (split_sql.py) and the objects in a
#   fresh copy of live_tpl (default database name: tplcheck), compares trigger
#   definitions text-for-text with snapshot triggers.sql. Exit 1 on a mismatch.
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0; fi
db="${1:-tplcheck}"; "$RIG/newdb.sh" "$db" >/dev/null
q() { SUPSQL -d "$db" -q -At -v ON_ERROR_STOP=1 -c "$1"; }
snapcount() { python3 -I "$RIG/split_sql.py" names "$RIG/snap/$1.sql" | awk -F'\t' -v k="$2" -v s="$3" '$1 ~ k && index($2, "\"" s "\".") > 0' | wc -l; }
# constraints that create an index (PRIMARY KEY / UNIQUE / EXCLUDE) per schema
snapconidx() { python3 -I - "$RIG/snap/$1.sql" "$2" <<'PY'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
n = 0
for m in re.finditer(r'ALTER TABLE ONLY "%s"\."[^"]+"\s+ADD CONSTRAINT "[^"]+" (PRIMARY KEY|UNIQUE|EXCLUDE)' % re.escape(sys.argv[2]), src):
    n += 1
print(n)
PY
}
snapcon() { grep -cE '^    ADD CONSTRAINT "[^"]+" (PRIMARY KEY|UNIQUE|FOREIGN KEY|EXCLUDE)' "$RIG/snap/$1.sql" || true; }
bad=0
row() { # label snapshot loaded
  local st=OK; [ "$2" = "$3" ] || { st=MISMATCH; bad=1; }
  printf '%-44s %8s %8s  %s\n' "$1" "$2" "$3" "$st"
}
printf '%-44s %8s %8s\n' "object kind" "snapshot" "loaded"
for sc in public auth storage realtime; do
  f=schema_system; [ $sc = public ] && f=schema_public
  row "$sc tables"            "$(snapcount $f '^TABLE$' $sc)"            "$(q "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='$sc' and c.relkind in ('r','p') and c.relname <> 'messages_default'")"
  row "$sc functions"         "$(snapcount $f '^FUNCTION$' $sc)"         "$(q "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='$sc'")"
  row "$sc views"             "$(snapcount $f '^VIEW$' $sc)"             "$(q "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='$sc' and c.relkind='v'")"
  row "$sc types (enum/composite)" "$(snapcount $f '^TYPE$' $sc)"        "$(q "select count(*) from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='$sc' and (t.typtype='e' or (t.typtype='c' and exists (select 1 from pg_class c where c.oid=t.typrelid and c.relkind='c')))")"
  row "$sc sequences (explicit)" "$(snapcount $f '^SEQUENCE$' $sc)"      "$(q "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='$sc' and c.relkind='S' and not exists (select 1 from pg_depend d where d.objid=c.oid and d.deptype='i')")"
  row "$sc indexes (CREATE INDEX + PK/UNIQUE)" "$(( $(snapcount $f 'INDEX$' $sc) + $(snapconidx $f $sc) ))" "$(q "select count(*) from pg_indexes where schemaname='$sc' and tablename <> 'messages_default'")"
  row "$sc policies"          "$(python3 -I "$RIG/split_sql.py" names "$RIG/snap/$f.sql" | awk -F'\t' -v s="$sc" '$1=="POLICY" && index($2, " ON \"" s "\".") > 0' | wc -l)" "$(q "select count(*) from pg_policies where schemaname='$sc'")"
  row "$sc triggers"          "$(python3 -I "$RIG/split_sql.py" names "$RIG/snap/$f.sql" | awk -F'\t' -v s="$sc" '$1=="TRIGGER" && index($2, " ON \"" s "\".") > 0' | wc -l)" "$(q "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname='$sc'")"
  row "$sc tables with RLS enabled" "$(grep -cE "^ALTER TABLE \"$sc\"\.\"[^\"]+\" ENABLE ROW LEVEL SECURITY;" "$RIG/snap/$f.sql" || true)" "$(q "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='$sc' and c.relkind in ('r','p') and c.relrowsecurity and c.relname <> 'messages_default'")"
done
row "PK/UNIQUE/FK constraints (ADD CONSTRAINT)" "$(( $(snapcon schema_public) + $(snapcon schema_system) ))" \
    "$(q "select count(*) from pg_constraint con join pg_namespace n on n.oid=con.connamespace where n.nspname in ('public','auth','storage','realtime') and con.contype in ('p','u','f','x') and con.conrelid <> 'realtime.messages_default'::regclass")"
row "public function comments" "$(grep -cE '^COMMENT ON FUNCTION "public"' "$RIG/snap/schema_public.sql" || true)" \
    "$(q "select count(*) from pg_description d join pg_proc p on p.oid=d.objoid and d.classoid='pg_proc'::regclass join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'")"
# triggers.sql is produced on live by this very query -> must be identical text
q "SELECT pg_get_triggerdef(t.oid)||';' FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname='public' ORDER BY c.relname, t.tgname;" > "$RIG/load/triggers_loaded.sql"
if diff <(LC_ALL=C sort "$RIG/snap/triggers.sql") <(LC_ALL=C sort "$RIG/load/triggers_loaded.sql") > "$RIG/load/triggers.diff"; then
  row "public trigger definitions identical to triggers.sql" "$(grep -c 'CREATE TRIGGER' "$RIG/snap/triggers.sql")" "$(grep -c 'CREATE TRIGGER' "$RIG/load/triggers_loaded.sql")"
else
  echo "trigger definitions differ from snapshot triggers.sql: see $RIG/load/triggers.diff"; bad=1
fi
# Strongest proof: dump the loaded public schema again and compare it line by
# line with the snapshot (both normalised: IF NOT EXISTS / OR REPLACE removed,
# MAINTAIN removed, role order in policy TO lists and PG17 type quoting unified).
norm() { sed -E 's/CREATE TABLE IF NOT EXISTS/CREATE TABLE/; s/CREATE OR REPLACE (FUNCTION|TRIGGER|VIEW)/CREATE \1/; s/CREATE SEQUENCE IF NOT EXISTS/CREATE SEQUENCE/; s/CREATE SCHEMA IF NOT EXISTS/CREATE SCHEMA/; /^GRANT /s/,MAINTAIN//; /^GRANT /s/MAINTAIN,//; s/ TO "authenticated", "anon" / TO "anon", "authenticated" /; s/ RETURNS json$/ RETURNS "json"/; /^--/d; /^$/d; /^SET /d; /^SELECT pg_catalog.set_config/d; /^\\(un)?restrict/d' | LC_ALL=C sort; }
as_pg "$BIN/pg_dump" -h "$PGSOCK" -p "$PGPORT_SQLB" -U "$SU" -d "$db" -s -n public --quote-all-identifiers 2>/dev/null | norm > "$RIG/load/redump_norm.txt"
norm < "$RIG/snap/schema_public.sql" > "$RIG/load/snap_norm.txt"
if diff "$RIG/load/snap_norm.txt" "$RIG/load/redump_norm.txt" > "$RIG/load/redump.diff"; then
  row "re-dump of public == snapshot (normalised lines)" "$(wc -l < "$RIG/load/snap_norm.txt")" "$(wc -l < "$RIG/load/redump_norm.txt")"
else
  echo "re-dump differs from the snapshot: see $RIG/load/redump.diff ($(grep -c '^[<>]' "$RIG/load/redump.diff") lines)"; bad=1
fi
[ "$db" = tplcheck ] && SUPSQL -d postgres -q -c "drop database if exists tplcheck with (force)"
[ $bad = 0 ] && echo "TEMPLATE OK: every object of the snapshot is present" || { echo "TEMPLATE MISMATCH"; exit 1; }
