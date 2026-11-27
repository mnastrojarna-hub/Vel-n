-- =============================================================================
-- 20261128a2_seo_blog_fixes_2.sql (část 2/3)
-- 2026-11-28, schváleno majitelem 2026-11-27. Části 1–3 vznikly rozdělením jednoho souboru po celých článcích
-- (všechny úpravy jednoho článku jsou v jedné části, v původním pořadí). Tato část: články zavadime-100-smluvni-kryti-skod, motorka-bez-kauce-u-motogo24-ano, proc-je-motogo24-nejlepsi-motopujcovna-v-cr, jaka-motorka-pro-zacatecnika-….
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
-- /blog/zavadime-100-smluvni-kryti-skod
-- verdikt: opravit (P1) — rozpory s VOP čl. 6–7, titulek, perex (měl 311 znaků), pravopis
-- -----------------------------------------------------------------------------
-- Titulek/H1: hlavní sdělení (spoluúčast 0 Kč) místo „Zavádíme…“. <title> = „100% smluvní krytí škod: spoluúčast 0 Kč | Blog MotoGo24“ (56 znaků).
UPDATE public.cms_pages
   SET title = $new$100% smluvní krytí škod: spoluúčast 0 Kč$new$
 WHERE id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND slug = 'zavadime-100-smluvni-kryti-skod'
   AND title = $old$Zavádíme 100% smluvní krytí škod$old$;
-- Perex = meta description: zkráceno, bez neověřeného tvrzení o „většině půjčoven“. (152 znaků; dosud 311)
UPDATE public.cms_pages
   SET excerpt = $new$Poškodíš-li motorku vlastní vinou, u MotoGo24 platíš spoluúčast 0 Kč. Za jakých podmínek krytí platí a co nekryje – krádež, výbavu a hrubé porušení VOP.$new$
 WHERE id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND slug = 'zavadime-100-smluvni-kryti-skod'
   AND excerpt = $old$Většina půjčoven motocyklů ti při nehodě naúčtuje spoluúčast v řádu desítek tisíc korun. My jsme ji zrušili. Od nové verze obchodních podmínek (od 1.8.2026) platí v MotoGo24 100% smluvní krytí škod se spoluúčastí 0 Kč – a v tomhle článku si poctivě řekneme, co to znamená, co to nekryje a proč jsme do toho šli.$old$;
-- VOP čl. 6 d), e) a čl. 7 d): policii je nájemce povinen přivolat VŽDY a je to podmínka krytí;
-- „pokud to situace vyžaduje“ mohlo zákazníka o krytí připravit (a odporovalo bodu 3 podmínek v témže článku).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$3. <strong>Přivolej policii, </strong>pokud to situace vyžaduje.$old$,
               $new$3. <strong>Vždy přivolej policii </strong>(158, v zahraničí místní policii) – je to podmínka smluvního krytí škod.$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- VOP čl. 7 g): parkovat na veřejném osvětleném místě, přes noc pokud možno hlídané parkoviště / uzamčená garáž.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$rozumné parkovací místo, použití kotoučového zámku$old$,
               $new$veřejné osvětlené místo, přes noc ideálně hlídané parkoviště nebo garáž, použití kotoučového zámku$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- VOP čl. 7 g): řádné zabezpečení prokazuje nájemce (ne policie); při porušení odpovídá až do obvyklé tržní hodnoty.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Pokud Policie prokáže, že bylo zabezpečení zanedbáno, odpovídáš za
plnou tržní hodnotu motocyklu.$old$,
               $new$Že byl stroj řádně zabezpečen, musíš prokázat ty. Když pravidla zabezpečení porušíš (klíč v zapalování, nezamčené řízení, bez kotoučového zámku, parkování na neosvětleném místě), odpovídáš až do obvyklé tržní hodnoty motocyklu.$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- VOP čl. 7 f): úplný výčet výluk (chyběla jízda bez řidičského oprávnění a zakázané účely); VOP pojem „hrubá nedbalost“ nepoužívá.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$nejezdíš pod vlivem alkoholu nebo návykových látek, nepředáš motorku někomu
