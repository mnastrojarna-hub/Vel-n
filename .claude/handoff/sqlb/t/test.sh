#!/usr/bin/env bash
# test.sh <db> — testy skupiny t (texty majitele) na DB, kde je aplikovaný celý balík.
# exit 0 = vše prošlo. Vedle toho si vytvoří vlastní DB sqlb_t_neg / sqlb_t_empty / sqlb_t_adv.
set -uo pipefail
DB=${1:?usage: test.sh <db>}
S=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb
RIG=$S/pg; T=$S/t; MIG=/home/user/Vel-n/supabase/migrations
FILES=$(ls $MIG/20261112t*.sql 2>/dev/null | LC_ALL=C sort)
[ -z "$FILES" ] && FILES=$(ls $T/final/20261112t*.sql | LC_ALL=C sort)
[ $(echo "$FILES" | wc -l) -eq 32 ] || { echo "FAIL: nenalezeno 32 souborů skupiny t"; exit 1; }
fail=0; ok(){ echo "PASS: $*"; }; bad(){ echo "FAIL: $*"; fail=1; }
q(){ $RIG/psql.sh "$1" -Atq -v ON_ERROR_STOP=1 -c "$2"; }

# 1) funkce _gate_procedure_msg: nové tělo, ACL beze změny (jen postgres + service_role)
md5=$(q $DB "select md5(prosrc) from pg_proc where oid = to_regprocedure('public._gate_procedure_msg(text,integer,boolean)')")
acl=$(q $DB "select proacl::text from pg_proc where oid = to_regprocedure('public._gate_procedure_msg(text,integer,boolean)')")
[ "$md5" = 1972a4a83ca2587adc616a1964441d05 ] && ok "gate fn new body" || bad "gate fn md5=$md5"
[ "$acl" = '{postgres=X/postgres,service_role=X/postgres}' ] && ok "gate fn acl $acl" || bad "gate fn acl=$acl"
out=$(q $DB "select public._gate_procedure_msg('1234', 3, true)")
echo "$out" | grep -q 'Motorku vracejte umytou a tak, aby nesvítila kontrolka rezervy (tankovat do plna nemusíte).$' && ok "gate fn text" || bad "gate fn text"
[ "$(q $DB "select public._gate_procedure_msg(NULL, 3, true)")" = "" ] && ok "gate fn NULL brána = ''" || bad "gate fn NULL"

# 2) listy: žádný list nesmí zůstat ve znění z 2026-10-15 (jen když DB má živá data)
n=$(q $DB "select count(*) from public.cms_variables")
if [ "$n" -gt 1000 ]; then
  res=$($RIG/psql.sh $DB -Atq -F'|' < $T/check_leaves.sql 2>&1)
  line=$(echo "$res" | grep -E '^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$' | head -1)
  still=$(echo "$line" | cut -d'|' -f2)
  [ "$still" = 0 ] && ok "leaves ok_new|still_old|missing|total = $line" || { bad "leaves $line"; echo "$res" | grep STILL_OLD; }
  echo "$res" | grep '^OTHER' | sed 's/^/INFO (list změněn jinou migrací\/úpravou): /'
else
  echo "SKIP: DB bez živých dat (cms_variables=$n) – kontrola listů vynechána"
fi

# 3) idempotence: opětovný běh všech 32 souborů nezmění data ani schéma
$RIG/datasig.sh $DB > $T/.d0; $RIG/sig.sh $DB > $T/.s0
QUIET=1 $RIG/apply.sh $DB $FILES > $T/.again.log 2>&1 || bad "re-apply selhal (viz $T/.again.log)"
$RIG/datasig.sh $DB > $T/.d1; $RIG/sig.sh $DB > $T/.s1
cmp -s $T/.d0 $T/.d1 && ok "re-apply data beze změny" || { bad "re-apply změnil data"; diff $T/.d0 $T/.d1; }
cmp -s $T/.s0 $T/.s1 && ok "re-apply schéma beze změny" || { bad "re-apply změnil schéma"; diff $T/.s0 $T/.s1; }

# 4) negativní test: úpravy ve Velínu po 2026-10-15 zůstanou
$RIG/newdb.sh sqlb_t_neg >/dev/null && $T/seed.sh sqlb_t_neg >/dev/null 2>&1
$RIG/psql.sh sqlb_t_neg -q -v ON_ERROR_STOP=1 < $T/neg_edits.sql
QUIET=1 $RIG/apply.sh sqlb_t_neg $FILES > $T/.neg.log 2>&1 || bad "neg apply selhal"
chg=$($RIG/psql.sh sqlb_t_neg -At < $T/neg_check.sql)
cnt=$(q sqlb_t_neg "select count(*) from public.t_neg")
[ -z "$chg" ] && [ "$cnt" = 11 ] && ok "11 simulovaných úprav ve Velínu zůstalo" || bad "přepsané úpravy: $chg (počet $cnt)"

# 5) robustnost: prázdné tabulky a rozbité tvary dat, každý 2×, bez chyby; 2. běh beze změny dat
$RIG/newdb.sh sqlb_t_empty >/dev/null
for i in 1 2; do QUIET=1 $RIG/apply.sh sqlb_t_empty $FILES > $T/.empty$i.log 2>&1 || bad "prázdná DB běh $i"; done
$RIG/newdb.sh sqlb_t_adv >/dev/null && $T/seed.sh sqlb_t_adv >/dev/null 2>&1
$RIG/psql.sh sqlb_t_adv -q -v ON_ERROR_STOP=1 < $T/adversarial.sql
for i in 1 2; do QUIET=1 $RIG/apply.sh sqlb_t_adv $FILES > $T/.adv$i.log 2>&1 || bad "rozbitá data běh $i"; $RIG/datasig.sh sqlb_t_adv > $T/.adv$i; done
cmp -s $T/.adv1 $T/.adv2 && ok "rozbitá data: 2 běhy bez chyby, 2. beze změny" || bad "rozbitá data: 2. běh změnil data"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
