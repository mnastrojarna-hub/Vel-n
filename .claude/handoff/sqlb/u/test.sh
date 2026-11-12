#!/bin/bash
# test.sh <db> — testy skupiny u (QA texty) na DB, kde je aplikovaný celý bundle 20261112*.
# Seedovaná DB (seed.sh před bundle): kontroluje výsledky textů. Prázdná DB: jen idempotenci.
# Exit 0 = vše prošlo.
set -u
DB=${1:?usage: test.sh <db>}
R=/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/pg
M=/home/user/Vel-n/supabase/migrations
fail=0
ids=$(cat $M/20261112u08_*.sql $M/20261112u09_*.sql | grep -oE "^\s*\('[0-9a-f-]{36}'" | grep -oE "[0-9a-f-]{36}" | sort -u | paste -sd, -)
$R/psql.sh "$DB" -v ON_ERROR_STOP=1 -At -v ids="{$ids}" > /tmp/u_test_$$.out 2>&1 <<'SQL'
\set QUIET on
CREATE TEMP TABLE t_res(name text, ok boolean);
-- seedovaná DB = existují řádky z živé DB
CREATE TEMP TABLE t_seeded AS SELECT EXISTS (SELECT 1 FROM public.faq_items WHERE id='fa9603a9-a628-4349-9797-4c0bcc71fc57') AS s;
INSERT INTO t_res SELECT 'u01 recenze jen Google', NOT EXISTS (SELECT 1 FROM public.faq_items WHERE id='fa9603a9-a628-4349-9797-4c0bcc71fc57' AND (answer ~* 'facebook|firmy|tripadvisor' OR translations::text ~* 'facebook|firmy|tripadvisor'));
INSERT INTO t_res SELECT 'u02 adresa FAQ e7079920', NOT EXISTS (SELECT 1 FROM public.faq_items WHERE id='e7079920-f08c-4b08-b52a-9b8623909035' AND (answer ~ '393 01 Mezná' OR translations::text ~ '393 01 Mezná'));
INSERT INTO t_res SELECT 'u02 pl motorower pryč', NOT EXISTS (SELECT 1 FROM public.cms_variables WHERE translations->'pl'->>'value' ~* 'motorower');
INSERT INTO t_res SELECT 'u02 ploché klíče sync triggeru nevrácené (intro.body = živá hodnota)', NOT (SELECT s FROM t_seeded) OR (SELECT md5(value::text) FROM public.cms_variables WHERE key='web.pujcovna.intro.body') = '2b49edf1d9bec393de99a8e1ddad16c5';
INSERT INTO t_res SELECT 'u02 benefits.closing = živá hodnota', NOT (SELECT s FROM t_seeded) OR (SELECT md5(value::text) FROM public.cms_variables WHERE key='web.pujcovna.benefits.closing') = '6f7de59b1d3c7c6f7b4dbcedb65b6561';
INSERT INTO t_res SELECT 'u03 co-v-cene cs (u motorek z Mezné)', NOT (SELECT s FROM t_seeded) OR (SELECT value#>>'{}' FROM public.cms_variables WHERE key='web.jak_pujcit_cena.gear.services.items.1') ~ 'z Mezné';
INSERT INTO t_res SELECT 'u03 jihomoravsky intro Němčice', NOT (SELECT s FROM t_seeded) OR (SELECT value#>>'{}' FROM public.cms_variables WHERE key='web.oblasti.region.jihomoravsky_kraj.intro') ~ 'Němčic';
INSERT INTO t_res SELECT 'u04 VOP bez zastaralého slibu plné nádrže', NOT EXISTS (SELECT 1 FROM public.document_templates d, jsonb_each_text(CASE WHEN jsonb_typeof(d.content_translations)='object' THEN d.content_translations ELSE '{}' END) e(l,v) WHERE d.type='vop' AND d.translation_src->>l IS NULL AND v ~* '(full tank|depósito lleno|réservoir plein|volle tank|vollem Tank|pełnym bakiem|повним баком)');
INSERT INTO t_res SELECT 'u05 patička VOP Pelhřimov', NOT (SELECT s FROM t_seeded) OR EXISTS (SELECT 1 FROM public.document_templates WHERE type='vop' AND active AND content_html !~ 'Mezná\s+9,\s+393\s+01\s+Mezná' AND content_html ~ 'IČO: 21874263 · Mezná 9, 393 01 Pelhřimov');
INSERT INTO t_res SELECT 'u05 VOP: úvodní sídlo beze změny', NOT (SELECT s FROM t_seeded) OR EXISTS (SELECT 1 FROM public.document_templates WHERE type='vop' AND content_html ~ 'sídlem Mezná 9, 393 01 Pelhřimov');
INSERT INTO t_res SELECT 'u06 smlouva bez zastaralé věty o čistotě', NOT EXISTS (SELECT 1 FROM public.document_templates d, jsonb_each_text(CASE WHEN jsonb_typeof(d.content_translations)='object' THEN d.content_translations ELSE '{}' END) e(l,v) WHERE d.type='rental_contract' AND (d.translation_src->>l) IS DISTINCT FROM encode(extensions.digest(convert_to(d.content_html,'UTF8'),'sha1'),'hex') AND v ~* '(clean condition|gereinigtem Zustand|condiciones de limpieza|état de propreté|schone staat|stanie czystości|стані чистоти|чистому стані)');
INSERT INTO t_res SELECT 'u07 uk produkty', NOT (SELECT s FROM t_seeded) OR (SELECT count(*) FROM public.products WHERE id IN ('0551496d-77a4-4f51-bc23-9196b3440f14','86616309-d992-443d-8d70-07183b7788cf') AND translations ? 'uk') = 2;
INSERT INTO t_res SELECT 'u08/u09 uk FAQ doplněné', NOT EXISTS (SELECT 1 FROM public.faq_items WHERE id = ANY (:'ids'::uuid[]) AND NOT translations ? 'uk');
INSERT INTO t_res SELECT 'u10 KTM SX 50 features 7 jazyků', NOT (SELECT s FROM t_seeded) OR (SELECT count(*) FROM public.motorcycles m, unnest(ARRAY['en','de','es','fr','nl','pl','uk']) l WHERE m.id='6071c49d-8019-415e-a9d9-ef23c7ec88a6' AND coalesce(m.translations->l->>'features','')<>'') = 7;
INSERT INTO t_res SELECT 'u11 adresa v překladech', NOT EXISTS (SELECT 1 FROM public.cms_variables WHERE key IN ('web.layout.rez.pickup.deliveryTip','web.layout.rez.pickup.returnTip','web.layout.editRez.loc.atRental','web.kontakt.address','web.kontakt.billing.addr') AND translations::text ~ '393 01 Mezná');
INSERT INTO t_res SELECT 'u12 blog top10 nl nizozemsky', NOT (SELECT s FROM t_seeded) OR (SELECT translations->'nl'->>'title' FROM public.cms_pages WHERE id='c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0') = 'Top 10 cadeaus voor motorrijders waar ze echt blij mee zijn';
INSERT INTO t_res SELECT 'u13 editRez.h1 = tlačítko (de/es/nl)', NOT EXISTS (SELECT 1 FROM public.cms_variables h, public.cms_variables b, unnest(ARRAY['de','es','nl']) l WHERE h.key='web.layout.editRez.h1' AND b.key='web.layout.menu.editReservation' AND (SELECT s FROM t_seeded) AND h.translations->l->>'value' IS DISTINCT FROM b.translations->l->>'value');
INSERT INTO t_res SELECT 'u14 slug p přejmenován', NOT EXISTS (SELECT 1 FROM public.cms_pages WHERE slug='p') AND (NOT (SELECT s FROM t_seeded) OR EXISTS (SELECT 1 FROM public.cms_pages WHERE id='5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc' AND slug='proc-je-motogo24-nejlepsi-motopujcovna-v-cr'));
INSERT INTO t_res SELECT 'žádné translations neobjektové', NOT EXISTS (SELECT 1 FROM public.cms_variables WHERE jsonb_typeof(translations)<>'object' UNION ALL SELECT 1 FROM public.faq_items WHERE jsonb_typeof(translations)<>'object' UNION ALL SELECT 1 FROM public.motorcycles WHERE jsonb_typeof(translations)<>'object' UNION ALL SELECT 1 FROM public.products WHERE jsonb_typeof(translations)<>'object') OR NOT (SELECT s FROM t_seeded);
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name FROM t_res ORDER BY name;
SQL
rc=$?; cat /tmp/u_test_$$.out; grep -q '^FAIL' /tmp/u_test_$$.out && fail=1; [ $rc -ne 0 ] && fail=1; rm -f /tmp/u_test_$$.out
# idempotence: 2. aplikace u souborů nesmí změnit žádný řádek ani schéma
$R/datasig.sh "$DB" > /tmp/u_d1_$$; $R/sig.sh "$DB" > /tmp/u_s1_$$
for f in $(ls $M/20261112u*.sql | LC_ALL=C sort); do QUIET=1 $R/apply.sh "$DB" "$f" >/dev/null 2>&1 || { echo "FAIL reapply $f"; fail=1; }; done
$R/datasig.sh "$DB" > /tmp/u_d2_$$; $R/sig.sh "$DB" > /tmp/u_s2_$$
if diff -q /tmp/u_d1_$$ /tmp/u_d2_$$ >/dev/null && diff -q /tmp/u_s1_$$ /tmp/u_s2_$$ >/dev/null; then echo "PASS idempotence (data + schéma beze změny)"; else echo "FAIL idempotence"; diff /tmp/u_d1_$$ /tmp/u_d2_$$; fail=1; fi
rm -f /tmp/u_d1_$$ /tmp/u_d2_$$ /tmp/u_s1_$$ /tmp/u_s2_$$
[ $fail = 0 ] && echo "ALL PASS" || echo "TESTS FAILED"
exit $fail
