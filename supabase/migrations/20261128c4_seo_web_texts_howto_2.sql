-- =============================================================================
-- 20261128c4_seo_web_texts_howto_2.sql
-- datová migrace (bez změn schématu): texty webu ve Velín CMS – Jak si půjčit: dokumenty, postup, převzetí, text pod častými dotazy (část 4/5).
--
-- Datum: 2026-11-28. Zadání majitele 2026-11-27: zkvalitnění a zpřesnění textů (SEO).
-- Schváleno majitelem 2026-11-27.
-- Mění se JEN české hodnoty (sloupec cms_variables.value). Sloupec translations (cizí jazyky)
-- se nemění – cizojazyčné verze ukazují dál dosavadní překlad, dokud se text ve Velínu znovu
-- neuloží / nepřeloží.
-- Znění = nové výchozí texty v PHP (data/*-content-*.php, pages/faq.php, commit 488ee074), aby kód i databáze říkaly totéž.
--
-- Bezpečnost: každý text se změní jen tehdy, když má v databázi PŘESNĚ znění ověřené proti
-- živé DB 2026-11-27 ('full' = celý text; 'phrase' = uvedená část textu, zbytek zůstává).
-- Co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE. Idempotentní (2. běh nic nezmění).
-- Bez BEGIN/COMMIT – deploy-sql.yml pouští soubor v jedné transakci (ON_ERROR_STOP).
-- Záměrně nemění: schéma, žádný nový klíč (INSERT), 16 starých „plochých“ klíčů z triggeru
-- trg_sync_cms_flat_to_nested (web.pujcovna.h1/intro/ben.*/step.*, web.kontakt.hours/seo),
-- texty čekající na potvrzení majitele (otázky předány majiteli 2026-11-27).
-- =============================================================================

DO $$
DECLARE
  r record;
  n integer;
  v_cur text;
  n_upd integer := 0;
  n_done integer := 0;
  n_skip integer := 0;