dalšímu a nejde o hrubou nedbalost nebo úmysl.$old$,
               $new$nejezdíš pod vlivem alkoholu nebo návykových látek, máš platný řidičák příslušné skupiny, nepředáš motorku nikomu, kdo není uvedený ve smlouvě, nejezdíš závody ani soutěže a nejde o úmysl ani jiné hrubé porušení smlouvy či VOP.$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: čárka před „aby“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Je zapotřebí aby policie prověřila skutečnosti.$old$,
               $new$Je zapotřebí, aby policie událost prověřila.$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: „od teď“ → „odteď“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Kalkulace je od teď naše starost.$old$,
               $new$Kalkulace je odteď naše starost.$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Typografie: dvojitá mezera.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Telefonicky&nbsp; nebo přes$old$,
               $new$Telefonicky nebo přes$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Text odkazu: „Mrkni na Katalog motorek | MotoGo24“ → „Mrkni na katalog motorek“ (v odkazu byl zkopírovaný <title> stránky).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$>Katalog motorek | MotoGo24</a>$old$,
               $new$>katalog motorek</a>$new$)) AS x(old, new)
 WHERE p.id = 'c3356f4a-e608-4bca-b16d-dcee9dc6c101' AND p.slug = 'zavadime-100-smluvni-kryti-skod'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/motorka-bez-kauce-u-motogo24-ano
-- verdikt: přepsat (P1) — celý přepis je navazující práce; zde jen vymyšlená čísla a slib článku „brzy“
-- -----------------------------------------------------------------------------
-- Perex = meta description: „na 99 % zaplatíš kauci 10–30 tisíc“ je nepodložené číslo; nahrazeno údajem z vlastního průzkumu
-- ceníků 17 půjčoven z 22. 10. 2026 (kauce 10–50 tis., nejčastěji 20–30 tis. Kč — data/landing-trust.php). (146 znaků; dosud 84)
UPDATE public.cms_pages
   SET excerpt = $new$Jinde u velké motorky složíš kauci obvykle 20–30 tisíc Kč. U MotoGo24 ji neskládáš ani poprvé. Jak to funguje a co se děje, když motorku poškodíš.$new$
 WHERE id = 'b54a6520-e56c-4991-ad5a-062342018e82' AND slug = 'motorka-bez-kauce-u-motogo24-ano'
   AND excerpt = $old$Když si v Česku půjčíš motorku, na 99 % zaplatíš kauci 10–30 tisíc. U nás ne. Nikdy.$old$;
-- Druhé vymyšlené procento („zbývající 1 %“) nahrazeno doložitelným údajem z průzkumu. Zbytek věty („až od třetího pronájmu“)
-- beze změny — musí potvrdit majitel.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Zbývající 1 % jsou půjčovny, kde ti řeknou, že kauci$old$,
               $new$Podle našeho průzkumu ceníků 17 českých půjčoven (říjen 2026) se u velkých motorek skládá vratná kauce 10–50 tisíc Kč, nejčastěji 20–30 tisíc. A pak jsou půjčovny, kde ti řeknou, že kauci$new$)) AS x(old, new)
 WHERE p.id = 'b54a6520-e56c-4991-ad5a-062342018e82' AND p.slug = 'motorka-bez-kauce-u-motogo24-ano'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Článek o škodách vyšel už v srpnu 2026 — místo slibu „brzy“ odkaz na něj (VOP čl. 7 d), g)).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Detailní postup při škodě, krádeži a pojistných
událostech najdeš v samostatném článku, který taky brzy najdeš na našem blogu. $old$,
               $new$Jak funguje 100% smluvní krytí škod se spoluúčastí 0 Kč a co nekryje (odcizení, zapůjčená výbava), najdeš v <a href="https://www.motogo24.cz/blog/zavadime-100-smluvni-kryti-skod">článku o 100% smluvním krytí škod</a>. $new$)) AS x(old, new)
 WHERE p.id = 'b54a6520-e56c-4991-ad5a-062342018e82' AND p.slug = 'motorka-bez-kauce-u-motogo24-ano'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/proc-je-motogo24-nejlepsi-motopujcovna-v-cr
