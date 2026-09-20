-- MotoGo24 — katalog míst: nová kategorie „Studánky a prameny" + přetřídění
-- ------------------------------------------------------------------------
-- Zadání uživatele (2026-09-20): „lépe roztřiď dle filtru, například kopce
-- mohou být jako rozhledny". Katalog má dnes 40 515 řádků a kategorie u části
-- z nich neodpovídá tomu, co místo doopravdy je:
--   * 255 objektů československého opevnění (Dobrošov, Stachelberg, Hanička,
--     pěchotní sruby „N-S 82 Březinka", řopíky) má kategorii `castle`
--     s automatickým popisem „Hrad či zámek v Česku" — kategorie `military`
--     měla pro celé Česko JEDINÝ záznam,
--   * 145 pojmenovaných vrchů a hor zůstalo v `nature` (mezi rybníky a sedly),
--     takže je chip „Rozhledny a vrcholy" neukáže,
--   * 137 vodopádů je v `nature` místo `water`,
--   * studánky a prameny neměly kategorii ŽÁDNOU — proto se v appce nedaly
--     vyfiltrovat (uživatel: „chybí studánky").
--
-- Migrace proto:
--   1) rozšiřuje CHECK o hodnotu `spring` (Studánky a prameny),
--   2) přetřiďuje existující body podle NÁZVU (u opevnění i podle popisu)
--      konzervativními pravidly s negativními výjimkami — městské hradby
--      zůstávají u hradů, sedla/plesa/rezervace zůstávají v přírodě.
-- Idempotentní: pravidla jsou `where category in (...) and name ~* ...`,
-- opakované spuštění už nic nenajde.

-- 1) Číselník kategorií ------------------------------------------------------
alter table public.points_of_interest
  drop constraint if exists points_of_interest_category_check;
alter table public.points_of_interest
  add constraint points_of_interest_category_check check (category in (
    'food','castle','lookout','water','spring','sights','nature',
    'other','military','aviation','tech','moto'));

-- 2a) Československé opevnění, bunkry, vojenská muzea → military -------------
update public.points_of_interest
   set category = 'military', updated_at = now()
 where category in ('castle','sights','nature','tech','other','lookout')
   and (name || ' ' || coalesce(description,'')) ~*
       '(řop\M|\mr-s ?[0-9]|\mk-s ?[0-9]|\mn-s ?[0-9]|\mmo-s ?[0-9]|\mt-s ?[0-9]|\mb-s ?[0-9]|řopík|ropík|pěchotní srub|dělostřelecká tvrz|dělostřelecký srub|lehké opevnění|těžké opevnění|čs\. opevnění|čs opevnění|československého opevnění|bunkr|bunker|pevnůstk|muniční sklad|maginot|atlantikwall|vojenské muzeum|vojenský prostor|kasárn|podzemní kryt)'
   and (name || ' ' || coalesce(description,'')) !~*
       '(městské opevnění|mestské opevnenie|hradby)';

-- 2b) Motocyklová a automobilová muzea, okruhy → moto ------------------------
update public.points_of_interest
   set category = 'moto', updated_at = now()
 where category in ('sights','tech','castle','nature','other')
   and name ~* '(motocyklov|muzeum motocykl|muzeum mopedů|automuzeum|muzeum automobil|muzeum veterán|autodrom|závodní okruh|motokros)';

-- 2c) Studánky, prameny, prameniště, kyselky → spring ------------------------
update public.points_of_interest
   set category = 'spring', updated_at = now()
 where category in ('nature','water','lookout','sights','other','tech','castle')
   and name ~* '(studánk|studánc|prameništ|pramenisk|kyselk|vývěr|\mpramen\M|\mprameny\M|\mpramene\M|žriedl|minerální pramen)'
   -- Negativní pojistka se MUSÍ dívat i do popisu: u bodů z Wikidat je druh
   -- objektu skoro vždy jen tam („Vrchol v Česku, 604 m n. m."), takže
   -- „Nad Zlatou studánkou" (vrchol) ani „Sedlo nad Karlovou Studánkou"
   -- (průsmyk) do studánek nepatří — jsou po studánce jen pojmenované.
   and (name || ' ' || coalesce(description,'')) !~*
       '(řop\M|\mr-s ?[0-9]|srub|bunkr|pramenitá|pramenice|rozhledna|\mvrch\M|\mvrchol|\mhora\M|\mkopec\M|\msedlo|průsmyk|priesmyk)';

-- 2d) Vodopády → water -------------------------------------------------------
update public.points_of_interest
   set category = 'water', updated_at = now()
 where category in ('nature','lookout','other')
   and name ~* '(vodopád|vodopad|waterfall|wasserfall)';

-- 2e) Mlýny, štoly, hamry, hornická a technická muzea → tech -----------------
update public.points_of_interest
   set category = 'tech', updated_at = now()
 where category in ('nature','water','lookout','castle','sights','other')
   -- „Hamr" je i název OBCE (Hamr na Jezeře) a „viadukt" se objevuje
   -- v názvech přírodních památek („U Banínského viaduktu"), proto u obou
   -- vyžadujeme upřesnění.
   and name ~* '(větrný mlýn|veterný mlyn|vodní mlýn|vodný mlyn|vodní hamr|starý hamr|\mhamr [a-zá-ž]|\mštola\M|\mštoly\M|vápenka|železniční viadukt|kamenný viadukt|úzkokolejk|sklárna|papírna|koksovna|vysoká pec|železárn|těžní věž|hornické muzeum|hornická muzeum|technické muzeum|železniční muzeum)'
   and name !~* '(přehrada|nádrž|vodní dílo|rybník|jezero|^tvrz|^zámek|^zámeček|^hrad)'
   -- Popis prozradí, že jde o vrchol / památku / obec, ne o technický cíl.
   and (name || ' ' || coalesce(description,'')) !~*
       '(\mvrchol v |přírodní památka|prírodná pamiatka|chráněn|chránen)';

-- 2f) Pojmenované vrchy a hory, které zůstaly v přírodě → lookout ------------
--     (chip „Rozhledny a vrcholy"; navazuje na 20260919_poi_hills_recategorize.sql,
--      které jelo podle pevného seznamu z Wikidat — tohle dojede zbytek pravidlem)
update public.points_of_interest
   set category = 'lookout', updated_at = now()
 where category = 'nature'
   and name ~* '(\mvrch\M|\mvrchu\M|\mvrchy\M|\mhora\M|\mhory\M|\mkopec\M|\mkopce\M|\mvrchol\M|\mštít\M|\mhůrka\M|\mvršek\M|\mhoľa\M)'
   -- KLÍČOVÉ: negativní pojistka se musí dívat i do POPISU. U bodů z Wikidat
   -- je druh objektu skoro vždy jen tam („Přírodní památka v Česku…"), takže
   -- samotný název nic neprozradí a do „Rozhleden a vrcholů" by spadlo
   -- 142 chráněných území — „Přírodní památka Mařský vrch", „Arboretum
   -- Borová hora" i lom „Lom Janičův vrch".
   and (name || ' ' || coalesce(description,'')) !~*
       '(sedlo|průsmyk|priesmyk|pleso|jeskyn|jaskyn|rezervac|národní park|přírodní park|přírodní památk|prírodná pamiatk|chráněný areál|chránený areál|arboretum|\mlom\M|chko|chránen|chráněn|hrad|zámek|kostel|kaple|klášter|rybník|jezero|vodopád|studánk|pramen|synagog|muzeum|údolí|dolina|potok|\mpod\M)';
