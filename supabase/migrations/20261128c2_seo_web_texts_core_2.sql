-- =============================================================================
-- 20261128c2_seo_web_texts_core_2.sql
-- datová migrace (bez změn schématu): texty webu ve Velín CMS – katalog, detail motorky, e-shop, mapa stránek, blog, provozní doba v patičce (část 2/5).
--
-- Datum: 2026-11-28. Zadání majitele 2026-11-27: zkvalitnění a zpřesnění textů (SEO).
-- Schváleno majitelem 2026-11-27.
-- Mění se JEN české hodnoty (sloupec cms_variables.value). Sloupec translations (cizí jazyky)
-- se nemění – cizojazyčné verze ukazují dál dosavadní překlad, dokud se text ve Velínu znovu
-- neuloží / nepřeloží.
-- web.katalog.outro.body1: odstavec „Dětské motorky“ zůstává slovo od slova (čeká na potvrzení majitele),
-- mění se jen značky kolem (odstavce už nejsou uvnitř nadpisů <h4>).
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
    -- /katalog · Úvod katalogu: pryč „Nově nabízíme…“ (stejné znění jako nový výchozí text v kódu)
    (1, 'web.katalog.intro', 'full', $o$Vyber si z naší nabídky <strong>cestovních, supermoto, naked a dětských motorek</strong>. Nově nabízíme k pronájmu také <strong>skútry a choppery.</strong>&nbsp;Můžeš filtrovat podle kategorie, řidičského průkazu, výkonu, ceny a dalších parametrů.$o$,
      $n$Vyber si z naší nabídky <strong>cestovních, naked, supermoto i dětských motorek, chopperů a skútrů</strong>. Filtrovat můžeš podle kategorie, řidičského průkazu, výkonu, ceny a dalších parametrů.$n$),
    -- /katalog · Popis kategorií: odstavce už nejsou označené jako nadpisy; supermoto – Yamaha XT660 X je na ŘP A2; „Chopper je symbolem…“, bez „rád/a“. Odstavec o dětských motorkách beze změny (čeká na tvé potvrzení)
    (2, 'web.katalog.outro.body1', 'full', $o$<p>V katalogu MotoGo24 najdeš pět hlavních kategorií motorek a také skútry — vyber si podle toho, co od jízdy očekáváš:</p>
<h3>Cestovní motorky</h3><h4>
<p>Cestovky jsou srdcem naší flotily. <span style="font-weight: normal;">Pohodlné, výkonné a vybavené pro dlouhé mototripy. Cestovku si u nás půjč, pokud plánuješ vícedenní výlet po Česku nebo do zahraničí, jízdu ve dvou s plnou bagáží, nebo prostě chceš stroj, na kterém po osmihodinové cestě neslezeš s bolavými zády. V nabídce máme klasiku jako</span> Suzuki DL650 V-Strom<span style="font-weight: normal;">, moderní italskou střední třídu </span>Benelli TRK 702 X <span style="font-weight: normal;">i staré dobré</span> Varadero XL 1000.</p>
</h4><h3>Naked motorky</h3><h4>
<p><span style="font-weight: normal;">Naked je pro tebe, pokud rád/a jezdíš dynamicky, miluješ hbitost a hledáš motorku stejně dobrou ve městě i na klikatých silnicích. Zábava a čistá radost z jízdy. Ideální volba na jednodenní vyjížďky po Vysočině, městské brázdění nebo víkendové výlety po širokém okolí. V nabídce máme ostrou </span>Kawasaki Z900<span style="font-weight: normal;"> se čtyřválcem, kterou si zamiluješ hned po prvním otočení plynem, nebo svižnou&nbsp;</span>MT-09<span style="font-weight: normal;">.</span></p>
</h4><h3>Supermoto</h3><h4>
<p><span style="font-weight: normal;">Supermoto je pro každého, kdo si chce pořádně zalétat v zatáčkách a nestará se moc o pohodlí na dálkových cestách. Vysoký posed, lehký rám, silné brzdy a pneumatiky se silničním vzorkem — supermoto je adrenalin i tam, kde ho nečekáš. Skvělý stroj pro pokročilejší jezdce s řidičákem A, kteří chtějí ze sezony vytáhnout maximum, i pro fanoušky technické jízdy po okolí. U nás si vyzkoušíš třeba</span> Husqvarnu 701 Supermoto — <span style="font-weight: normal;">ikonu celé kategorie.</span></p>
</h4><h3>Choppery a cruisery</h3><h4>
<p><span style="font-weight: normal;">Chopper to je symbol jízdy, u které nikam nespěcháš. Nízké sedlo, nohy dopředu, ruce na širokých řídítkách. Chopper si u nás půjč, pokud tě baví cesta víc než cíl, chceš si vychutnat nedělní vyjížďku ve dvou, vyrazit na sraz, nebo prostě jednou zažít, jaké to je, když se za tebou otáčí okolí. Nízký posed navíc znamená, že nohama bezpečně dosáhneš na zem — i proto jsou některé choppery vděčné i pro méně zkušené jezdce. Vyber si stylový </span>Royal Enfield Shotgun 650, který zvládneš i na řidičák A2, nebo legendární Hondu VTX 1800 s téměř dvoulitrovým motorem pro ty, kdo chtějí zažít opravdového obra.</p>
</h4><h3>Dětské motorky</h3><h4>
<p><span style="font-weight: normal;">Jsme jediná oficiální půjčovna motorek na Vysočině s dětskými motorkami. Máme stroje už od 3 let pro ty nejšikovnější malé nedočkavce až po plnohodnotné motorky pro dospívající jezdce. Ať jsou tvému dítěti tři, sedm, nebo dvanáct — vždycky u nás najdeš motorku přesně podle jeho věku a zkušeností. Flotilu navíc neustále rozšiřujeme o nové modely.</span></p>
</h4><h3>Skútry</h3><h4>
<p><span style="font-weight: normal;">Skútr je nejjednodušší způsob, jak se svézt. Automatická převodovka, žádné řazení, úložný prostor pod sedlem a nízká spotřeba — nasedneš a jedeš. Ideální na výlet po okolí, popojíždění po městě i pro toho, kdo si chce jen tak zpříjemnit hezký den. A skvělá volba i pro začátečníky nebo držitele řidičáku skupiny B.</span></p></h4>$o$,
      $n$<p>V katalogu MotoGo24 najdeš pět hlavních kategorií motorek a také skútry – vyber si podle toho, co od jízdy očekáváš:</p>
<h3>Cestovní motorky</h3>
<p><strong>Cestovky jsou srdcem naší flotily.</strong> Pohodlné, výkonné a vybavené pro dlouhé mototripy. Cestovku si u nás půjč, pokud plánuješ vícedenní výlet po Česku nebo do zahraničí, jízdu ve dvou s plnou bagáží, nebo prostě chceš stroj, ze kterého po osmihodinové cestě neslezeš s bolavými zády. V nabídce máme klasiku jako <strong>Suzuki DL650 V-Strom</strong>, moderní italskou střední třídu <strong>Benelli TRK 702 X</strong> i staré dobré <strong>Varadero XL 1000</strong>.</p>
<h3>Naked motorky</h3>
<p>Naked je pro tebe, pokud rád jezdíš dynamicky, miluješ hbitost a hledáš motorku stejně dobrou ve městě i na klikatých silnicích. Zábava a čistá radost z jízdy. Ideální volba na jednodenní vyjížďky po Vysočině, městské brázdění nebo víkendové výlety po širokém okolí. V nabídce máme ostrou <strong>Kawasaki Z900</strong> se čtyřválcem, kterou si zamiluješ hned po prvním otočení plynem, nebo svižnou <strong>MT-09</strong>.</p>
<h3>Supermoto</h3>
<p>Supermoto je pro každého, kdo si chce pořádně zalétat v zatáčkách a nestará se moc o pohodlí na dálkových cestách. Vysoký posed, lehký rám, silné brzdy a pneumatiky se silničním vzorkem – supermoto je adrenalin i tam, kde ho nečekáš. Skvělý stroj pro pokročilejší jezdce, kteří chtějí ze sezóny vytáhnout maximum, i pro fanoušky technické jízdy po okolí. U nás si vyzkoušíš třeba <strong>Husqvarnu 701 Supermoto</strong> (ŘP A) – ikonu celé kategorie – nebo <strong>Yamahu XT660 X</strong>, kterou řídíš už s ŘP A2.</p>
<h3>Choppery a cruisery</h3>
<p>Chopper je symbolem jízdy, při které nikam nespěcháš. Nízké sedlo, nohy dopředu, ruce na širokých řídítkách. Chopper si u nás půjč, pokud tě baví cesta víc než cíl, chceš si vychutnat nedělní vyjížďku ve dvou, vyrazit na sraz, nebo prostě jednou zažít, jaké to je, když se za tebou otáčí okolí. Nízký posed navíc znamená, že nohama bezpečně dosáhneš na zem – i proto jsou některé choppery vděčné i pro méně zkušené jezdce. Vyber si stylový <strong>Royal Enfield Shotgun 650</strong>, který zvládneš i na řidičák A2, nebo legendární <strong>Hondu VTX 1800</strong> s téměř dvoulitrovým motorem pro ty, kdo chtějí zažít opravdového obra.</p>
<h3>Dětské motorky</h3>
<p>Jsme jediná oficiální půjčovna motorek na Vysočině s dětskými motorkami. Máme stroje už od 3 let pro ty nejšikovnější malé nedočkavce až po plnohodnotné motorky pro dospívající jezdce. Ať jsou tvému dítěti tři, sedm, nebo dvanáct — vždycky u nás najdeš motorku přesně podle jeho věku a zkušeností. Flotilu navíc neustále rozšiřujeme o nové modely.</p>
<h3>Skútry</h3>
<p>Skútr je nejjednodušší způsob, jak se svézt. Automatická převodovka, žádné řazení, úložný prostor pod sedlem a nízká spotřeba – nasedneš a jedeš. Ideální na výlet po okolí, popojíždění po městě i pro toho, kdo si chce jen tak zpříjemnit hezký den. A skvělá volba i pro začátečníky nebo držitele řidičáku skupiny B.</p>$n$),
    -- /katalog · Závěr: lomítkový tvar „jistý/á“
    (3, 'web.katalog.outro.body2', 'phrase', $o$Pokud si nejsi jistý/á výběrem$o$,
      $n$Pokud si nejsi jistý výběrem$n$),
    -- /katalog/<motorka> · Text se zobrazuje i u dětských motokrosek: zahraničí platí jen pro silniční motorky, dětské jen mimo silnice (obchodní podmínky čl. 10). Věta o telefonu 24/7 beze změny (čeká na tvé potvrzení)
    (4, 'web.katalog_detail.outro.body2', 'phrase', $o$<span style="font-weight: 700;">S našimi motorkami můžeš bez obav vyrazit do zahraničí - i mimo EU! </span>Stačí se řídit pokyny v zelené kartě.$o$,
      $n$<span style="font-weight: 700;">Se silničními motorkami můžeš bez obav vyrazit do zahraničí – i mimo EU! </span>Stačí dodržet územní platnost zelené karty. Dětské motorky jsou určené jen pro jízdu v uzavřeném prostoru mimo pozemní komunikace a pod dohledem dospělého.$n$),
    -- /eshop · Text sliboval zboží skladem a expedici do druhého dne, přestože e-shop hlásí „nemáme žádné produkty“
    (5, 'web.eshop.outro.body1', 'full', $o$V e-shopu MotoGo24 najdeš <strong>motorkářské doplňky, oblečení a merchandise</strong> pro každý typ jízdy. Aktuálně si u nás vybereš <strong>kšiltovky, trička, rukavice i kukly</strong> — a sortiment <strong>neustále rozšiřujeme</strong> o další kousky, které ti udělají radost na cestě, ve městě i mimo motorku. Většinu zboží máme <strong>skladem u nás v Mezné u Pelhřimova</strong> a expedujeme <strong>do druhého pracovního dne</strong>.$o$,
      $n$V e-shopu MotoGo24 nabízíme <strong>merch a motorkářské doplňky</strong> – například trička, kšiltovky, rukavice nebo kukly. Aktuálně dostupné zboží vidíš v nabídce nad tímto textem.$n$),
    -- /eshop · „QR“ velkými písmeny
    (6, 'web.eshop.outro.body2', 'phrase', $o$<strong>qr kódem </strong>$o$,
      $n$<strong>QR kódem </strong>$n$),
    -- /mapa-stranek · „Jsme dostupní nonstop“ neplatí – telefon a e-mail jen Po–Pá 8–17 (stejné znění jako nový výchozí text v kódu)
    (7, 'web.mapa_stranek.outro.body2', 'phrase', $o$Jsme dostupní nonstop a rádi poradíme s výběrem motorky, termínem nebo s objednávkou dárkového poukazu.$o$,
      $n$Telefon a e-mail vyřizujeme Po–Pá 8–17, AI asistent na webu ti poradí kdykoli — s výběrem motorky, termínem i s objednávkou dárkového poukazu.$n$),
    -- /blog · O blogu: pryč slib článků o trasách a online check-inu (na blogu nejsou) a věta o Googlu; „nepotřebuješ“ místo „nepotřebujete“
    (8, 'web.blog.outro.body1', 'full', $o$<p>Tady na blogu nepíšeme proto, aby Google viděl naše stránky. Píšeme pro tebe — motorkáře, budoucí motorkáře a všechny, kdo si chtějí z půjčené motorky <strong>odvézt zážitek, ne stres</strong>.</p>
<p>Co tu najdeš:</p><ul><li><strong>Tipy pro motorkáře</strong> — od nováčků s čerstvým řidičákem až po ty nejzkušenější;</li><li><strong>Inspirace na trasy</strong> — Vysočina, ČR, ale i zahraničí;</li><li><strong>Praktické rady</strong> — jak vybrat motorku k pronájmu, co dělat s dárkovým poukazem, čím obdarovat motorkáře apod.;</li><li><strong>Vše o naší půjčovně</strong> — proč a jak jsme vznikli, proč u nás <strong>nepotřebujete kauci</strong>, co všechno je v ceně nájmu, jak funguje online check-in a mnoho dalšího.</li></ul>$o$,
      $n$<p>Píšeme pro tebe – motorkáře, budoucí motorkáře a všechny, kdo si chtějí z půjčené motorky <strong>odvézt zážitek, ne stres</strong>.</p>
<p>Co tu najdeš:</p><ul><li><strong>Tipy pro motorkáře</strong> – od nováčků s čerstvým řidičákem až po ty nejzkušenější;</li><li><strong>Praktické rady</strong> – jak vybrat motorku k pronájmu, co dělat s dárkovým poukazem, čím obdarovat motorkáře apod.;</li><li><strong>Vše o naší půjčovně</strong> – proč a jak jsme vznikli, proč u nás <strong>nepotřebuješ kauci</strong>, co všechno je v ceně nájmu a mnoho dalšího.</li></ul>$n$),
    -- patička (všechny stránky) · Provozní doba: jen typografie (pomlčky v rozsazích, časy bez úvodní nuly) – údaje beze změny
    (9, 'web.layout.footer.openHours', 'full', $o$<span style="font-size: small;">PO - NE 00:00 - 24:00&nbsp;</span><div><span style="font-size: small;">(výdej a příjem motorek dle rezervace)</span><div><div><span style="font-size: small;">PO - PÁ 08:00 - 17:00&nbsp;</span></div><div><span style="font-size: small;">(technická podpora)</span></div></div></div>$o$,
      $n$<span style="font-size: small;">PO–NE 0:00–24:00&nbsp;</span><div><span style="font-size: small;">(výdej a příjem motorek podle rezervace)</span><div><div><span style="font-size: small;">PO–PÁ 8:00–17:00&nbsp;</span></div><div><span style="font-size: small;">(technická podpora)</span></div></div></div>$n$)
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
        RAISE NOTICE 'seo_texts_core_2: % PŘESKOČENO – klíč v cms_variables neexistuje', r.key;
      ELSIF (CASE WHEN r.how = 'phrase' THEN strpos(coalesce(v_cur, ''), r.new) > 0 ELSE v_cur = r.new END) THEN
        n_done := n_done + 1;
      ELSE
        n_skip := n_skip + 1;
        RAISE NOTICE 'seo_texts_core_2: % [%] PŘESKOČENO – text ve Velínu mezitím změněn: %', r.key, r.how, left(coalesce(v_cur, '∅'), 160);
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'seo_texts_core_2: cms_variables změněno %, už hotovo %, přeskočeno %', n_upd, n_done, n_skip;
END $$;
