<?php
// ===== MotoGo24 Web PHP — Fallback blog články =====
// Použito když v DB tabulce cms_pages nejsou žádné záznamy.
// Správná cesta je naplnit DB přes SQL seed; toto je jen záchranná síť.

function getBlogFallbackPosts() {
    return [
        [
            'id' => 'fallback-1',
            'slug' => 'top-motorkarske-trasy-vysocina',
            'title' => 'Top motorkářské trasy na Vysočině',
            'excerpt' => 'Vybrali jsme pro vás 5 nejkrásnějších motorkářských tras, které projedete z Pelhřimova během víkendu. Žďárské vrchy, Český ráj i Telč.',
            'description' => 'Vybrali jsme pro vás 5 nejkrásnějších motorkářských tras, které projedete z Pelhřimova během víkendu.',
            'tags' => ['Motorkářské trasy', 'Vysočina'],
            'image_url' => '/gfx/hero-banner.png',
            'images' => [],
            'created_at' => '2026-03-15',
            'content' => '<p>Vysočina je rájem pro motorkáře – klikaté silnice, otevřené vyhlídky, historická městečka i přírodní rezervace. Tady je 5 našich oblíbených tras z Pelhřimova.</p>'
                . '<h2>1. Pelhřimov → Telč → Třebíč (cca 120 km)</h2>'
                . '<p>UNESCO historie v pohodovém tempu. Náměstí Zachariáše z Hradce v Telči je jedno z nejkrásnějších v Česku. V Třebíči stojí za zastávku Bazilika sv. Prokopa i židovská čtvrť.</p>'
                . '<h2>2. Žďárské vrchy okruh (180 km)</h2>'
                . '<p>Přes Devět skal, Drátenickou skálu a Zelenou horu. Dechberoucí vyhlídky i klikaté lesní silničky. Ideální na celou sobotu.</p>'
                . '<h2>3. Pelhřimov → Orlík → Písek (160 km)</h2>'
                . '<p>Cesta k přehradě Orlík s přestávkou na kávu u vody a návratem přes Písek. Hodně slunce, minimum kamionů.</p>'
                . '<h2>4. Železné hory (110 km)</h2>'
                . '<p>Méně známá perla pro pohodové nedělní odpoledne. Průjezd lesy, řekami a vesničkami, které se zastavily v čase.</p>'
                . '<h2>5. Šumava přes Kašperské Hory (240 km)</h2>'
                . '<p>Celodenní túra pro zkušenější jezdce. Průsmyky, vyhlídky a pravá šumavská klidná atmosféra.</p>'
                . '<p><strong>Tip:</strong> Při rezervaci motorky v Motogo24 se ptejte, půjčíme vám zdarma i mapu s naplánovanými trasami.</p>',
        ],
        [
            'id' => 'fallback-2',
            'slug' => 'jak-si-pujcit-motorku-na-vikend',
            'title' => 'Jak si půjčit motorku na víkend bez stresu',
            'excerpt' => 'Přehledný návod od rezervace až po vrácení. Co si vzít s sebou, co musíte mít za řidičák a jak funguje naše nonstop předání.',
            'description' => 'Přehledný návod od rezervace až po vrácení motorky.',
            'tags' => ['Rady a tipy', 'Rezervace'],
            'image_url' => '/gfx/darkovy-poukaz.jpg',
            'images' => [],
            'created_at' => '2026-03-08',
            'content' => '<p>Plánujete víkendovou jízdu, ale vlastní motorku zatím nemáte? U nás v Motogo24 si vše zařídíte online za pár minut. Tady je kompletní návod.</p>'
                . '<h2>1. Vyberte si motorku</h2>'
                . '<p>V našem <a href="/katalog">katalogu motorek</a> najdete cestovní, sportovní, enduro i dětské motorky. Filtr vám pomůže zúžit výběr podle řidičáku, výkonu i ceny.</p>'
                . '<h2>2. Zarezervujte termín</h2>'
                . '<p>V rezervačním systému vyberete data vyzvednutí a vrácení. Online kalendář hned ukáže, kdy je motorka volná. Platba kartou proběhne okamžitě (Visa/Mastercard, Apple/Google Pay).</p>'
                . '<h2>3. Vyzvednutí</h2>'
                . '<p>Adresa: <strong>Mezná 9, 393 01 Pelhřimov</strong>. Provoz je <strong>nonstop</strong> – vyzvednete si kdykoli, i večer. Nabízíme také <a href="/jak-pujcit/pristaveni">přistavení</a> na hotel nebo vlakové nádraží.</p>'
                . '<h2>4. Co si vzít</h2>'
                . '<ul><li>Občanský průkaz nebo pas</li><li>Řidičský průkaz (skupina A, A2 nebo A1 podle motorky)</li><li>Vhodnou obuv (moto boty půjčíme jako nadstandard)</li></ul>'
                . '<p>Helma, bunda, kalhoty a rukavice jsou v ceně – prostě si je u nás vyzvednete.</p>'
                . '<h2>5. Vrácení</h2>'
                . '<p>Kdykoli během posledního dne výpůjčky. Nemusíte tankovat ani mýt. Podepíšeme předávací protokol a máte hotovo.</p>'
                . '<p><strong>A co kauce?</strong> U nás <strong>žádná</strong>. Férové podmínky, žádné skryté poplatky.</p>',
        ],
        [
            'id' => 'fallback-3',
            'slug' => 'tipy-pro-bezpecnou-jizdu-na-motorce',
            'title' => 'Tipy pro bezpečnou jízdu na motorce',
            'excerpt' => '8 pravidel, která vám udrží jízdu v pohodě. Od správné výbavy přes techniku zatáčení až po chování v dešti a na mokré vozovce.',
            'description' => '8 pravidel pro bezpečnou motorkářskou sezónu.',
            'tags' => ['Rady a tipy', 'Bezpečnost'],
            'image_url' => '/gfx/hero-banner.png',
            'images' => [],
            'created_at' => '2026-02-20',
            'content' => '<p>Ať už jste začínající jezdec nebo ostřílený cestovatel, pár jednoduchých pravidel vám udrží jízdu v pohodě. Tady je 8 tipů z praxe.</p>'
                . '<h2>1. Dobrá výbava = polovina bezpečí</h2>'
                . '<p>Helma, bunda s chrániči, kalhoty, rukavice a pevná obuv. U Motogo24 vše dostanete zdarma v ceně pronájmu.</p>'
                . '<h2>2. Před jízdou kontrola</h2>'
                . '<p>Tlak v pneumatikách, světla, brzdy, hladina chladicí kapaliny. Ne, opravdu to nezabere víc než 2 minuty.</p>'
                . '<h2>3. Plynule, ne prudce</h2>'
                . '<p>Plyn i brzda v plynulých pohybech. Prudké zásahy ztrácejí trakci – obzvlášť v dešti.</p>'
                . '<h2>4. Dívejte se tam, kam chcete jet</h2>'
                . '<p>V zatáčce se dívejte na výjezd, ne do krajnice. Motorka jde tam, kam se díváte.</p>'
                . '<h2>5. Mokrá vozovka = dvojnásobná opatrnost</h2>'
                . '<p>Zvlášť prvních 15 minut po začátku deště je vozovka nejkluzčí (olej + voda). Snižte tempo a zvětšete rozestupy.</p>'
                . '<h2>6. Dostatečný rozestup</h2>'
                . '<p>2 sekundy za suchou vozovkou, 4+ sekundy v dešti. Brzdná dráha motorky je delší než auta.</p>'
                . '<h2>7. Viditelnost</h2>'
                . '<p>Reflexní prvky, světlá výbava, vyhýbejte se mrtvým úhlům aut. Dejte lidem šanci vás vidět.</p>'
                . '<h2>8. Hlavu chladnou</h2>'
                . '<p>Nevzteklete se na agresivní řidiče. Nechte je odjet. Vaším úkolem je dojet v pořádku domů.</p>'
                . '<p>A samozřejmě – nikdy po alkoholu. <strong>Ani kapka</strong>.</p>',
        ],
        [
            'id' => 'fallback-4',
            'slug' => 'nove-motorky-v-nabidce-2026',
            'title' => 'Nové motorky v nabídce pro sezónu 2026',
            'excerpt' => 'Rozšířili jsme flotilu o další cestovní a enduro modely. Podívejte se, co přibylo a na co se můžete těšit v letošní sezóně.',
            'description' => 'Novinky z flotily Motogo24 pro sezónu 2026.',
            'tags' => ['Novinky půjčovny'],
            'image_url' => '/gfx/hero-banner.png',
            'images' => [],
            'created_at' => '2026-02-05',
            'content' => '<p>Sezóna 2026 je tady a s ní i rozšíření naší flotily. Investovali jsme do nových strojů, které najdete v <a href="/katalog">katalogu motorek</a>.</p>'
                . '<h2>Cestovní novinky</h2>'
                . '<p>Přibyly další cestovní motorky s výbavou pro dlouhé túry – kufry, Bluetooth komunikátor k zapůjčení, ABS i TCS. Ideální na týden po Evropě.</p>'
                . '<h2>Enduro flotila</h2>'
                . '<p>Pro milovníky lehkého terénu máme další enduro stroje s vyšším podvozkem a terénními gumami.</p>'
                . '<h2>Dětské motorky</h2>'
                . '<p>Nejmenší jezdci mají k dispozici elektrické dětské motorky bez nutnosti řidičáku (skupina N v našem katalogu). Ideální dárek.</p>'
                . '<h2>Co zůstává</h2>'
                . '<p>Všechny naše výhody: <strong>bez kauce, výbava v ceně, nonstop provoz, online rezervace</strong>. Nic se nemění, jen lepší stroje.</p>'
                . '<p>Vyberte si v <a href="/katalog">katalogu</a> a rezervujte online během pár minut.</p>',
        ],
        [
            'id' => 'fallback-5',
            'slug' => 'darkovy-poukaz-na-motorku-napady',
            'title' => 'Dárkový poukaz na motorku: originální dárek pro každou příležitost',
            'excerpt' => 'Narozeniny, Vánoce, výročí? Dárek, který opravdu potěší. Náš voucher platí 3 roky a obdarovaný si sám vybere termín i motorku.',
            'description' => 'Proč je dárkový poukaz Motogo24 lepší než další kravata.',
            'tags' => ['Dárky a poukazy'],
            'image_url' => '/gfx/darkovy-poukaz.jpg',
            'images' => [],
            'created_at' => '2026-01-20',
            'content' => '<p>Hledáte dárek, který opravdu potěší? Dárkový poukaz na pronájem motorky je originální, flexibilní a má dlouhou platnost.</p>'
                . '<h2>Pro koho</h2>'
                . '<ul><li><strong>Motorkáři</strong>, kteří zkusí nový model</li>'
                . '<li><strong>Začátečníci</strong> s čerstvým řidičákem</li>'
                . '<li><strong>Cestovatelé</strong>, kteří chtějí zážitek na víkend</li>'
                . '<li><strong>Páry</strong> – pronájem pro dvě motorky, společná túra</li></ul>'
                . '<h2>Jak to funguje</h2>'
                . '<p>Vyberete hodnotu nebo konkrétní motorku, zaplatíte online a voucher ti přijde e-mailem. Můžeme ho i vytisknout na dárkové papírnictví.</p>'
                . '<h2>Platnost 3 roky</h2>'
                . '<p>Obdarovaný si sám zvolí termín – jaro, léto nebo další sezónu. Žádný stres, žádný tlak.</p>'
                . '<h2>Žádné kauce</h2>'
                . '<p>Obdarovaný u nás neplatí žádnou kauci. Výbava pro řidiče (helma, bunda, kalhoty, rukavice) je v ceně.</p>'
                . '<p><a href="/koupit-darkovy-poukaz" class="btn btngreen">OBJEDNAT POUKAZ</a></p>',
        ],
    ];
}
