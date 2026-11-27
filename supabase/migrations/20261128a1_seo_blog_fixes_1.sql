-- =============================================================================
-- 20261128a1_seo_blog_fixes_1.sql (část 1/3)
-- 2026-11-28, schváleno majitelem 2026-11-27. Části 1–3 vznikly rozdělením jednoho souboru po celých článcích
-- (všechny úpravy jednoho článku jsou v jedné části, v původním pořadí). Tato část: článek 12-hlavnich-vyhod-motogo24.
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
-- /blog/12-hlavnich-vyhod-motogo24
-- verdikt: opravit (P1) — titulek, perex, přestavba HTML z Wordu, pravopis, zelená karta
-- -----------------------------------------------------------------------------
-- Titulek/H1: doplněno, o čem článek je (půjčení motorky). <title> = „12 výhod půjčení motorky u MotoGo24 | Blog MotoGo24“ (51 znaků).
UPDATE public.cms_pages
   SET title = $new$12 výhod půjčení motorky u MotoGo24$new$
 WHERE id = '48a316a8-08d3-4d8b-8006-fa8edaaf4215' AND slug = '12-hlavnich-vyhod-motogo24'
   AND title = $old$12 hlavních výhod MotoGo24$old$;
-- Perex = meta description: konkrétní výhody a obě pobočky místo „kterými se MotoGo24 pyšní“. (152 znaků; dosud 107)
UPDATE public.cms_pages
   SET excerpt = $new$Bez kauce, bez limitu kilometrů, výbava pro řidiče v ceně a převzetí nonstop v Mezné u Pelhřimova i u Brna. Co u MotoGo24 dostaneš a za jakých podmínek.$new$
 WHERE id = '48a316a8-08d3-4d8b-8006-fa8edaaf4215' AND slug = '12-hlavnich-vyhod-motogo24'
   AND excerpt = $old$Bez kauce, bez limitu km a s kompletní výbavou řidiče v ceně. Tady je 12 výhod, kterými se MotoGo24 pyšní. $old$;
-- Přestavba HTML vloženého z Wordu: odstavce ven z <h2> do <p>, nadpisy 1.–12. a „Tak co — vyrazíš?“ jako čisté <h2>
-- (bez vloženého font-size), pryč jsou jen pomocné <span>, zalomení řádků z Wordu a prázdný odstavec na konci.
-- Tučné „komplet online check-in“ a odkaz „Rezervuj svou motorku →“ zůstávají tučné (<strong>). Znění beze změny.
-- Provede se jen při shodě md5 celého obsahu se stavem z 2026-11-27.
UPDATE public.cms_pages
   SET content = $html$<p style="margin-bottom: 8.0pt; line-height: 133%">Půjčit si motorku není věda — ale je to rozhodnutí. Spousta otázek, spousta nabídek a každá půjčovna slibuje něco trochu jiného. Tak jsme sepsali, co u nás dostaneš a proč si myslíme, že u MotoGo24 je líp než kdekoliv jinde:</p>
