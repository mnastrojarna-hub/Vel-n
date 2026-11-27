-- =============================================================================
-- 20261128a3_seo_blog_fixes_3.sql (část 3/3)
-- 2026-11-28, schváleno majitelem 2026-11-27. Části 1–3 vznikly rozdělením jednoho souboru po celých článcích
-- (všechny úpravy jednoho článku jsou v jedné části, v původním pořadí). Tato část: články podpor-sen-sveho-maleho-motorkare, laska-na-dvou-kolech, svoboda-se-da-pujcit, top-10-darku-…, aplikace-motogo24-…, proc-si-pujcit-motorku-…, vyhraj-motorku-….
-- Datová migrace (bez změn schématu): opravy textů blogových článků v cms_pages.
--
-- Zadání majitele 2026-11-27: zkvalitnění textů pro SEO. Podklad: redakční/SEO revize blogu
-- a motorek z 2026-11-27 (review_blogbikes.json). Tento soubor řeší jen to, co jde opravit
-- přesnou, ověřitelnou změnou textu:
--   1) titulek a perex článků s verdiktem „ponechat / opravit“. Web bere <title> i H1 ze sloupce
--      `title` (příponu „ | Blog MotoGo24“, u titulků nad 45 znaků „ | MotoGo24“, přidává
--      pages/blog-detail.php sám — do sloupce se proto NEPÍŠE) a meta description, viditelný perex
--      i perex ve výpisu blogu ze sloupce `excerpt` (sloupec meta_description web nečte). Cíl:
--      <title> do 60 znaků, perex do 155 znaků;
--   2) věcné opravy vět, které odporují VOP (verze 15, účinné od 1. 8. 2026, čl. 6, 7 a 10),
--      pobočkám (motogo-web-php/data/pobocky.php), FAQ nebo vlastnímu průzkumu kaucí
--      (motogo-web-php/data/landing-trust.php, 17 půjčoven, 22. 10. 2026), a pravopis;
--   3) článek „12 hlavních výhod MotoGo24“ vložený z Wordu: odstavce byly zabalené v <h2>
--      (26 „nadpisů“ místo 13). Odstavce jsou nově <p>, nadpisy 1.–12. čisté <h2>; znění
--      textu se tímto krokem nemění ani o slovo (ověřeno porovnáním viditelného textu).
--
-- Záměrně NEMĚNÍ: schéma; překlady (sloupec translations — cizojazyčné verze článků zůstávají
-- ve starém znění, po nasazení je potřeba ve Velínu u dotčených článků znovu spustit překlad);
-- články k přepsání / sloučení / noindex jako celek (jen jednotlivé chybné věty); slugy;
-- stav publikace; tvrzení, která musí potvrdit majitel (superlativy „jediná / největší“,
-- čísla o konkurenci, počty tras, výsledek soutěže) — ta jsou v seznamu otázek pro majitele.
--
-- Bezpečnost: každý UPDATE míří na jeden článek (id + slug) a provede se jen tehdy, když je
-- v něm stále přesně to znění, proti kterému byl připraven (živá data 2026-11-27, REST anon):
-- titulek/perex porovnáním celé hodnoty, věta v článku jen když je v textu právě jednou,
-- přestavba článku z Wordu jen při shodě md5 celého obsahu. Co mezitím někdo upravil ve
-- Velínu, se přeskočí (UPDATE 0). Idempotentní — 2. běh nezmění nic. Bez BEGIN/COMMIT:
-- deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP). updated_at nastaví
-- trigger cms_pages_updated_at (propíše se do dateModified ve schématu článku).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- /blog/podpor-sen-sveho-maleho-motorkare
-- verdikt: opravit (P2) — titulek, perex, pravidla z VOP čl. 10 a konkrétní stroje (FAQ), pomlčky
-- -----------------------------------------------------------------------------
-- Titulek/H1: hledaný dotaz („od kolika let“) místo obecného „Podpoř sen…“. <title> = „Půjčení dětské motorky: od kolika let a jak začít | MotoGo24“ (60 znaků).
UPDATE public.cms_pages
   SET title = $new$Půjčení dětské motorky: od kolika let a jak začít$new$
 WHERE id = '30595eae-9ca4-4161-aec1-43d53ff0d953' AND slug = 'podpor-sen-sveho-maleho-motorkare'
   AND title = $old$Podpoř sen svého malého motorkáře$old$;
