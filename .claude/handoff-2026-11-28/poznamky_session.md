# Pracovní poznámky 27. 11. 2026 (pro pokračování po shrnutí kontextu)

Větev: claude/moto-go-mobile-conversion-gqg5qo (main = 9255ba70 = merge #2230, appka 5.0.2). Na větvi navíc (nepushnuto do main, bez PR):
- b289d2f7 appka 5.0.3+121 (řádek „Půjčit samotnou výbavu“ celý rok) — majitel 27. 11.: „app bude mít verzi 5.0.3“
- f3b53551 web: Oblasti pryč, menu Pobočky s podmenu, SEO stránky /motopujcovna-brno, /motopujcovna-vysocina
- web: slevové kódy u výbavy (víc kódů, G.rpcCodes s fallbackem na starý server) + u nákupu poukazu (js/voucher-codes.js, RPC quote_web_voucher_order), edge process-payment (voucher větev s codes), test pp_web_voucher_codes_test.ts
- web+Velín: e-shop zvlášť web (eshop_visible_web, fetchFeatureFlagOr) a appka (eshop_visible)

SQL NÁVRHY (NE v gitu, čekají na „ano“ majitele; po schválení → supabase/migrations + STATE_3/STATE_6):
- scratchpad/seo/sql/20261127a_web_discount_codes.sql (testováno v rig DB c_codes; starý tvar volání bajtově shodný)
- scratchpad/seo/sql/20261127b_eshop_visible_web.sql (testováno c_flags)
- SEO texty: agenti píšou do scratchpad/seo/sql/20261128a..e + owner_questions.md + changes_overview.md

SEO (majitel: cíl top 2 na „motopůjčovna“ a „půjčovna motorek“, „použij fable“, bez změn UX/UI/flow):
- Recenze: scratchpad/seo/review_core.json, review_howto.json, review_blogbikes.json (60+60+50 nálezů)
- Hlavní nálezy: rozpory s VOP (5 000 Kč, policie, storno), vymyšlená čísla a superlativy, opakovaný boilerplate, kanibalizace úvod × /pujcovna-motorek (stejné H1, 143 interních odkazů „Půjčovna motorek“ na /pujcovna-motorek), šablona meta u motorek („Půjč si Honda…“, „1 dní“), zimní banner „motopůjčovna zavřená“ nahoře na každé stránce
- Head-term změny (úvod title/H1, /pujcovna-motorek, patička, menu) ODLOŽENY do dat z Google Search Console (20261128d_seo_head_terms.sql = neaplikovat bez rozhodnutí)
- Agenti (model fable): W2 how-to kód, W1 katalog/landing/blog kód, D1 SQL cms_variables+faq_items, D2 SQL blog+motorky
- Web deploy: v repu NENÍ workflow pro motogo-web-php (Hosting90) — dřívější tvrzení „web se nasadí sám“ bylo neověřené → zeptat se majitele
- Deno pro testy edge: scratchpad/denoinst/node_modules/.bin/deno; lokální web: php -S 127.0.0.1:8099 s routerem scratchpad/web/router.php (Host: www.motogo24.cz), cache rm -rf /home/user/Vel-n/motogo-web-php/.cache/pages
- Předem existující selhání edge testů (11) v pp_* sadě — stejné i bez mých změn

Další úkoly: level-up animace (agent audit běží), po schválení SQL commit migrací + STATE, PR až na „ano“.

## Stav 27. 11. večer (po kompakci) — otevřené věci
- Větev claude/moto-go-mobile-conversion-gqg5qo, WIP commity (agenti pracují). Pomocník: $S/sync/wip_sync.sh (zrcadlí Android lib → iOS mimo 20 platformních souborů, lint, parita). Mazání v iOS ručně s plnou cestou.
- Běžící agenti: appka A–E (rank pryč z Moje, e-shop jako motorky, „Nová rezervace“, „Rezervovat“ na kartě motorky, kalendář rozsah) a8b5f03514653a4a8; level-up opravy ac9c1eb791f710bef; mapa pravidel přistavení pro kalkulačku af38876a768777145 ($S/calc/delivery_rules.md, design.md); web kalendáře (Opus) a68d908d82501031c ($S/calfix/); D1 SQL cms_variables+FAQ a11285fbf749e00ac; inventura provozovatele ab813c1038708d0ba ($S/operator/inventory.md, plan.md).
- Hotovo: W1 + W2 web SEO kód (commit 7dcddfb8), D2 SQL blog+motorky ($S/seo/sql/20261128a/b, 27 otázek majiteli v reportu), howto_needs_db.json (41 klíčů → D1).
- Provozovatel: MotoGo24 s.r.o., IČO 29909864, Mezná 9, 393 01 Mezná, KS České Budějovice C 36876, jednatelé Jiří Semorád a Petra Semorádová (každý samostatně), neplátce DPH, vznik 18. 8. 2026. Majitel: platí HNED po nasazení, všude (smlouvy, VOP, faktury, poukazy, e-maily, web, appka, Velín), nikde nesmí zůstat původní; už vystavené doklady se nepřepisují; nový účet 2303580494/2010 všude; Stripe si dořeší sám; bez DPH. Chce vědět stav napojení na bankovní API (Fio).
- Po dokončení změny provozovatele ve webu spustit: php motogo-web-php/scripts/build_pages_cs.php a build_master_json.php (referenční kopie textů; skripty mají natvrdo starého provozovatele ve stubu konstant → opravit). Velín kopie výchozích textů velin/src/pages/cms/webTexts*.js zarovnat (Opus).
- Majitel rozhodl dříve: seznam 23 výhod na úvodní stránce nechat (vráceno po W1). Čekám od něj: export Search Console, jak se web nasazuje na Hosting90, „ano“ k SQL (20261127a kódy, 20261127b eshop_visible_web, SEO SQL), otázky z reportů (W1 10, W2 7, D2 27, + level-up intro při každém startu).
- Kalkulačka s přistavením: po mapě pravidel implementace web + appka (Fable), drobnosti Opus. Appka až po doběhnutí agenta A–E (konflikty).

## Stav 27. 11. pozdě večer
- Majitel: „ANO, ANO“ = schválil SQL (kódy, eshop_visible_web, SEO texty) → v supabase/migrations 20261127a1–a3, b, 20261128a1–a3, b1–b2, c1–c5 + STATE (commit b77a23f4). „Nasazuje se ručně“ = web na Hosting90 nahrává ručně → na konci mu dát seznam změněných souborů webu. „FAQ musí korespondovat s realitou“ → FAQ SQL (e1/e2) NEcommitnuto, běží audit FAQ proti realitě (agent a9734c735033b388f → $S/faq/). Hlavní slova (20261128d) čekají na Search Console.
- Provozovatel: inventura hotová ($S/operator/inventory.md, plan.md, sql_draft.sql). Datová schránka s.r.o. = 2xfihrd (ISDS veřejný seznam). IBAN CZ8320100000002303580494. Rozhodnutí: vše v JEDNOM merge (kód tolerantní k chybějícímu sloupci), invoices.issuer_snapshot chrání staré doklady, dobropis dědí vystavitele, smlouvy „zastoupená jednatelem“, patička webu beze změny, appka = 5.0.3 (ne 5.0.4).
  Běží: backend a151fd79d2e781a1a (edge + SQL návrhy do $S/operator/sql/ + PREHLED_ZMEN.md), web ac749623d58211779, Velín ae67a3eb921844130. Appka (operator_info.dart, faktury ze snapshotu, SOS karta) AŽ po doběhnutí agenta appky A–E.
  Majitel musí: Fio token → secret FIO_API_TOKEN; 3 PDF e-shop (OP, reklamační řád, cookies); Stripe; účetní (zálohy/poukazy přijaté OSVČ).
- Level-up opravy hotové (29 testů). Otázka majiteli: úvodní animace při každém startu → jen poprvé? (mg_intro_shown do keep-listu).
- Kalendáře web hotové (commit 37e025fc). Kalkulačka web s přistavením běží (a3d57e12ee2046a78); appka kalkulačka až po A–E. Majiteli položena otázka na 4 rozdíly web × appka u přistavení.
- Po všem: CLAUDE.md (Firma, účet, issuer_snapshot pravidlo, 5.0.3 rozhodnutí), seznam souborů webu k nahrání, závěrečný běh celé sady testů appky (Android + iOS scratch), analyze, diff -rq.

## POZOR 27. 11. ~21:45 — majitel sám merguje větev do main (PR #2234 v 20:07 a #2235 ve 21:43 CET)
- Merge = edge + SQL + Velín jdou naostro. Zatím se dostalo naostro jen hotové (SQL kódy/eshop flag/SEO texty, process-payment kódy, Velín flags). Web a appka se nasazují ručně.
- Majiteli řečeno: NEMERGOVAT / nenahrávat web / nebuildovat appku, dokud nenapíšu „připraveno“. Větev sloučena s main (merge commit b626df98), 6 commitů před main.
- Na větvi nyní NEsloučeno: FAQ migrace e1–e3 (schváleno „dávám nové ano k faq“), změna provozovatele web (hotovo), Velín (hotovo, build OK), backend (běží a151fd79d2e781a1a), kalkulačka web (běží), appka A–E (běží).
- SQL návrhy čekající na schválení: $S/faq/sql_fix/20261128f_web_booking_license_groups.sql (skútry na ŘP B; hotovo+test), $S/operator/sql/* (běží), fioqr (návrh běží a746628a34c904868).
- PDF e-shopu: stáhnuto do $S/operator/pdf_in/, nové se vyrábí (Opus a5d36fd8868f8a09d → $S/operator/pdf_out/out/), datum účinnosti 28. 11. 2026 (parametr).
- Po merge připomenout majiteli: znovu načíst Velín (stará karta = staré konstanty), překlady ve Velínu, vyčistit cache webu.
- Slevomat workflow (slevomat-vouchers.yml) padá 26. i 27. 11. (schedule) — zmínit majiteli.

## Stav 27. 11. noc
- GSC data od majitele: /root/.claude/uploads/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/{542fae48-MotoGo24_SEO_data.xlsx, accba8ac-MotoGo24_SEO_analyza.pdf, c39ab330-MotoGo24_SEO_komplet.zip}. Závěr PDF: „půjčovna motorek“ mobil 7,78→4,85, počítač ~15 (slabina), hlavní URL = homepage; /oblasti sbíralo zobrazení; návrh title „Půjčovna motorek bez kauce | MotoGo24“, H1 s „Motopůjčovna“; 404 rodiny (…000005, /blog/podporte-sen-…), 23 neplatných Product. Běží Fable agent a5136355c956a48f8 → $S/seo/gsc/ (SQL návrh 20261128g_seo_head_terms.sql nahradí 20261128d, SHRNUTI_PRO_MAJITELE.md, změny v motogo-web-php).
- Web kalkulačka s přistavením HOTOVÁ (a3d57e12ee2046a78): nové js/delivery-rules.js, landing-calc-delivery(.ui).js, rezervace-delivery-carry.js, css/landing-calc-delivery.css, pages/katalog-calc-delivery.php; snímky $S/calcweb/. Nález: živé překlady názvů doplňků přistavení/vrácení ve Velínu (DE/PL/EN/ES/NL/FR) nesedí se vzory v _booking_extras_delivery (ILIKE 'Motorradlieferung%' atd.) → u cizojazyčných rezervací s přistavením se při úpravě rezervace poplatek započítá špatně/na druhou stranu. Na seznam nesrovnalostí (oprava: formulář posílat kanonické názvy, nebo opravit překlady). Též živý CS text rez.alert.minTimeDelivery končí „: + 6 hodin“.
- Appka A–E hotová (7472 testů). Běží: appka provozovatel a38c7254cb92d505f, appka kalkulačka aac36f157f5ecc70c, backend provozovatel a151fd79d2e781a1a.
- Fio/QR návrh hotový ($S/fioqr/); 9 výchozích pravidel posláno majiteli; stavba po backendu provozovatele. 1 min interval = ano (s lease + tichým logováním).
- PDF e-shopu hotová ($S/operator/pdf_out/out/), poslána majiteli; nahraje je ve Velínu až s přepnutím provozovatele.
- SQL návrh skútry ŘP B: $S/faq/sql_fix/20261128f_web_booking_license_groups.sql (+ poznamka_pro_majitele.md) — poslat ke schválení s SQL provozovatele.
- Otevřené otázky majiteli: úvodní animace jen poprvé?; 4 rozdíly přistavení web×appka; 4 věci k appce (Rezervovat na Domů, Nová rezervace místo CTA v prázdném stavu, fotky e-shopu, starý vzhled kalendáře); 9 pravidel QR; otázky k textům (45) a FAQ (14); datum účinnosti PDF.
- Majitel 27. 11. noc: „ano jinak vše ok“ = beru jako ANO k opravě názvů doplňků přistavení/vrácení (web má posílat pevné názvy) + souhlas s výchozími pravidly (QR 9 bodů, appka 4 body). Zeptal se, zda Fio bude párovat i podle částky a jména → dnes JEN VS; doplnit do stavby Fio/QR (B1 + V1): u nespárované platby ve Velínu návrh kandidátů (stejná částka mezi čekajícími + podobnost jména plátce), potvrzení jedním klikem; plně automaticky jen pokud majitel výslovně chce (zeptáno).
- Do webu doplnit (malý úkol, Opus): rezervační formulář posílá do create_web_booking kanonické názvy doplňků přistavení/vrácení (viz vzory v _booking_extras_delivery) nezávisle na CMS překladech; + oprava textu rez.alert.minTimeDelivery („: + 6 hodin“) do SQL.
- Majitel: párování podle částky+jména = JEN návrh ve Velínu s potvrzením jedním klikem (žádná automatika); automatiku případně později.
- Backend provozovatele HOTOV (a151fd79d2e781a1a), dolaďuje SQL (literál firmy v protokolech, STATE_ZMENY.md). SQL návrhy: $S/operator/sql/20261129a…f + 00_checks_before.sql, 99_checks_after.sql, PREHLED_ZMEN.md. Po doladění poslat majiteli ke schválení SPOLU s $S/faq/sql_fix/20261128f_web_booking_license_groups.sql.
- Běží: Fio/QR backend abc523b754d3d8555 (píše $S/fioqr/CONTRACT.md → pak spustit Velín „Banka“ agenta a později web W1–W3), web názvy doplňků (Opus) ad9d61375ba204c92, SEO GSC a5136355c956a48f8, appka provozovatel a38c7254cb92d505f, appka kalkulačka aac36f157f5ecc70c.
- Majitel o SEO: web se měnil stovkykrát (data nejsou měřením dnešního webu), Google v listopadu změnil podmínky → předáno SEO agentovi.

## 27. 11. noc — schváleno „Ano“: provozovatel SQL + skútry ŘP B
- Migrace 20261128f + 20261129a…f jsou na větvi (commit e2e7fc68); STATE doplňuje Opus agent ad806ebb1e96f8922 (+ společná zkouška e1…f na rigu). CLAUDE.md upraven (provozovatel, web ručně, majitel merguje sám, 5.0.3).
- Fio backend agent abc523b754d3d8555: „deploy-safe now“, DRŽÍ zapojení do existujících vstupů, dokud nepošlu „merge done — wire now“. Velín Banka agent a536e34f59dedf04b: staví v velin/src/pages/accounting/bank/ bez importu; registraci (Finance.jsx) udělá až po „merge done“; ozve se „ready to register“.
- Velín z HEAD se sestaví (ověřeno v $S/velin_headbuild).
- Až Opus agent potvrdí zkoušku: napsat majiteli „PŘIPRAVENO“ + postup: 1) merge větve, 2) počkat na zelené deploye (SQL, edge) + Vercel, 3) znovu načíst Velín, 4) nahrát 3 PDF e-shopu ve Velínu + přeložit, 5) ve Velínu nechat přeložit VOP/smlouvu/GDPR/protokoly + dotčené texty/FAQ, 6) web NEnahrávat, dokud nepošlu seznam (SEO agent ještě upravuje web), 7) appku nebuildovat, dokud neřeknu. Po merge poslat agentům „merge done“.

## 27. 11. ~23:00 CET — „PŘIPRAVENO“ odesláno majiteli (merge změny provozovatele)
- Třetí merge majitele: PR #2236 ve 22:05 CET (větev na b626df98) → naostro FAQ e1–e3 + kód provozovatele pro edge/Velín v režimu „nový kód + stará DB“ (ukazuje starého provozovatele z company_info; bezpečné, deploye zelené).
- Čekající migrace na větvi (vs main): 20261128f, 20261129a–f. Společná zkouška e1…f OK (Opus ad806ebb1e96f8922), STATE_1–6 doplněny (commit 178cc13c), větev sloučena s main (a62e7168).
- Majiteli poslán postup: merge → 7 min → Ctrl+F5 Velín → nahrát 3 PDF → přeložit → kontrola. Web NEnahrávat, appku NEbuildovat, po merge znovu neslučovat, dokud neřeknu.
- AŽ MAJITEL POTVRDÍ MERGE (nebo to zjistím přes git fetch origin main): poslat „merge done — wire now“ agentovi abc523b754d3d8555 (Fio backend) a „merge done“ agentovi a536e34f59dedf04b (Velín Banka). Ověřit Actions (deploy-sql, deploy-functions) + sql-deploy-failed issues. Pak sloučit main do větve.
- Při každém WIP commitu teď hlídat: žádné změny existujících edge vstupů ani existujících souborů Velínu (jen nové nezapojené soubory), dokud merge neproběhne.
