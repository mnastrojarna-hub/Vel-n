-- =============================================================================
-- 20261128c5_seo_web_texts_pobocky.sql
-- datová migrace (bez změn schématu): texty poboček ve Velín CMS – převod z vykání na tykání (část 5/5).
--
-- Datum: 2026-11-28. Zadání majitele 2026-11-27: zkvalitnění a zpřesnění textů (SEO).
-- Schváleno majitelem 2026-11-27.
-- Mění se JEN české hodnoty (sloupec cms_variables.value). Sloupec translations (cizí jazyky)
-- se nemění – cizojazyčné verze ukazují dál dosavadní překlad, dokud se text ve Velínu znovu
-- neuloží / nepřeloží.
-- POZOR: klíče web.pobocky.* čte i mobilní aplikace (obrazovka Pobočky) – změna se projeví i tam.
-- web.pobocky.branches.0.hours se nemění (čeká na potvrzení sezóny majitelem).
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
    -- /pobocky · Úvod: tykání (zbytek stránky tyká)
    (1, 'web.pobocky.intro', 'full', $o$Motorku si u nás vyzvednete na <strong>dvou místech</strong> — na <strong>obslužné pobočce v Mezné u Pelhřimova</strong>, kde vás přivítáme osobně, nebo na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>, kde si motorku i výbavu převezmete sami pomocí kódů.$o$,
      $n$Motorku si u nás vyzvedneš na <strong>dvou místech</strong> – na <strong>obslužné pobočce v Mezné u Pelhřimova</strong>, kde tě přivítáme osobně, nebo na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>, kde si motorku i výbavu převezmeš sám pomocí kódů z aplikace.$n$),
    -- /pobocky · Výzva dole: tykání
    (2, 'web.pobocky.cta.title', 'full', $o$Vyberte si motorku na své pobočce$o$,
      $n$Vyber si motorku na své pobočce$n$),
    -- /pobocky · Výzva dole: tykání
    (3, 'web.pobocky.cta.text', 'full', $o$V rezervaci si zvolíte pobočku a nabídnou se vám jen motorky, které na ní jsou.$o$,
      $n$V rezervaci si zvolíš pobočku a nabídnou se ti jen motorky, které na ní jsou.$n$),
    -- /pobocky/mezna · O pobočce: tykání, u přistavení doplněno „za příplatek“
    (4, 'web.pobocky.branches.0.text', 'full', $o$Naše hlavní pobočka na Vysočině. Motorku vám <strong>předáme osobně</strong> — vše vysvětlíme, pomůžeme s nastavením a výběrem výbavy a společně projdeme předávací protokol. Výbava pro řidiče je v ceně. Odtud nabízíme i <strong>přistavení motorky</strong> na vámi zvolenou adresu.$o$,
      $n$Naše hlavní pobočka na Vysočině. Motorku ti <strong>předáme osobně</strong> – vše vysvětlíme, pomůžeme s nastavením a výběrem výbavy a společně projdeme předávací protokol. Výbava pro řidiče je v ceně. Odtud ti motorku za příplatek <strong>přistavíme</strong> i na zvolenou adresu.$n$),
    -- /pobocky/mezna · Výbava: tykání
    (5, 'web.pobocky.branches.0.gear', 'full', $o$Výbava pro řidiče v ceně — bundy a kalhoty ve velikostech až do <strong>6XL</strong>. Jen tady si můžete zapůjčit i <strong>nepromoky</strong> a další doplňkovou výbavu.$o$,
      $n$Výbava pro řidiče v ceně – bundy a kalhoty ve velikostech až do <strong>6XL</strong>. Jen tady si můžeš zapůjčit i <strong>nepromoky</strong> a další doplňkovou výbavu.$n$),
    -- /pobocky/mezna · Jak to probíhá (4 kroky): tykání, obsah beze změny
    (6, 'web.pobocky.branches.0.steps', 'full', $o$1. Rezervujete a zaplatíte online (web nebo aplikace) a nahrajete doklady (OP/pas + ŘP) — žádáme o to i na obslužné pobočce; pokud je nenahrajete, zkontrolujeme je při převzetí na místě.<br>2. Ve zvolený čas přijedete na pobočku, kde vás čekáme.<br>3. Předáme motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíte na pobočku (nebo si ji vyzvedneme na domluvené adrese) — mýt ani tankovat ji nemusíte, jen ať nesvítí rezerva.$o$,
      $n$1. Rezervuješ a zaplatíš online (web nebo aplikace) a nahraješ doklady (OP/pas + ŘP) – žádáme o to i na obslužné pobočce; pokud je nenahraješ, zkontrolujeme je při převzetí na místě.<br>2. Ve zvolený čas přijedeš na pobočku, kde tě čekáme.<br>3. Předáme ti motorku i výbavu a podepíšeme předávací protokol.<br>4. Po jízdě motorku vrátíš na pobočku (nebo si ji vyzvedneme na domluvené adrese) – mýt ani tankovat ji nemusíš, jen ať nesvítí rezerva.$n$),
    -- /pobocky/velke-nemcice · Provozní doba: tykání, obsah beze změny
    (7, 'web.pobocky.branches.1.hours', 'full', $o$Nonstop 24/7 kódem z aplikace. Čas vyzvednutí si zvolíte v rezervaci — při vyzvednutí od 12:00 (výpůjčka 2 a více dní) máte 1. den za polovinu a kiosk vám motorku vydá až od 12:00. Čas vrácení nevolíte: motorku vrátíte kdykoliv poslední den výpůjčky do 24:00.$o$,
      $n$Nonstop 24/7 kódem z aplikace. Čas vyzvednutí si zvolíš v rezervaci – při vyzvednutí od 12:00 (výpůjčka na 2 a více dní) máš 1. den za polovinu a kiosk ti motorku vydá až od 12:00. Čas vrácení nevolíš: motorku vrátíš kdykoli poslední den výpůjčky do 24:00.$n$),
    -- /pobocky/velke-nemcice · O pobočce: tykání, obsah beze změny
    (8, 'web.pobocky.branches.1.text', 'full', $o$Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha — vše vyřídíte sami na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostanete po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí jen přímo na pobočce — přistavení ani odvoz u nich nenabízíme. U pobočky můžete po celou dobu výpůjčky <strong>parkovat zdarma</strong>.$o$,
      $n$Moderní <strong>samoobslužná pobočka</strong> jižně od Brna. Na místě není obsluha – vše vyřídíš sám na dotykovém displeji pomocí <strong>kódů z aplikace</strong>, které dostaneš po zaplacení a doplnění dokladů. Motorky z této pobočky se přebírají i vracejí jen přímo na pobočce – přistavení ani odvoz u nich nenabízíme. U pobočky můžeš po celou dobu výpůjčky <strong>parkovat zdarma</strong>.$n$),
    -- /pobocky/velke-nemcice · Výbava: tykání, obsah (i velikosti) beze změny
    (9, 'web.pobocky.branches.1.gear', 'full', $o$K dispozici je jen <strong>helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty</strong> — výbava pro řidiče je v ceně, motocyklové boty za příplatek. Bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). <strong>Nepromoky</strong> ani další doplňkovou výbavu na samoobslužné pobočce nepůjčujeme — ty jsou jen na obslužné pobočce v Mezné. Výbavu si v šatně vyzkoušíte, a když vám velikost nesedí, vezmete si jinou dostupnou a v předávacím protokolu ji jen označíte. Reflexní vestu, lékárničku, záznam o nehodě, kotoučový zámek a klíček k držáku telefonu najdete v motorce.$o$,
      $n$K dispozici je jen <strong>helma, bunda s páteřákem, kalhoty, rukavice, kukla a boty</strong> – výbava pro řidiče je v ceně, motocyklové boty za příplatek. Bundy a kalhoty do velikosti <strong>4XL</strong> (větší velikosti až do 6XL nabízíme v Mezné). <strong>Nepromoky</strong> ani další doplňkovou výbavu na samoobslužné pobočce nepůjčujeme – ty jsou jen na obslužné pobočce v Mezné. Výbavu si v šatně vyzkoušíš, a když ti velikost nesedí, vezmeš si jinou dostupnou a v předávacím protokolu ji jen označíš. Reflexní vestu, lékárničku, záznam o nehodě, kotoučový zámek a klíček k držáku telefonu najdeš v motorce.$n$),
    -- /pobocky/velke-nemcice · Jak to probíhá (6 kroků): tykání, obsah a pořadí kroků beze změny
    (10, 'web.pobocky.branches.1.steps', 'full', $o$1. Rezervujete a zaplatíte online, zvolíte čas vyzvednutí a nahrajete doklady (OP/pas + ŘP) — na samoobslužné pobočce je to nezbytné: bez ověřených dokladů kódy nedostanete a na pobočku se nedostanete. Po ověření dokladů dostanete v aplikaci, e-mailu a SMS kódy v pořadí, v jakém je budete zadávat: <strong>1) kód schránky s klíčem od brány, 2) kód šatny</strong> (máte-li zapůjčenou výbavu) <strong>a 3) kód motorky</strong>.<br>2. <strong>Je-li vjezdová brána zavřená</strong>, otevřete kódem z aplikace <strong>horní schránku na pravém sloupku vrat</strong> — je v ní klíč od visacího zámku. Bránu odemkněte, vjeďte dovnitř a zaparkujte na kterémkoli místě <strong>1–7 vpravo u plotu</strong> (viz fotka parkoviště). Auto tu může zdarma stát po celou dobu výpůjčky. Je-li brána otevřená, kód schránky nepotřebujete.<br>3. Na displeji zadáte kód šatny — <strong>šatna jsou dveře č. 8</strong>. Vezmete si výbavu, převléknete se a dveře šatny zavřete (s vlastní výbavou šatnu přeskočíte). Máte-li slevu za vyzvednutí od 12:00, kódy platí až od 12:00.<br>4. Na displeji v předávacím protokolu upravíte velikosti, protokol podepíšete a zadáte kód motorky — otevře se kóje s motorkou. Kóji zavřete a vyrazíte.<br>5. <strong>Byla-li brána zavřená, po odjezdu ji zase zavřete, zamkněte visacím zámkem, klíč vraťte do horní schránky a přetočte číselník.</strong> Otevřenou bránu nechte otevřenou — stav brány nikdy neměňte.<br>6. Po jízdě motorku vrátíte do kóje a výbavu do šatny — kdykoliv poslední den výpůjčky do 24:00. Motorku vraťte umytou a bez svítící rezervy (plnou nádrž nepotřebujete). Je-li brána zavřená, postupujete stejně: odemknete ji klíčem ze schránky a po odjezdu ji zase zamknete a klíč vrátíte.$o$,
      $n$1. Rezervuješ a zaplatíš online, zvolíš čas vyzvednutí a nahraješ doklady (OP/pas + ŘP) – na samoobslužné pobočce je to nezbytné: bez ověřených dokladů kódy nedostaneš a na pobočku se nedostaneš. Po ověření dokladů dostaneš v aplikaci, e-mailu a SMS kódy v pořadí, v jakém je budeš zadávat: <strong>1) kód schránky s klíčem od brány, 2) kód šatny</strong> (máš-li zapůjčenou výbavu) <strong>a 3) kód motorky</strong>.<br>2. <strong>Je-li vjezdová brána zavřená</strong>, otevři kódem z aplikace <strong>horní schránku na pravém sloupku vrat</strong> – je v ní klíč od visacího zámku. Bránu odemkni, vjeď dovnitř a zaparkuj na kterémkoli místě <strong>1–7 vpravo u plotu</strong> (viz fotka parkoviště). Auto tu může zdarma stát po celou dobu výpůjčky. Je-li brána otevřená, kód schránky nepotřebuješ.<br>3. Na displeji zadáš kód šatny – <strong>šatna jsou dveře č. 8</strong>. Vezmeš si výbavu, převlékneš se a dveře šatny zavřeš (s vlastní výbavou šatnu přeskočíš). Máš-li slevu za vyzvednutí od 12:00, kódy platí až od 12:00.<br>4. Na displeji v předávacím protokolu upravíš velikosti, protokol podepíšeš a zadáš kód motorky – otevře se kóje s motorkou. Kóji zavřeš a vyrazíš.<br>5. <strong>Byla-li brána zavřená, po odjezdu ji zase zavři, zamkni visacím zámkem, klíč vrať do horní schránky a přetoč číselník.</strong> Otevřenou bránu nech otevřenou – stav brány nikdy neměň.<br>6. Po jízdě motorku vrátíš do kóje a výbavu do šatny – kdykoli poslední den výpůjčky do 24:00. Motorku vrať umytou a bez svítící rezervy (plnou nádrž nepotřebuješ). Je-li brána zavřená, postupuješ stejně: odemkneš ji klíčem ze schránky a po odjezdu ji zase zamkneš a klíč vrátíš.$n$)
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
        RAISE NOTICE 'seo_texts_pobocky: % PŘESKOČENO – klíč v cms_variables neexistuje', r.key;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_texts_pobocky: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.key, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'seo_texts_pobocky: cms_variables změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