-- verdikt: sloučit do „12 výhod“ (řeší se v kódu / redakčně); do té doby aspoň nepravdivé věty
-- -----------------------------------------------------------------------------
-- VOP čl. 7 b), d), g), k): havarijní pojištění sjednané není, krytí není pojištění a limit 5 000 Kč už neplatí.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$<strong>u nás po tobě nechceme žádnou náhradu škody do 5 000 Kč.</strong> Díky vlastnímu internímu havarijnímu pojištění tyhle maličkosti vůbec neřešíme.$old$,
               $new$<strong>u nás od 1. 8. 2026 platí 100% smluvní krytí škod:</strong> když motorku poškodíš vlastní vinou, tvoje spoluúčast je 0 Kč – při dodržení podmínek VOP (čl. 7). Krytí se nevztahuje na odcizení a zapůjčenou výbavu.$new$)) AS x(old, new)
 WHERE p.id = '5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc' AND p.slug = 'proc-je-motogo24-nejlepsi-motopujcovna-v-cr'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Web i aplikace mají 8 jazyků (cs, en, de, es, fr, nl, pl, uk — i18n.php I18N_SUPPORTED, appka supportedLocales).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$v <strong>sedmi jazycích</strong>$old$,
               $new$v <strong>osmi jazycích</strong>$new$)) AS x(old, new)
 WHERE p.id = '5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc' AND p.slug = 'proc-je-motogo24-nejlepsi-motopujcovna-v-cr'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Pravopis: „zapomenut“, „naše slovenských bratov“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$nesmíme zapomenut ani na naše slovenských bratov$old$,
               $new$nesmíme zapomenout ani na naše slovenské bratry$new$)) AS x(old, new)
 WHERE p.id = '5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc' AND p.slug = 'proc-je-motogo24-nejlepsi-motopujcovna-v-cr'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- data/pobocky.php + FAQ: přistavení jen z obslužné pobočky Mezná a za příplatek; Velké Němčice přistavení nenabízejí.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$<p>A motorku můžeme předat&nbsp;&nbsp;<strong>kdekoliv na území České republiky.</strong>&nbsp;</p>$old$,
               $new$<p>A motorky z pobočky v Mezné můžeme za příplatek přistavit <strong>kamkoli v České republice</strong>; motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají a vracejí jen na pobočce.</p>$new$)) AS x(old, new)
 WHERE p.id = '5ec9affa-b1e6-48c4-8d3f-a3ee1be22acc' AND p.slug = 'proc-je-motogo24-nejlepsi-motopujcovna-v-cr'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);

-- -----------------------------------------------------------------------------
-- /blog/jaka-motorka-pro-zacatecnika-radce-ktery-ti-pomuze-vybrat-prvni-stroj
-- verdikt: opravit (P2) — titulek měl 82 a perex 210 znaků; „nejnižší sedlo“ není pravda
-- -----------------------------------------------------------------------------
-- Titulek/H1 zkrácen. <title> = „Jaká motorka pro začátečníka? Rádce pro A2 i A | MotoGo24“ (57 znaků).
UPDATE public.cms_pages
   SET title = $new$Jaká motorka pro začátečníka? Rádce pro A2 i A$new$
 WHERE id = '2c803b4d-c0d0-4412-a43c-4948d45b9b45' AND slug = 'jaka-motorka-pro-zacatecnika-radce-ktery-ti-pomuze-vybrat-prvni-stroj'
   AND title = $old$Jaká motorka pro začátečníka? Rádce, který ti pomůže vybrat první stroj$old$;
-- Perex = meta description: zkráceno na obsah článku. (153 znaků; dosud 210)
UPDATE public.cms_pages
   SET excerpt = $new$Jak vybrat první motorku podle řidičáku A1, A2 nebo A, výšky sedla a hmotnosti – a proč ji nejdřív půjčit. Tipy na stroje pro začátečníky z naší flotily.$new$
 WHERE id = '2c803b4d-c0d0-4412-a43c-4948d45b9b45' AND slug = 'jaka-motorka-pro-zacatecnika-radce-ktery-ti-pomuze-vybrat-prvni-stroj'
   AND excerpt = $old$Uděláš si řidičák, těšíš se do sedla — a pak přijde otázka za milion: na čem začít? Poradíme ti, jak vybrat první motorku podle řidičáku, zkušeností i toho, jak chceš jezdit. A hlavně: nemusíš hned nic kupovat.$old$;
-- Věcná oprava: Honda VTX 1800 má v katalogu sedlo 700 mm a Kawasaki Z 900 také 795 mm.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Nejnižší sedlo v naší flotile (795 mm)$old$,
               $new$Jedno z nejnižších sedel v naší flotile (795 mm)$new$)) AS x(old, new)
 WHERE p.id = '2c803b4d-c0d0-4412-a43c-4948d45b9b45' AND p.slug = 'jaka-motorka-pro-zacatecnika-radce-ktery-ti-pomuze-vybrat-prvni-stroj'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