<h2>1. Půjčíme každému — bez omezení zkušeností</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Většina půjčoven po tobě vyžaduje 2–3 roky řidičáku, několik tisíc najetých kilometrů a místy ti dokonce řekne, kterým směrem můžeš jet. ;)</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">My ne. Stačí, že máš platný řidičák odpovídající kategorie a chuť vyrazit. Začátečník s čerstvým papírem? Vítej. Zkušený harcovník se sto tisíci km v nohách? Taky vítej.</p>
<h2>2. Bez kauce. Bez výmluv.</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Tahle věc nás odlišuje od všech půjčoven v&nbsp;Česku. Jsme jediná motopůjčovna v ČR, která půjčuje úplně bez kauce — a to už při první rezervaci.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">Nepotřebujeme blokovat desetitisíce korun na tvojí kartě, neúčtujeme zálohu, nemusíš s sebou tahat hotovost.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">Půjčíš si motorku, vyrazíš, vrátíš ji. Konec. Co ušetříš, můžeš dát do benzínu nebo do dálničních známek.</p>
<h2>3. Rezervuješ ráno, odpoledne jedeš</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Žádné dlouhé čekání na potvrzení, žádná dvoutýdenní rezervační anabáze. Online si rezervuješ stroj, zaplatíš a do hodiny u nás můžeš stát s helmou v ruce. Rezervaci, smlouvu i předání vyřídíme prakticky obratem.</p>
<h2>4. Vyzvedáš a vracíš kdykoliv — i o půlnoci</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Jestli chceš vyjet ráno v 5, nebo si motorku vrátit v neděli pozdě večer, klidně můžeš. Přizpůsobíme se tvému programu, ne ty našemu.</p>
<h2>5. Všechno vyřídíš online, 24/7</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Žádné papíry, žádné fronty, žádné dohadování po telefonu. Vyplníš si rezervaci, vybereš si stroj, termín i čas vyzvednutí, výbavu, zaplatíš — a kdykoliv si pak rezervaci sám/sama změníš, když to budeš potřebovat.</p>
<h2>6. Helma, bunda, kalhoty, rukavice — vše v ceně</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Kompletní výbavu pro řidiče máme v ceně pronájmu. Helmu, bundu, kalhoty i rukavice si u nás půjčíš zdarma — nemusíš tahat své věci přes celou republiku ani nic dál řešit.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">Přijdeš, převlékneš se, jedeš. A ušetříš tím tisíce korun, které bys jinak dal(a) za pořízení vlastní výbavy.</p>
<h2>7. Jeď do Itálie. Nebo na Balkán. Bez kilometrů, bez omezení.</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Tohle umožní málokterá půjčovna — s naší motorkou jezdíš kam chceš, klidně až mimo EU. Stačí se řídit územní platností vedenou v zelené kartě.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">A nehlídáme ti kilometry! Žádné limity, žádné doplatky, žádný stres. Užij si výlet podle sebe — Alpy, Balkán, Norsko, Turecko, kamkoliv tě to táhne.</p>
<h2>8. Pohodlné zázemí, ne polní operace</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">V Mezné u Pelhřimova jsme si vybudovali provozovnu, ve které ti bude příjemně. Najdeš tu:</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Oblékací kabinku — převlékneš se v klidu</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Toaletu — pohodlně</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Posezení — projedeš plán trasy</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Wi-Fi — pošleš e-mail nebo stáhneš mapy</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">Po dlouhé cestě k nám si můžeš oddychnout - než se vyhoupneš do sedla.</p>
<h2>9. Klidná lokalita — bez stresu z města</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Sídlíme u Pelhřimova, strategicky mezi Prahou a Brnem, blízko dálnice D1. Žádné motání v jednosměrkách, žádné hledání parkování, žádné placení v centru velkého města. Přijedeš, zaparkuješ vedle nás, převezmeš motorku a jedeš.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">Pro spoustu lidí je právě tohle jeden z důvodů, proč jezdí raději k nám než do Prahy nebo Brna.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">A od září 2026 si motorku můžeš vyzvednout i sám, nonstop, na naší samoobslužné pobočce ve Velkých Němčicích u Brna.</p>
<h2>10. Jsme rodinná půjčovna a děláme to srdcem</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Tohle se těžko měří, ale poznáš to hned. Žádné anonymní call centrum, žádné „číslo, počkejte si“, žádné šablony z firemního manuálu.</p>
<p style="margin-bottom: 8.0pt; line-height: 133%">Ke každému zákazníkovi přistupujeme individuálně a každý stroj pečlivě udržujeme. Jsme my, ty a motorky. A baví nás to!</p>
<h2>11. Největší půjčovna motorek na Vysočině</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">A jedna z největších v celé ČR. Díky tomu u nás vždycky najdeš motorku, která ti sedne — i v hlavní sezóně, kdy se po půjčovnách běžně hledá poslední volný kus. A naší flotilu neustále rozšiřujeme.</p>
<h2>12. Široký výběr — cestovní, naked, supermoto i dětské</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Celá flotila pro různé jezdce a různé situace:</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Začínáš a chceš něco snadno ovladatelného? Máme.</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Plánuješ tisícovku km přes Alpy? Cestovák je tu.</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Chceš si vyřádit po okreskách Vysočiny? Supermoto na tebe čeká.</p>
<p style="margin: 0cm 0cm 5pt 36pt; line-height: 133%;">• Potřebuje se vyřádit synátor nebo dcera? Máme i pravé dětské motorky — jsme jediná půjčovna v regionu s ucelenou dětskou flotilou. U nás najdeš motorku už od 3 let.</p>
<h2 style="margin-top: 24.0pt">Tak co — vyrazíš?</h2>
<p style="margin-bottom: 8.0pt; line-height: 133%">Udělej si <strong>komplet online check-in</strong> a motorka už tě bude čekat. Čas vyzvednutí je čistě na tobě – klidně i pozdě večer, o víkendu nebo o svátku. A vrátit motorku můžeš kdykoliv během posledního dne výpůjčky – třeba až o půlnoci.</p>
<p style="margin-top: 12.0pt; margin-right: 0cm; margin-bottom: 6.0pt; margin-left: 0cm"><a href="https://www.motogo24.cz/rezervace" rel="noopener" target="_blank"><strong>Rezervuj svou motorku →</strong></a></p>
<p style="margin-bottom: 6.0pt">Nebo si nejdřív <a href="https://www.motogo24.cz/katalog" rel="noopener" target="_blank">prohlédni naši flotilu</a> a najdi si tu pravou.</p>
<p style="margin-top: 12.0pt">Těšíme se! 🏍️</p>$html$
 WHERE id = '48a316a8-08d3-4d8b-8006-fa8edaaf4215' AND slug = '12-hlavnich-vyhod-motogo24'
   AND md5(content) = 'bc7d796ed7c4fb372a6c293638c700a5';
