-- =============================================================================
-- 20261128c1_seo_web_texts_core_1.sql
-- datová migrace (bez změn schématu): texty webu ve Velín CMS – úvodní stránka (kroky), kontakt, poukazy, titulky a popisky poboček (část 1/5).
--
-- Datum: 2026-11-28. Zadání majitele 2026-11-27: zkvalitnění a zpřesnění textů (SEO).
-- Schváleno majitelem 2026-11-27.
-- Mění se JEN české hodnoty (sloupec cms_variables.value). Sloupec translations (cizí jazyky)
-- se nemění – cizojazyčné verze ukazují dál dosavadní překlad, dokud se text ve Velínu znovu
-- neuloží / nepřeloží.
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
    -- / · Krok 1: pryč „nově také“ (skútry a choppery už nejsou novinka) a dvojité mezery
    (1, 'web.home.process.steps.0.text', 'full', $o$Vyber si&nbsp; ideální motorku z naší nabídky <span style="font-weight: bold;">cestovních,</span> <span style="font-weight: bold;">supermoto</span>, <span style="font-weight: bold;">naked</span>, <span style="font-weight: bold;">dětských </span>modelů a nově také <span style="font-weight: bold;">skútrů a chopperů</span>.$o$,
      $n$Vyber si motorku z naší nabídky <strong>cestovních</strong>, <strong>supermoto</strong>, <strong>naked</strong> i <strong>dětských motorek</strong>, <strong>skútrů</strong> a <strong>chopperů</strong>.$n$),
    -- / · Krok 2: odstraněna dvojitá mezera
    (2, 'web.home.process.steps.1.text', 'full', $o$Rezervuj si motorku online přes&nbsp; jednoduchý rezervační systém.$o$,
      $n$Rezervuj si motorku online přes jednoduchý rezervační systém.$n$),
    -- / · Nadpis postupu: postup platí i pro pobočku u Brna; pryč vložené barvy písma
    (3, 'web.home.process.title', 'full', $o$<font style="background-color: rgb(10, 31, 20);" color="#73f970">Jak probíhá půjčení motorky na Vysočině</font>$o$,
      $n$Jak probíhá půjčení motorky$n$),
    -- / · Úvod sekce motorek (starý vzhled): pryč „nově také“, motorky stojí na dvou pobočkách, ne jen na Vysočině
    (4, 'web.home.motos_section.intro', 'full', $o$Prohlédni si nabídku <strong>cestovních</strong>, <strong>supermoto</strong>, <strong>naked, dětských motorek </strong>a nově také <strong>skútrů a chopperů</strong>&nbsp;z naší motopůjčovny<strong>&nbsp;na Vysočině</strong>. Vyber si ideální motorku pro své dobrodružství po Česku i v zahraničí a rezervuj online.&nbsp;$o$,
      $n$Prohlédni si nabídku <strong>cestovních</strong>, <strong>supermoto</strong>, <strong>naked</strong> a <strong>dětských motorek</strong>, <strong>skútrů</strong> i <strong>chopperů</strong> z našich dvou poboček. Vyber si motorku pro své dobrodružství po Česku i v zahraničí a rezervuj online.$n$),
    -- /kontakt · Popisek pro vyhledávače: konkrétní kontakty místo obecné věty „moderní půjčovna… otevřeni nonstop“
    (5, 'web.kontakt.seo.description', 'full', $o$Motogo24 je moderní půjčovna motorek na Vysočině. Sídlíme v Mezné u Pelhřimova, jsme otevřeni nonstop a půjčujeme bez kauce, s kompletní výbavou pro řidiče v ceně.$o$,
      $n$Volej +420 774 256 271 (Po–Pá 8–17) nebo piš na info@motogo24.cz. Adresy a navigace na pobočky Mezná u Pelhřimova a Velké Němčice u Brna, fakturační údaje.$n$),
    -- /kontakt · Blok „Půjčovna motorek u Pelhřimova“: fakta místo „prakticky nonstop“ a opakované reklamní věty
    (6, 'web.kontakt.seo_text.body', 'full', $o$Motogo24 je <strong>moderní půjčovna motorek na Vysočině</strong>. Sídlíme v <strong>Mezné u Pelhřimova,</strong>&nbsp;máme otevřeno prakticky&nbsp;<strong>nonstop</strong> a půjčujeme <strong>bez kauce</strong>, s kompletní <strong>výbavou pro řidiče v ceně</strong>. Kontaktuj nás pro <strong>cestovní</strong>, <strong>naked</strong>, <strong>supermoto</strong>,&nbsp;<strong>dětské motorky, choppery</strong>&nbsp;i <strong>skútry </strong>- vše s plně automatizovanou a jednoduchou online rezervací i platbou.$o$,
      $n$MotoGo24 sídlí v <strong>Mezné u Pelhřimova</strong>. Motorky tu vydáváme a přijímáme <strong>podle rezervace každý den</strong>, i o víkendu a ve svátek; telefon a e-mail vyřizujeme v pracovní dny od 8:00 do 17:00. Druhou, samoobslužnou pobočku máme ve <strong>Velkých Němčicích u Brna</strong>.$n$),
    -- /kontakt · Provozní doba: jen typografie (pomlčky v rozsazích, časy bez úvodní nuly) – údaje beze změny
    (8, 'web.kontakt.place.hours', 'full', $o$<div style="text-align: right;"><div style="text-align: left;"><b>PO – NE</b>: 00:00 – 24:00 (výdej a příjem motorek, dle rezervace)</div><div style="text-align: left;"><b>PO – PÁ</b>: 08:00 – 17:00 (technická podpora)</div><div style="text-align: left;"><br></div></div>$o$,
      $n$<div style="text-align: right;"><div style="text-align: left;"><b>PO–NE</b>: 0:00–24:00 (výdej a příjem motorek podle rezervace)</div><div style="text-align: left;"><b>PO–PÁ</b>: 8:00–17:00 (technická podpora)</div><div style="text-align: left;"><br></div></div>$n$),
    -- /kontakt · Výhody: chybějící mezera „alespoň18“
    (9, 'web.kontakt.outro.body2', 'phrase', $o$věk alespoň18 let$o$,
      $n$věk alespoň 18 let$n$),
    -- /kontakt · Výhody: lomítkový tvar „sám/sama“
    (10, 'web.kontakt.outro.body2', 'phrase', $o$Všechno vyřešíš sám/sama hned.$o$,
      $n$Všechno vyřešíš hned sám.$n$),
    -- /kontakt · Výhody: chybné spojení „16 druhů značek motocyklů“
    (11, 'web.kontakt.outro.body2', 'phrase', $o$<span style="font-weight: bold;">16 druhů značek motocyklů</span>$o$,
      $n$<span style="font-weight: bold;">motorky 16 značek</span>$n$),
    -- /kontakt · Výhody: pryč zastaralé „nově také“
    (12, 'web.kontakt.outro.body2', 'phrase', $o$<strong>cestovní, naked, supermoto i dětské motorky </strong>a nově také<strong>&nbsp;choppery a skútry</strong>$o$,
      $n$<strong>cestovní, naked, supermoto i dětské motorky, choppery a skútry</strong>$n$),
    -- /kontakt · Výhody: u „Rezervuješ a za hodinu můžeš jet“ doplněno, že u Brna přijdou kódy až po ověření dokladů
    (13, 'web.kontakt.outro.body2', 'phrase', $o$Rezervaci zpracujeme prakticky obratem a motorka už na tebe čeká.$o$,
      $n$Rezervaci zpracujeme prakticky obratem a motorka už na tebe čeká. Na samoobslužné pobočce ve Velkých Němčicích ti přístupové kódy pošleme po ověření dokladů.$n$),
    -- /poukazy · Hlavní nadpis: obsahuje „dárkový poukaz na motorku“, bez rozkazu „Kup“ a vykřičníku
    (14, 'web.poukazy.h1', 'full', $o$Kup dárkový poukaz – daruj zážitek na dvou kolech!$o$,
      $n$Dárkový poukaz na motorku – daruj zážitek na dvou kolech$n$),
    -- /poukazy · Úvod: pryč vsuvka „půjčovny motorek na Vysočině“ (poukaz platí na obou pobočkách), značka MotoGo24
    (15, 'web.poukazy.intro_left', 'full', $o$<p>Hledáš originální dárek pro partnera, kamaráda nebo někoho blízkého?</p><p>Naše <strong>dárkové poukazy na pronájem motorky</strong> od Motogo24 – <strong>půjčovny motorek na Vysočině</strong>&nbsp;– potěší začátečníky i zkušené jezdce.</p><p>&nbsp;Vyber hodnotu poukazu a daruj svobodu na dvou kolech.</p>$o$,
      $n$<p>Hledáš originální dárek pro partnera, kamaráda nebo někoho blízkého?</p><p><strong>Dárkový poukaz na pronájem motorky</strong> od MotoGo24 potěší začátečníky i zkušené jezdce.</p><p>Vyber hodnotu poukazu a daruj svobodu na dvou kolech.</p>$n$),
    -- /poukazy · Proč poukaz, bod 1: bez opakování „hodnota… hodnota“
    (16, 'web.poukazy.why.items.0', 'full', $o$<strong>Flexibilní hodnota</strong>&nbsp;– libovolná hodnota poukazu (nejméně 100 Kč).$o$,
      $n$<strong>Libovolná hodnota</strong> – poukaz koupíš na jakoukoli částku od 100 Kč.$n$),
    -- /poukazy · Proč poukaz, bod 2: bez opakování „poukazu… poukazu“, pomlčka místo spojovníku
    (17, 'web.poukazy.why.items.1', 'full', $o$<strong>Velkorysá platnost poukazu </strong>- na využití poukazu máš celé 3 roky.$o$,
      $n$<strong>Platnost 3 roky</strong> – na využití poukazu je dost času.$n$),
    -- /poukazy · Proč poukaz, bod 4: „PDF“ velkými písmeny, „poukaz“ místo „voucher“
    (18, 'web.poukazy.why.items.3', 'full', $o$<strong>Elektronická i tištěná varianta</strong>&nbsp;– poukaz ve formě pdf nebo tištěného voucheru.&nbsp;$o$,
      $n$<strong>Elektronická i tištěná varianta</strong> – poukaz dostaneš v PDF, na přání i vytištěný.$n$),
    -- /poukazy · Poznámka o platnosti: „poukazy“ místo „vouchery“
    (19, 'web.poukazy.validity_note', 'full', $o$Všechny vouchery mají platnost 3 roky od data vystavení.$o$,
      $n$Všechny poukazy mají platnost 3 roky od data vystavení.$n$),
    -- /poukazy · Dotaz o platnosti: „poukazy“ místo „vouchery“
    (20, 'web.poukazy.faq.items.0.a', 'full', $o$Všechny vouchery mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.$o$,
      $n$Všechny poukazy mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.$n$),
    -- /poukazy · Dotaz o doručení: překlep „varintu“ a lomítkový tvar „zvolil/a“
    (21, 'web.poukazy.faq.items.1.a', 'full', $o$<strong>Okamžitě e-mailem</strong> po úhradě. V případě, že sis zvolil/a tištěnou varintu, poukaz dorazí za pár dní do tvé poštovní schránky.$o$,
      $n$<strong>Okamžitě e-mailem</strong> po úhradě. Když si zvolíš tištěnou variantu, poukaz ti dorazí poštou za pár dní.$n$),
    -- /poukazy · Dotaz o kauci: „výbava pro řidiče“ jako jinde na webu
    (22, 'web.poukazy.faq.items.2.a', 'full', $o$Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové, výbava řidiče je v ceně.$o$,
      $n$Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové, výbava pro řidiče je v ceně.$n$),
    -- /poukazy · Dotaz: „poukaz“ místo „voucher“
    (23, 'web.poukazy.faq.items.4.q', 'full', $o$Na jaké motorky lze voucher uplatnit?$o$,
      $n$Na jaké motorky lze poukaz uplatnit?$n$),
    -- /poukazy · Odpověď: značka „MotoGo24“
    (24, 'web.poukazy.faq.items.4.a', 'full', $o$Poukaz můžeš uplatnit na všechny motorky v nabídce Motogo24 – podle zvolené hodnoty poukazu.$o$,
      $n$Poukaz můžeš uplatnit na všechny motorky v nabídce MotoGo24 – podle zvolené hodnoty poukazu.$n$),
    -- /poukazy · Závěrečná výzva: pryč opakovaná věta „půjčovna motorek na Vysočině s nonstop provozem…“
    (25, 'web.poukazy.cta.text', 'full', $o$Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, půjčením&nbsp;<strong>bez kauce</strong> a <strong>výbavou pro řidiče v ceně</strong>. Dárkový voucher je ideální volba, jak darovat <em>zážitek na motorce</em>&nbsp;– od <strong>cestovních</strong> přes <strong>naked </strong>a<strong> supermoto</strong>&nbsp;až po&nbsp;<strong>dětské motorky, choppery </strong>nebo<strong> skútry</strong>.$o$,
      $n$Obdarovaný si sám vybere motorku i termín. Půjčujeme <strong>bez kauce</strong> a <strong>výbava pro řidiče je v ceně</strong>.$n$),
    -- /poukazy · Tlačítko: „poukaz“ místo „voucher“
    (26, 'web.poukazy.cta.buttons.0.label', 'full', $o$OBJEDNAT VOUCHER$o$,
      $n$OBJEDNAT POUKAZ$n$),
    -- /pobocky · Titulek: názvy obou poboček (dnes stejná slova jako úvodní stránka)
    (27, 'web.pobocky.seo.title', 'full', $o$Pobočky | MotoGo24 – půjčovna motorek Pelhřimov a Brno$o$,
      $n$Pobočky Mezná u Pelhřimova a Velké Němčice | MotoGo24$n$),
    -- /pobocky · Popisek pro vyhledávače: čím se pobočky liší
    (28, 'web.pobocky.seo.description', 'full', $o$Pobočky půjčovny motorek MotoGo24: obslužná pobočka Mezná u Pelhřimova (Vysočina) a samoobslužná pobočka Velké Němčice u Brna — převzetí motorky nonstop.$o$,
      $n$Porovnej naše dvě pobočky: Mezná u Pelhřimova s osobním předáním a přistavením na adresu, Velké Němčice u Brna samoobslužně 24/7 kódem z aplikace.$n$),
    -- /pobocky/mezna · Titulek: cílí na „půjčovna motorek Pelhřimov“
    (29, 'web.pobocky.branches.0.seo_title', 'full', $o$Pobočka Mezná u Pelhřimova | MotoGo24 – obslužná půjčovna motorek$o$,
      $n$Půjčovna motorek Pelhřimov – pobočka Mezná | MotoGo24$n$),
    -- /pobocky/mezna · Popisek pro vyhledávače: konkrétní výhody pobočky, tykání
    (30, 'web.pobocky.branches.0.seo_description', 'full', $o$Obslužná pobočka půjčovny motorek MotoGo24 v Mezné u Pelhřimova (Vysočina): osobní předání motorky nonstop, výbava v ceně, přistavení na adresu.$o$,
      $n$Pobočka Mezná u Pelhřimova: motorku ti předáme osobně v čase, který si zvolíš, i o víkendu. Výbava do 6XL v ceně, nepromoky, přistavení za příplatek.$n$),
    -- /pobocky/velke-nemcice · Titulek: cílí na „samoobslužná půjčovna motorek“
    (31, 'web.pobocky.branches.1.seo_title', 'full', $o$Samoobslužná pobočka Velké Němčice u Brna | MotoGo24$o$,
      $n$Velké Němčice: samoobslužná půjčovna motorek | MotoGo24$n$),
    -- /pobocky/velke-nemcice · Popisek pro vyhledávače: kratší (dnes přes 155 znaků a vyká)
    (32, 'web.pobocky.branches.1.seo_description', 'full', $o$Samoobslužná pobočka půjčovny motorek MotoGo24 ve Velkých Němčicích u Brna: převzetí i vrácení 24/7 kódem z aplikace, čas vyzvednutí volíte v rezervaci (od 12:00 je 1. den za polovinu), parkování zdarma.$o$,
      $n$Jak funguje samoobslužná pobočka u Brna: kódy z aplikace, šatna s výbavou a kóje s motorkou. Vrácení poslední den do 24:00, parkování zdarma.$n$)
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
        RAISE NOTICE 'seo_texts_core_1: % PŘESKOČENO – klíč v cms_variables neexistuje', r.key;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_texts_core_1: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.key, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'seo_texts_core_1: cms_variables změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