-- Perex = meta description: odpovídá na otázky rodičů; věk podle FAQ, pobočka podle katalogu. (136 znaků; dosud 91)
UPDATE public.cms_pages
   SET excerpt = $new$Od kolika let na motorku, jak poznat, že je dítě připravené, a kde smí jezdit. Dětské motorky od 3–4 let k půjčení v Mezné u Pelhřimova.$new$
 WHERE id = '30595eae-9ca4-4161-aec1-43d53ff0d953' AND slug = 'podpor-sen-sveho-maleho-motorkare'
   AND excerpt = $old$Půjčení dětské motorky je nejjednodušší způsob, jak zjistit, jestli zájem o ježdění vydrží.$old$;
-- DOPLNĚNÝ odstavec (článek pravidla neuváděl): VOP čl. 10 a)–d) — jen uzavřený prostor mimo pozemní komunikace, dohled dospělého,
-- ochranná výbava, nájemce 18+; stroje a věk podle FAQ „Od kolika let může dítě jezdit na motorce?“, všechny tři stojí v Mezné.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$doporučíme vhodná místa pro ježdění.</strong></p><p>Naším cílem není$old$,
               $new$doporučíme vhodná místa pro ježdění.</strong></p><p>Na dětských motorkách se smí jezdit jen v&nbsp;uzavřeném, bezpečném prostoru mimo silnice, stezky a&nbsp;chodníky, vždy pod dohledem dospělého a&nbsp;s&nbsp;ochrannou výbavou (helma, rukavice, moto kalhoty a&nbsp;pevná obuv); nájemcem je vždy zákonný zástupce starší 18 let. V&nbsp;Mezné u&nbsp;Pelhřimova půjčujeme Yamahu PW 50 (od 3–4 let), KTM SX 50 Replica (od 5–6 let) a&nbsp;Husqvarnu TC 65 (9–12 let).</p><p>Naším cílem není$new$)) AS x(old, new)
 WHERE p.id = '30595eae-9ca4-4161-aec1-43d53ff0d953' AND p.slug = 'podpor-sen-sveho-maleho-motorkare'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Typografie: rozsah s pomlčkou.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$od 3-4 let nejdříve$old$,
               $new$od 3–4 let nejdříve$new$)) AS x(old, new)
 WHERE p.id = '30595eae-9ca4-4161-aec1-43d53ff0d953' AND p.slug = 'podpor-sen-sveho-maleho-motorkare'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Typografie: rozsah s pomlčkou.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$od 5-6 let ideálně$old$,
               $new$od 5–6 let ideálně$new$)) AS x(old, new)
 WHERE p.id = '30595eae-9ca4-4161-aec1-43d53ff0d953' AND p.slug = 'podpor-sen-sveho-maleho-motorkare'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/laska-na-dvou-kolech
-- verdikt: opravit (P3) — perex měl 34 znaků a začínal malým písmenem; pravopis
-- -----------------------------------------------------------------------------
-- Titulek/H1: téma článku (motorkářská svatba) místo „Láska na dvou kolech“. <title> = „Motorkářská svatba: příběh a tipy na motorky | Blog MotoGo24“ (60 znaků).
UPDATE public.cms_pages
   SET title = $new$Motorkářská svatba: příběh a tipy na motorky$new$
 WHERE id = 'bd6dece7-5a8c-44fb-8221-31cee3aa7c76' AND slug = 'laska-na-dvou-kolech'
   AND title = $old$Láska na dvou kolech$old$;
-- Perex = meta description: obsah článku místo „aneb netradiční motorkářská svatba“. (146 znaků; dosud 34)
UPDATE public.cms_pages
   SET excerpt = $new$Svatba na motorkách? Příběh Dáši a Lukáše, pět důvodů pro motorkářskou svatbu a jak u MotoGo24 domluvit víc motorek najednou i se svatební slevou.$new$
 WHERE id = 'bd6dece7-5a8c-44fb-8221-31cee3aa7c76' AND slug = 'laska-na-dvou-kolech'
   AND excerpt = $old$aneb netradiční motorkářská svatba$old$;
-- Pravopis: chybějící předložka.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$těšíme se tebe!$old$,
               $new$těšíme se na tebe!$new$)) AS x(old, new)
 WHERE p.id = 'bd6dece7-5a8c-44fb-8221-31cee3aa7c76' AND p.slug = 'laska-na-dvou-kolech'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: „z venku“ → „zvenku“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$z venku$old$,
               $new$zvenku$new$)) AS x(old, new)
 WHERE p.id = 'bd6dece7-5a8c-44fb-8221-31cee3aa7c76' AND p.slug = 'laska-na-dvou-kolech'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/svoboda-se-da-pujcit