BEGIN
  -- x: pořadí, klíč, how ('full' = old je celé dosavadní znění; 'phrase' = old je část textu), old, new
  FOR r IN
    SELECT * FROM (VALUES
    -- /jak-pujcit/postup · Hlavní nadpis: obsahuje „jak si půjčit motorku“
    (1, 'web.jak_pujcit_postup.h1', 'full', $o$Postup půjčení motorky$o$,
      $n$Jak si půjčit motorku – postup krok za krokem$n$),
    -- /jak-pujcit/postup · Podnadpis: místo řetězce „půjčovna Motogo24 – Vysočina“
    (2, 'web.jak_pujcit_postup.intro_h2', 'full', $o$Jak si půjčit motorku – půjčovna Motogo24 – Vysočina$o$,
      $n$Kde si motorku vyzvedneš$n$),
    -- /jak-pujcit/postup · Krok 6: doplněno číslo jako u ostatních kroků
    (3, 'web.jak_pujcit_postup.process.steps.5.title', 'full', $o$Místo a čas vrácení$o$,
      $n$6. Místo a čas vrácení$n$),
    -- /jak-pujcit/prevzeti · Hlavní nadpis: „převzetí motorky“ místo „motocyklu… rychle, jednoduše a nonstop“
    (4, 'web.jak_pujcit_vyzvednuti.h1', 'full', $o$Převzetí motocyklu v motopůjčovně – rychle, jednoduše a nonstop$o$,
      $n$Převzetí motorky v půjčovně: jak předání probíhá$n$),
    -- /jak-pujcit/prevzeti · Nadpis výzvy: bez „půjčovna motorek v Pelhřimově“
    (5, 'web.jak_pujcit_vyzvednuti.cta.title', 'full', $o$Převzetí v půjčovně – půjčovna motorek v Pelhřimově$o$,
      $n$Rezervuj si motorku i čas převzetí$n$),
    -- /jak-pujcit/dokumenty · Hlavní nadpis: odpovídá obsahu stránky (podmínky + dokumenty), nesoupeří se stránkou smlouvy
    (6, 'web.jak_pujcit_dokumenty.h1', 'full', $o$Nájemní smlouva a půjčení bez kauce – férové podmínky u MotoGo24$o$,
      $n$Podmínky půjčení motorky a dokumenty ke stažení$n$),
    -- /jak-pujcit/dokumenty · Nadpis závěrečné výzvy: bez „motopůjčovna na Vysočině“
    (7, 'web.jak_pujcit_dokumenty.cta.title', 'full', $o$Nájemní smlouva bez kauce – motopůjčovna na Vysočině$o$,
      $n$Rezervuj motorku online$n$),
    -- /jak-pujcit/postup · Úvod: bez formule, která otevírá čtyři stránky, a bez „Vysočiny“ (platí i pro Brno)
    (8, 'web.jak_pujcit_postup.intro_p1', 'full', $o$V <strong>Motogo24 </strong>–<strong> půjčovně motorek na Vysočině&nbsp;</strong>–&nbsp;je půjčení jednoduché, rychlé a férové.&nbsp;<strong>Bez kauce, s výbavou pro řidiče v ceně a nonstop provozem pro půjčení a vrácení motorky</strong>. Přesvědč se, jak snadno to funguje.$o$,
      $n$Motorku si u <strong>MotoGo24</strong> rezervuješ a zaplatíš online za pár minut – <strong>bez kauce a s výbavou pro řidiče v ceně</strong>. Tady je celý postup od výběru motorky po vrácení.$n$),
    -- /jak-pujcit/postup · Krok 6: u Brna se čas vrácení nevolí a vrací se jen na pobočce
    (9, 'web.jak_pujcit_postup.process.steps.5.text', 'full', $o$Vyber, jestli budeš motorku vracet na adrese motopůjčovny, nebo jinde a kdy.$o$,
      $n$Vyber, kde a kdy motorku vrátíš – na pobočce, nebo u motorek z Mezné i na jiné adrese v ČR. Ve Velkých Němčicích čas vrácení nevolíš: motorku vrátíš kdykoli poslední den do 24:00.$n$),
    -- /jak-pujcit/postup · Krok 9: doplněny přístupové kódy pro samoobslužnou pobočku
    (10, 'web.jak_pujcit_postup.process.steps.8.text', 'full', $o$Po dokončení rezervace ti přijde e-mail s potvrzením rezervace, dokladem o platbě,&nbsp; nájemní smlouvou a základními instrukcemi pro vyzvednutí motorky.$o$,
      $n$Po zaplacení ti přijde e-mail s potvrzením rezervace, dokladem o platbě, nájemní smlouvou a instrukcemi k vyzvednutí. U samoobslužné pobočky ve Velkých Němčicích dostaneš po ověření dokladů i přístupové kódy – v aplikaci, e-mailem a SMS.$n$),
    -- /jak-pujcit/postup · Krok 10: popsáno převzetí na obou pobočkách
    (11, 'web.jak_pujcit_postup.process.steps.9.text', 'full', $o$Při předání zkontrolujeme doklady (pokud již nejsou ověřeny), podepíšeme předávací protokol a převezmeš si výbavu.$o$,
      $n$V Mezné ti motorku předáme osobně: zkontrolujeme doklady (pokud je nemáš ověřené online), převezmeš výbavu a podepíšeme předávací protokol. Ve Velkých Němčicích si motorku i výbavu vyzvedneš bez obsluhy pomocí kódů z aplikace – doklady musíš mít předem ověřené a protokol podepíšeš na displeji.$n$),
    -- /jak-pujcit/prevzeti · Úvod: jak převzetí probíhá na obou pobočkách, bez opakované formule
    (12, 'web.jak_pujcit_vyzvednuti.intro', 'full', $o$V <strong>Motogo24 – půjčovně motorek na Vysočině</strong>&nbsp;je převzetí motorky otázkou pár minut. Půjčujeme bez <strong>kauce, s výbavou pro řidiče v ceně a nonstop provozem</strong>. Přijď osobně do Mezné u Pelhřimova a vyraz na cestu! Na samoobslužné pobočce ve Velkých Němčicích u Brna si motorku vyzvedneš sám přístupovým kódem z aplikace nebo e-mailu.$o$,
      $n$Převzetí motorky trvá pár minut. V <strong>Mezné u Pelhřimova</strong> ti ji předáme osobně v čase, který sis zvolil/a v rezervaci – spolu projdeme motorku, výbavu i předávací protokol. Na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong> si motorku i výbavu vyzvedneš bez obsluhy pomocí kódů z aplikace.$n$),
    -- /jak-pujcit/prevzeti · Co s sebou: skupiny ŘP včetně skútrů (A1 nebo B)
    (13, 'web.jak_pujcit_vyzvednuti.bring.items.1', 'full', $o$- platný řidičský průkaz s oprávněním odpovídající skupiny (A/A2 podle vybrané motorky)$o$,
      $n$- platný řidičský průkaz skupiny, kterou motorka vyžaduje (A, A2, u skútrů A1 nebo B – najdeš ji u motorky v katalogu)$n$),
    -- /jak-pujcit/prevzeti · Co s sebou: oprava pádu („helmu, bundu…“)
    (14, 'web.jak_pujcit_vyzvednuti.bring.items.2', 'full', $o$- vlastní výbavu – helma, bunda, kalhoty, rukavice (pokud nemáš zarezervované u nás)$o$,
      $n$- vlastní výbavu – helmu, bundu, kalhoty, rukavice (pokud je nemáš zarezervované u nás)$n$),
    -- /jak-pujcit/prevzeti · Druhá věta výzvy: krátká (prázdný text by nechal prázdný odstavec)
    (15, 'web.jak_pujcit_vyzvednuti.cta.text2', 'full', $o$Vyber si z naší stále se rozrůstající nabídky motorek&nbsp;a rezervuj si svůj stroj pohodlně online.$o$,
      $n$Vyber motorku a rezervuj online.$n$),
    -- /jak-pujcit/dokumenty · Úvod: co na stránce je, místo obecné reklamní věty
    (16, 'web.jak_pujcit_dokumenty.intro', 'full', $o$V <strong>Motogo24 – </strong>v naší <strong>půjčovně motorek v Mezné u&nbsp; Pelhřimova (Vysočina)</strong> klademe důraz na jednoduchost a férovost. Půjčujeme <strong>bez kauce</strong>, s <strong>jasnou nájemní smlouvou</strong>&nbsp;a&nbsp;<strong>výbavou pro řidiče</strong> zahrnutou v půjčovném.$o$,
      $n$Na této stránce najdeš přehled nejdůležitějších pravidel: co potřebuješ k uzavření smlouvy, jak se platí, kolik stojí storno a za co odpovídáš. Níže si stáhneš <strong>obchodní podmínky, vzor smlouvy o pronájmu a protokoly v PDF</strong>.$n$),
    -- /jak-pujcit/dokumenty · Co potřebuješ: skupiny ŘP včetně skútrů (A1/B)
    (17, 'web.jak_pujcit_dokumenty.required_docs.items.1', 'full', $o$<strong>- řidičský průkaz</strong>&nbsp;odpovídající skupiny (dle stroje),$o$,
      $n$<strong>- řidičský průkaz</strong>&nbsp;odpovídající skupiny (A, A2 nebo A1/B podle motorky),$n$),
    -- /jak-pujcit/dokumenty · Co potřebuješ: u dětských motorek zákonný zástupce neručí, ale je přímo nájemcem (obchodní podmínky čl. 10)
    (18, 'web.jak_pujcit_dokumenty.required_docs.items.2', 'full', $o$<strong>- věk</strong>&nbsp;min. 18 let (u dětských motorek ručí zákonný zástupce),$o$,
      $n$<strong>- věk</strong>&nbsp;alespoň 18 let (u dětských motorek je nájemcem zákonný zástupce dítěte, např. rodič),$n$),
    -- /jak-pujcit/dokumenty · Platby: doplněna lhůta 4 hodiny a to, že QR platba a převod jdou jen při rezervaci na webu (obchodní podmínky čl. 4)
    (19, 'web.jak_pujcit_dokumenty.payments.lead', 'full', $o$<strong>Kauce:</strong>&nbsp;<em>nevyžadujeme</em>. Platba za nájem probíhá online kartou, qr platbou nebo bankovním převodem.$o$,
      $n$<strong>Kauce:</strong>&nbsp;<em>nevyžadujeme</em>. Nájem zaplatíš předem online kartou (i přes Apple Pay nebo Google Pay), při rezervaci na webu také QR platbou nebo bankovním převodem. Platba musí dorazit do 4 hodin od odeslání rezervace, jinak můžeme rezervaci zrušit.$n$),
    -- /jak-pujcit/dokumenty · Tabulka – storno: konkrétní čísla z obchodních podmínek (čl. 3) místo „do předem domluveného času“
    (20, 'web.jak_pujcit_dokumenty.payments.rows.1.1', 'full', $o$Lze bezplatně do předem domluveného času (uvedeno ve VOP).$o$,
      $n$Zdarma nejpozději 7 dní před převzetím. Při zrušení 2–7 dní předem můžeme účtovat až 50 % nájemného, při zrušení méně než 2 dny předem nebo při nevyzvednutí motorky celé nájemné (VOP čl. 3).$n$),
    -- /jak-pujcit/dokumenty · Tabulka – pozdní vrácení: kolik to stojí (obchodní podmínky čl. 2 d)
    (21, 'web.jak_pujcit_dokumenty.payments.rows.4.1', 'full', $o$Prosíme o včasné vrácení v poslední den výpůjčky nebo o oficiální prodloužení výpůjčky.$o$,
      $n$Motorku vrať poslední den výpůjčky do 24:00. Za každý další započatý den platíš nájemné za den navíc (VOP čl. 2 d). Nestihneš to? Prodluž si výpůjčku v sekci Upravit rezervaci.$n$),
    -- /jak-pujcit/dokumenty · Odpovědnost: místo obecné věty o předpisech pravidla krytí škod a krádeže (obchodní podmínky čl. 7)
    (22, 'web.jak_pujcit_dokumenty.usage.items.0', 'full', $o$Jezdi v&nbsp;<strong>souladu s předpisy</strong>&nbsp;a s ohledem na technický stav a typ motorky.$o$,
      $n$Škody na motorce, které zaviníš, kryje <strong>100% smluvní krytí škod</strong> se spoluúčastí 0 Kč. Nevztahuje se na zapůjčenou výbavu, na hrubé porušení podmínek (např. jízda pod vlivem nebo bez řidičského oprávnění) ani na odcizení – u řádně zabezpečené motorky odpovídáš nejvýš do 30 000 Kč, u nezabezpečené až do její obvyklé tržní hodnoty.$n$),
    -- /jak-pujcit/dokumenty · Nehoda/porucha: při nehodě nebo krádeži vždy volat policii (obchodní podmínky čl. 6)
    (23, 'web.jak_pujcit_dokumenty.usage.items.3', 'full', $o$V případě&nbsp;<strong>nehody nebo poruchy</strong>&nbsp;postupuj podle pokynů - kontaktuj tým MotoGo24.$o$,
      $n$Při&nbsp;<strong>nehodě nebo poruše</strong>&nbsp;nám hned zavolej a řiď se našimi pokyny; při dopravní nehodě nebo krádeži vždy přivolej i policii – je to podmínka smluvního krytí škod.$n$),
    -- /jak-pujcit/dokumenty · Servis: řetěz během výpůjčky mažeš ty (obchodní podmínky čl. 1 l)
    (24, 'web.jak_pujcit_dokumenty.usage.items.4', 'full', $o$<strong>Servis a údržbu</strong>&nbsp;zajišťujeme my; závady hlas okamžitě.$o$,
      $n$<strong>Servis</strong>&nbsp;zajišťujeme my, ty během výpůjčky jen pravidelně mažeš řetěz. Závady nám hlas hned.$n$),
    -- /jak-pujcit/dokumenty · Výzva uprostřed: krátká věta místo výčtu kategorií
    (25, 'web.jak_pujcit_dokumenty.midcta.text', 'full', $o$Vyber si z&nbsp;<strong>cestovních, supermoto, naked </strong>i <strong>dětských motorek </strong>nebo<strong> chopperů či skútrů</strong>&nbsp;a potvrď rezervaci online.$o$,
      $n$Vyber motorku a rezervuj online.$n$),
    -- /jak-pujcit/dokumenty · Závěrečná výzva: krátká věta místo čtvrtého opakování „bez kauce, výbava, nonstop“ (prázdný text by nechal prázdný odstavec)
    (26, 'web.jak_pujcit_dokumenty.cta.text', 'full', $o$Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s férovými podmínkami: <strong>bez kauce</strong>, s&nbsp;<strong>výbavou pro řidiče v ceně</strong> a <strong>nonstop provozem pro vyzvednutí i vrácení motorky.</strong>&nbsp;Vše přehledně ve vzorové nájemní smlouvě a na této stránce.$o$,
      $n$Vyber motorku a termín – cenu spočítáme hned.$n$),
    -- /jak-pujcit/faq · Text pod dotazy: kontakt místo reklamní věty jen o Vysočině
    (27, 'web.faq.closing', 'full', $o$Naše <strong>půjčovna motorek na Vysočině</strong> je tu pro všechny, kdo chtějí zažít <strong>nezapomenutelnou jízdu</strong> bez zbytečných komplikací. Pronájem je <strong>bez kauce</strong>, s <strong>výbavou pro řidiče v ceně</strong> a <strong>nonstop provozem </strong>pro převzetí i vrácení motorky.$o$,
      $n$Nenašel/a jsi odpověď? Zavolej nám na <strong>+420 774 256 271</strong> nebo napiš na <strong>info@motogo24.cz</strong>.$n$),
    -- /jak-pujcit/postup · Krok 8: „QR“ velkými písmeny; QR platba a převod jen při rezervaci na webu
    (28, 'web.jak_pujcit_postup.process.steps.7.text', 'full', $o$Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online platební kartou, qr kódem nebo bankovním převodem.$o$,
      $n$Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online kartou (i přes Apple Pay nebo Google Pay), při rezervaci na webu také QR platbou nebo bankovním převodem.$n$)
    ) AS x(ord, key, how, old, new)
    ORDER BY ord
  LOOP
    UPDATE public.cms_variables
       SET value = to_jsonb(CASE WHEN r.how = 'phrase' THEN replace(value #>> '{}', r.old, r.new) ELSE r.new END),
           updated_at = now()
     WHERE key = r.key AND jsonb_typeof(value) = 'string'
       AND CASE WHEN r.how = 'phrase' THEN strpos(value #>> '{}', r.old) > 0 AND strpos(value #>> '{}', r.new) = 0
                ELSE value #>> '{}' = r.old END;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
      n_upd := n_upd + n;
    ELSE
      SELECT value #>> '{}' INTO v_cur FROM public.cms_variables WHERE key = r.key;
      IF NOT FOUND THEN
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_texts_howto_2: % PŘESKOČENO – klíč v cms_variables neexistuje', r.key;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_texts_howto_2: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.key, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'seo_texts_howto_2: cms_variables změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
