-- =============================================================================
-- 20261128c3_seo_web_texts_howto_1.sql
-- datová migrace (bez změn schématu): texty webu ve Velín CMS – Jak si půjčit: vrácení v půjčovně, vrácení jinde, co je v ceně, přistavení (část 3/5).
--
-- Datum: 2026-11-28. Zadání majitele 2026-11-27: zkvalitnění a zpřesnění textů (SEO).
-- Schváleno majitelem 2026-11-27.
-- Mění se JEN české hodnoty (sloupec cms_variables.value). Sloupec translations (cizí jazyky)
-- se nemění – cizojazyčné verze ukazují dál dosavadní překlad, dokud se text ve Velínu znovu
-- neuloží / nepřeloží.
-- Znění = nové výchozí texty v PHP (data/*-content-*.php, commit 488ee074), aby kód i databáze říkaly totéž.
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
    -- /jak-pujcit/vraceni-pujcovna · Krok 1: krátký nadpis bez vloženého zmenšeného písma
    (1, 'web.jak_pujcit_vraceni_pujcovna.process.steps.0.title', 'full', $o$<span style="font-size: 1em"><span style="font-size: 0.85em"><span style="font-weight: normal">Přijeď kdykoliv během posledního dne výpůjčky (ideálně v orientační čas, který jsi uvedl/a při rezervaci).</span></span></span>$o$,
      $n$Přijeď poslední den výpůjčky do 24:00$n$),
    -- /jak-pujcit/vraceni-pujcovna · Krok 2: bez vloženého zmenšeného písma a tečky
    (2, 'web.jak_pujcit_vraceni_pujcovna.process.steps.1.title', 'full', $o$<span style="font-weight: normal;"><span style="font-size: 0.85em;">Předej klíče a výbavu.</span></span>$o$,
      $n$Předej klíče a výbavu$n$),
    -- /jak-pujcit/vraceni-pujcovna · Krok 3: bez vloženého zmenšeného písma a tečky
    (3, 'web.jak_pujcit_vraceni_pujcovna.process.steps.2.title', 'full', $o$<span style="font-weight: normal;"><span style="font-size: 0.85em;">Společně zkontrolujeme stav motorky a výbavy.</span></span>$o$,
      $n$Společně zkontrolujeme stav motorky a výbavy$n$),
    -- /jak-pujcit/vraceni-pujcovna · Krok 4: krátký nadpis (slevový kód zůstal)
    (4, 'web.jak_pujcit_vraceni_pujcovna.process.steps.3.title', 'full', $o$<span style="font-weight: normal;"><span style="font-size: 0.85em;">Na e-mail ti přijde potvrzení o ukončení nájmu, konečná faktura a slevový kód na další rezervaci.</span></span>$o$,
      $n$Potvrzení, fakturu a slevový kód dostaneš e-mailem$n$),
    -- /jak-pujcit/pristaveni · Nadpis výzvy: bez řetězce klíčových slov
    (5, 'web.jak_pujcit_pristaveni.cta.title', 'full', $o$Přistavení motorky – půjčovna motorek MotoGo24$o$,
      $n$Objednej si přistavení$n$),
    -- /jak-pujcit/vraceni-pujcovna · Úvod: vrácení kdykoli poslední den do 24:00 (ne „v domluvený čas“) a doplněna samoobslužná pobočka u Brna
    (6, 'web.jak_pujcit_vraceni_pujcovna.intro', 'full', $o$Výpůjčka končí stejně jednoduše jako začala. Přijeď v domluvený čas vrácení na naši adresu v Mezné u Pelhřimova. Vrať motorku a zapůjčenou výbavu a je hotovo. Před vrácením nemusíš mýt ani tankovat – jen ať nesvítí rezerva.&nbsp;$o$,
      $n$Motorku vrátíš na pobočku, kde sis ji půjčil/a, kdykoli poslední den výpůjčky do 24:00. Tankovat nemusíš – jen ať nesvítí rezerva. V Mezné u Pelhřimova ji nemusíš ani mýt; ve Velkých Němčicích u Brna ji vrať umytou do kóje a výbavu do šatny – pomocí kódů z aplikace.$n$),
    -- /jak-pujcit/vraceni-pujcovna · Čas vrácení: podle obchodních podmínek (čl. 2 d) platíš za každý další započatý den, ne až při „výrazném“ zpoždění; sekce se jmenuje „Upravit rezervaci“
    (7, 'web.jak_pujcit_vraceni_pujcovna.time.text', 'full', $o$Motorku můžeš vrátit kdykoliv během posledního dne výpůjčky, ideálně v čas, který jsi uvedl/a v rezervačním formuláři. Pokud se přeci jen dost zpozdíš, dej nám, prosím, vědět telefonicky, nebo změnu příjezdu nahlaš v sekci Úprava rezervace nebo ve své aplikaci MotoGo24.&nbsp; Do půlnoci posledního dne výpůjčky neplatíš žádný poplatek za pozdní vrácení. Pokud motorku vrátíš výrazně po tomto termínu, bude ti účtováno nájemné za další den.$o$,
      $n$Motorku vrať kdykoli poslední den výpůjčky do 24:00 – čas vrácení uvedený v rezervaci je jen orientační. Když víš, že to do půlnoci nestihneš, zavolej nám, nebo si výpůjčku prodluž v sekci Upravit rezervaci či v aplikaci MotoGo24 (pokud je motorka volná). Za každý další započatý den, kdy máš motorku u sebe, platíš nájemné za den navíc.$n$),
    -- /jak-pujcit/vraceni-pujcovna · Závěrečná výzva: krátká věta místo opakované reklamní („půjčovna motorek na Vysočině s nonstop provozem…“)
    (8, 'web.jak_pujcit_vraceni_pujcovna.cta.text', 'full', $o$MotoGo24 je půjčovna motorek na Vysočině s nonstop provozem a jednoduchým vrácením motorky kdykoliv v den výpůjčky. Bez kauce, bez tankování (jen ať nesvítí rezerva), v Mezné i bez mytí. Vyber si z naší široké nabídky motorek (a skútrů) a rezervuj online z pohodlí domova.$o$,
      $n$Zavolej nám nebo napiš – rádi ti poradíme.$n$),
    -- /jak-pujcit/vraceni-jinde · Závěrečná výzva: konkrétní informace místo výčtu kategorií motorek
    (9, 'web.jak_pujcit_vraceni_jinde.cta.text', 'full', $o$Půjčovna motorek MotoGo24 na Vysočině nabízí <strong>vrácení motorky kdekoliv v České republice</strong>. Předej nám motorku na místě podle svého výběru – my přijedeme v domluvený čas. Cena se odvíjí od vzdálenosti z místa vrácení do naší provozovny v Pelhřimově. Vyber si <strong>cestovní, supermoto, naked,&nbsp;</strong><strong>dětskou motorku</strong>, <strong>choppera</strong> nebo <strong>skútra</strong> a rezervuj <strong>online</strong> a vyraž. O zbytek se postaráme my.$o$,
      $n$Místo a čas vrácení zadáš přímo v rezervaci a cenu ti formulář spočítá hned. Když si nevíš rady, zavolej nám nebo napiš.$n$),
    -- /jak-pujcit/co-v-cene · Karta „Bez kauce“: „0 Kč záloha“ není pravda (nájem se platí předem), nulová je jen kauce
    (10, 'web.jak_pujcit_cena.benefits.items.2.text', 'full', $o$<strong>0 Kč záloha</strong> při půjčení.$o$,
      $n$žádná kauce ani blokace peněz na kartě – platíš jen nájem.$n$),
    -- /jak-pujcit/co-v-cene · Závěrečná výzva: bez třetího opakování „bez kauce, výbava v ceně, nonstop“
    (11, 'web.jak_pujcit_cena.cta.text', 'full', $o$<strong>MotoGo24 je moderní půjčovna motorek na Vysočině</strong> s výbavou pro řidiče v ceně, půjčením bez kauce a nonstop provozem. Vyber si <strong>cestovní, supermoto, naked, dětskou motorku nebo choppera či skútra</strong> a rezervuj online. U nás je vše jasné a bez skrytých poplatků.$o$,
      $n$Cenu všech doplňků uvidíš v rezervaci ještě před platbou. Vyber si motorku a rezervuj online.$n$),
    -- /jak-pujcit/co-v-cene · Závěr 1: havarijní pojištění sjednané není (jen smluvní krytí škod), „standardní otevírací doba“ neexistuje
    (12, 'web.jak_pujcit_cena.outro.body1', 'full', $o$V MotoGo24 jsme od samého začátku stavěli ceník tak, aby byl <strong>maximálně transparentní</strong>. Co je v ceně nájmu, to v ceně <strong>opravdu dostaneš</strong> — žádné dodatečné poplatky za výbavu řidiče, za vyzvednutí mimo standardní otevírací dobu, za papírování ani za pojištění. Pokud bys cokoliv potřeboval/a navíc (doplňková výbava, prodloužení rezervace, přistavení motorky apod.), cenu víš vždy&nbsp;<strong>dopředu</strong> — při vrácení motorky tě nečeká žádné nemilé překvapení.$o$,
      $n$Co je v ceně nájmu, to <strong>opravdu dostaneš</strong>: za výbavu řidiče, převzetí večer či o víkendu ani za smluvní krytí škod nic nedoplácíš. Cenu doplňků (výbava pro spolujezdce, boty, přistavení) vidíš v rezervaci <strong>předem</strong>, takže tě při vrácení nic nepřekvapí.$n$),
    -- /jak-pujcit/co-v-cene · Závěr 2: kratší text, kauce jinde 20 000–30 000 Kč podle našeho průzkumu, bez nadpisu a seznamu uvnitř odstavce
    (13, 'web.jak_pujcit_cena.outro.body2', 'full', $o$<h4>Žádná kauce. Místo toho důvěra a kvalitní smlouva.</h4>
<p>Klasický model běžných půjčoven&nbsp;<em>"splatná kauce 10 000–30 000 Kč před vyzvednutím motorky"</em> jsme rovnou zamítli. <strong>U nás žádnou kauci neplatíš</strong> — žádné blokování peněz na kartě, žádné skládání hotovosti. Místo toho stavíme na:</p>
<ul>
<li><strong>Kvalitní smlouvě o pronájmu</strong>, která jasně popisuje práva i povinnosti obou stran.</li>
<li><strong>Důvěře a osobním přístupu</strong> — jsme rodinná půjčovna a chováme se k tobě tak, jak bychom chtěli, aby se někdo choval k nám.</li>
</ul>
<p>Kdyby se přesto něco přihodilo, <strong>máš k dispozici SOS kontakt pro nečekané situace</strong> - když se ozveš, vše začneme individuálně řešit.</p>$o$,
      $n$<strong>Žádná kauce – místo ní férová smlouva.</strong> Jinde u velké motorky obvykle skládáš vratnou kauci 20 000–30 000 Kč. U nás ti nic neblokujeme na kartě ani nechceme hotovost: spoléháme na srozumitelnou smlouvu o pronájmu a osobní přístup rodinné půjčovny. Když se během jízdy něco stane, zavolej nám a hned to začneme řešit.$n$),
    -- /jak-pujcit/pristaveni · Závěrečná výzva: jak přistavení objednat (místo fráze se značkou „Motogo24“)
    (14, 'web.jak_pujcit_pristaveni.cta.text', 'full', $o$Motogo24 nabízí přistavení motocyklu po regionu i mimo něj. Nonstop provoz, bez kauce, výbava řidiče v ceně.$o$,
      $n$Přistavení si objednáš přímo v rezervaci – adresu a čas zadáš ve formuláři a cenu uvidíš hned.$n$),
    -- /jak-pujcit/vraceni-pujcovna · Nesrovnalosti: hranice „do 5 000 Kč neřešíme“ v obchodních podmínkách není – škodu na motorce nehradíš (čl. 7), výbavu ano
    (15, 'web.jak_pujcit_vraceni_pujcovna.issues.lead', 'full', $o$Při vrácení společně zkontrolujeme stav motorky a výbavy. Drobná poškození do 5 000 Kč neřešíme, nemusíš se stresovat. Až v níže uvedených případech, kdy by byl motocykl nebo výbava značně poškozeny, sepsali bychom protokol o zjištěném poškození:$o$,
      $n$Při osobním vrácení spolu zkontrolujeme motorku i výbavu. Škody na motorce, které zaviníš, kryje 100% smluvní krytí škod se spoluúčastí 0 Kč (podmínky a výjimky uvádí čl. 7 obchodních podmínek). Zapůjčenou výbavu, která chybí nebo je poškozená nad rámec běžného opotřebení, hradíš. Protokol o poškození sepíšeme, když:$n$),
    -- /jak-pujcit/vraceni-pujcovna · Nesrovnalosti, bod 1: bez limitu „nad 5000 Kč“ (obchodní podmínky čl. 5 i)
    (16, 'web.jak_pujcit_vraceni_pujcovna.issues.items.0', 'full', $o$- zcela chybějící výbava v hodnotě nad 5000 Kč,$o$,
      $n$- chybí zapůjčená výbava,$n$),
    -- /jak-pujcit/vraceni-pujcovna · Nesrovnalosti, bod 2: bez limitu „nad 5000 Kč“
    (17, 'web.jak_pujcit_vraceni_pujcovna.issues.items.1', 'full', $o$- výrazně poškozená výbava v hodnotě nad 5000 Kč,$o$,
      $n$- výbava je poškozená nad rámec běžného opotřebení,$n$),
    -- /jak-pujcit/vraceni-pujcovna · Nesrovnalosti, bod 3: znění podle obchodních podmínek (místo „markantně poškozený motocykl“)
    (18, 'web.jak_pujcit_vraceni_pujcovna.issues.items.2', 'full', $o$- markantně poškozený motocykl.$o$,
      $n$- motorka je výrazně poškozená nebo má jinou závadu vzniklou během výpůjčky.$n$),
    -- /jak-pujcit/vraceni-jinde · Nesrovnalosti, bod 1: stejné znění jako u vrácení v půjčovně, bez limitu „nad 5000 Kč“
    (19, 'web.jak_pujcit_vraceni_jinde.issues.items.0', 'full', $o$- zcela chybějící výbava v hodnotě nad 5000 Kč,$o$,
      $n$- chybí zapůjčená výbava,$n$),
    -- /jak-pujcit/vraceni-jinde · Nesrovnalosti, bod 2: bez „dramaticky“ a limitu „nad 5000 Kč“
    (20, 'web.jak_pujcit_vraceni_jinde.issues.items.1', 'full', $o$- dramaticky poškozená výbava v hodnotě nad 5000 Kč,$o$,
      $n$- výbava je poškozená nad rámec běžného opotřebení,$n$),
    -- /jak-pujcit/vraceni-jinde · Nesrovnalosti, bod 3: bez limitu „se škodou nad 5000 Kč“
    (21, 'web.jak_pujcit_vraceni_jinde.issues.items.2', 'full', $o$- výrazně poškozený motocykl se škodou nad 5000 Kč.$o$,
      $n$- motorka je výrazně poškozená nebo má jinou závadu vzniklou během výpůjčky.$n$),
    -- /jak-pujcit/co-v-cene · Poznámka u výbavy: nepromoky a doplňky jsou jen v Mezné; doplněno, co je v ceně vždy (zámek, vesta, lékárnička, držák telefonu)
    (22, 'web.jak_pujcit_cena.gear.basic.note2', 'full', $o$Vybrané motorky jsou vybaveny kufry – viz detail motorky v katalogu. Pokud je v katalogu u motorky uveden kufr/y, zapůjčení je zdarma. K výpůjčce dostaneš v ceně také kotoučový zámek a přibrat si můžeš i reflexní prvky, zavazadlovou síť, nepromoky aj.$o$,
      $n$Kufry mají vybrané motorky – najdeš je v detailu motorky v katalogu – a nic za ně neplatíš. Ke každé výpůjčce dostaneš také kotoučový zámek, reflexní vestu, lékárničku a držák na telefon. V Mezné ti k motorce bez kufru zdarma půjčíme tankvak a podle dostupnosti i nepromoky nebo zavazadlovou síť; na samoobslužné pobočce ve Velkých Němčicích doplňkovou výbavu nepůjčujeme.$n$)
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
        RAISE NOTICE 'seo_texts_howto_1: % PŘESKOČENO – klíč v cms_variables neexistuje', r.key;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_texts_howto_1: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.key, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'seo_texts_howto_1: cms_variables změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