-- verdikt: ponechat (P3) — titulek, perex, dvě gramatické chyby
-- -----------------------------------------------------------------------------
-- Titulek/H1: doplněno, o čem příběh je. <title> = „Svoboda se dá půjčit: jak vzniklo MotoGo24 | Blog MotoGo24“ (58 znaků).
UPDATE public.cms_pages
   SET title = $new$Svoboda se dá půjčit: jak vzniklo MotoGo24$new$
 WHERE id = '901e4e63-1e1a-4d05-9a3b-1b07b2ccf39b' AND slug = 'svoboda-se-da-pujcit'
   AND title = $old$Svoboda se dá půjčit$old$;
-- Perex = meta description: se jménem značky a klíčovým slovem. (143 znaků; dosud 91)
UPDATE public.cms_pages
   SET excerpt = $new$Příběh rodinné motopůjčovny MotoGo24: jak se z rozhovorů nad sklenkou vína a jednoho letního večera v Krušných horách zrodila půjčovna motorek.$new$
 WHERE id = '901e4e63-1e1a-4d05-9a3b-1b07b2ccf39b' AND slug = 'svoboda-se-da-pujcit'
   AND excerpt = $old$Příběh o tom, jak se z jednoho snu a letního večera v Krušných horách zrodila motopůjčovna.$old$;
-- Pravopis: nadbytečné „se“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Mluvili jsme se o&nbsp;tom$old$,
               $new$Mluvili jsme o&nbsp;tom$new$)) AS x(old, new)
 WHERE p.id = '901e4e63-1e1a-4d05-9a3b-1b07b2ccf39b' AND p.slug = 'svoboda-se-da-pujcit'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: chybějící „jsme“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$A&nbsp;znovu se zamilovali do toho pocitu$old$,
               $new$A&nbsp;znovu jsme se zamilovali do toho pocitu$new$)) AS x(old, new)
 WHERE p.id = '901e4e63-1e1a-4d05-9a3b-1b07b2ccf39b' AND p.slug = 'svoboda-se-da-pujcit'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/top-10-darku-pro-motorkare-ktere-skutecne-potesi
-- verdikt: opravit (P2) — „Top 10“ nesedí (článek má 2 × 10 tipů), krátký perex, pravopis
-- -----------------------------------------------------------------------------
-- Titulek/H1: článek obsahuje 10 tipů pro dospělé + 10 pro děti. <title> = „Dárek pro motorkáře: 20 tipů pro dospělé i děti | MotoGo24“ (58 znaků).
UPDATE public.cms_pages
   SET title = $new$Dárek pro motorkáře: 20 tipů pro dospělé i děti$new$
 WHERE id = 'c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0' AND slug = 'top-10-darku-pro-motorkare-ktere-skutecne-potesi'
   AND title = $old$Top 10 dárků pro motorkáře, které skutečně potěší$old$;
-- Perex = meta description: konkrétní obsah místo řečnické otázky. (153 znaků; dosud 60)
UPDATE public.cms_pages
   SET excerpt = $new$Dárky pro motorkáře, které se opravdu použijí: od drobností do 500 Kč přes intercom a kameru až po dárkový poukaz na půjčení motorky. Pro dospělé i děti.$new$
 WHERE id = 'c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0' AND slug = 'top-10-darku-pro-motorkare-ktere-skutecne-potesi'
   AND excerpt = $old$Hledáš dárek pro motorkáře, na který nebude jen sedat prach?$old$;
-- Pravopis: „tématika“ → „tematika“ (1/3).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$s&nbsp;moto tématikou$old$,
               $new$s&nbsp;moto tematikou$new$)) AS x(old, new)
 WHERE p.id = 'c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0' AND p.slug = 'top-10-darku-pro-motorkare-ktere-skutecne-potesi'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: „tématika“ → „tematika“ (2/3).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$s&nbsp;motorkářskou tématikou$old$,
               $new$s&nbsp;motorkářskou tematikou$new$)) AS x(old, new)
 WHERE p.id = 'c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0' AND p.slug = 'top-10-darku-pro-motorkare-ktere-skutecne-potesi'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: „tématika“ → „tematika“ (3/3).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$s&nbsp;motocyklovou tématikou$old$,
               $new$s&nbsp;motocyklovou tematikou$new$)) AS x(old, new)
 WHERE p.id = 'c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0' AND p.slug = 'top-10-darku-pro-motorkare-ktere-skutecne-potesi'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Typografie: rozsah bez mezer, tisíce s mezerou (jako „nad 2 000 Kč“ o řádek níž).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$<p>500 – 2000 Kč – kvalitní$old$,
               $new$<p>500–2 000 Kč – kvalitní$new$)) AS x(old, new)
 WHERE p.id = 'c84d8e65-eb6e-4bd8-bf11-cf3256ae3dd0' AND p.slug = 'top-10-darku-pro-motorkare-ktere-skutecne-potesi'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/aplikace-motogo24-pujcovna-navigace-i-partak-na-cesty