-- Pravopis: „naší flotilu“ → „naši flotilu“ (4. pád).
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$A naší flotilu neustále rozšiřujeme.$old$,
               $new$A naši flotilu neustále rozšiřujeme.$new$)) AS x(old, new)
 WHERE p.id = '48a316a8-08d3-4d8b-8006-fa8edaaf4215' AND p.slug = '12-hlavnich-vyhod-motogo24'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Výraz: „oblékací kabinka“ → „převlékací kabinka“.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$• Oblékací kabinku — převlékneš se v klidu$old$,
               $new$• Převlékací kabinku — převlékneš se v klidu$new$)) AS x(old, new)
 WHERE p.id = '48a316a8-08d3-4d8b-8006-fa8edaaf4215' AND p.slug = '12-hlavnich-vyhod-motogo24'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
-- Věcná oprava: „kamkoliv tě to táhne“ odporuje VOP čl. 1 p) (jen státy na zelené kartě) a FAQ „Můžu odcestovat s motorkou
-- do zahraničí?“ (zákaz: Bělorusko, Írán, Rusko, Srbsko, Kypr). Turecko vypuštěno do potvrzení majitelem.
UPDATE public.cms_pages p
   SET content = replace(p.content, x.old, x.new)
  FROM (VALUES ($old$Alpy, Balkán, Norsko, Turecko, kamkoliv tě to táhne.$old$,
               $new$Alpy, Balkán, Norsko, kamkoliv, kde platí zelená karta (nevztahuje se na Bělorusko, Írán, Rusko, Srbsko a Kypr).$new$)) AS x(old, new)
 WHERE p.id = '48a316a8-08d3-4d8b-8006-fa8edaaf4215' AND p.slug = '12-hlavnich-vyhod-motogo24'
   AND length(p.content) - length(replace(p.content, x.old, '')) = length(x.old);