-- verdikt: opravit (P2) — titulek dával se značkou 66 znaků, perex 200; počet tras („přes 1 370“) beze změny — potvrdí majitel
-- -----------------------------------------------------------------------------
-- Titulek/H1 zkrácen, s funkcemi, které lidé hledají. <title> = „Aplikace MotoGo24: rezervace motorky, trasy i SOS | MotoGo24“ (60 znaků).
UPDATE public.cms_pages
   SET title = $new$Aplikace MotoGo24: rezervace motorky, trasy i SOS$new$
 WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7' AND slug = 'aplikace-motogo24-pujcovna-navigace-i-partak-na-cesty'
   AND title = $old$Aplikace MotoGo24: půjčovna, navigace i parťák na cesty$old$;
-- Perex = meta description: zkráceno; číslo „přes 1 370 tras“ převzato z dosavadního perexu. (141 znaků; dosud 200)
UPDATE public.cms_pages
   SET excerpt = $new$Rezervace a úprava výpůjčky, smlouvy a faktury na jednom místě, přes 1 370 tras s navigací a SOS linka. Aplikace zdarma pro Android i iPhone.$new$
 WHERE id = '4185202a-9c04-4101-a098-423b7cd3ade7' AND slug = 'aplikace-motogo24-pujcovna-navigace-i-partak-na-cesty'
   AND excerpt = $old$Rezervace motorky za dvě minuty, přes 1 370 tras po okolí, SOS tlačítko pro případ nouze i věrnostní slevy — to všechno teď nosíš v kapse. Aplikace MotoGo24 je ke stažení na Google Play i v App Store.$old$;

-- -----------------------------------------------------------------------------
-- /blog/proc-si-pujcit-motorku-misto-toho-abys-ji-kupoval
-- verdikt: přepsat (P2) — celý přepis je navazující práce; zde jen věta odporující VOP čl. 6 a gramatika
-- -----------------------------------------------------------------------------
-- VOP čl. 6 a), d) a čl. 7 d), g): nájemce musí událost hlásit a řídit se pokyny; „problémy řeší motopůjčovna“ je zavádějící.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Pokud se během jízdy něco přihodí, problémy řeší motopůjčovna.$old$,
               $new$Když se během jízdy něco stane, zavoláš nám a&nbsp;provedeme tě dalším postupem; škody na motorce, které zaviníš, u&nbsp;MotoGo24 kryje 100% smluvní krytí se spoluúčastí 0&nbsp;Kč (neplatí pro odcizení a&nbsp;zapůjčenou výbavu).$new$)) AS x(old, new)
 WHERE p.id = '051b9fa4-6c59-443d-90e8-2d95ff1562ef' AND p.slug = 'proc-si-pujcit-motorku-misto-toho-abys-ji-kupoval'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: nadbytečné „se“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$nebo se chceš jen zjistit$old$,
               $new$nebo chceš jen zjistit$new$)) AS x(old, new)
 WHERE p.id = '051b9fa4-6c59-443d-90e8-2d95ff1562ef' AND p.slug = 'proc-si-pujcit-motorku-misto-toho-abys-ji-kupoval'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/vyhraj-motorku-rozjizdime-soutez-s-next1k
-- verdikt: noindex (řeší se v kódu); výsledek soutěže doplní majitel — zde jen pravopis
-- -----------------------------------------------------------------------------
-- Pravopis: „přibyde“ → „přibude“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$brzy přibyde další motorkář$old$,
               $new$brzy přibude další motorkář$new$)) AS x(old, new)
 WHERE p.id = '5a901658-0c66-4e72-930e-78f5e3a0561c' AND p.slug = 'vyhraj-motorku-rozjizdime-soutez-s-next1k'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
